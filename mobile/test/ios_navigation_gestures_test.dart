import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('iOS home swipes change tabs without wrapping', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..token = ''
      ..userId = 'guest'
      ..email = ''
      ..glassEnabled = false
      ..xiaochiEnabled = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: const Home(initialTab: 1),
    ));
    await tester.pumpAndSettle();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
    await tester.fling(
        find.byType(Scaffold).first, const Offset(-250, 0), 1000);
    await tester.pumpAndSettle();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2);
    await tester.fling(find.byType(Scaffold).first, const Offset(250, 0), 1000);
    await tester.pumpAndSettle();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
  });

  testWidgets('library subpage hides navigation and edge swipe returns',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..token = ''
      ..userId = 'guest'
      ..email = ''
      ..glassEnabled = false
      ..xiaochiEnabled = false;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const Home(initialTab: 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-track-考研')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await tester.dragFrom(const Offset(5, 400), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('library-track-考研')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-track-考研')));
    await tester.pumpAndSettle();
    // Safari's back button dispatches the same platform popRoute.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-track-考研')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
