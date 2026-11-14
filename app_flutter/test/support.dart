import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:splitken/src/api_client.dart';
import 'package:splitken_server/splitken_server.dart';

/// The real splitken server API on an in-memory store, reached through a
/// mock HTTP client. Set [online] to false to make every request fail as it
/// does with no network.
class TestServer {
  TestServer() {
    _handler = buildApi(store);
  }

  final store = MemoryStore();
  late final shelf.Handler _handler;
  bool online = true;
  int requests = 0;

  ApiClient client() => ApiClient(
    Uri.parse('http://splitken.test'),
    client: MockClient((request) async {
      requests++;
      if (!online) throw http.ClientException('no network', request.url);
      final response = await _handler(
        shelf.Request(
          request.method,
          request.url,
          headers: request.headers,
          body: request.bodyBytes,
        ),
      );
      return http.Response(
        await response.readAsString(),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );
}
