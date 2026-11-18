import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'app/app.dart';
import 'app/shared.dart';
export 'app/app.dart' show DentStudy;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

Future<void> _start() async {
  try {
    await store.init();
    // The browser has no notification implementation and can start with
    // storage access in a transient state.  Keep its first render independent
    // of the retired native-notification cleanup.
    if (!kIsWeb) {
      await store.prefs.setBool('reminders', false);
      try {
        await reminders.disable();
      } catch (_) {
        // Notification cleanup must never prevent the learning app from opening.
      }
    }
    runApp(const DentStudy());
  } catch (e) {
    runApp(MaterialApp(home: _StartupFailure(error: e)));
  }
}

class _StartupFailure extends StatefulWidget {
  final Object error;
  const _StartupFailure({required this.error});
  @override
  State<_StartupFailure> createState() => _StartupFailureState();
}

class _StartupFailureState extends State<_StartupFailure> {
  bool retrying = false;

  Future<void> retry() async {
    if (retrying) return;
    setState(() => retrying = true);
    await _start();
    if (mounted) setState(() => retrying = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('学习数据加载失败，请保留本机数据。\n${widget.error}'),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: retrying ? null : retry,
                        child: Text(retrying ? '正在重试…' : '重新加载')),
                  ])))));
}
