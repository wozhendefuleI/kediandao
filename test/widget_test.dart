import 'package:flutter_test/flutter_test.dart';
import 'package:kediandao/main.dart';

void main() {
  testWidgets('M1 骨架冒烟：三 Tab 可切、版本标记在场', (WidgetTester tester) async {
    await tester.pumpWidget(const V9App());
    await tester.pumpAndSettle();

    // 默认点名页 + 版本标记对质串
    expect(find.text('点名'), findsWidgets);
    expect(find.textContaining('android-dev M1'), findsOneWidget);

    // 切到「我的」
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.textContaining('M1-④'), findsOneWidget);
  });
}
