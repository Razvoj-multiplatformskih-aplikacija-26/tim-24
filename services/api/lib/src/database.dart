import 'dart:convert';
import 'package:postgres/postgres.dart';

typedef Json = Map<String, dynamic>;

/// All commands that touch shared resources are serialized in PostgreSQL, even
/// across multiple API processes. The lock is released by commit or rollback.
class Database {
  Database(this.pool, {this.schema});
  final Pool pool;
  final String? schema;
  static Database connect(String url) => Database(Pool.withUrl(url));

  Future<T> transaction<T>(Future<T> Function(Tx tx) action) async {
    final outcome = await pool.runTx<_TransactionOutcome<T>>((session) async {
      final tx = Tx(session);
      if (schema != null) {
        if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(schema!)) {
          throw ArgumentError('Invalid schema');
        }
        await tx.query('SET LOCAL search_path TO $schema');
      }
      await tx.query('SELECT pg_advisory_xact_lock(72419831)');
      // The lock predates this savepoint, so rolling back the business
      // operation does not expose its file capacity to another transaction.
      await tx.query('SAVEPOINT hedrion_operation');
      try {
        final value = await action(tx);
        await tx.query('RELEASE SAVEPOINT hedrion_operation');
        return _TransactionOutcome<T>.success(value);
      } catch (error, stack) {
        await tx.query('ROLLBACK TO SAVEPOINT hedrion_operation');
        for (final compensate in tx.onRollback.reversed) {
          await compensate(tx);
        }
        await tx.query('RELEASE SAVEPOINT hedrion_operation');
        // Commit retained-file accounting first. Throwing inside runTx would
        // roll it back together with the failed business operation.
        return _TransactionOutcome<T>.failure(error, stack);
      }
    });
    if (outcome.error != null) {
      Error.throwWithStackTrace(outcome.error!, outcome.stack!);
    }
    return outcome.value as T;
  }

  Future<void> close() => pool.close();
}

class Tx {
  Tx(this.session);
  final Session session;
  final List<Future<void> Function(Tx)> onRollback = [];
  Future<List<Json>> query(String sql, [Json parameters = const {}]) async {
    final rows = await session.execute(Sql.named(sql), parameters: parameters);
    return rows.map((row) => row.toColumnMap()).toList();
  }

  Future<Json?> one(String sql, [Json parameters = const {}]) async {
    final rows = await query(sql, parameters);
    return rows.isEmpty ? null : rows.first;
  }
}

class _TransactionOutcome<T> {
  const _TransactionOutcome.success(T this.value)
      : error = null,
        stack = null;
  const _TransactionOutcome.failure(this.error, this.stack) : value = null;
  final T? value;
  final Object? error;
  final StackTrace? stack;
}

Json jsonMap(dynamic value) => value is String
    ? Map<String, dynamic>.from(jsonDecode(value) as Map)
    : Map<String, dynamic>.from(value as Map);

Json wire(Json row) => row.map((key, value) =>
    MapEntry(key, value is DateTime ? value.toUtc().toIso8601String() : value));
