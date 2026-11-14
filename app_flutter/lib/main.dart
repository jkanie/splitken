import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/api_client.dart';
import 'src/key_value_store.dart';
import 'src/library.dart';
import 'src/screens/home_screen.dart';

/// The server to sync with. Set it with
/// `--dart-define=SPLITKEN_API=https://host:port`.
const apiBase = String.fromEnvironment('SPLITKEN_API', defaultValue: 'http://localhost:8080');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await Library.load(
    ApiClient(Uri.parse(apiBase)),
    PrefsKeyValueStore(SharedPreferencesAsync()),
  );
  runApp(SplitkenApp(library: library));
}

class SplitkenApp extends StatelessWidget {
  const SplitkenApp({super.key, required this.library});

  final Library library;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'splitken',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      home: HomeScreen(library: library),
    );
  }
}
