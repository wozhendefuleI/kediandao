import 'package:flutter_test/flutter_test.dart';
import 'package:kediandao/main.dart';

void main() {
  testWidgets('M1 骨架冒烟：三 Tab 可切、版本标记在场', (WidgetTester tester) async {
    await tester.pumpWidget(const V9App());
    await tester.pumpAndSettle();

    // 默认点名页 + 版本标记对质串
    expect(find.text('点名'), findsWidgets);
    expect(find.textContaining('android-dev M'), findsOneWidget);

    // 切到「我的」（Tab 栏的项 = 最后一个匹配；页面标题同名在前）
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('数据管理'), findsOneWidget);
  });
}
