// ══════════════════════════════════════════════════════════════
// AppLog · 运行日志（鸿蒙 model/AppLog.ets 直译，M8-⑥）
// 环形缓冲 300 行；[MM-DD HH:mm:ss] tag: msg 格式；exportText 全量导出
// ══════════════════════════════════════════════════════════════

/// 运行日志（内存环形缓冲；与鸿蒙 AppLog 同构：MAX_LINES=300）
class AppLog {
  AppLog._();
  static const int maxLines = 300;
  static final List<String> _lines = [];

  /// 记录一条日志：[MM-DD HH:mm:ss] tag: msg
  static void log(String tag, String msg) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts =
        '${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    _lines.add('[$ts] $tag: $msg');
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
  }

  /// 导出全部日志文本（空=占位文案，对齐鸿蒙）
  static String exportText() =>
      _lines.isEmpty ? '（暂无日志）' : _lines.join('\n');
}
