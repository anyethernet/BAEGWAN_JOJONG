import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'net/pipe_link.dart';
import 'ui/drive_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockPlus.enable();
  final link = PipeLink();
  await link.loadPrefs();
  link.start();
  runApp(DronCtlApp(link: link));
}

class DronCtlApp extends StatefulWidget {
  const DronCtlApp({super.key, required this.link});

  final PipeLink link;

  @override
  State<DronCtlApp> createState() => _DronCtlAppState();
}

class _DronCtlAppState extends State<DronCtlApp> {
  @override
  void dispose() {
    widget.link.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '배관조종',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070D1C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A75E2),
          brightness: Brightness.dark,
        ),
      ),
      home: DrivePage(link: widget.link),
    );
  }
}
