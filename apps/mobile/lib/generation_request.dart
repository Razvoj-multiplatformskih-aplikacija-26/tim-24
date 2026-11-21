import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app_connection.dart';

class AssetGenerationButton extends StatefulWidget {
  const AssetGenerationButton({
    super.key,
    required this.asset,
    this.disabled = false,
  });
  final Asset asset;
  final bool disabled;
  @override
  State<AssetGenerationButton> createState() => _AssetGenerationButtonState();
}

class _AssetGenerationButtonState extends State<AssetGenerationButton> {
  bool busy = false;
  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await requestAssetGeneration(context, widget.asset);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy || widget.disabled ? null : submit,
    icon: busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.auto_awesome),
    label: Text(
      busy
          ? 'Priprema zahteva…'
          : widget.asset.lifecycle == AssetLifecycle.failed
          ? 'Pokušaj ponovo'
          : 'Zatraži generisanje',
    ),
  );
}

/// A retry is explicit: it keeps the previous input and model unless changed.
Future<void> requestAssetGeneration(BuildContext context, Asset asset) async {
  final workflows = StudioConnection.maybeOf(context)!.workflows;
  if (workflows.supportsSamples) {
    try {
      await workflows.generate(
        asset,
        idempotencyKey: '${asset.id.value}-${asset.revision}-generation',
      );
    } on DomainException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error.error))));
      }
    }
    if (context.mounted) context.read<AssetBloc>().add(const LoadAssets());
    return;
  }
  final prompt = TextEditingController(text: asset.description);
  try {
    final capabilities = await workflows.capabilities();
    final history = await workflows.generationHistory(asset.id);
    if (!context.mounted) return;
    final previous = (history['jobs'] as List? ?? [])
        .whereType<Map>()
        .firstOrNull;
    final models = (capabilities['generationModels'] as List? ?? [])
        .whereType<Map>()
        .where((model) => model['available'] != false)
        .toList();
    if (capabilities['demo'] != true && models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generisanje trenutno nije dostupno. Pokušaj kasnije.'),
        ),
      );
      return;
    }
    var provider =
        previous?['modelProvider'] ??
        previous?['provider'] ??
        capabilities['defaultModel'] ??
        'spar3d';
    if (models.isNotEmpty && !models.any((model) => model['id'] == provider)) {
      provider = models.first['id'];
    }
    var textInput = previous?['inputType'] == 'text_to_3d';
    final previousPrompt = previous?['sourcePrompt'];
    if (previousPrompt is String && previousPrompt.isNotEmpty) {
      prompt.text = previousPrompt;
    }
    final seed = previous?['seed'] is int ? previous!['seed'] as int : 42;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Generisanje 3D modela'),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (models.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: provider as String,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'AI model'),
                    items: [
                      for (final model in models)
                        DropdownMenuItem(
                          value: model['id'] as String,
                          child: Text(
                            model['label'] as String? ?? model['id'] as String,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => provider = value!),
                  ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Generisanje iz teksta'),
                  subtitle: const Text('Qwen priprema referentnu sliku.'),
                  value: textInput,
                  onChanged: capabilities['textTo3d'] == true
                      ? (value) => setState(() => textInput = value)
                      : null,
                ),
                if (textInput)
                  TextField(
                    controller: prompt,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Opis objekta',
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                else
                  const Text(
                    'Koristi se sačuvana referentna slika. Ako je nema, prvo je postavi u detaljima modela.',
                  ),
                const SizedBox(height: 12),
                const Text('Novi pokušaj troši jedno mesto u dnevnoj kvoti.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: textInput && prompt.text.trim().runes.length < 3
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Pokreni generisanje'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !context.mounted) return;
    await workflows.generate(
      asset,
      idempotencyKey:
          '${asset.id.value}-${asset.revision}-$provider-${textInput ? 'text' : 'image'}-$seed',
      inputType: textInput ? 'text_to_3d' : 'image_to_3d',
      sourcePrompt: textInput ? prompt.text.trim() : null,
      modelProvider: capabilities['demo'] == true ? null : provider as String,
      seed: seed,
    );
    if (context.mounted) context.read<AssetBloc>().add(const LoadAssets());
  } on DomainException catch (error) {
    if (context.mounted) {
      context.read<AssetBloc>().add(const LoadAssets());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(error.error))));
    }
  } finally {
    prompt.dispose();
  }
}
