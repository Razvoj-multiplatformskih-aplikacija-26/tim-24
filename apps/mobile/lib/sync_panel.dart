import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app_connection.dart';
import 'studio_theme.dart';

class SyncPanel extends StatelessWidget {
  const SyncPanel({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<AssetBloc, AssetState>(
    builder: (context, state) {
      final connection = StudioConnection.maybeOf(context);
      final offline = connection?.offline;
      if (offline == null) {
        return const SizedBox.shrink();
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        color: offline.conflicts.isNotEmpty
            ? const Color(0xff3d2533)
            : const Color(0xff1b2437),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              offline.online ? Icons.cloud_done_outlined : Icons.cloud_off,
              color: accent,
              size: 17,
            ),
            Text(
              offline.online
                  ? 'Povezano · ${offline.pendingCount} izmena čeka slanje'
                  : 'Bez mreže · ${offline.pendingCount} trajno sačuvanih izmena',
              style: const TextStyle(fontSize: 12),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await connection!.client!.me();
                  offline.online = true;
                  final count = await offline.sync();
                  if (context.mounted) {
                    context.read<AssetBloc>().add(const LoadAssets());
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sinhronizovano izmena: $count.')),
                    );
                  }
                } on DomainException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(errorMessage(e.error))),
                    );
                  }
                }
              },
              child: const Text('Sinhronizuj'),
            ),
            if (offline.conflicts.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final conflict = offline.conflicts.first;
                  final choice = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Izmena sa drugog uređaja'),
                      content: Text(
                        'Tvoja verzija: ${conflict.local.title}\nServerska verzija: ${conflict.server.title}\n\nIzaberi koju izmenu želiš da zadržiš. Lokalna izmena se nikada ne šalje preko novije verzije bez ove odluke.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Preuzmi serversku'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Ponovo primeni moju'),
                        ),
                      ],
                    ),
                  );
                  if (choice != null) {
                    try {
                      await offline.resolveConflict(
                        conflict.local.id,
                        keepLocal: choice,
                      );
                      if (choice) {
                        await offline.sync();
                      }
                      if (context.mounted) {
                        context.read<AssetBloc>().add(const LoadAssets());
                      }
                    } on DomainException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(errorMessage(e.error))),
                        );
                        context.read<AssetBloc>().add(const LoadAssets());
                      }
                    }
                  }
                },
                child: Text('Reši konflikte (${offline.conflicts.length})'),
              ),
          ],
        ),
      );
    },
  );
}
