// ══════════════════════════════════════════════════════════════
// Store · 持久化层（M2）
// 存储形态决策：与鸿蒙 DataStore「整库 JSON 单键」同构——存档文件
// 即备份文件（app/format/exportedAt/classId/...，口径 §5），零转译。
// 纪律落实：
//   纪律1 await 落盘 —— persist() 写临时文件再 rename 原子覆盖
//   纪律3 ID 单调 —— 装载后跑 repairDuplicateStudentIds（v29.15 同构）
//   纪律5 导入前快照 —— snapshotBefore() 滚动保留最近 10 份
// ══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'checkin_engine.dart';

class Store {
  Store._();
  static final Store I = Store._();

  static const int kFormat = 2;
  static const String kAppTag = '课点到';
  static const int kMaxSnapshots = 10;

  String? _docsDir;

  Future<String> _dir() async {
    if (_docsDir != null) return _docsDir!;
    final docs = await getApplicationDocumentsDirectory();
    _docsDir = docs.path;
    return _docsDir!;
  }

  Future<String> dataFilePath() async => '${await _dir()}/kediandao_data.json';

  // ── JSON 编解码（口径 §5：字段与鸿蒙备份一一对应）──

  static Map<String, dynamic> encode(CheckInEngine eng) => {
        'app': kAppTag,
        'format': kFormat,
        'exportedAt': DateTime.now().toIso8601String(),
        'classId': 'cls_android_main',
        'className': eng.className,
        'students': [
          for (final s in eng.students)
            {
              'id': s.id,
              'name': s.name,
              'className': s.className,
              'payType': s.payType,
              'totalHours': s.totalHours,
              'usedHours': s.usedHours,
              'remainingHours': s.remainingHours,
              'totalSessions': s.totalSessions,
              'monthlySessions': s.monthlySessions,
            }
        ],
        'records': [
          for (final r in eng.records)
            {
              'date': r.date,
              'studentId': r.studentId,
              'studentName': r.studentName,
              'timestamp': r.timestamp,
              'hours': r.hours,
            }
        ],
        'studentIdCounter': eng.studentIdCounter,
      };

  /// 解码到引擎（fresh 对象重建 = v29.15「源头重建实例」同构语义）
  /// 返回 null 表示文件不存在/格式不符（调用方保持内存态不变）
  static CheckInEngine? decodeToEngine(String text, CheckInEngine eng) {
    final payload = jsonDecode(text);
    if (payload is! Map<String, dynamic>) return null;
    if (payload['app'] != kAppTag) return null;
    final students = payload['students'];
    final records = payload['records'];
    if (students is! List || records is! List) return null;

    eng.students
      ..clear()
      ..addAll([
        for (final raw in students)
          Student(
            id: (raw['id'] as num).toInt(),
            name: raw['name'] as String? ?? '',
            className: raw['className'] as String? ?? '',
            payType: raw['payType'] as String? ?? 'semester',
            totalHours: (raw['totalHours'] as num?)?.toDouble() ?? 30,
            usedHours: (raw['usedHours'] as num?)?.toDouble() ?? 0,
            remainingHours: (raw['remainingHours'] as num?)?.toDouble() ?? 0,
            totalSessions: (raw['totalSessions'] as num?)?.toInt() ?? 0,
            monthlySessions: (raw['monthlySessions'] as num?)?.toInt() ?? 0,
          )
      ]);
    eng.records
      ..clear()
      ..addAll([
        for (final raw in records)
          CheckInRecord(
            date: raw['date'] as String? ?? '',
            studentId: (raw['studentId'] as num).toInt(),
            studentName: raw['studentName'] as String? ?? '',
            timestamp: (raw['timestamp'] as num?)?.toInt() ?? 0,
            hours: (raw['hours'] as num?)?.toDouble() ?? 1,
          )
      ]);
    eng.className = payload['className'] as String? ?? '我的班';
    eng.studentIdCounter = (payload['studentIdCounter'] as num?)?.toInt() ?? 0;
    eng.repairDuplicateStudentIds(); // 口径 §2.4 自愈
    return eng;
  }

  // ── 读写 ──

  /// 纪律1：await 落盘 + 原子覆盖（临时文件 → rename）
  Future<bool> persist(CheckInEngine eng) async {
    try {
      final path = await dataFilePath();
      final tmp = '$path.tmp';
      final f = File(tmp);
      await f.writeAsString(jsonEncode(encode(eng)), flush: true);
      await f.rename(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 装载：文件不存在或损坏 → 返回 false（内存态不动，种子数据可继续用）
  Future<bool> load(CheckInEngine eng) async {
    try {
      final f = File(await dataFilePath());
      if (!f.existsSync()) return false;
      final text = await f.readAsString();
      return decodeToEngine(text, eng) != null;
    } catch (_) {
      return false;
    }
  }

  /// 纪律5：导入/还原前快照（当前存档复制 + 滚动清理）
  Future<String?> snapshotBefore() async {
    try {
      final src = File(await dataFilePath());
      if (!src.existsSync()) return null;
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final dst = '${await _dir()}'
          '/snapshot_${now.year}${two(now.month)}${two(now.day)}'
          '_${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
      await src.copy(dst);
      await _pruneSnapshots();
      return dst;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pruneSnapshots() async {
    final dir = Directory(await _dir());
    final snaps = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('snapshot_'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in snaps.skip(kMaxSnapshots)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// 导出备份 JSON 文本（口径 §5 结构，供分享/存档）
  String backupText(CheckInEngine eng) => jsonEncode(encode(eng));

  /// 从备份文本还原（口径 §5：校验 app 标签 → 全量重建 → 落盘）
  /// 返回错误信息；null = 成功
  Future<String?> restoreFromText(String text, CheckInEngine eng) async {
    try {
      await snapshotBefore();
    } catch (_) {}
    if (decodeToEngine(text, eng) == null) {
      return '文件格式不符（缺少课点到备份标识）';
    }
    final ok = await persist(eng);
    if (!ok) return '还原后落盘失败';
    return null;
  }
}
