import 'package:applemusicdecrypt_android/api_client.dart';
import 'package:applemusicdecrypt_android/grpc/manager_messages.dart';
import 'package:applemusicdecrypt_android/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeManagerTransport implements ManagerTransport {
  @override
  Future<StatusData> status() async => const StatusData(
        status: true,
        regions: ['us'],
        clientCount: 1,
        ready: true,
      );

  @override
  Future<int> login(String username, String password) async => 0;

  @override
  Future<int> submitTwoFactor(String username, String code) async => 0;

  @override
  Future<void> logout(String username) async {}

  @override
  Future<void> close() async {}
}

ApiClient _fakeApi(String endpoint) => ApiClient(
      baseUrl: endpoint,
      transport: _FakeManagerTransport(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('download controls do not overflow on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialApiUrl: 'grpc://127.0.0.1:8080',
          onApiUrlChanged: (_) async {},
          apiFactory: _fakeApi,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    expect(dropdowns, findsNWidgets(2));
    expect(
      tester.getTopLeft(dropdowns.at(1)).dy,
      greaterThan(tester.getTopLeft(dropdowns.at(0)).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('manager URL dialog closes without a lifecycle assertion',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialApiUrl: 'grpc://127.0.0.1:8080',
          onApiUrlChanged: (_) async {},
          apiFactory: _fakeApi,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final managerField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'gRPC 地址',
    );
    await tester.enterText(managerField, 'grpc://127.0.0.1:8081');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
