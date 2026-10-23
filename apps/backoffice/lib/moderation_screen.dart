import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'memory_moderation_repository.dart';
import 'live_backoffice.dart';
import 'studio_theme.dart';
import 'submission_preview.dart';
import 'submission_metadata.dart';

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});
  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  AssetId? selected;
  String query = '';
  AssetLifecycle? filter;
  bool ascending = true;
  final focus = FocusNode(debugLabel: 'Moderation records');
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  List<Asset> filtered(AssetState state) {
    final records = state.assets
        .where(
          (a) =>
              a.title.toLowerCase().contains(query.toLowerCase()) &&
              (filter == null || a.lifecycle == filter),
        )
        .toList();
    records.sort(
      (a, b) =>
          ascending ? a.title.compareTo(b.title) : b.title.compareTo(a.title),
    );
    return records;
  }

  Asset? selection(AssetState state) {
    final matches = state.assets.where((a) => a.id == selected);
    return matches.isEmpty ? null : matches.first;
  }

  void move(int delta) {
    final records = filtered(context.read<AssetBloc>().state);
    if (records.isEmpty) {
      return;
    }
    final index = records.indexWhere((a) => a.id == selected);
    setState(
      () => selected = records[(index + delta).clamp(0, records.length - 1)].id,
    );
  }

  void approve() {
    final state = context.read<AssetBloc>().state;
    final asset = selection(state);
    if (asset == null ||
        state.busy ||
        asset.lifecycle != AssetLifecycle.pendingReview) {
      return;
    }
    context.read<AssetBloc>().add(
      TransitionAsset(
        asset.id,
        AssetLifecycle.published,
        baseRevision: asset.revision,
        idempotencyKey: '${asset.id.value}-${asset.revision}-approve',
      ),
    );
  }

  Future<void> reject() async {
    final state = context.read<AssetBloc>().state;
    final asset = selection(state);
    if (asset == null ||
        state.busy ||
        asset.lifecycle != AssetLifecycle.pendingReview) {
      return;
    }
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odbij javnu prijavu'),
        content: SizedBox(
          width: 430,
          child: Form(
            key: form,
            child: TextFormField(
              autofocus: true,
              controller: controller,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Razlog odbijanja'),
              validator: (value) {
                final validation = validateTransition(
                  asset,
                  AssetLifecycle.rejected,
                  MemoryModerationRepository.actor,
                  reason: value,
                );
                return validation.isValid
                    ? null
                    : errorMessage(validation.error!);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Odbij prijavu'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      context.read<AssetBloc>().add(
        TransitionAsset(
          asset.id,
          AssetLifecycle.rejected,
          baseRevision: asset.revision,
          reason: controller.text.trim(),
          idempotencyKey: '${asset.id.value}-${asset.revision}-reject',
        ),
      );
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<AssetBloc, AssetState>(
    listener: (context, state) {
      if (state.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(state.error!))));
      }
    },
    builder: (context, state) {
      final repository = context.read<AssetRepository>();
      final stats = repository is ApiAssetRepository
          ? repository.moderationStats
          : const <String, dynamic>{};
      final records = filtered(state);
      selected ??=
          state.assets
              .where((a) => a.lifecycle == AssetLifecycle.pendingReview)
              .firstOrNull
              ?.id ??
          state.assets.firstOrNull?.id;
      final asset = selection(state);
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              approve,
          const SingleActivator(LogicalKeyboardKey.backspace, control: true):
              reject,
          const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
              context.read<AssetBloc>().add(const LoadAssets()),
        },
        child: Focus(
          autofocus: true,
          focusNode: focus,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent ||
                (FocusManager.instance.primaryFocus?.context?.widget
                        is EditableText ||
                    FocusManager.instance.primaryFocus?.context
                            ?.findAncestorWidgetOfExactType<EditableText>() !=
                        null)) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              move(1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              move(-1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Row(
                children: [
                  Icon(Icons.view_in_ar_rounded, color: accent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'hedrion',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(width: 18),
                  Text(
                    'BACKOFFICE',
                    style: TextStyle(
                      color: muted,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Chip(
                    avatar: Icon(Icons.shield_outlined, size: 16),
                    label: Text(
                      BackofficeConnection.maybeOf(context)?.api == null
                          ? 'Moderator · KT1'
                          : 'Moderator',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Osveži (Ctrl+R)',
                  onPressed: () =>
                      context.read<AssetBloc>().add(const LoadAssets()),
                  icon: const Icon(Icons.refresh),
                ),
                if (BackofficeConnection.maybeOf(context)?.api != null)
                  IconButton(
                    tooltip: 'Odjavi se',
                    onPressed: BackofficeConnection.maybeOf(context)?.onLogout,
                    icon: const Icon(Icons.logout),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Demonstracione komande',
                  onSelected: (value) {
                    final repository = context.read<AssetRepository>();
                    if (repository is! MemoryModerationRepository) {
                      return;
                    }
                    if (value == 'fail') {
                      repository.failNext = true;
                    } else {
                      repository.reset();
                    }
                    context.read<AssetBloc>().add(const LoadAssets());
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'fail',
                      child: Text('Izazovi grešku sledećeg zahteva'),
                    ),
                    PopupMenuItem(
                      value: 'reset',
                      child: Text('Vrati demonstracione podatke'),
                    ),
                  ],
                ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zajednica počinje kvalitetom.',
                        style: TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pregledaj modele i odluči šta ulazi u javnu biblioteku.',
                        style: TextStyle(color: muted),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 14,
                        runSpacing: 10,
                        children: [
                          _metric(
                            'NA PROVERI',
                            state.assets
                                .where(
                                  (a) =>
                                      a.lifecycle ==
                                      AssetLifecycle.pendingReview,
                                )
                                .length,
                            const Color(0xffc4b0ff),
                          ),
                          _metric(
                            'OBJAVLJENO',
                            state.assets
                                .where(
                                  (a) =>
                                      a.lifecycle == AssetLifecycle.published,
                                )
                                .length,
                            const Color(0xff74ddbe),
                          ),
                          _metric(
                            'ODBIJENO',
                            state.assets
                                .where(
                                  (a) => a.lifecycle == AssetLifecycle.rejected,
                                )
                                .length,
                            const Color(0xffffa49e),
                          ),
                          if (stats.isNotEmpty) ...[
                            _metric(
                              'DANAS PREGLEDANO',
                              stats['reviewedToday'] ?? 0,
                              accent,
                            ),
                            _metric(
                              'ODOBRENJA',
                              '${(((stats['approvalRate'] as num?) ?? 0) * 100).toStringAsFixed(0)}%',
                              const Color(0xff74ddbe),
                            ),
                            _metric(
                              'AKTIVNI POSLOVI',
                              stats['activeJobs'] ?? 0,
                              accent,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Pretraži prijave po nazivu...',
                        ),
                        onChanged: (v) => setState(() => query = v),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Sva stanja'),
                            selected: filter == null,
                            onSelected: (_) => setState(() => filter = null),
                          ),
                          for (final s in [
                            AssetLifecycle.pendingReview,
                            AssetLifecycle.published,
                            AssetLifecycle.rejected,
                          ])
                            FilterChip(
                              label: Text(lifecycleLabel(s)),
                              selected: filter == s,
                              onSelected: (v) =>
                                  setState(() => filter = v ? s : null),
                            ),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => ascending = !ascending),
                            icon: Icon(
                              ascending
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              size: 16,
                            ),
                            label: Text(ascending ? 'Naziv A–Ž' : 'Naziv Ž–A'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (state.busy) const LinearProgressIndicator(minHeight: 2),
                if (state.error != null && state.assets.isNotEmpty)
                  MaterialBanner(
                    content: Text(errorMessage(state.error!)),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            context.read<AssetBloc>().add(const LoadAssets()),
                        child: const Text('Pokušaj ponovo'),
                      ),
                    ],
                  ),
                Expanded(child: _body(context, state, records, asset)),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 10, 24, 14),
                  child: Text(
                    '↑ ↓ izbor   ·   Ctrl+Enter odobri   ·   Ctrl+Backspace odbij   ·   Tab fokus',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _metric(String title, Object count, Color color) => Container(
    width: 180,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xff2a3249)),
    ),
    child: Row(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _body(
    BuildContext context,
    AssetState state,
    List<Asset> records,
    Asset? asset,
  ) {
    if ((state.status == AssetLoadStatus.loading && state.assets.isEmpty) ||
        state.status == AssetLoadStatus.initial) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == AssetLoadStatus.failure && state.assets.isEmpty) {
      return MessageState(
        icon: Icons.cloud_off,
        title: 'Prijave nisu učitane',
        description: errorMessage(state.error!),
        action: FilledButton.icon(
          onPressed: () => context.read<AssetBloc>().add(const LoadAssets()),
          icon: const Icon(Icons.refresh),
          label: const Text('Pokušaj ponovo'),
        ),
      );
    }
    if (records.isEmpty) {
      return const MessageState(
        icon: Icons.inbox_outlined,
        title: 'Nema prijava za ovaj izbor',
        description: 'Promenite pretragu ili filter stanja.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1050;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Card(
                    child: SingleChildScrollView(
                      child: DataTable(
                        showCheckboxColumn: false,
                        columnSpacing: 20,
                        headingRowColor: const WidgetStatePropertyAll(
                          Color(0xff1b2234),
                        ),
                        columns: const [
                          DataColumn(label: Text('MODEL')),
                          DataColumn(label: Text('STATUS')),
                          DataColumn(label: Text('KATEGORIJA')),
                        ],
                        rows: [
                          for (final record in records)
                            DataRow(
                              selected: record.id == selected,
                              color: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? accent.withValues(alpha: .1)
                                    : null,
                              ),
                              onSelectChanged: (_) =>
                                  setState(() => selected = record.id),
                              cells: [
                                DataCell(
                                  _RecordFocus(
                                    selected: record.id == selected,
                                    onSelected: () =>
                                        setState(() => selected = record.id),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.view_in_ar_outlined,
                                          size: 20,
                                          color: record.id == selected
                                              ? accent
                                              : muted,
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 170,
                                          child: Text(
                                            record.title,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(StatusBadge(record.lifecycle)),
                                DataCell(
                                  Text(
                                    record.category,
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                SizedBox(
                  width: 330,
                  child: _inspector(context, asset, state.busy),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          children: [
            if (asset != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.radio_button_checked,
                      color: accent,
                    ),
                    title: Text(asset.title),
                    subtitle: const Text('Izabrani model'),
                    trailing: StatusBadge(asset.lifecycle),
                  ),
                ),
              ),
            for (final record in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _RecordFocus(
                  selected: record.id == selected,
                  onSelected: () => setState(() => selected = record.id),
                  child: ListTile(
                    selected: record.id == selected,
                    selectedTileColor: accent.withValues(alpha: .1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.view_in_ar_outlined),
                    title: Text(record.title),
                    subtitle: Text(
                      record.category,
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    trailing: StatusBadge(record.lifecycle),
                    onTap: () => setState(() => selected = record.id),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _inspector(context, asset, state.busy),
          ],
        );
      },
    );
  }

  Widget _inspector(BuildContext context, Asset? asset, bool busy) {
    if (asset == null) {
      return const Card(
        child: MessageState(
          icon: Icons.touch_app_outlined,
          title: 'Izaberi model',
          description: 'Detalji prijave pojaviće se ovde.',
        ),
      );
    }
    final repository = context.read<AssetRepository>();
    final submission = repository is ApiAssetRepository
        ? repository.submissionsByAssetId[asset.id.value]
        : null;
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'PREGLED PRIJAVE',
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
                StatusBadge(asset.lifecycle),
              ],
            ),
            const SizedBox(height: 18),
            SubmissionPreview(asset: asset),
            const SizedBox(height: 18),
            Text(
              asset.title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              asset.description,
              style: const TextStyle(color: muted, height: 1.6, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text(
              'Kategorija: ${asset.category}\nRevizija: ${asset.revision}\nLicenca: ${asset.license == AssetLicense.ccBy
                  ? 'CC BY 4.0'
                  : asset.license == AssetLicense.cc0
                  ? 'CC0'
                  : 'Sva prava zadržana'}',
              style: const TextStyle(color: muted, height: 1.8, fontSize: 12),
            ),
            if (asset.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Oznake: ${asset.tags.join(', ')}',
                  style: const TextStyle(color: muted),
                ),
              ),
            if (submission != null) SubmissionMetadata(submission: submission),
            if (submission == null)
              const Text(
                'Autor: demonstracioni kreator',
                style: TextStyle(color: muted),
              ),
            const SizedBox(height: 12),
            if (asset.rejectionReason != null)
              Text(
                'Razlog: ${asset.rejectionReason}',
                style: const TextStyle(color: Color(0xffffa49e), fontSize: 12),
              ),
            const SizedBox(height: 18),
            if (asset.lifecycle == AssetLifecycle.pendingReview) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : approve,
                  icon: const Icon(Icons.check),
                  label: const Text('Odobri objavljivanje'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : reject,
                  icon: const Icon(Icons.close),
                  label: const Text('Odbij uz razlog'),
                ),
              ),
            ] else
              const Text(
                'Ovaj zapis trenutno ne čeka odluku moderatora.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            const SizedBox(height: 14),
            Text(
              BackofficeConnection.maybeOf(context)?.api == null
                  ? 'Ilustracija u KT1 režimu. Privatni rezultat ostaje sačuvan i nakon odbijanja prijave.'
                  : 'Verzija podneta na proveru. Pregled slike rezultata; 3D viewport nije aktivan.',
              style: TextStyle(color: muted, fontSize: 10, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordFocus extends StatefulWidget {
  const _RecordFocus({
    required this.selected,
    required this.onSelected,
    required this.child,
  });
  final bool selected;
  final VoidCallback onSelected;
  final Widget child;
  @override
  State<_RecordFocus> createState() => _RecordFocusState();
}

class _RecordFocusState extends State<_RecordFocus> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    onShowFocusHighlight: (v) => setState(() => focused = v),
    onFocusChange: (v) {
      if (v) {
        widget.onSelected();
      }
    },
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onSelected();
          return null;
        },
      ),
    },
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: focused ? accent : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: widget.child,
    ),
  );
}
