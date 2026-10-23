import 'models.dart';

List<Asset> seedAssets({
  required UserId ownerId,
  int count = 16,
  DateTime? now,
}) {
  final clock = (now ?? DateTime.now()).toUtc();
  const titles = [
    'Kristalni mač',
    'Stari sanduk',
    'Kamena kapija',
    'Šumska stena',
    'Pilotska kaciga',
    'Magični fenjer',
    'Drveni sto',
    'Metalni štit',
    'Planinski bor',
    'Svemirski kontejner',
    'Keramička vaza',
    'Srednjovekovni luk',
    'Kameni stub',
    'Putnički ranac',
    'Oklopna vrata',
    'Drevni oltar',
  ];
  return List.generate(count, (i) {
    final state = AssetLifecycle.values[i % AssetLifecycle.values.length];
    final completed = {
      AssetLifecycle.ready,
      AssetLifecycle.pendingReview,
      AssetLifecycle.published,
      AssetLifecycle.rejected,
    }.contains(state);
    return Asset(
      id: AssetId('demo-${i + 1}'),
      ownerId: ownerId,
      title: titles[i % titles.length],
      description:
          'Demonstracioni statični rekvizit za razvoj video-igara. Primer lokalnih KT1 podataka.',
      category: switch (i % 4) {
        0 => 'weapons',
        1 => 'props',
        2 => 'architecture',
        _ => 'nature',
      },
      tags: ['demo', 'stilizovano'],
      favorite: i % 5 == 0,
      lifecycle: state,
      createdAt: clock.subtract(Duration(hours: i + 1)),
      updatedAt: clock,
      outputFileId: completed ? 'demo-model.glb' : null,
      previewFileId: completed ? 'demo-preview.png' : null,
      rejectionReason: state == AssetLifecycle.rejected
          ? 'Dopunite opis i licencu.'
          : null,
      allowDownload: completed,
    );
  });
}

List<GenerationAdmission> seedAdmissions(DateTime now, {int count = 18}) =>
    List.generate(
      count,
      (i) => GenerationAdmission(
        jobId: JobId('accepted-$i'),
        ownerId: UserId(i < 12 ? 'creator-a' : 'creator-b'),
        acceptedAt: now.toUtc(),
      ),
    );
