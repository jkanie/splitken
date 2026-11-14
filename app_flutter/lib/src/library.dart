import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'api_client.dart';
import 'group_book.dart';
import 'ids.dart';
import 'key_value_store.dart';

/// Every group on this device, and the device's client id.
class Library extends ChangeNotifier {
  Library._(this.clientId, this._api, this._store, this.books);

  final String clientId;
  final ApiClient _api;
  final KeyValueStore _store;
  final List<GroupBook> books;

  static const _clientKey = 'clientId';
  static const _groupsKey = 'groups';

  /// Loads the groups saved on this device. The 1st run makes a client id.
  static Future<Library> load(ApiClient api, KeyValueStore store) async {
    var clientId = await store.read(_clientKey);
    if (clientId == null) {
      clientId = 'c${randomId(11)}';
      await store.write(_clientKey, clientId);
    }
    final ids = (jsonDecode(await store.read(_groupsKey) ?? '[]') as List<Object?>).cast<String>();
    final books = <GroupBook>[];
    for (final id in ids) {
      final saved = await store.read(GroupBook.storageKey(id));
      if (saved == null) continue;
      books.add(
        GroupBook.fromJson(
          jsonDecode(saved) as Map<String, Object?>,
          clientId: clientId,
          api: api,
          store: store,
        ),
      );
    }
    return Library._(clientId, api, store, books);
  }

  /// Makes a group on the server. This 1 step needs the network.
  Future<GroupBook> create(String name, String currency, List<String> members) async {
    return _keep(await _api.createGroup(name, currency, members));
  }

  /// Joins a group by the id someone shared, and fetches its history.
  Future<GroupBook> join(String id) async {
    final existing = books.where((b) => b.meta.id == id).firstOrNull;
    if (existing != null) return existing;
    final book = await _keep(await _api.group(id.trim()));
    await book.sync();
    return book;
  }

  /// Forgets a group on this device. Its pending changes are lost.
  Future<void> remove(GroupBook book) async {
    books.remove(book);
    await _store.delete(GroupBook.storageKey(book.meta.id));
    await _saveIds();
    notifyListeners();
  }

  Future<GroupBook> _keep(GroupMeta meta) async {
    final book = GroupBook(meta: meta, clientId: clientId, api: _api, store: _store);
    books.add(book);
    await book.save();
    await _saveIds();
    notifyListeners();
    return book;
  }

  Future<void> _saveIds() =>
      _store.write(_groupsKey, jsonEncode([for (final b in books) b.meta.id]));
}
