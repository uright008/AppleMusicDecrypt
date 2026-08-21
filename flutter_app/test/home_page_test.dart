import 'package:applemusicdecrypt_android/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'apiUrl': 'http://127.0.0.1:1',
    });
  });

  testWidgets('download controls do not overflow on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: HomePage()),
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
  });

  testWidgets('backend URL dialog closes without a lifecycle assertion',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomePage()),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final apiField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'API 地址',
    );
    await tester.enterText(apiField, 'http://127.0.0.1:2');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
