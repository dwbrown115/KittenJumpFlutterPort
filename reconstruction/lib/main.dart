import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/game_store.dart';
import 'ui/game_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const KittenJumpApp());
}

class KittenJumpApp extends StatelessWidget {
  const KittenJumpApp({super.key, this.store});
  final GameStore? store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kitten Jump Christmas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff283b62),
        surface: const Color(0xfff8fbff),
      ),
      scaffoldBackgroundColor: const Color(0xff172235),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    ),
    home: store != null ? GameScreen(store: store!) : const _Bootstrap(),
  );
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<GameStore> _store = GameStore.open();

  @override
  Widget build(BuildContext context) => FutureBuilder<GameStore>(
    future: _store,
    builder: (context, snapshot) {
      if (snapshot.hasData) return GameScreen(store: snapshot.data!);
      return Scaffold(
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            color: const Color(0xfff8fbff),
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load your saved scores.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            setState(() => _store = GameStore.open()),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading Kitten Jump Christmas…'),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
