import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/widgets/no_artwork_cube.dart';
import 'package:musify/widgets/spinner.dart';

/// Square artwork that does not letterbox.
///
/// YouTube's `default.jpg` and `hqdefault.jpg` thumbnails ship with black bars
/// baked into the image, so `BoxFit.cover` faithfully renders the bars. The app
/// already solves this in SongBar and the queue list by stretching over them
/// with fill + centerSlice; this is that same treatment, extracted so the AI
/// cards can share it instead of growing their own third copy.
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    required this.url,
    required this.size,
    this.borderRadius = 12,
    this.icon = FluentIcons.music_note_1_24_regular,
    super.key,
  });

  final String? url;

  /// Null makes the artwork fill whatever box the parent gives it, which is
  /// how the big card art works.
  final double? size;

  final double borderRadius;
  final IconData icon;

  bool get _hasBakedInLetterbox {
    final value = url ?? '';
    return value.contains('default.jpg') || value.contains('hqdefault');
  }

  @override
  Widget build(BuildContext context) {
    final value = url;
    if (value == null || value.isEmpty) return _fallback();

    return CachedNetworkImage(
      imageUrl: value,
      width: size,
      height: size,
      imageBuilder: (_, imageProvider) => ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image(
          image: imageProvider,
          width: size,
          height: size,
          fit: _hasBakedInLetterbox ? BoxFit.fill : BoxFit.cover,
          centerSlice: _hasBakedInLetterbox
              ? const Rect.fromLTRB(1, 1, 1, 1)
              : null,
        ),
      ),
      placeholder: (_, __) => _placeholder(context),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(borderRadius),
    ),
    child: const Center(child: Spinner()),
  );

  Widget _fallback() {
    final fixedSize = size;
    if (fixedSize != null) {
      return NullArtworkWidget(
        icon: icon,
        size: fixedSize,
        borderRadius: borderRadius,
      );
    }

    // NullArtworkWidget needs a concrete size, so when this image is meant to
    // fill its parent (the big card art), take the size from the constraints.
    return LayoutBuilder(
      builder: (context, constraints) => NullArtworkWidget(
        icon: icon,
        size: constraints.hasBoundedWidth ? constraints.maxWidth : 160,
        borderRadius: borderRadius,
      ),
    );
  }
}
