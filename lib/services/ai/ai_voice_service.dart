import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/settings_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voice input/output for Musify IA. Groq is tried first for both
/// directions (Whisper transcription, Orpheus TTS) since it is already one
/// of the configured chat providers and works identically on every desktop/
/// mobile target; the device's own speech engine is used as a fallback
/// when Groq has no key configured or a call fails.
class AiVoiceService {
  AiVoiceService._internal();
  static final AiVoiceService instance = AiVoiceService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _ttsPlayer = AudioPlayer();
  final SpeechToText _nativeSpeech = SpeechToText();
  final FlutterTts _nativeTts = FlutterTts();

  bool _nativeSpeechReady = false;
  bool _usingGroqRecording = false;
  String? _recordingPath;

  final ValueNotifier<bool> isRecording = ValueNotifier(false);
  final ValueNotifier<bool> isSpeaking = ValueNotifier(false);
  final ValueNotifier<String> liveTranscript = ValueNotifier('');

  String get _groqApiKey {
    final keys = aiProviders.value['groq']?['apiKeys'] as List?;
    return (keys != null && keys.isNotEmpty) ? keys.first.toString() : '';
  }

  Future<void> startListening() async {
    if (isRecording.value) return;
    liveTranscript.value = '';

    if (_groqApiKey.isNotEmpty) {
      final started = await _startGroqRecording();
      if (started) return;
    }

    await _startNativeListening();
  }

  /// Stops listening and returns the final transcript, or null if nothing
  /// could be transcribed by either path.
  Future<String?> stopListening() async {
    if (!isRecording.value) return null;

    if (_usingGroqRecording) {
      final path = await _recorder.stop();
      isRecording.value = false;
      _usingGroqRecording = false;
      if (path == null) return null;

      try {
        return await _transcribeWithGroq(File(path));
      } catch (e, stackTrace) {
        logger.log(
          'Groq transcription failed',
          error: e,
          stackTrace: stackTrace,
        );
        return null;
      }
    }

    await _nativeSpeech.stop();
    isRecording.value = false;
    final result = liveTranscript.value;
    return result.isEmpty ? null : result;
  }

  Future<bool> _startGroqRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return false;

      final dir = await getTemporaryDirectory();
      _recordingPath =
          '${dir.path}/musify_ia_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: _recordingPath!);
      _usingGroqRecording = true;
      isRecording.value = true;
      return true;
    } catch (e, stackTrace) {
      logger.log(
        'Groq mic recording unavailable',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<String?> _transcribeWithGroq(File audioFile) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'),
          )
          ..headers['Authorization'] = 'Bearer $_groqApiKey'
          ..fields['model'] = 'whisper-large-v3-turbo'
          ..files.add(
            await http.MultipartFile.fromPath('file', audioFile.path),
          );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 30),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 400) {
      throw Exception(
        'Groq STT error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    return decoded['text']?.toString();
  }

  Future<void> _startNativeListening() async {
    if (!_nativeSpeechReady) {
      _nativeSpeechReady = await _nativeSpeech.initialize(
        onError: (error) => logger.log('Native STT error: $error'),
      );
    }
    if (!_nativeSpeechReady) return;

    isRecording.value = true;
    await _nativeSpeech.listen(
      onResult: (result) {
        liveTranscript.value = result.recognizedWords;
      },
    );
  }

  /// Whether tap-to-speak has any chance of working: either Groq is
  /// configured, or the device exposes a native TTS engine (unsupported on
  /// Linux desktop today).
  bool get canSpeak => _groqApiKey.isNotEmpty || !Platform.isLinux;

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await stopSpeaking();

    if (_groqApiKey.isNotEmpty && await _speakWithGroq(text)) {
      return;
    }

    if (Platform.isLinux) {
      logger.log('Musify IA: no TTS available (no Groq key, Linux desktop).');
      return;
    }

    try {
      isSpeaking.value = true;
      _nativeTts
        ..setCompletionHandler(() => isSpeaking.value = false)
        ..setCancelHandler(() => isSpeaking.value = false);
      await _nativeTts.speak(text);
    } catch (e, stackTrace) {
      isSpeaking.value = false;
      logger.log('Native TTS failed', error: e, stackTrace: stackTrace);
    }
  }

  Future<bool> _speakWithGroq(String text) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/audio/speech'),
            headers: {
              'Authorization': 'Bearer $_groqApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'canopylabs/orpheus-v1-english',
              'input': text,
              'voice': 'troy',
              'response_format': 'wav',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 400) {
        throw Exception('Groq TTS error ${response.statusCode}');
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/musify_ia_tts_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(response.bodyBytes);

      isSpeaking.value = true;
      await _ttsPlayer.setFilePath(file.path);
      unawaited(
        _ttsPlayer.playerStateStream
            .firstWhere(
              (state) => state.processingState == ProcessingState.completed,
            )
            .then((_) => isSpeaking.value = false),
      );
      await _ttsPlayer.play();
      return true;
    } catch (e, stackTrace) {
      isSpeaking.value = false;
      logger.log('Groq TTS failed', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> stopSpeaking() async {
    isSpeaking.value = false;
    try {
      await _ttsPlayer.stop();
    } catch (_) {}
    try {
      await _nativeTts.stop();
    } catch (_) {}
  }
}
