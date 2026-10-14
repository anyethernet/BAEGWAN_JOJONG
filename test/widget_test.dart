import 'dart:io';

import 'package:dronctl_app/net/pipe_link.dart';
import 'package:dronctl_app/ui/drive_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future<http.StreamedResponse>.error(const SocketException('offline'));
  }
}

void main() {
  testWidgets('drive hud shows sticks, leds, and stop', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final link = PipeLink(httpClient: _Offline());
    addTearDown(link.dispose);

    await tester.pumpWidget(MaterialApp(home: DrivePage(link: link)));
    await tester.pump();

    expect(find.byKey(const Key('stick-move')), findsOneWidget);
    expect(find.byKey(const Key('stick-vert')), findsOneWidget);
    expect(find.byKey(const Key('led-1')), findsOneWidget);
    expect(find.byKey(const Key('led-2')), findsOneWidget);
    expect(find.byKey(const Key('led-4')), findsNothing);
    expect(find.text('밝기'), findsWidgets);
    expect(find.text('게인'), findsWidgets);
    expect(find.text('노출'), findsWidgets);
    expect(find.text('정지'), findsOneWidget);
    expect(find.text('상승 후 전진'), findsOneWidget);
    expect(find.text('상승'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pump();
    expect(find.text('기록 시작'), findsOneWidget);
    expect(find.text('기록 정지'), findsOneWidget);
    expect(find.text('상태 점검'), findsOneWidget);
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
