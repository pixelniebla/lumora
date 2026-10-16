import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'l10n.dart' show translate;
import 'screens/dashboard_screen.dart';
import 'screens/sources_screen.dart';
import 'services/log.dart';
import 'services/player_service.dart';
import 'theme.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Log.init();
    FlutterError.onError = (d) {
      Log.e('Flutter error', d.exception, d.stack);
      FlutterError.presentError(d);
    };
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();

    final state = AppState();
    await state.initPrefs(); // fast: preferences only, the window opens right away
    runApp(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        Provider<PlayerService>(create: (_) => PlayerService(), dispose: (_, p) => p.dispose()),
      ],
      child: const IptvApp(),
    ));
    unawaited(state.restoreLast()); // cached lists appear instantly, refresh happens in background
    unawaited(state.maybeCheckUpdates());
    state.onReminder = (it) => messengerKey.currentState?.showSnackBar(SnackBar(
          duration: const Duration(seconds: 20),
          content: Text(translate(state.lang, 'sched_remind_msg', args: {'title': it.title, 'ch': it.channelName})),
        ));
    state.onRecordingFinished = (it, path) {
      if (path != null) {
        messengerKey.currentState?.showSnackBar(SnackBar(content: Text(translate(state.lang, 'sched_done', args: {'path': path}))));
      }
    };
    state.startScheduler();
  }, (e, st) => Log.e('Uncaught', e, st));
}

/// Lets non-UI code (reminders, finished recordings) show a message.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumora',
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      theme: lumoraTheme(),
      home: Selector<AppState, bool>(
        selector: (_, s) => s.library != null,
        builder: (_, hasLibrary, _) => hasLibrary ? const DashboardScreen() : const SourcesScreen(),
      ),
    );
  }
}
