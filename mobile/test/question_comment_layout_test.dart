import 'dart:convert';

import 'package:dentstudy/app/shared.dart' show store;
import 'package:dentstudy/features/practice/question_comments.dart';
import 'package:dentstudy/features/profile/user_avatar.dart';
import 'package:dentstudy/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final width in [320.0, 760.0]) {
    testWidgets('discussion replies align with the parent text at width $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      store.baseUrl = 'https://discussion.test';
      const longReply = '这里是比较长的回复，用来检查窄屏上正文换行后，回复和删除按钮是否仍然能使用。';
      final comments = [
        {'id': 'a', 'body': '主评论'},
        {'id': 'b', 'parentId': 'a', 'body': longReply, 'canDelete': true},
        {'id': 'c', 'parentId': 'b', 'body': '继续回复'},
        {'id': 'd', 'body': '另一条主评论'},
      ];
      final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(
              jsonEncode({'comments': comments, 'participantCount': 2})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'}));

      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
                body: SingleChildScrollView(
                    child:
                        QuestionComments(question: Question({'id': 'q1'}))))));
        await tester.pumpAndSettle();

        final avatars = find.byType(UserAvatar);
        double left(Finder f) => tester.getTopLeft(f).dx;
        expect(left(avatars.at(1)), left(find.text('主评论')));
        expect(left(avatars.at(2)), left(avatars.at(1)));
        expect(left(avatars.at(3)), left(avatars.first));
        expect(left(find.text(longReply)), greaterThan(left(avatars.at(1))));
        final delete = find.widgetWithText(TextButton, '删除');
        expect(left(delete), greaterThanOrEqualTo(left(find.text(longReply))));
        expect(tester.getTopRight(delete).dx, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }
}
