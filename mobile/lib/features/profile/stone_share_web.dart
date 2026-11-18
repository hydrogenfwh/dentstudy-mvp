import 'dart:js_interop';
import 'dart:ui' show Rect;
import 'package:share_plus/share_plus.dart' show ShareResultStatus;
import 'package:web/web.dart' as web;

Future<ShareResultStatus> shareStones({
  required String title,
  required String text,
  required Rect origin,
}) async {
  // share_plus 11 reports unavailable even when Web Share resolves. Await the
  // browser promise directly; never substitute mailto or clipboard fallback.
  // Call synchronously from the tap, preserving transient user activation.
  final data = web.ShareData(title: title, text: text);
  try {
    if (!web.window.navigator.canShare(data)) {
      return ShareResultStatus.unavailable;
    }
    await web.window.navigator.share(data).toDart;
    return ShareResultStatus.success;
  } on web.DOMException catch (error) {
    return error.name == 'AbortError'
        ? ShareResultStatus.dismissed
        : ShareResultStatus.unavailable;
  } catch (_) {
    // Unsupported APIs and other failures must never mint a reward.
    return ShareResultStatus.unavailable;
  }
}
