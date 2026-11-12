// ══════════════════════════════════════════════════════════════
// V9 Palette · 主题注入层（M6）
// 视图层不再直引 V9Dark/V9Light 常量，改经 InheritedWidget 取
// 当前调色板实例（c.ink / c.act2 ...），三模式切换零重建残留。
// 渐变族沿用 V9G.xxx(dark) 函数式（本就按 dark 参数化）。
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../engine/store.dart';
import 'v9_tokens.dart';

abstract class V9Palette {
  bool get dark;
  Color get bgPageBase;
  Color get surfCard;
  Color get surfCardSolid;
  Color get surfNavSolid;
  Color get surfSheet;
  Color get surfTrack;
  Color get dfBg;
  Color get searchBg;
  Color get bdGlass;
  Color get bdSoft;
  Color get ink;
  Color get ink60;
  Color get ink45;
  Color get act;
  Color get act2;
  Color get tint;
  Color get tintSoft;
  Color get saveBg;
  Color get saveBd;
  Color get purpleTxt;
  Color get warn;
  Color get warnSoft;
  Color get avatarBg;
  Color get mask;
}

class V9LightPalette implements V9Palette {
  const V9LightPalette();
  @override bool get dark => false;
  @override Color get bgPageBase => V9Light.bgPageBase;
  @override Color get surfCard => V9Light.surfCard;
  @override Color get surfCardSolid => V9Light.surfCardSolid;
  @override Color get surfNavSolid => V9Light.surfNavSolid;
  @override Color get surfSheet => V9Light.surfSheet;
  @override Color get surfTrack => V9Light.surfTrack;
  @override Color get dfBg => V9Light.dfBg;
  @override Color get searchBg => V9Light.searchBg;
  @override Color get bdGlass => V9Light.bdGlass;
  @override Color get bdSoft => V9Light.bdSoft;
  @override Color get ink => V9Light.ink;
  @override Color get ink60 => V9Light.ink60;
  @override Color get ink45 => V9Light.ink45;
  @override Color get act => V9Light.act;
  @override Color get act2 => V9Light.act2;
  @override Color get tint => V9Light.tint;
  @override Color get tintSoft => V9Light.tintSoft;
  @override Color get saveBg => V9Light.saveBg;
  @override Color get saveBd => V9Light.saveBd;
  @override Color get purpleTxt => V9Light.purpleTxt;
  @override Color get warn => V9Light.warn;
  @override Color get warnSoft => V9Light.warnSoft;
  @override Color get avatarBg => V9Light.avatarBg;
  @override Color get mask => V9Light.mask;
}

class V9DarkPalette implements V9Palette {
  const V9DarkPalette();
  @override bool get dark => true;
  @override Color get bgPageBase => V9Dark.bgPageBase;
  @override Color get surfCard => V9Dark.surfCard;
  @override Color get surfCardSolid => V9Dark.surfCardSolid;
  @override Color get surfNavSolid => V9Dark.surfNavSolid;
  @override Color get surfSheet => V9Dark.surfSheet;
  @override Color get surfTrack => V9Dark.surfTrack;
  @override Color get dfBg => V9Dark.dfBg;
  @override Color get searchBg => V9Dark.searchBg;
  @override Color get bdGlass => V9Dark.bdGlass;
  @override Color get bdSoft => V9Dark.bdSoft;
  @override Color get ink => V9Dark.ink;
  @override Color get ink60 => V9Dark.ink60;
  @override Color get ink45 => V9Dark.ink45;
  @override Color get act => V9Dark.act;
  @override Color get act2 => V9Dark.act2;
  @override Color get tint => V9Dark.tint;
  @override Color get tintSoft => V9Dark.tintSoft;
  @override Color get saveBg => V9Dark.saveBg;
  @override Color get saveBd => V9Dark.saveBd;
  @override Color get purpleTxt => V9Dark.purpleTxt;
  @override Color get warn => V9Dark.warn;
  @override Color get warnSoft => V9Dark.warnSoft;
  @override Color get avatarBg => V9Dark.avatarBg;
  @override Color get mask => V9Dark.mask;
}

class V9ThemeScope extends InheritedWidget {
  final V9Palette palette;
  const V9ThemeScope(
      {required this.palette, required super.child, super.key});

  static V9Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<V9ThemeScope>()!.palette;

  @override
  bool updateShouldNotify(V9ThemeScope oldWidget) =>
      oldWidget.palette.dark != palette.dark;
}

/// 主题三模式控制器（跟随系统/浅色/深色；KEY_THEME_MODE 同构）
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController I = ThemeController._();

  /// 'dark' | 'light' | 'system'（与鸿蒙 theme_mode 值域一致）
  String mode = 'dark';
  bool _systemDark = true;

  bool get dark => mode == 'system' ? _systemDark : mode == 'dark';
  V9Palette get palette =>
      dark ? const V9DarkPalette() : const V9LightPalette();

  Future<void> load() async {
    final saved = await Store.I.loadThemeMode();
    if (saved != null) mode = saved;
    notifyListeners();
  }

  Future<void> setMode(String m) async {
    if (mode == m) return;
    mode = m;
    notifyListeners();
    await Store.I.saveThemeMode(m);
  }

  /// 系统深浅变化（仅 system 模式生效）
  void setSystemDark(bool v) {
    if (_systemDark == v) return;
    _systemDark = v;
    if (mode == 'system') notifyListeners();
  }
}
