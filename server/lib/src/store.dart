import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:splitken_core/splitken_core.dart';

/// A group as created: its founding members never change. Members added
/// later live in the operation log.
class Group {
  Group({
    required this.id,
    required this.name,
    required this.currency,
    required this.founders,
  });

  final String id;
  final String name;
  final String currency;
  final List<Member> founders;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'currency': currency,
    'founders': [for (final m in founders) m.toJson()],
  };
}

/// Where groups and their operations live.
///
/// [append] runs [check] on the group's operations so far and the new ones,
/// and stores the new ones only when it returns without throwing. Both
/// happen as 1 step: no other append to the same group runs in between.
abstract class Store {
  Future<void> createGroup(Group group);

  Future<Group?> group(String id);

  /// The group's operations with a seq above [since], in seq order.
  Future<List<Op>> opsSince(String groupId, int since);

  /// Stores the operations of [ops] the group does not have yet, and returns
  /// how many it stored. An operation the group has (same clientId and opId)
  /// is skipped, such that a device may safely send a batch again.
  Future<int> append(
    String groupId,
    List<Op> ops,
    void Function(List<Op> existing, List<Op> fresh) check,
  );

  Future<void> close();
}

/// A group id: 16 random bytes as URL-safe base64, 22 characters. Anyone
/// with the id can read and change the group, as with a shared link.
String newGroupId([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Keeps everything in memory. For tests and for `--memory` demo runs.
class MemoryStore implements Store {
  final _groups = <String, Group>{};
  final _ops = <String, List<Op>>{};
  var _seq = 0;

  @override
  Future<void> createGroup(Group group) async {
    _groups[group.id] = group;
    _ops[group.id] = [];
  }

  @override
  Future<Group?> group(String id) async => _groups[id];

  @override
  Future<List<Op>> opsSince(String groupId, int since) async => [
    for (final op in _ops[groupId] ?? const <Op>[])
      if (op.seq! > since) op,
  ];

  @override
  Future<int> append(
    String groupId,
    List<Op> ops,
    void Function(List<Op> existing, List<Op> fresh) check,
  ) async {
    final existing = _ops[groupId]!;
    final known = {for (final op in existing) _key(op)};
    final fresh = <Op>[];
    for (final op in ops) {
      if (known.add(_key(op))) fresh.add(op);
    }
    check(existing, fresh);
    for (final op in fresh) {
      existing.add(op.withSeq(++_seq));
    }
    return fresh.length;
  }

  @override
  Future<void> close() async {}
}

String _key(Op op) => '${op.clientId}\u0000${op.opId}';

/// Keeps groups and operations in PostgreSQL. The tables are made on 1st use.
class PostgresStore implements Store {
  PostgresStore._(this._pool);

  final Pool<void> _pool;

  static Future<PostgresStore> open(String url) async {
    final pool = Pool<void>.withUrl(url);
    await pool.execute('''
      CREATE TABLE IF NOT EXISTS groups (
        id text PRIMARY KEY,
        name text NOT NULL,
        currency text NOT NULL,
        founders jsonb NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now()
      )''');
    await pool.execute('''
      CREATE TABLE IF NOT EXISTS ops (
        seq bigserial PRIMARY KEY,
        group_id text NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
        client_id text NOT NULL,
        op_id text NOT NULL,
        body jsonb NOT NULL,
        received_at timestamptz NOT NULL DEFAULT now(),
        UNIQUE (group_id, client_id, op_id)
      )''');
    await pool.execute(
      'CREATE INDEX IF NOT EXISTS ops_group_seq ON ops (group_id, seq)',
    );
    return PostgresStore._(pool);
  }

  @override
  Future<void> createGroup(Group group) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO groups (id, name, currency, founders) VALUES (@id, @name, @currency, @founders)',
      ),
      parameters: {
        'id': group.id,
        'name': group.name,
        'currency': group.currency,
        'founders': TypedValue(Type.jsonb, [
          for (final m in group.founders) m.toJson(),
        ]),
      },
    );
  }

  @override
  Future<Group?> group(String id) async {
    final rows = await _pool.execute(
      Sql.named('SELECT name, currency, founders FROM groups WHERE id = @id'),
      parameters: {'id': id},
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return Group(
      id: id,
      name: row[0]! as String,
      currency: row[1]! as String,
      founders: [
        for (final m in row[2]! as List<Object?>)
          Member.fromJson((m! as Map).cast<String, Object?>()),
      ],
    );
  }

  @override
  Future<List<Op>> opsSince(String groupId, int since) =>
      _opsSince(_pool, groupId, since);

  Future<List<Op>> _opsSince(Session s, String groupId, int since) async {
    final rows = await s.execute(
      Sql.named(
        'SELECT seq, body FROM ops WHERE group_id = @g AND seq > @since ORDER BY seq',
      ),
      parameters: {'g': groupId, 'since': since},
    );
    return [
      for (final row in rows)
        Op.fromJson(
          (row[1]! as Map).cast<String, Object?>(),
        ).withSeq(row[0]! as int),
    ];
  }

  @override
  Future<int> append(
    String groupId,
    List<Op> ops,
    void Function(List<Op> existing, List<Op> fresh) check,
  ) {
    return _pool.runTx((tx) async {
      // The row lock makes appends to 1 group take turns, such that check()
      // always sees every operation stored before it.
      await tx.execute(
        Sql.named('SELECT 1 FROM groups WHERE id = @g FOR UPDATE'),
        parameters: {'g': groupId},
      );
      final existing = await _opsSince(tx, groupId, 0);
      final known = {for (final op in existing) _key(op)};
      final fresh = <Op>[];
      for (final op in ops) {
        if (known.add(_key(op))) fresh.add(op);
      }
      check(existing, fresh);
      for (final op in fresh) {
        final body = op.toJson()..remove('seq');
        await tx.execute(
          Sql.named(
            'INSERT INTO ops (group_id, client_id, op_id, body) VALUES (@g, @c, @o, @b)',
          ),
          parameters: {
            'g': groupId,
            'c': op.clientId,
            'o': op.opId,
            'b': TypedValue(Type.jsonb, body),
          },
        );
      }
      return fresh.length;
    });
  }

  @override
  Future<void> close() => _pool.close();
}
