import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:splitken_server/splitken_server.dart';

/// Starts the server on PORT (8080 by default).
///
/// DATABASE_URL names the PostgreSQL database, such as
/// `postgresql://splitken:splitken@localhost:5432/splitken?sslmode=disable`.
/// `--memory` keeps everything in memory instead, for a quick try-out.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final Store store;
  if (args.contains('--memory')) {
    store = MemoryStore();
    stderr.writeln('splitken: in-memory store, nothing is kept after exit');
  } else {
    final url = env['DATABASE_URL'];
    if (url == null || url.isEmpty) {
      stderr.writeln('splitken: set DATABASE_URL, or pass --memory');
      exit(2);
    }
    store = await PostgresStore.open(url);
  }
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(buildApi(store));
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stderr.writeln('splitken: listening on port ${server.port}');
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close();
    await store.close();
    exit(0);
  });
}
