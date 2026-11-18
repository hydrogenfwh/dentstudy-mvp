import 'package:flutter/material.dart';
import '../store.dart';
import '../reminders.dart';
import 'theme_palette.dart';
import 'theme_surfaces.dart';
import 'motion.dart';
import 'language_state.dart';
export 'theme_palette.dart';
export 'language_state.dart' show tr, usesEnglish;

final store = StudyStore();
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();
final reminders = Reminders();
Color get teal =>
    themeColors[store.themeColorKey == 'custom'
        ? store.customPrimaryKey
        : store.themeColorKey] ??
    themeColors['teal']!;
Color get activeThemeColor => teal;
Color get ink => Color.lerp(const Color(0xFF253238), teal, .18)!;
// A constant tint ratio preserves the light/dark hierarchy across hues.
Color get backgroundTint =>
    themeColors[store.themeColorKey == 'custom'
        ? store.customBackgroundKey
        : store.themeColorKey] ??
    themeColors['teal']!;
Color get paper => Color.lerp(Colors.white, backgroundTint, .045)!;
Color studyBackground(Brightness brightness) => brightness == Brightness.dark
    ? Color.lerp(const Color(0xFF101516), backgroundTint, .08)!
    : paper;
void message(BuildContext c, String text) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(tr(text))));
Future<void> safely(BuildContext c, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (c.mounted) message(c, e.toString());
  }
}

Widget box(Widget child, {Color? color}) => Builder(builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return StudySurface(
          glass: store.glassEnabled,
          tint: backgroundTint,
          borderColor: colors.onSurface.withAlpha(18),
          color: color ?? colors.surface,
          child: child);
    });
Widget studyCard({required Widget child}) => PressFeedback(
    child: store.glassEnabled
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: StudySurface(
                glass: true,
                tint: backgroundTint,
                borderColor: Colors.transparent,
                radius: 18,
                padding: EdgeInsets.zero,
                child: child))
        : Card(child: child));
Widget heading(String text, {String? sub}) => Builder(builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(text),
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface)),
            if (sub != null)
              Text(tr(sub),
                  style:
                      TextStyle(color: colors.onSurfaceVariant, fontSize: 13))
          ]));
    });

Widget pill(String text) => Builder(builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: colors.primary.withAlpha(16),
              borderRadius: BorderRadius.circular(8)),
          child: Text(tr(text),
              style: TextStyle(fontSize: 12, color: colors.primary)));
    });

class PageBody extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  const PageBody({super.key, required this.children, this.controller});
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      bottom: false,
      child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                  controller: controller,
                  // Insets belong to the scroll content, so it can pass behind
                  // the glass chrome while the first/last controls remain clear.
                  padding: EdgeInsets.fromLTRB(
                      20,
                      MediaQuery.paddingOf(context).top,
                      20,
                      32 + MediaQuery.paddingOf(context).bottom),
                  children: children))));
}
