import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/services/ai/ai_model_catalog.dart';
import 'package:musify/services/ai/ai_tools.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/section_header.dart';

const _providerLabels = {
  'groq': 'Groq',
  'gemini': 'Gemini',
  'openrouter': 'OpenRouter',
};

const _toolLabels = {
  'search': 'Buscar músicas/playlists/artistas',
  'get_library_index': 'Ver resumo da biblioteca',
  'get_library_item': 'Abrir item da biblioteca',
  'play_song': 'Tocar música',
  'queue_action': 'Ver/editar a fila',
  'playback_control': 'Play/pause/pular',
  'like_item': 'Curtir/descurtir',
  'create_playlist': 'Criar playlist',
  'edit_playlist': 'Editar playlist',
  'offline_control': 'Baixar/remover offline',
  'get_lyrics': 'Ver letra da música',
  'get_wrapped_insights': 'Analisar seu Wrapped (gostos musicais)',
};

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Musify IA')),
      body: SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: Column(
          children: [
            const SectionHeader(
              title: 'Musify IA (experimental)',
              icon: FluentIcons.bot_24_filled,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'Recurso experimental: um assistente de IA que pode buscar, '
                'tocar e organizar sua música dentro do Musify. Teste '
                'individual - use por sua conta e risco. Requer que você '
                'configure a chave de ao menos um provedor abaixo.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: aiEnabled,
              builder: (context, enabled, _) {
                return CustomBar(
                  'Ativar Musify IA',
                  FluentIcons.sparkle_24_regular,
                  borderRadius: commonCustomBarRadiusFirst,
                  trailing: Switch(value: enabled, onChanged: setAiEnabled),
                );
              },
            ),
            ValueListenableBuilder<String>(
              valueListenable: aiName,
              builder: (context, name, _) {
                return CustomBar(
                  'Nome da IA',
                  FluentIcons.rename_24_regular,
                  description: name,
                  borderRadius: commonCustomBarRadiusLast,
                  onTap: () => _showRenameDialog(context, name),
                );
              },
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              title: 'Provedores e ordem de fallback',
              icon: FluentIcons.cloud_sync_24_regular,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'O primeiro provedor é usado por padrão. Se ele falhar '
                '(sem chave, limite de uso, erro), o Musify tenta o próximo '
                'da lista automaticamente. Arraste para reordenar.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ValueListenableBuilder<List<String>>(
              valueListenable: aiProviderOrder,
              builder: (context, order, _) {
                return ValueListenableBuilder<Map<String, Map<String, Object>>>(
                  valueListenable: aiProviders,
                  builder: (context, providers, __) {
                    return ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: order.length,
                      onReorderItem: (oldIndex, newIndex) {
                        final updated = List<String>.from(order);
                        final item = updated.removeAt(oldIndex);
                        updated.insert(newIndex, item);
                        updateAiProviderOrder(updated);
                      },
                      itemBuilder: (context, index) {
                        final providerId = order[index];
                        final config = providers[providerId];
                        final keyCount =
                            (config?['apiKeys'] as List?)?.length ?? 0;
                        final hasKey = keyCount > 0;
                        return CustomBar(
                          key: ValueKey(providerId),
                          _providerLabels[providerId] ?? providerId,
                          hasKey
                              ? FluentIcons.checkmark_circle_24_filled
                              : FluentIcons.warning_24_regular,
                          description: hasKey
                              ? '${index == 0 ? "Padrão · " : ""}${config?['model'] ?? ''}'
                                    ' · $keyCount chave(s)'
                              : 'Sem chave configurada',
                          borderRadius: index == 0
                              ? commonCustomBarRadiusFirst
                              : (index == order.length - 1
                                    ? commonCustomBarRadiusLast
                                    : BorderRadius.zero),
                          trailing: const Icon(FluentIcons.re_order_24_regular),
                          onTap: () => _showProviderDialog(context, providerId),
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              title: 'Ferramentas da IA',
              icon: FluentIcons.wrench_24_regular,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'Desative o que não quiser que a IA seja capaz de fazer.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ValueListenableBuilder<Map<String, bool>>(
              valueListenable: aiToolsEnabled,
              builder: (context, enabledMap, _) {
                return Column(
                  children: [
                    for (var i = 0; i < aiToolSpecs.length; i++)
                      CustomBar(
                        _toolLabels[aiToolSpecs[i].name] ?? aiToolSpecs[i].name,
                        FluentIcons.wrench_24_regular,
                        borderRadius: i == 0
                            ? commonCustomBarRadiusFirst
                            : (i == aiToolSpecs.length - 1
                                  ? commonCustomBarRadiusLast
                                  : BorderRadius.zero),
                        trailing: Switch(
                          value: enabledMap[aiToolSpecs[i].name] != false,
                          onChanged: (value) =>
                              setAiToolEnabled(aiToolSpecs[i].name, value),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: aiIncludeRecentlyPlayed,
              builder: (context, value, _) {
                return CustomBar(
                  'Incluir músicas recentes automaticamente',
                  FluentIcons.history_24_regular,
                  description:
                      'Não é uma tool: as últimas músicas ouvidas são '
                      'enviadas direto no contexto, sem gastar uma chamada '
                      'extra.',
                  borderRadius: BorderRadius.circular(16),
                  trailing: Switch(
                    value: value,
                    onChanged: setAiIncludeRecentlyPlayed,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nome da IA'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await setAiName(result);
    }
  }

  Future<void> _showProviderDialog(
    BuildContext context,
    String providerId,
  ) async {
    final config =
        aiProviders.value[providerId] ?? {'apiKeys': <String>[], 'model': ''};
    final existingKeys = (config['apiKeys'] as List?)?.cast<String>() ?? [];
    final keyControllers = [
      for (final key in existingKeys) TextEditingController(text: key),
      if (existingKeys.isEmpty) TextEditingController(),
    ];
    final modelController = TextEditingController(
      text: config['model']?.toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String firstNonEmptyKey() {
              for (final controller in keyControllers) {
                if (controller.text.trim().isNotEmpty) {
                  return controller.text.trim();
                }
              }
              return '';
            }

            return AlertDialog(
              title: Text(_providerLabels[providerId] ?? providerId),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chaves de API - a primeira é usada primeiro; se '
                      'falhar (ex: limite atingido), a próxima é tentada '
                      'antes de cair pro próximo provedor.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < keyControllers.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: keyControllers[i],
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: 'Chave ${i + 1}',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(FluentIcons.delete_24_regular),
                              onPressed: keyControllers.length == 1
                                  ? null
                                  : () => setDialogState(
                                      () => keyControllers.removeAt(i),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(FluentIcons.add_24_regular),
                        label: const Text('Adicionar chave'),
                        onPressed: () => setDialogState(
                          () => keyControllers.add(TextEditingController()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: modelController,
                      decoration: const InputDecoration(labelText: 'Modelo'),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(FluentIcons.arrow_sync_24_regular),
                        label: const Text('Carregar modelos disponíveis'),
                        onPressed: () async {
                          try {
                            final models = await fetchProviderModels(
                              providerId,
                              firstNonEmptyKey(),
                            );
                            if (!context.mounted) return;
                            final picked = await _showModelPicker(
                              context,
                              models,
                            );
                            if (picked != null) {
                              modelController.text = picked;
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao listar modelos: $e'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    setAiProviderKeys(
                      providerId,
                      keyControllers.map((c) => c.text.trim()).toList(),
                    );
                    setAiProviderModel(providerId, modelController.text.trim());
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _showModelPicker(BuildContext context, List<String> models) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: models.isEmpty
                ? const Center(child: Text('Nenhum modelo encontrado.'))
                : ListView.builder(
                    itemCount: models.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(models[index]),
                      onTap: () => Navigator.pop(context, models[index]),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
