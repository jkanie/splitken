import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:splitken_core/splitken_core.dart';

import 'store.dart';

/// The most operations 1 sync request may send.
const int maxOpsPerSync = 500;

/// The most members a group may have, founders included.
const int maxMembers = 50;

/// The most bytes a request body may hold.
const int maxBodyBytes = 1 << 20;

/// The HTTP API. See `api/openapi.yaml` for the full description.
Handler buildApi(Store store, {String Function()? newId}) {
  final makeId = newId ?? newGroupId;
  final router = Router()
    ..get('/health', (Request _) => _json(200, {'status': 'ok'}))
    ..post('/v1/groups', (Request request) async {
      final body = await _body(request);
      final name = body['name'];
      final currency = body['currency'];
      final members = body['members'];
      if (name is! String || name.trim().isEmpty || name.length > 80) {
        throw _ApiError(
          422,
          'bad_group',
          'A group name is 1 to 80 characters.',
        );
      }
      if (currency is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
        throw _ApiError(
          422,
          'bad_group',
          'currency is a 3-letter ISO 4217 code such as CAD.',
        );
      }
      if (members is! List || members.isEmpty || members.length > maxMembers) {
        throw _ApiError(
          422,
          'bad_group',
          'A group starts with 1 to $maxMembers members.',
        );
      }
      final founders = <Member>[];
      for (final (i, m) in members.indexed) {
        if (m is! String || m.trim().isEmpty || m.length > 60) {
          throw _ApiError(
            422,
            'bad_member',
            'A member name is 1 to 60 characters.',
          );
        }
        founders.add(Member('m${i + 1}', m.trim()));
      }
      final group = Group(
        id: makeId(),
        name: name.trim(),
        currency: currency,
        founders: founders,
      );
      await store.createGroup(group);
      return _json(201, {...group.toJson(), 'seq': 0});
    })
    ..get('/v1/groups/<id>', (Request request, String id) async {
      final group = await _group(store, id);
      final ops = await store.opsSince(id, 0);
      final state = fold(group.founders, ops);
      return _json(200, {
        ...group.toJson(),
        'members': [for (final m in state.members) m.toJson()],
        'seq': ops.isEmpty ? 0 : ops.last.seq,
      });
    })
    ..post('/v1/groups/<id>/sync', (Request request, String id) async {
      final group = await _group(store, id);
      final body = await _body(request);
      final since = body['since'] ?? 0;
      final raw = body['ops'] ?? const [];
      if (since is! int || since < 0) {
        throw _ApiError(422, 'bad_sync', 'since is a seq of 0 or more.');
      }
      if (raw is! List || raw.length > maxOpsPerSync) {
        throw _ApiError(
          422,
          'bad_sync',
          'ops is a list of at most $maxOpsPerSync operations.',
        );
      }
      final ops = <Op>[];
      for (final o in raw) {
        if (o is! Map<String, Object?>) {
          throw _ApiError(422, 'bad_op', 'Each operation is a JSON object.');
        }
        ops.add(Op.fromJson(o).withoutSeq());
      }
      final stored = await store.append(id, ops, (existing, fresh) {
        _check(group, existing, fresh);
      });
      final out = await store.opsSince(id, since);
      final all = since == 0 ? out : await store.opsSince(id, 0);
      return _json(200, {
        'stored': stored,
        'seq': all.isEmpty ? 0 : all.last.seq,
        'ops': [for (final op in out) op.toJson()],
      });
    })
    ..get('/v1/groups/<id>/balances', (Request request, String id) async {
      final group = await _group(store, id);
      final state = fold(group.founders, await store.opsSince(id, 0));
      final net = balances(state.members, state.expenses);
      return _json(200, {
        'currency': group.currency,
        'net': net,
        'settle': [for (final t in settleUp(state.members, net)) t.toJson()],
      });
    });

  return const Pipeline()
      .addMiddleware(_cors)
      .addMiddleware(_errors)
      .addHandler(router.call);
}

/// Checks new operations against the group as the stored ones leave it,
/// 1 at a time, such that an expense may name a member added earlier in the
/// same batch. Any broken rule refuses the whole batch.
void _check(Group group, List<Op> existing, List<Op> fresh) {
  final seen = [...existing];
  for (final op in fresh) {
    final state = fold(group.founders, seen);
    final memberIds = {for (final m in state.members) m.id};
    try {
      if (op.kind == OpKind.expense) {
        op.expense!.validate(memberIds);
        splitExpense(op.expense!);
      }
      if (op.kind == OpKind.member && !memberIds.contains(op.member!.id)) {
        // m1, m2 and so on are the server's ids for founders. A device names
        // the members it adds with its own prefix, such that ids never clash.
        if (RegExp(r'^m\d+$').hasMatch(op.member!.id)) {
          throw SplitError(
            'bad_member',
            'Member ids m1, m2 and so on are for founders.',
          );
        }
        if (memberIds.length >= maxMembers) {
          throw SplitError(
            'too_many_members',
            'A group has at most $maxMembers members.',
          );
        }
      }
    } on SplitError catch (e) {
      throw _ApiError(422, e.code, e.message, opId: op.opId);
    }
    seen.add(op);
  }
}

Future<Group> _group(Store store, String id) async {
  final group = await store.group(id);
  if (group == null) {
    throw _ApiError(404, 'not_found', 'No group with that id.');
  }
  return group;
}

Future<Map<String, Object?>> _body(Request request) async {
  final length = request.contentLength;
  if (length != null && length > maxBodyBytes) {
    throw _ApiError(
      413,
      'too_large',
      'A request body is at most $maxBodyBytes bytes.',
    );
  }
  final text = await request.readAsString();
  if (text.length > maxBodyBytes) {
    throw _ApiError(
      413,
      'too_large',
      'A request body is at most $maxBodyBytes bytes.',
    );
  }
  try {
    final json = jsonDecode(text);
    if (json is Map<String, Object?>) return json;
  } on FormatException {
    // Falls through to the error below.
  }
  throw _ApiError(400, 'bad_json', 'The body is a JSON object.');
}

class _ApiError implements Exception {
  _ApiError(this.status, this.code, this.message, {this.opId});

  final int status;
  final String code;
  final String message;
  final String? opId;
}

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

Handler _errors(Handler inner) => (request) async {
  try {
    return await inner(request);
  } on _ApiError catch (e) {
    return _json(e.status, {
      'error': e.code,
      'message': e.message,
      if (e.opId != null) 'opId': e.opId,
    });
  } on SplitError catch (e) {
    return _json(422, {'error': e.code, 'message': e.message});
  }
};

/// The apps' web builds call the API from another origin. Nothing rides on
/// cookies (the group id is the key), so any origin may call.
Handler _cors(Handler inner) => (request) async {
  const headers = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'content-type',
    'access-control-max-age': '600',
  };
  if (request.method == 'OPTIONS') return Response(204, headers: headers);
  final response = await inner(request);
  return response.change(headers: headers);
};
