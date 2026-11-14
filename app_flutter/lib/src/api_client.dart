import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:splitken_core/splitken_core.dart';

/// A group as the server describes it.
class GroupMeta {
  GroupMeta({required this.id, required this.name, required this.currency, required this.founders});

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

  factory GroupMeta.fromJson(Map<String, Object?> json) => GroupMeta(
    id: json['id']! as String,
    name: json['name']! as String,
    currency: json['currency']! as String,
    founders: [
      for (final m in json['founders']! as List<Object?>)
        Member.fromJson(m! as Map<String, Object?>),
    ],
  );
}

/// What a sync returns: the operations after `since`, and the newest seq.
class SyncResult {
  SyncResult(this.seq, this.ops);

  final int seq;
  final List<Op> ops;
}

/// The server could not be reached, or answered with something unexpected.
/// Pending changes stay on the device and go out on the next sync.
class OfflineError implements Exception {
  OfflineError(this.reason);

  final String reason;

  @override
  String toString() => 'OfflineError: $reason';
}

/// The server refused a request. [opId] names the operation it refused.
class RefusedError implements Exception {
  RefusedError(this.code, this.message, {this.opId});

  final String code;
  final String message;
  final String? opId;

  @override
  String toString() => 'RefusedError($code): $message';
}

/// Talks to the splitken server.
class ApiClient {
  ApiClient(this.base, {http.Client? client}) : _http = client ?? http.Client();

  final Uri base;
  final http.Client _http;

  Future<GroupMeta> createGroup(String name, String currency, List<String> members) async {
    final json = await _send('POST', '/v1/groups', {
      'name': name,
      'currency': currency,
      'members': members,
    });
    return GroupMeta.fromJson(json);
  }

  Future<GroupMeta> group(String id) async =>
      GroupMeta.fromJson(await _send('GET', '/v1/groups/${Uri.encodeComponent(id)}'));

  Future<SyncResult> sync(String groupId, int since, List<Op> ops) async {
    final json = await _send('POST', '/v1/groups/${Uri.encodeComponent(groupId)}/sync', {
      'since': since,
      'ops': [for (final op in ops) op.toJson()],
    });
    return SyncResult(json['seq']! as int, [
      for (final o in json['ops']! as List<Object?>) Op.fromJson(o! as Map<String, Object?>),
    ]);
  }

  Future<Map<String, Object?>> _send(String method, String path, [Object? body]) async {
    final http.Response response;
    try {
      final request = http.Request(method, base.resolve(path))
        ..headers['content-type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 15)),
      );
    } on Exception catch (e) {
      throw OfflineError('$e');
    }
    final Object? json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      throw OfflineError('HTTP ${response.statusCode} without JSON');
    }
    if (json is! Map<String, Object?>) {
      throw OfflineError('HTTP ${response.statusCode} without a JSON object');
    }
    if (response.statusCode >= 500) {
      throw OfflineError('HTTP ${response.statusCode}');
    }
    if (response.statusCode >= 400) {
      throw RefusedError(
        json['error'] as String? ?? 'refused',
        json['message'] as String? ?? 'HTTP ${response.statusCode}',
        opId: json['opId'] as String?,
      );
    }
    return json;
  }
}
