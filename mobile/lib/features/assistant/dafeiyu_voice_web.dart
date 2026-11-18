import 'dart:js_interop';
import 'package:web/web.dart' as web;

class DafeiyuVoicePlayer {
  final web.HTMLAudioElement _audio = web.HTMLAudioElement();
  bool get available => true;

  Future<bool> play(String asset) async {
    try {
      _audio.pause();
      _audio.src = Uri.base.resolve('assets/$asset').toString();
      await _audio.play().toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  void stop() {
    _audio.pause();
    _audio.currentTime = 0;
  }

  void dispose() {
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
  }
}
