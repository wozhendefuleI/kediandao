import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/v9_tokens.dart';
import 'theme/v9_palette.dart';
import 'views/checkin_view.dart';
import 'views/me_view.dart';
import 'views/stats_view.dart';

void main() {
  runApp(const V9App());
}

/// 主题三模式挂载：ThemeController(持久化) → V9App 监听 → ThemeScope 下发
/// 三视图保活（IndexedStack，对齐鸿蒙 V9Home 语义）+ 悬浮胶囊导航。
class V9App extends StatelessWidget {
  const V9App({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ThemeController.I;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final c = t.palette;
        return V9ThemeScope(
          palette: c,
          child: MaterialApp(
            title: '课点到',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              brightness: c.dark ? Brightness.dark : Brightness.light,
              scaffoldBackgroundColor: V9G.bgFlat(c.dark),
              colorScheme: c.dark
                  ? const ColorScheme.dark(
                      primary: V9Dark.act2,
                      secondary: V9Dark.act,
                      surface: V9Dark.surfCardSolid)
                  : const ColorScheme.light(
                      primary: V9Light.act2,
                      secondary: V9Light.act,
                      surface: V9Light.surfCardSolid),
            ),
            home: const V9HomePage(),
          ),
        );
      },
    );
  }
}

class V9HomePage extends StatefulWidget {
  const V9HomePage({super.key});

  @override
  State<V9HomePage> createState() => _V9HomePageState();
}

class _V9HomePageState extends State<V9HomePage>
    with WidgetsBindingObserver {
  int _tab = 0; // 0 点名 1 统计 2 我的

  V9Palette get c => V9ThemeScope.of(context);

  static const List<({IconData icon, String label})> _tabs = [
    (icon: Icons.radio_button_checked, label: '点名'),
    (icon: Icons.bar_chart, label: '统计'),
    (icon: Icons.person, label: '我的'),
  ];

  /// 三视图保活（对齐 V9Home IndexedStack 语义）
  final List<Widget> _views = const [
    CheckinView(),
    StatsView(),
    MeView(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeController.I.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // DartSDK 3.x：WidgetsBinding 上的便捷 getter 已移除，走 FlutterView
    final view = WidgetsBinding.instance.platformDispatcher;
    ThemeController.I.setSystemDark(
        view.platformBrightness == Brightness.dark);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: V9G.bgFlat(c.dark),
        body: IndexedStack(index: _tab, children: _views),
        bottomNavigationBar: _buildPillBar(),
      ),
    );
  }

  /// 悬浮胶囊底栏（实色降级 + 渐变选中指示）
  Widget _buildPillBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(48, 0, 48, 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: c.surfNavSolid,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: c.bdSoft),
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
          gradient: selected ? LinearGradient(colors: V9G.tabColors(c.dark)) : null,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon, size: 20, color: selected ? Colors.white : c.ink45),
            const SizedBox(height: 2),
            Text(
              t.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white : c.ink45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
