import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'player_controller.dart' show isDesktop;
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (isDesktop) await windowManager.ensureInitialized();
  final state = AppState();
  runApp(IptvApp(state: state));
  state.init();
}

class IptvApp extends StatelessWidget {
  const IptvApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeScreen(state: state),
    );
  }
}
