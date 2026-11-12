import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/v9_tokens.dart';
import 'version.dart' show kVersionMark;
import 'views/checkin_view.dart';
import 'views/me_view.dart';

/// 版本标记对质串（纪律7：模拟器看到 = 已实装）— 单源已迁至 lib/version.dart

void main() {
  runApp(const V9App());
}

/// M1 骨架：暗夜葡萄默认 + 三 Tab 保活挂载
/// 对齐鸿蒙 V9Home 语义：IndexedStack 保活 + 底部悬浮胶囊导航（降级实色）。
/// 主题三模式（light/system）随「我的-外观」在 M4 落地，M1 先钉 dark。
class V9App extends StatelessWidget {
  const V9App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '课点到',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: V9G.bgFlat(true),
        colorScheme: const ColorScheme.dark(
          primary: V9Dark.act2,
          secondary: V9Dark.act,
          surface: V9Dark.surfCardSolid,
        ),
      ),
      home: const V9HomePage(),
    );
  }
}

class V9HomePage extends StatefulWidget {
  const V9HomePage({super.key});

  @override
  State<V9HomePage> createState() => _V9HomePageState();
}

class _V9HomePageState extends State<V9HomePage> {
  int _tab = 0; // 0 点名 1 统计 2 我的

  static const List<({IconData icon, String label})> _tabs = [
    (icon: Icons.radio_button_checked, label: '点名'),
    (icon: Icons.bar_chart, label: '统计'),
    (icon: Icons.person, label: '我的'),
  ];

  /// 三视图保活（对齐 V9Home IndexedStack 语义）
  final List<Widget> _views = const [
    CheckinView(),
    _StatsView(),
    MeView(),
  ];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light, // 暗底白字状态栏
      child: Scaffold(
        backgroundColor: V9G.bgFlat(true),
        body: IndexedStack(index: _tab, children: _views),
        bottomNavigationBar: _buildPillBar(),
      ),
    );
  }

  /// 悬浮胶囊底栏（降级实色版：surfNavSolid 实底 + 渐变选中指示）
  /// 鸿蒙对照：ptab 悬浮胶囊 + V9G.tab(dark) 渐变指示
  Widget _buildPillBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(48, 0, 48, 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: V9Dark.surfNavSolid,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: V9Dark.bdSoft),
        ),
        child: Row(
          children: [
            for (int i = 0; i < _tabs.length; i++)
              Expanded(child: _buildTabItem(i)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int i) {
    final selected = _tab == i;
    final t = _tabs[i];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(colors: V9G.tabColors(true))
              : null,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon,
                size: 20,
                color: selected ? Colors.white : V9Dark.ink45),
            const SizedBox(height: 2),
            Text(
              t.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : V9Dark.ink45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── M1 占位视图（统计/我的；点名页已实装 lib/views/checkin_view.dart）──

class _StatsView extends StatelessWidget {
  const _StatsView();

  @override
  Widget build(BuildContext context) {
    return _PlaceholderPage(
      title: '统计',
      hint: 'M1-⑤ 待实现：本月统计 / 记录详情',
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  final String title;
  final String hint;
  const _PlaceholderPage({required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: V9Dark.ink)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: V9Dark.tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(kVersionMark,
                      style:
                          TextStyle(fontSize: 11, color: V9Dark.ink60)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: V9Dark.surfCardSolid, // 降级实色卡片
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: V9Dark.bdSoft),
                ),
                child: Text(hint,
                    style: const TextStyle(
                        fontSize: 13, color: V9Dark.ink45, height: 1.6)),
              ),
            ),
            const SizedBox(height: 88), // 给胶囊底栏让位
          ],
        ),
      ),
    );
  }
}
