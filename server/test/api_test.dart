import 'package:shelf/shelf.dart';
import 'package:splitken_server/splitken_server.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late MemoryStore store;
  late Future<(int, Map<String, Object?>)> Function(String, String, [Object?])
  api;

  setUp(() {
    store = MemoryStore();
    var n = 0;
    final handler = buildApi(store, newId: () => 'group-${++n}');
    api = (method, path, [body]) => call(handler, method, path, body);
  });

  Future<String> trip() async {
    final (status, json) = await api('POST', '/v1/groups', {
      'name': 'Tofino trip',
      'currency': 'CAD',
      'members': ['Ana', 'Ben', 'Cai'],
    });
    expect(status, 201);
    return json['id']! as String;
  }

  test('health', () async {
    final (status, json) = await api('GET', '/health');
    expect(status, 200);
    expect(json, {'status': 'ok'});
  });

  test('a new group gets ids m1, m2... for its founders', () async {
    final (status, json) = await api('POST', '/v1/groups', {
      'name': ' Tofino trip ',
      'currency': 'CAD',
      'members': ['Ana', ' Ben '],
    });
    expect(status, 201);
    expect(json, {
      'id': 'group-1',
      'name': 'Tofino trip',
      'currency': 'CAD',
      'founders': [
        {'id': 'm1', 'name': 'Ana'},
        {'id': 'm2', 'name': 'Ben'},
      ],
      'seq': 0,
    });
  });

  test('a bad group is refused with a code', () async {
    for (final (body, code) in [
      (
        {
          'name': '',
          'currency': 'CAD',
          'members': ['A'],
        },
        'bad_group',
      ),
      (
        {
          'name': 'X',
          'currency': 'cad',
          'members': ['A'],
        },
        'bad_group',
      ),
      ({'name': 'X', 'currency': 'CAD', 'members': <String>[]}, 'bad_group'),
      (
        {'name': 'X', 'currency': 'CAD', 'members': List.filled(51, 'A')},
        'bad_group',
      ),
      (
        {
          'name': 'X',
          'currency': 'CAD',
          'members': [' '],
        },
        'bad_member',
      ),
    ]) {
      final (status, json) = await api('POST', '/v1/groups', body);
      expect((status, json['error']), (422, code), reason: '$body');
    }
    final (dupStatus, dupJson) = await api('POST', '/v1/groups', {
      'name': 'X',
      'currency': 'CAD',
      'members': ['Ana', 'Ben', ' ana '],
    });
    expect(
      (dupStatus, dupJson['error'], dupJson['message']),
      (
        422,
        'bad_member',
        '"ana" is listed twice. Each member needs a name of their own.',
      ),
    );
    final (badStatus, badJson) = await api('POST', '/v1/groups', '[1');
    expect((badStatus, badJson['error']), (400, 'bad_json'));
  });

  test('an unknown group is 404', () async {
    for (final (method, path) in [
      ('GET', '/v1/groups/nope'),
      ('POST', '/v1/groups/nope/sync'),
      ('GET', '/v1/groups/nope/balances'),
    ]) {
      final (status, json) = await api(
        method,
        path,
        method == 'POST' ? {'since': 0} : null,
      );
      expect((status, json['error']), (404, 'not_found'), reason: path);
    }
  });

  test('2 devices sync through the server', () async {
    final id = await trip();
    final (s1, phone) = await api('POST', '/v1/groups/$id/sync', {
      'since': 0,
      'ops': [
        expenseOp('o1', 'phone', 1, 'x1', 9000, 'm1', ['m1', 'm2', 'm3']),
      ],
    });
    expect(s1, 200);
    expect(phone['stored'], 1);
    expect(phone['seq'], 1);

    // The tablet has seen nothing yet: it sends its own expense and gets both.
    final (_, tablet) = await api('POST', '/v1/groups/$id/sync', {
      'since': 0,
      'ops': [
        expenseOp('o1', 'tablet', 1, 'x2', 1200, 'm2', ['m1', 'm2', 'm3']),
      ],
    });
    expect(tablet['seq'], 2);
    expect([for (final o in tablet['ops']! as List) (o as Map)['seq']], [1, 2]);

    // The phone asks only for what it has not seen.
    final (_, again) = await api('POST', '/v1/groups/$id/sync', {'since': 1});
    expect(
      [
        for (final o in again['ops']! as List)
          ((o as Map)['expense'] as Map)['id'],
      ],
      ['x2'],
    );

    final (_, bal) = await api('GET', '/v1/groups/$id/balances');
    expect(bal, {
      'currency': 'CAD',
      'net': {'m1': 5600, 'm2': -2200, 'm3': -3400},
      'settle': [
        {'from': 'm3', 'to': 'm1', 'amountCents': 3400},
        {'from': 'm2', 'to': 'm1', 'amountCents': 2200},
      ],
    });
  });

  test('totals give what each member paid and owes, without transfers', () async {
    final id = await trip();
    final (empty, json0) = await api('GET', '/v1/groups/$id/totals');
    expect(empty, 200);
    expect(json0['spent'], 0);
    Map<String, Object?> op(String opId, int lamport, Map<String, Object?> e) =>
        {
          'opId': opId,
          'clientId': 'phone',
          'lamport': lamport,
          'kind': 'expense',
          'expense': {'isTransfer': false, ...e},
        };
    final (status, _) = await api('POST', '/v1/groups/$id/sync', {
      'since': 0,
      'ops': [
        expenseOp('o1', 'phone', 1, 'x1', 1000, 'm1', ['m1', 'm2', 'm3']),
        op('o2', 2, {
          'id': 'x2',
          'description': 'Kayaks',
          'amountCents': 900,
          'paidBy': 'm2',
          'participants': ['m2', 'm3'],
          'method': 'shares',
          'weights': [2, 1],
        }),
        op('o3', 3, {
          'id': 'x3',
          'description': 'Ben pays Ana back',
          'amountCents': 2500,
          'paidBy': 'm2',
          'participants': ['m1'],
          'method': 'exact',
          'weights': [2500],
          'isTransfer': true,
        }),
      ],
    });
    expect(status, 200);
    final (got, json) = await api('GET', '/v1/groups/$id/totals');
    expect(got, 200);
    // 10.00 / 3 gives Ana the 1 cent left over. The 25.00 transfer is not spending.
    expect(json, {
      'currency': 'CAD',
      'spent': 1900,
      'members': [
        {'id': 'm1', 'name': 'Ana', 'paid': 1000, 'share': 334},
        {'id': 'm2', 'name': 'Ben', 'paid': 900, 'share': 933},
        {'id': 'm3', 'name': 'Cai', 'paid': 0, 'share': 633},
      ],
    });
    final (missing, _) = await api('GET', '/v1/groups/nope/totals');
    expect(missing, 404);
  });

  test(
    'the expenses down-load as CSV, by name, without deleted ones',
    () async {
      final id = await trip();
      Map<String, Object?> op(
        String opId,
        int lamport,
        Map<String, Object?> e,
      ) => {
        'opId': opId,
        'clientId': 'phone',
        'lamport': lamport,
        'kind': 'expense',
        'expense': {
          'method': 'equal',
          'weights': <int>[],
          'isTransfer': false,
          ...e,
        },
      };
      final (status, _) = await api('POST', '/v1/groups/$id/sync', {
        'since': 0,
        'ops': [
          memberOp('o0', 'phone', 1, 'p-dee', '\uFF20Dee'),
          op('o1', 2, {
            'id': 'x1',
            'description': 'Fuel, ferry, "snacks"',
            'amountCents': 1000,
            'paidBy': 'm1',
            'participants': ['m1', 'm2', 'm3'],
          }),
          op('o2', 3, {
            'id': 'x2',
            'description': '=1+1',
            'amountCents': 900,
            'paidBy': 'p-dee',
            'participants': ['m2', 'p-dee'],
            'method': 'shares',
            'weights': [2, 1],
          }),
          op('o3', 4, {
            'id': 'x3',
            'description': 'Ben pays Ana back',
            'amountCents': 2500,
            'paidBy': 'm2',
            'participants': ['m1'],
            'method': 'exact',
            'weights': [2500],
            'isTransfer': true,
          }),
          op('o4', 5, {
            'id': 'x4',
            'description': 'Deleted',
            'amountCents': 100,
            'paidBy': 'm1',
            'participants': ['m1'],
          }),
          {
            'opId': 'o5',
            'clientId': 'phone',
            'lamport': 6,
            'kind': 'delete',
            'expenseId': 'x4',
          },
        ],
      });
      expect(status, 200);

      final response = await buildApi(store)(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/groups/$id/expenses.csv'),
        ),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'text/csv; charset=utf-8');
      expect(
        response.headers['content-disposition'],
        'attachment; filename="expenses.csv"',
      );
      // The 10 cents left over from 10.00 / 3 go to the 1st participant.
      expect(
        await response.readAsString(),
        'description,amount,currency,paid_by,split,shares,transfer\r\n'
        '"Fuel, ferry, ""snacks""",10.00,CAD,Ana,equal,'
        'Ana 3.34; Ben 3.33; Cai 3.33,no\r\n'
        "'=1+1,9.00,CAD,'\uFF20Dee,shares,Ben 6.00; \uFF20Dee 3.00,no\r\n"
        'Ben pays Ana back,25.00,CAD,Ben,exact,Ana 25.00,yes\r\n',
      );

      final (missing, _) = await api('GET', '/v1/groups/nope/expenses.csv');
      expect(missing, 404);
    },
  );

  test('a batch sent twice is stored once', () async {
    final id = await trip();
    final batch = {
      'since': 0,
      'ops': [
        expenseOp('o1', 'phone', 1, 'x1', 900, 'm1', ['m1', 'm2', 'm3']),
      ],
    };
    expect((await api('POST', '/v1/groups/$id/sync', batch)).$2['stored'], 1);
    final (status, json) = await api('POST', '/v1/groups/$id/sync', batch);
    expect((status, json['stored'], json['seq']), (200, 0, 1));
  });

  test('a since past the newest seq is refused and stores nothing', () async {
    final id = await trip();
    final first = {
      'since': 0,
      'ops': [
        expenseOp('o1', 'phone', 1, 'x1', 900, 'm1', ['m1', 'm2', 'm3']),
      ],
    };
    final seq =
        (await api('POST', '/v1/groups/$id/sync', first)).$2['seq'] as int;
    final (status, json) = await api('POST', '/v1/groups/$id/sync', {
      'since': seq + 5,
      'ops': [
        expenseOp('o2', 'phone', 2, 'x2', 300, 'm2', ['m1', 'm2']),
      ],
    });
    expect(
      (status, json['error'], json['message']),
      (
        409,
        'seq_ahead',
        'since is ${seq + 5}, past this group\'s newest seq $seq. Fetch the group again from 0.',
      ),
    );
    // o2 was not stored, and a sync from the newest seq itself is fine.
    final (okStatus, okJson) = await api('POST', '/v1/groups/$id/sync', {
      'since': seq,
    });
    expect((okStatus, okJson['seq']), (200, seq));
    expect(okJson['ops'], isEmpty);
    final all =
        (await api('POST', '/v1/groups/$id/sync', {'since': 0})).$2['ops']
            as List;
    expect(all.map((o) => (o as Map)['opId']), ['o1']);
  });

  test('a member added offline may pay in the same batch', () async {
    final id = await trip();
    final (status, json) = await api('POST', '/v1/groups/$id/sync', {
      'since': 0,
      'ops': [
        memberOp('o1', 'phone', 1, 'phone-1', 'Dev'),
        expenseOp('o2', 'phone', 2, 'x1', 400, 'phone-1', ['m1', 'phone-1']),
      ],
    });
    expect((status, json['stored']), (200, 2));
    final (_, group) = await api('GET', '/v1/groups/$id');
    expect((group['members']! as List).last, {'id': 'phone-1', 'name': 'Dev'});
    expect(group['seq'], 2);
  });

  test('1 bad operation refuses the whole batch, naming it', () async {
    final id = await trip();
    final (status, json) = await api('POST', '/v1/groups/$id/sync', {
      'since': 0,
      'ops': [
        expenseOp('o1', 'phone', 1, 'x1', 400, 'm1', ['m1', 'm2']),
        expenseOp('o2', 'phone', 2, 'x2', 400, 'm1', ['m1', 'ghost']),
      ],
    });
    expect(
      (status, json['error'], json['opId']),
      (422, 'unknown_member', 'o2'),
    );
    expect(await store.opsSince(id, 0), isEmpty);
  });

  test(
    'founder ids are reserved, and a group holds at most 50 members',
    () async {
      final id = await trip();
      final (status, json) = await api('POST', '/v1/groups/$id/sync', {
        'ops': [memberOp('o1', 'phone', 1, 'm9', 'Eve')],
      });
      expect((status, json['error']), (422, 'bad_member'));

      final more = [
        for (var i = 0; i < 47; i++)
          memberOp('a$i', 'phone', i + 1, 'phone-$i', 'P$i'),
      ];
      expect((await api('POST', '/v1/groups/$id/sync', {'ops': more})).$1, 200);
      final (s2, j2) = await api('POST', '/v1/groups/$id/sync', {
        'ops': [memberOp('b1', 'phone', 99, 'phone-x', 'One too many')],
      });
      expect((s2, j2['error']), (422, 'too_many_members'));
    },
  );

  test(
    'a sync of more than 500 operations, or with a bad since, is refused',
    () async {
      final id = await trip();
      final ops = [
        for (var i = 0; i < 501; i++)
          expenseOp('o$i', 'phone', i + 1, 'x$i', 100, 'm1', ['m1']),
      ];
      expect(
        (await api('POST', '/v1/groups/$id/sync', {'ops': ops})).$2['error'],
        'bad_sync',
      );
      expect(
        (await api('POST', '/v1/groups/$id/sync', {'since': -1})).$2['error'],
        'bad_sync',
      );
      expect(
        (await api('POST', '/v1/groups/$id/sync', {
          'ops': ['x'],
        })).$2['error'],
        'bad_op',
      );
    },
  );

  test('any origin may call, and a preflight gets 204', () async {
    final handler = buildApi(MemoryStore());
    final response = await handler(
      Request('OPTIONS', Uri.parse('http://localhost/v1/groups')),
    );
    expect(response.statusCode, 204);
    expect(response.headers['access-control-allow-origin'], '*');
  });
}
