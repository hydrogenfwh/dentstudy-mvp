import 'dart:ui' show Rect;
import 'package:share_plus/share_plus.dart';

Future<ShareResultStatus> shareStones({
  required String title,
  required String text,
  required Rect origin,
}) async {
  final result = await SharePlus.instance.share(ShareParams(
    title: title,
    text: text,
    downloadFallbackEnabled: false,
    mailToFallbackEnabled: false,
    sharePositionOrigin: origin,
  ));
  return result.status;
}
