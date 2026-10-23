import 'package:flutter/material.dart';
import 'studio_theme.dart';

/// Displays the immutable submission's public attribution and recorded decisions.
class SubmissionMetadata extends StatelessWidget {
  const SubmissionMetadata({super.key, required this.submission});
  final Map<String, dynamic> submission;

  String date(dynamic value) =>
      DateTime.tryParse('$value')?.toLocal().toString().split('.').first ?? '—';

  @override
  Widget build(BuildContext context) {
    final events = (submission['audit'] as List? ?? []).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Autor: ${submission['submitterName'] ?? 'Kreator'}',
          style: const TextStyle(color: muted, height: 1.8),
        ),
        Text(
          'Podneto: ${date(submission['submittedAt'])}',
          style: const TextStyle(color: muted, height: 1.8),
        ),
        if (submission['reviewedAt'] != null)
          Text(
            'Pregledano: ${date(submission['reviewedAt'])}',
            style: const TextStyle(color: muted, height: 1.8),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Istorija odluka'),
          children: [
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Za ovu prijavu još nema odluke.',
                  style: TextStyle(color: muted),
                ),
              ),
            for (final event in events)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  event['action'] == 'approved'
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                ),
                title: Text(
                  '${event['actorName']} · ${event['action'] == 'approved' ? 'Odobreno' : 'Odbijeno'}',
                ),
                subtitle: Text(
                  '${date(event['createdAt'])}${event['reason'] == null ? '' : '\n${event['reason']}'}',
                ),
                isThreeLine: event['reason'] != null,
              ),
          ],
        ),
      ],
    );
  }
}
