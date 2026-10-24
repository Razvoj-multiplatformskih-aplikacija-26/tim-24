import 'dart:typed_data';
import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'app_connection.dart';
import 'asset_preview.dart';
import 'generation_setup.dart';
import 'mesh_scene.dart';
import 'model_viewport.dart';
import 'studio_chrome.dart';
import 'studio_theme.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    this.flow = GenerationFlow.textTo3d,
    this.gateway = const LocalPreviewGateway(),
  });
  final GenerationFlow flow;
  final GenerationGateway gateway;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final prompt = TextEditingController();
  final search = TextEditingController();
  final prompts = <GenerationFlow, String>{};
  late GenerationFlow flow = widget.flow;
  SampleModel selected = SampleModel.sentinel;
  ViewportMaterial material = ViewportMaterial.studio;
  final previews = <GenerationPreview>[];
  GenerationPreview? activePreview;
  Asset? activeAsset;
  late String model = widget.flow == GenerationFlow.textToImage
      ? 'hedrion-image'
      : 'hedrion-3d';
  String quality = 'Standard';
  String? imageName, error;
  Uint8List? imageBytes;
  bool pose = false, enhance = true, textured = true, grid = false;
  bool generating = false, saving = false, mine = false;
  int seed = 42, resetKey = 0, mobileTab = 0;

  @override
  void didUpdateWidget(WorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flow != widget.flow) _changeFlow(widget.flow);
  }

  @override
  void dispose() {
    prompt.dispose();
    search.dispose();
    super.dispose();
  }

  void _changeFlow(GenerationFlow value) {
    prompts[flow] = prompt.text;
    setState(() {
      flow = value;
      prompt.text = prompts[value] ?? '';
      error = null;
      model = value == GenerationFlow.textToImage
          ? 'hedrion-image'
          : 'hedrion-3d';
      activeAsset = null;
    });
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        requestFullMetadata: false,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 10000000) throw StateError('Izaberi sliku do 10 MB.');
      // Existing upload API accepts PNG and JPEG.
      final png =
          bytes.length >= 8 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78;
      final jpeg = bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216;
      if (!png && !jpeg) throw StateError('Izaberi PNG ili JPEG sliku.');
      if (mounted) {
        setState(() {
          imageBytes = bytes;
          imageName = file.name;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'Slika nije dostupna. Pokušaj ponovo.',
        );
      }
    }
  }

  GenerationSetup _setup() => GenerationSetup(
    flow: flow,
    prompt: prompt.text.trim(),
    modelId: model,
    lowPoly: quality == 'Low Poly',
    textured: textured,
    pose: pose,
    enhance: enhance,
    seed: seed,
    imageName: imageName,
    imageBytes: imageBytes,
  );

  bool _validate() {
    if (flow == GenerationFlow.imageTo3d && imageBytes == null) {
      setState(() {
        error = 'Dodaj referentnu sliku da nastaviš.';
        mobileTab = 0;
      });
      return false;
    }
    if (flow != GenerationFlow.imageTo3d && prompt.text.trim().length < 3) {
      setState(() {
        error = 'Opiši svoju ideju u najmanje 3 znaka.';
        mobileTab = 0;
      });
      return false;
    }
    return true;
  }

  Future<void> _generate() async {
    if (!_validate()) return;
    final setup = _setup();
    setState(() {
      generating = true;
      error = null;
    });
    try {
      final result = await widget.gateway.preview(setup);
      if (!mounted) return;
      setState(() {
        previews.insert(0, result);
        activePreview = result;
        selected = result.sample;
        material = setup.textured
            ? ViewportMaterial.studio
            : ViewportMaterial.clay;
        activeAsset = null;
        generating = false;
        mobileTab = 1;
        mine = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demo pregled je spreman. AI generisanje ćemo povezati u sledećoj fazi.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          generating = false;
          error = 'Pregled nije uspeo. Pokušaj ponovo.';
        });
      }
    }
  }

  Future<void> _saveDraft() async {
    if (!_validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final setup = _setup();
      // Image concepts stay in this session until an image asset type is added.
      if (setup.flow == GenerationFlow.textToImage) {
        setState(() {
          error =
              'Image koncept je u istoriji sesije. Za privatni 3D nacrt izaberi Text to 3D ili Image to 3D.';
          mobileTab = 0;
        });
        return;
      }
      var name = setup.prompt.isEmpty
          ? setup.imageName ?? 'Novi 3D model'
          : setup.prompt.split('\n').first;
      if (name.length > 60) name = name.substring(0, 60);
      final repository = context.read<AssetRepository>();
      final api = StudioConnection.maybeOf(context)?.client;
      final asset = await repository.createAsset(
        AssetDraft(title: name, description: setup.prompt),
      );
      if (api != null &&
          setup.flow == GenerationFlow.imageTo3d &&
          setup.imageBytes != null) {
        try {
          await api.uploadImage(
            asset.id,
            setup.imageBytes!,
            mime: setup.imageBytes![0] == 137 ? 'image/png' : 'image/jpeg',
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Nacrt je sačuvan. Dodaj referentnu sliku ponovo u detaljima modela.',
                ),
              ),
            );
          }
        }
      }
      if (mounted) {
        context.read<AssetBloc>().add(const LoadAssets());
        context.go('/assets/${asset.id.value}');
      }
    } on DomainException catch (e) {
      if (mounted) setState(() => error = errorMessage(e.error));
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Nacrt nije sačuvan. Pokušaj ponovo.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => StudioShell(
    title: 'Workspace',
    activeTool: flow == GenerationFlow.textToImage ? 'image' : 'model',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final hasAssets = constraints.maxWidth >= 1120;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 306, child: _generator()),
                const SizedBox(width: 12),
                Expanded(child: _viewport(showAssetsButton: !hasAssets)),
                if (hasAssets) ...[
                  const SizedBox(width: 12),
                  SizedBox(width: 284, child: _assets()),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _segments(
                ['Create', 'Preview', 'Assets'],
                mobileTab,
                (i) => setState(() => mobileTab = i),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: switch (mobileTab) {
                  0 => _generator(),
                  1 => _viewport(),
                  _ => _assets(),
                },
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _generator() => Container(
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
          child: Row(
            children: [
              const Text(
                'New creation',
                style: TextStyle(
                  color: accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Novi unos',
                onPressed: generating || saving
                    ? null
                    : () => setState(() {
                        prompt.clear();
                        imageBytes = null;
                        imageName = null;
                        error = null;
                        activePreview = null;
                        activeAsset = null;
                      }),
                icon: const Icon(
                  Icons.add_box_outlined,
                  size: 21,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _segments(
                  ['3D Model', 'Image'],
                  flow == GenerationFlow.textToImage ? 1 : 0,
                  (i) => _changeFlow(
                    i == 1
                        ? GenerationFlow.textToImage
                        : GenerationFlow.textTo3d,
                  ),
                ),
                const SizedBox(height: 15),
                if (flow != GenerationFlow.textToImage) ...[
                  _segments(
                    ['Text to 3D', 'Image to 3D'],
                    flow == GenerationFlow.imageTo3d ? 1 : 0,
                    (i) => _changeFlow(
                      i == 1
                          ? GenerationFlow.imageTo3d
                          : GenerationFlow.textTo3d,
                    ),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  const SizedBox(height: 5),
                  const Text(
                    'Text to Image',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                ],
                if (flow == GenerationFlow.imageTo3d) ...[
                  _uploadBox(),
                  const SizedBox(height: 20),
                ],
                Row(
                  children: [
                    Text(
                      flow == GenerationFlow.imageTo3d
                          ? 'Prompt (optional)'
                          : 'Prompt',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Isprobaj primer prompta',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(
                        () => prompt.text =
                            'A friendly scout robot with ivory armor, a glowing lime visor and warm orange details. Game-ready, stylized hard-surface character.',
                      ),
                      icon: const Icon(
                        Icons.casino_outlined,
                        size: 17,
                        color: muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('generation-prompt'),
                  controller: prompt,
                  minLines: 6,
                  maxLines: 9,
                  maxLength: 800,
                  style: const TextStyle(fontSize: 12, height: 1.7),
                  decoration: const InputDecoration(
                    hintText:
                        'Describe your idea…\n\nA character, a tiny world, something that doesn’t exist yet.',
                    contentPadding: EdgeInsets.all(14),
                    counterStyle: TextStyle(fontSize: 10, color: muted),
                  ),
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                ),
                const SizedBox(height: 14),
                _label(
                  'AI Model',
                  trailing: Tooltip(
                    message: 'Izbor modela je priprema za buduće providere.',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PREVIEW',
                        style: TextStyle(
                          color: accent,
                          fontSize: 8,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  key: ValueKey('model-$flow-$model'),
                  initialValue: model,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xffeceee7),
                  ),
                  items: flow == GenerationFlow.textToImage
                      ? const [
                          DropdownMenuItem(
                            value: 'hedrion-image',
                            child: Text('Hedrion Image · Standard'),
                          ),
                          DropdownMenuItem(
                            value: 'hedrion-image-fast',
                            child: Text('Hedrion Image · Fast'),
                          ),
                        ]
                      : const [
                          DropdownMenuItem(
                            value: 'hedrion-3d',
                            child: Text('Hedrion 3D · Standard'),
                          ),
                          DropdownMenuItem(
                            value: 'hedrion-3d-fast',
                            child: Text('Hedrion 3D · Fast'),
                          ),
                        ],
                  onChanged: (v) => setState(() => model = v!),
                ),
                const SizedBox(height: 20),
                if (flow != GenerationFlow.textToImage) ...[
                  _label('Model type'),
                  const SizedBox(height: 10),
                  _segments(
                    ['Standard', 'Low Poly'],
                    quality == 'Standard' ? 0 : 1,
                    (i) => setState(
                      () => quality = i == 0 ? 'Standard' : 'Low Poly',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _toggle(
                    'Generate texture',
                    textured,
                    (v) => setState(() => textured = v),
                  ),
                  _toggle('A / T Pose', pose, (v) => setState(() => pose = v)),
                ],
                if (flow == GenerationFlow.imageTo3d)
                  _toggle(
                    'Image enhancement',
                    enhance,
                    (v) => setState(() => enhance = v),
                  ),
                const SizedBox(height: 6),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 10),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text(
                    'Advanced settings',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  children: [
                    TextFormField(
                      key: const Key('generation-seed'),
                      initialValue: '$seed',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Seed',
                        helperText: 'Sačuvan uz demo zahtev.',
                      ),
                      onChanged: (v) => seed = int.tryParse(v) ?? 42,
                    ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      key: const Key('generation-error'),
                      style: const TextStyle(
                        color: Color(0xffffb6a5),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
          decoration: const BoxDecoration(
            color: Color(0xff272824),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: accent),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'Local preview · No credits needed',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 43,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [accent, Color(0xffdeee92), Color(0xffff9dcb)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: FilledButton.icon(
                  key: const Key('generate-button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color(0xff171b12),
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor: const Color(0xff454b3d),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: generating || saving ? null : _generate,
                  icon: generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 19),
                  label: Text(
                    generating ? 'Creating preview…' : 'Generate',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Demo only · AI connection coming next',
                style: TextStyle(fontSize: 9, color: muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _uploadBox() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        key: const Key('reference-upload'),
        onTap: _pickImage,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 170,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xff191b18),
            border: Border.all(color: const Color(0xff45493d)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: imageBytes == null
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 31,
                      color: muted,
                    ),
                    SizedBox(height: 13),
                    Text(
                      'Click to upload an image',
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'PNG, JPG · up to 10 MB',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                )
              : Image.memory(
                  imageBytes!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, stack) =>
                      const Center(child: Text('Slika nije čitljiva.')),
                ),
        ),
      ),
      if (imageName != null)
        Row(
          children: [
            Expanded(
              child: Text(
                imageName!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
            IconButton(
              tooltip: 'Ukloni sliku',
              onPressed: () => setState(() {
                imageBytes = null;
                imageName = null;
              }),
              icon: const Icon(Icons.close, size: 15),
            ),
          ],
        ),
    ],
  );

  Widget _viewport({bool showAssetsButton = false}) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xff191b18),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: studioLine),
    ),
    child: Column(
      children: [
        Container(
          height: 52,
          color: const Color(0xff1c1e1b),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _tool(
                Icons.desktop_windows_outlined,
                'Reset view',
                () => setState(() => resetKey++),
              ),
              const SizedBox(
                height: 18,
                child: VerticalDivider(color: studioLine),
              ),
              _tool(
                Icons.blur_circular_outlined,
                'Studio material',
                () => setState(() => material = ViewportMaterial.studio),
                active: material == ViewportMaterial.studio,
              ),
              _tool(
                Icons.circle_outlined,
                'Clay material',
                () => setState(() => material = ViewportMaterial.clay),
                active: material == ViewportMaterial.clay,
              ),
              _tool(
                Icons.language_rounded,
                'Wireframe',
                () => setState(() => material = ViewportMaterial.wireframe),
                active: material == ViewportMaterial.wireframe,
              ),
              _tool(
                Icons.grid_4x4_outlined,
                'Toggle grid',
                () => setState(() => grid = !grid),
                active: grid,
              ),
              const Spacer(),
              if (showAssetsButton)
                _tool(
                  Icons.collections_outlined,
                  'My generations',
                  () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => SizedBox(
                      height: MediaQuery.sizeOf(context).height * .8,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _assets(),
                      ),
                    ),
                  ),
                ),
              _tool(
                Icons.fullscreen,
                'Fullscreen preview',
                () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog.fullscreen(
                    backgroundColor: const Color(0xff191b18),
                    child: Stack(
                      children: [
                        Positioned.fill(child: _scene()),
                        Positioned(
                          top: 18,
                          right: 18,
                          child: IconButton(
                            tooltip: 'Zatvori pregled',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, .1),
                      colors: [Color(0xff34372f), Color(0xff191b18)],
                      radius: .75,
                    ),
                  ),
                  child: _scene(),
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xd910120f),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeAsset != null
                            ? 'Asset preview'
                            : 'Topology        Polygon',
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        activeAsset != null
                            ? '2D thumbnail'
                            : 'Faces             ${SampleScene(selected).faces.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xffd7dbd0),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        activeAsset == null ? 'LOCAL SAMPLE' : 'SAVED ASSET',
                        style: const TextStyle(
                          fontSize: 8,
                          letterSpacing: 1.4,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xff48543a)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    flow == GenerationFlow.textToImage
                        ? 'IMAGE CONCEPT'
                        : 'PERSPECTIVE',
                    style: const TextStyle(
                      fontSize: 8,
                      color: muted,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              if (generating)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x99141512),
                    child: Center(
                      child: CircularProgressIndicator(color: accent),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 15,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xee2a2d25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xff42483b)),
                    ),
                    child: Wrap(
                      spacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(
                            () => material = material == ViewportMaterial.clay
                                ? ViewportMaterial.studio
                                : ViewportMaterial.clay,
                          ),
                          style: TextButton.styleFrom(foregroundColor: accent),
                          icon: const Icon(Icons.texture, size: 17),
                          label: const Text(
                            'Material',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        _tool(
                          Icons.restart_alt,
                          'Reset view',
                          () => setState(() => resetKey++),
                        ),
                        if (activeAsset != null)
                          FilledButton(
                            onPressed: () =>
                                context.go('/assets/${activeAsset!.id.value}'),
                            child: const Text('Detalji'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: generating || saving ? null : _saveDraft,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            icon: const Icon(
                              Icons.bookmark_add_outlined,
                              size: 16,
                            ),
                            label: Text(
                              saving ? 'Saving…' : 'Sačuvaj nacrt',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          color: const Color(0xff151713),
          child: Row(
            children: [
              const Icon(Icons.touch_app_outlined, size: 13, color: muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  activeAsset != null
                      ? 'Saved preview · Open details for GLB'
                      : flow == GenerationFlow.textToImage
                      ? '2D concept · Local sample'
                      : 'Drag to orbit · Scroll to zoom',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
              ),
              TextButton(
                onPressed: activePreview == null
                    ? null
                    : () => _reuse(activePreview!),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 30),
                ),
                child: const Text(
                  '↖ Reuse prompt',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _scene() {
    if (activeAsset != null) {
      return Center(child: StudioPreview(asset: activeAsset!, height: 420));
    }
    if (flow == GenerationFlow.textToImage) {
      return Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            margin: const EdgeInsets.all(35),
            decoration: BoxDecoration(
              color: const Color(0xff293128),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xff4d5c3d)),
            ),
            child: ModelViewport(
              model: selected,
              interactive: false,
              material: material,
            ),
          ),
        ),
      );
    }
    return ModelViewport(
      model: selected,
      material: material,
      showGrid: grid,
      resetKey: resetKey,
    );
  }

  Widget _assets() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xff242b1c),
          border: Border.all(color: const Color(0xff3c4a2b)),
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome, size: 18, color: accent),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Make room for imagination.',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Explore the studio. Your next dimension is one idea away.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: Color(0xffb7c0ab),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 17),
      TextField(
        key: const Key('workspace-search'),
        controller: search,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 11),
        decoration: const InputDecoration(
          hintText: 'Search my generations',
          prefixIcon: Icon(Icons.search, size: 18),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        ),
      ),
      const SizedBox(height: 12),
      _segments(
        ['Session', 'My Assets'],
        mine ? 1 : 0,
        (i) => setState(() => mine = i == 1),
      ),
      const SizedBox(height: 16),
      Expanded(
        child: BlocBuilder<AssetBloc, AssetState>(
          builder: (context, state) {
            final q = search.text.toLowerCase();
            if (mine) {
              if (state.status == AssetLoadStatus.loading &&
                  state.assets.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.status == AssetLoadStatus.failure &&
                  state.assets.isEmpty) {
                return MessageState(
                  icon: Icons.cloud_off,
                  title: 'Modeli nisu učitani',
                  description: 'Pokušaj ponovo.',
                  action: TextButton(
                    onPressed: () =>
                        context.read<AssetBloc>().add(const LoadAssets()),
                    child: const Text('Osveži'),
                  ),
                );
              }
              final assets = state.assets
                  .where((a) => a.title.toLowerCase().contains(q))
                  .toList();
              if (assets.isEmpty) {
                return const Center(
                  child: Text(
                    'Nema modela za ovaj izbor',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                );
              }
              return ListView.separated(
                itemCount: assets.length,
                separatorBuilder: (_, i) => const SizedBox(height: 12),
                itemBuilder: (context, i) => InkWell(
                  onTap: () => setState(() {
                    activeAsset = assets[i];
                    mobileTab = 1;
                  }),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: activeAsset?.id == assets[i].id
                            ? accent
                            : studioLine,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          assets[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        StudioPreview(asset: assets[i], height: 150),
                        const SizedBox(height: 8),
                        StatusBadge(assets[i].lifecycle),
                      ],
                    ),
                  ),
                ),
              );
            }
            final items = previews
                .where((p) => p.title.toLowerCase().contains(q))
                .toList();
            return ListView(
              children: [
                if (items.isNotEmpty) ...[
                  const Text(
                    'THIS SESSION',
                    style: TextStyle(
                      color: muted,
                      fontSize: 9,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final preview in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _sampleCard(
                        preview.sample,
                        preview.title,
                        activePreview == preview,
                        () {
                          _reuse(preview);
                          setState(() {
                            activePreview = preview;
                            activeAsset = null;
                            selected = preview.sample;
                            mobileTab = 1;
                          });
                        },
                        badge: preview.setup.flow.label,
                      ),
                    ),
                ],
                const Text(
                  'START WITH A LITTLE INSPIRATION',
                  style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1),
                ),
                const SizedBox(height: 12),
                for (final sample in SampleModel.values.where(
                  (s) => sampleName(s).toLowerCase().contains(q),
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _sampleCard(
                      sample,
                      sampleName(sample),
                      activeAsset == null &&
                          activePreview == null &&
                          selected == sample,
                      () => setState(() {
                        selected = sample;
                        activeAsset = null;
                        activePreview = null;
                        mobileTab = 1;
                      }),
                      badge: 'EXAMPLE',
                    ),
                  ),
                if (items.isEmpty &&
                    q.isNotEmpty &&
                    !SampleModel.values.any(
                      (s) => sampleName(s).toLowerCase().contains(q),
                    ))
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No results', style: TextStyle(color: muted)),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Session previews are temporary. Save a draft to keep your idea in My Assets.',
                    style: TextStyle(color: muted, fontSize: 10, height: 1.7),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );

  Widget _sampleCard(
    SampleModel sample,
    String name,
    bool active,
    VoidCallback onTap, {
    required String badge,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(13),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: active ? accent : const Color(0xff292c25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xffd8dbd2),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 17, color: muted),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 174,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const RadialGradient(
                colors: [Color(0xff3a3f32), Color(0xff232620)],
                radius: .8,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ModelViewport(model: sample, interactive: false),
                ),
                Positioned(
                  left: 9,
                  top: 9,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff1a1f14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 8,
                        color: accent,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  void _reuse(GenerationPreview preview) {
    _changeFlow(preview.setup.flow);
    setState(() {
      prompt.text = preview.setup.prompt;
      model = preview.setup.modelId;
      quality = preview.setup.lowPoly ? 'Low Poly' : 'Standard';
      textured = preview.setup.textured;
      pose = preview.setup.pose;
      enhance = preview.setup.enhance;
      seed = preview.setup.seed;
      imageName = preview.setup.imageName;
      imageBytes = preview.setup.imageBytes;
      mobileTab = 0;
    });
  }

  Widget _segments(
    List<String> labels,
    int selected,
    ValueChanged<int> onChanged,
  ) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xff161814),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: InkWell(
              onTap: generating || saving ? null : () => onChanged(i),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == selected
                      ? const Color(0xff343d26)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: i == selected ? accent : muted,
                    fontSize: 11,
                    fontWeight: i == selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Widget _label(String label, {Widget? trailing}) => Row(
    children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 5),
      const Icon(Icons.info_outline, size: 12, color: muted),
      const Spacer(),
      ?trailing,
    ],
  );
  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
      SizedBox(
        height: 39,
        child: Transform.scale(
          scale: .73,
          alignment: Alignment.centerRight,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: accent,
          ),
        ),
      ),
    ],
  );
  Widget _tool(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool active = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
    style: IconButton.styleFrom(
      backgroundColor: active
          ? accent.withValues(alpha: .1)
          : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
    icon: Icon(icon, size: 17, color: active ? accent : muted),
  );
}
