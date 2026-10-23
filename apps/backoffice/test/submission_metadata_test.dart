import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_backoffice/submission_metadata.dart';

void main() {
  testWidgets('inspector exposes author attribution and reviewer reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmissionMetadata(
            submission: {
              'submitterName': 'Autor modela',
              'submittedAt': '2026-10-22T09:00:00Z',
              'reviewedAt': '2026-10-22T10:00:00Z',
              'audit': [
                {
                  'actorName': 'Moderator Ana',
                  'action': 'rejected',
                  'createdAt': '2026-10-22T10:00:00Z',
                  'reason': 'Dopunite oznake modela.',
                },
              ],
            },
          ),
        ),
      ),
    );
    expect(find.text('Autor: Autor modela'), findsOneWidget);
    await tester.tap(find.text('Istorija odluka'));
    await tester.pumpAndSettle();
    expect(find.text('Moderator Ana · Odbijeno'), findsOneWidget);
    expect(find.textContaining('Dopunite oznake modela.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
