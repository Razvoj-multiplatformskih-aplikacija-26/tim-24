import 'dart:convert';
import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

final class Store implements AssetRepository {
  List<Asset> rows = seedAssets(ownerId: const UserId('owner'));
  bool fail = false;
  @override
  Future<List<Asset>> loadAssets() async {
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
}
