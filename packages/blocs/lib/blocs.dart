import 'package:bloc/bloc.dart';
import 'package:domain/domain.dart';
import 'package:equatable/equatable.dart';

sealed class AssetEvent extends Equatable {
  const AssetEvent();
  @override
  List<Object?> get props => [];
}

final class LoadAssets extends AssetEvent {
  const LoadAssets();
}

final class CreateAsset extends AssetEvent {
  const CreateAsset(this.draft);
  final AssetDraft draft;
  @override
  List<Object?> get props => [draft];
}

final class UpdateAsset extends AssetEvent {
  const UpdateAsset(this.asset, this.baseRevision);
  final Asset asset;
  final int baseRevision;
  @override
  List<Object?> get props => [asset, baseRevision];
}

final class TransitionAsset extends AssetEvent {
  const TransitionAsset(
    this.id,
    this.target, {
    required this.baseRevision,
    this.reason,
    this.idempotencyKey,
  });
  final AssetId id;
  final AssetLifecycle target;
  final int baseRevision;
  final String? reason;
  final String? idempotencyKey;
  @override
  List<Object?> get props => [id, target, baseRevision, reason, idempotencyKey];
}

final class DeleteAsset extends AssetEvent {
  const DeleteAsset(this.id, this.baseRevision);
  final AssetId id;
  final int baseRevision;
  @override
  List<Object?> get props => [id, baseRevision];
}

final class SubmitPublication extends AssetEvent {
  const SubmitPublication(
    this.id, {
    required this.baseRevision,
    required this.license,
    required this.allowDownload,
    required this.confirmRights,
    required this.idempotencyKey,
  });
  final AssetId id;
  final int baseRevision;
  final AssetLicense license;
  final bool allowDownload;
  final bool confirmRights;
  final String idempotencyKey;
  @override
  List<Object?> get props => [
    id,
    baseRevision,
    license,
    allowDownload,
    confirmRights,
    idempotencyKey,
  ];
}

enum AssetLoadStatus { initial, loading, empty, ready, failure }

final class AssetState extends Equatable {
  AssetState({
    this.status = AssetLoadStatus.initial,
    List<Asset> assets = const [],
    this.error,
    this.busy = false,
  }) : assets = List.unmodifiable(assets);
  final AssetLoadStatus status;
  final List<Asset> assets;
  final DomainError? error;
  final bool busy;
  @override
  List<Object?> get props => [
    status,
    assets.map((asset) => asset.toJson()).toList(growable: false),
    error?.code,
    busy,
  ];
}

final class AssetBloc extends Bloc<AssetEvent, AssetState> {
  AssetBloc(this.repository) : super(AssetState()) {
    // Serialize load + mutation events together; overlapping taps cannot reorder writes.
    on<AssetEvent>(
      _handle,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }
  final AssetRepository repository;
  Future<void> _handle(AssetEvent event, Emitter<AssetState> emit) async {
    final previous = state.assets;
    emit(
      AssetState(
        status: event is LoadAssets ? AssetLoadStatus.loading : state.status,
        assets: previous,
        busy: event is! LoadAssets,
      ),
    );
    try {
      switch (event) {
        case LoadAssets():
          break;
        case CreateAsset(:final draft):
          await repository.createAsset(draft);
        case UpdateAsset(:final asset, :final baseRevision):
          await repository.updateAsset(asset, baseRevision);
        case TransitionAsset(
          :final id,
          :final target,
          :final baseRevision,
          :final reason,
          :final idempotencyKey,
        ):
          await repository.transitionAsset(
            id,
            target,
            baseRevision: baseRevision,
            reason: reason,
            idempotencyKey: idempotencyKey,
          );
        case DeleteAsset(:final id, :final baseRevision):
          await repository.deleteAsset(id, baseRevision);
        case SubmitPublication(
          :final id,
          :final baseRevision,
          :final license,
          :final allowDownload,
          :final confirmRights,
          :final idempotencyKey,
        ):
          validatePublicationLicense(
            license,
            allowDownload: allowDownload,
            confirmRights: confirmRights,
          ).orThrow;
          if (repository is! PublicationRepository) {
            throw const DomainException(
              DomainError(ErrorCode.unsupportedInput),
            );
          }
          await (repository as PublicationRepository).submitPublication(
            id,
            baseRevision: baseRevision,
            license: license,
            allowDownload: allowDownload,
            confirmRights: confirmRights,
            idempotencyKey: idempotencyKey,
          );
      }
      final assets = await repository.loadAssets();
      emit(
        AssetState(
          status: assets.isEmpty
              ? AssetLoadStatus.empty
              : AssetLoadStatus.ready,
          assets: assets,
        ),
      );
    } on DomainException catch (e) {
      emit(
        AssetState(
          status: AssetLoadStatus.failure,
          assets: previous,
          error: e.error,
        ),
      );
    } catch (_) {
      emit(
        AssetState(
          status: AssetLoadStatus.failure,
          assets: previous,
          error: const DomainError(ErrorCode.unavailable),
        ),
      );
    }
  }
}
