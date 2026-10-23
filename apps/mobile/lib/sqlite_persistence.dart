import 'dart:convert';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:sqflite/sqflite.dart';

/// One atomic SQLite row contains cache and outbox so neither can be lost alone.
final class SqliteOfflinePersistence implements OfflinePersistence {
  SqliteOfflinePersistence(this.ownerId);
  final String ownerId;
  Database? _database;
  Future<Database> get database async => _database ??= await openDatabase(
    'hedrion_offline.db',
    version: 1,
    onCreate: (db, version) => db.execute(
      'CREATE TABLE snapshots (owner_id TEXT PRIMARY KEY, snapshot TEXT NOT NULL)',
    ),
  );
  @override
  Future<Map<String, dynamic>?> read() async {
    final db = await database;
    final rows = await db.query(
      'snapshots',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return jsonDecode(rows.single['snapshot']! as String)
        as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    final db = await database;
    await db.transaction(
      (txn) => txn.insert('snapshots', {
        'owner_id': ownerId,
        'snapshot': jsonEncode(snapshot),
      }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
  }

  Future<void> close() async => _database?.close();
}
