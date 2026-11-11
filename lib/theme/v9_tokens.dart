// ══════════════════════════════════════════════════════════════
// V9 Token 单源 · 从鸿蒙 v1.1.10 (3870d4f) 直译
//   静态色板 ← resources/base + dark/element/color.json (v9_* 31键)
//   渐变族   ← pages/v9/V9Theme.ets V9G 类
// 纪律：改色先改鸿蒙资源再同步此文件；两端 token 名保持同名对照。
// 玻璃质感说明：surf_card/glass_card 为半透明设计，M1 先按「降级实色」
//   路线跑（用 *_solid 值），BackdropFilter 玻璃作为拍板后的升级候选。
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// 外观三模式（对齐鸿蒙 KEY_THEME_MODE light/dark/system）
enum V9Mode { dark, light, system }

/// 浅色主题（奶油纸面）— base/element/color.json
class V9Light {
  static const bgPageBase = Color(0xFFF3F0FA);
  static const surfCard = Color(0xBDFFFFFF);
  static const surfCardSolid = Color(0xFFFFFFFF);
  static const surfNavRepl = Color(0xA3FFFFFF);
  static const surfNavSolid = Color(0xFFFFFFFF);
  static const surfSheet = Color(0xE0FFFFFF);
  static const surfTrack = Color(0x12221A38);
  static const dfBg = Color(0xCCF4F2F9);
  static const searchBg = Color(0x8CFFFFFF);
  static const glassCard = Color(0xBDFFFFFF);
  static const glassCardSolid = Color(0xFFFFFFFF);
  static const bdGlass = Color(0xD9FFFFFF);
  static const bdSoft = Color(0x12221A38);
  static const ink = Color(0xFF221A38);
  static const ink60 = Color(0x99221A38);
  static const ink45 = Color(0x8C221A38);
  static const act = Color(0xFF0A59F7);
  static const act2 = Color(0xFF5B21D6);
  static const tint = Color(0x1A5B21D6);
  static const tintSoft = Color(0x145B21D6);
  static const saveBg = Color(0x145B21D6);
  static const saveBd = Color(0x405B21D6);
  static const purpleTxt = Color(0xFF5B21D6);
  static const purpleDeepTxt = Color(0xFF4C1D95);
  static const warn = Color(0xFFC2410C);
  static const warnSoft = Color(0xFFFBEAE0);
  static const avatarBg = Color(0x145B21D6);
  static const mask = Color(0x66221A38);
  static const hiInset = Color(0xF2FFFFFF);
  static const blueTxt = Color(0xFF0A59F7);
  static const toastBg = Color(0xEB2E1065);
}

/// 深色主题（暗夜葡萄，默认）— dark/element/color.json
class V9Dark {
  static const bgPageBase = Color(0xFF080B14);
  static const surfCard = Color(0x0BFFFFFF);
  static const surfCardSolid = Color(0xFF141A28);
  static const surfNavRepl = Color(0xAD141A26);
  static const surfNavSolid = Color(0xFF141A26);
  static const surfSheet = Color(0xD1181A30);
  static const surfTrack = Color(0x12FFFFFF);
  static const dfBg = Color(0x0BFFFFFF);
  static const searchBg = Color(0x08FFFFFF);
  static const glassCard = Color(0x0BFFFFFF);
  static const glassCardSolid = Color(0xFF141A28);
  static const bdGlass = Color(0x14FFFFFF);
  static const bdSoft = Color(0x0FFFFFFF);
  static const ink = Color(0xFFF2F5FA);
  static const ink60 = Color(0x9EF2F5FA);
  static const ink45 = Color(0x80F2F5FA);
  static const act = Color(0xFF5B8CFF);
  static const act2 = Color(0xFF8B5CF6);
  static const tint = Color(0x4D5B21D6);
  static const tintSoft = Color(0x14FFFFFF);
  static const saveBg = Color(0x290A59F7);
  static const saveBd = Color(0x665B8CFF);
  static const purpleTxt = Color(0xFF8B5CF6);
  static const purpleDeepTxt = Color(0xFFD8CCFF);
  static const warn = Color(0xFFFF9F5A);
  static const warnSoft = Color(0x24FF8F40);
  static const avatarBg = Color(0x14FFFFFF);
  static const mask = Color(0x8005070E);
  static const hiInset = Color(0x24FFFFFF);
  static const blueTxt = Color(0xFF5B8CFF);
  static const toastBg = Color(0xF21E223C);
}

/// 渐变族 — V9Theme.ets V9G 类直译（stops = [色, 位置]）
class V9G {
  /// --grad-tab 底栏选中指示
  static List<Color> tabColors(bool dark) => dark
      ? [Color(0xF25B21D6), Color(0xD94C1D95)]
      : [Color(0xFF7C3AED), Color(0xFF5B21D6)];

  /// --grad-finish 完成按钮/主 CTA（fill 进度条同用此对）
  static List<Color> finishColors(bool dark) => dark
      ? [Color(0xFF0A59F7), Color(0xFF5B21D6)]
      : [Color(0xFF2E6BFF), Color(0xFF5B21D6)];

  /// --grad-check hero 打勾圆（双主题同）
  static const checkColors = [Color(0xFF8B5CF6), Color(0xFF6D28D9)];

  /// --grad-seg 课时分段控件
  static List<Color> segColors(bool dark) => dark
      ? [Color(0xFF6D3AED), Color(0xFF4C1D95)]
      : [Color(0xFF7C3AED), Color(0xFF5B21D6)];

  /// --bg-page 基底线性（168deg ≈ 纵向；光晕层单独叠）
  static List<Color> bgBaseColors(bool dark) => dark
      ? [Color(0xFF0C1220), Color(0xFF080B14), Color(0xFF0D0A1A)]
      : [Color(0xFFF9F7FD), Color(0xFFF3F0FA), Color(0xFFF0ECF8)];

  /// 降级基底（V9Perf.low 语义：单色实底）——M1 安卓默认走这条
  static Color bgFlat(bool dark) =>
      dark ? const Color(0xFF0A0E18) : const Color(0xFFF3F1FA);

  /// 光晕层 1：90% -4% 紫（dark .26 / light .12）
  static List<Color> glow1Colors(bool dark) => dark
      ? [Color(0x425B21D6), Color(0x005B21D6)]
      : [Color(0x1F7C3AED), Color(0x007C3AED)];

  /// 光晕层 2：50% 108% 紫（dark .14 / light .09）
  static List<Color> glow2Colors(bool dark) => dark
      ? [Color(0x245B21D6), Color(0x005B21D6)]
      : [Color(0x177C3AED), Color(0x007C3AED)];

  /// grad_hero：完成弹层 hero（dark 半透明紫 / light 实底紫）
  static List<Color> heroColors(bool dark) => dark
      ? [Color(0x668B5CF6), Color(0x804C1D95)]
      : [Color(0xFF7C3AED), Color(0xFF5B21D6), Color(0xFF4C1D95)];
}
