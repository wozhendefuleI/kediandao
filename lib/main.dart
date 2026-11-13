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
    // ⭐跟随系统修复：didChangePlatformBrightness 只在「变化时」触发，
    //   启动时必须显式读一次系统亮度（否则 _systemDark 停留默认值，system 模式不生效）
    ThemeController.I.setSystemDark(
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark);
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
        bottomNavigationBar: _buildHdsBar(),
      ),
    );
  }

  /// 底栏：对齐鸿蒙 HDS Tabs 官方语义——46vp 贴底通栏（非悬浮胶囊），
  /// 浅色底(accent_light)+选中项 accent 着色，无渐变/无二级按钮。栏高固定 46。
  Widget _buildHdsBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: c.surfNavSolid,
          border: Border(
            top: BorderSide(color: c.bdSoft, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            for (int i = 0; i < _tabs.length; i++) Expanded(child: _buildTabItem(i)),
          ],
        ),
      ),
    );
  }

  /// HDS 风格 tab 项：icon 22 + label 10，选中=accent 色（不铺渐变底），
  /// 未选中=ink45；点击态用 AnimatedContainer 平滑过渡颜色
  Widget _buildTabItem(int i) {
    final selected = _tab == i;
    final t = _tabs[i];
    final accent = V9G.finishColors(c.dark).first; // HDS lightColor=accent_brand 同源
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon, size: 22, color: selected ? accent : c.ink45),
            const SizedBox(height: 1),
            Text(
              t.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? accent : c.ink45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
