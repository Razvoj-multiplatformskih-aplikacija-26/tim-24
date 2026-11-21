import 'dart:convert';
import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

final class Store implements AssetRepository {
  List<Asset> rows = seedAssets(ownerId: const UserId('owner'));
  bool fail = false;
  int loadCalls = 0;
  @override
  Future<List<Asset>> loadAssets() async {
    loadCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (fail) {
      fail = false;
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
    return List.of(rows);
  }

  @override
  Future<Asset> createAsset(AssetDraft draft) async {
    validateDraft(draft).orThrow;
    final a = Asset(
      id: AssetId('created-${rows.length}'),
      ownerId: const UserId('owner'),
      title: draft.title,
      lifecycle: AssetLifecycle.draft,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    rows.add(a);
    return a;
  }

  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) async => asset;
  @override
  Future<Asset> transitionAsset(
    AssetId id,
    AssetLifecycle target, {
    required int baseRevision,
    String? reason,
    String? idempotencyKey,
  }) async {
    final index = rows.indexWhere((a) => a.id == id);
    final original = rows[index];
    validateTransition(
      original,
      target,
      const Actor(id: UserId('owner'), role: UserRole.creator),
      reason: reason,
    ).orThrow;
    if (original.revision != baseRevision) {
      throw const DomainException(DomainError(ErrorCode.revisionConflict));
    }
    return rows[index] = original.copyWith(
      lifecycle: target,
      revision: baseRevision + 1,
    );
  }

  @override
  Future<void> deleteAsset(AssetId id, int baseRevision) async {
    rows.removeWhere((a) => a.id == id);
  }
}

final class RacingStore extends Store {
  RacingStore({this.rejectReload = false});
  final bool rejectReload;
  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) async {
    rows[0] = rows[0].copyWith(title: 'Izmena drugog korisnika', revision: 9);
    this.fail = rejectReload;
    throw const DomainException(DomainError(ErrorCode.revisionConflict));
  }
}

void main() {
  test(
    'load exposes loading/data, typed failure retries and empty result',
    () async {
      final store = Store();
      final bloc = AssetBloc(store);
      final states = <AssetState>[];
      final sub = bloc.stream.listen(states.add);
      Future<AssetState> after(AssetEvent event) {
        final f = bloc.stream.firstWhere(
          (s) => s.status != AssetLoadStatus.loading && !s.busy,
        );
        bloc.add(event);
        return f;
      }

      expect((await after(const LoadAssets())).assets.length, 16);
      expect(states.first.status, AssetLoadStatus.loading);
      store.fail = true;
      expect(
        (await after(const LoadAssets())).error?.code,
        ErrorCode.unavailable,
      );
      expect((await after(const LoadAssets())).status, AssetLoadStatus.ready);
      store.rows.clear();
      expect((await after(const LoadAssets())).status, AssetLoadStatus.empty);
      await sub.cancel();
      await bloc.close();
    },
  );
  test(
    'event-driven state action and sequential double-click cannot reorder mutations',
    () async {
      final store = Store();
      final bloc = AssetBloc(store);
      final ready = bloc.stream.firstWhere(
        (s) => s.status == AssetLoadStatus.ready,
      );
      bloc.add(const LoadAssets());
      await ready;
      final draft = store.rows.firstWhere(
        (a) => a.lifecycle == AssetLifecycle.draft,
      );
      final done = bloc.stream.firstWhere(
        (s) => s.status == AssetLoadStatus.failure,
      );
      bloc.add(
        TransitionAsset(
          draft.id,
          AssetLifecycle.queued,
          baseRevision: draft.revision,
        ),
      );
      bloc.add(
        TransitionAsset(
          draft.id,
          AssetLifecycle.queued,
          baseRevision: draft.revision,
        ),
      );
      await done;
      expect(
        store.rows.firstWhere((a) => a.id == draft.id).lifecycle,
        AssetLifecycle.queued,
      );
      expect(store.rows.firstWhere((a) => a.id == draft.id).revision, 2);
      await bloc.close();
    },
  );
  test('Equatable state compares meaningful UI values', () {
    expect(
      AssetState(status: AssetLoadStatus.empty),
      AssetState(status: AssetLoadStatus.empty),
    );
    expect(
      AssetState(status: AssetLoadStatus.loading),
      isNot(AssetState(status: AssetLoadStatus.empty)),
    );
    final original = seedAssets(ownerId: const UserId('owner')).first;
    final decoded = Asset.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    AssetState populated(Asset asset) =>
        AssetState(status: AssetLoadStatus.ready, assets: [asset]);
    expect(identical(original, decoded), isFalse);
    expect(populated(original), populated(decoded));
    expect(populated(original).hashCode, populated(decoded).hashCode);
    for (final changed in [
      decoded.copyWith(title: '${decoded.title} izmena'),
      decoded.copyWith(tags: [...decoded.tags, 'nova-oznaka']),
      decoded.copyWith(revision: decoded.revision + 1),
    ]) {
      expect(populated(original), isNot(populated(changed)));
    }
  });

  test(
    'rejected mutation atomically publishes reason and refetched winner',
    () async {
      final store = RacingStore();
      final bloc = AssetBloc(store);
      final loaded = bloc.stream.firstWhere(
        (state) => state.status == AssetLoadStatus.ready,
      );
      bloc.add(const LoadAssets());
      await loaded;
      final stale = bloc.state.assets.first;
      final rejected = bloc.stream.firstWhere((state) => state.error != null);
      bloc.add(UpdateAsset(stale, stale.revision));
      final result = await rejected;
      expect(store.loadCalls, 2);
      expect(result.error!.code, ErrorCode.revisionConflict);
      expect(result.assets.first.title, 'Izmena drugog korisnika');
      expect(result.assets.first.revision, 9);
      expect(result.busy, isFalse);
      await bloc.close();
    },
  );

  test(
    'failed rejection refetch keeps original reason and clears busy',
    () async {
      final store = RacingStore(rejectReload: true);
      final bloc = AssetBloc(store);
      final loaded = bloc.stream.firstWhere(
        (state) => state.status == AssetLoadStatus.ready,
      );
      bloc.add(const LoadAssets());
      await loaded;
      final stale = bloc.state.assets.first;
      final rejected = bloc.stream.firstWhere((state) => state.error != null);
      bloc.add(UpdateAsset(stale, stale.revision));
      final result = await rejected;
      expect(store.loadCalls, 2);
      expect(result.error!.code, ErrorCode.revisionConflict);
      expect(result.assets.first.title, stale.title);
      expect(result.busy, isFalse);
      await bloc.close();
    },
  );
}
