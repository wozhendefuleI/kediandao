// ══════════════════════════════════════════════════════════════
// ClassStore · 多班级引擎层（M6-②，鸿蒙 ClassInfo[]/V9Engine 直译）
// 存档 v3：classes[] + currentClassId；v2 单班自动迁移（数据零丢失）
// 语义对齐：switchClass 自愈+广播 / 删当前班回退首班 / 全删光进空班
// ══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'app_log.dart';
import 'checkin_engine.dart';
import 'store.dart';

/// 单个班级的完整数据（元信息 + 引擎实例）
class ClassEntry {
  final String id;
  String name;
  final CheckInEngine eng;
  ClassEntry({required this.id, required this.name, required this.eng});

  int get studentCount => eng.students.length;
  int get recordCount => eng.records.length;
}

class ClassStore {
  ClassStore._();
  static final ClassStore I = ClassStore._();

  static const int kFormat = 3; // v3：多班
  final List<ClassEntry> classes = [];
  String currentClassId = '';

  ClassEntry? get current =>
      classes.where((c) => c.id == currentClassId).firstOrNull;

  // ── 装载 / v2→v3 迁移 ──

  /// 启动装载：识别 v3 多班结构；识别不了则尝试 v2 迁移；都没有返回 false
  Future<bool> loadAll() async {
    final text = await Store.I.loadRaw();
    AppLog.log('装载', '存档读取 ${text == null ? "（空）" : "${text.length} 字符"}');
    if (text == null) return false;
    try {
      final payload = jsonDecode(text);
      if (payload is! Map<String, dynamic>) return false;
      if (payload['app'] != Store.kAppTag) return false;
      final list = payload['classes'];
      if (list is List) {
        classes.clear();
        for (final raw in list) {
          if (raw is! Map<String, dynamic>) continue;
          final eng = blank();
          if (Store.decodeToEngine(jsonEncode(raw), eng) == null) continue;
          classes.add(ClassEntry(
            id: raw['classId'] as String? ?? 'cls_x',
            name: raw['className'] as String? ?? '未命名',
            eng: eng,
          ));
        }
        currentClassId = payload['currentClassId'] as String? ?? '';
        if (current == null && classes.isNotEmpty) {
          currentClassId = classes.first.id;
        }
        return classes.isNotEmpty;
      }
      return await migrateV2(text);
    } catch (_) {
      return false;
    }
  }

  /// v2 单班存档 → v3 多班（原样保留全部数据，结构升级后立即落盘）
  Future<bool> migrateV2(String v2text) async {
    final eng = blank();
    if (Store.decodeToEngine(v2text, eng) == null) return false;
    final id = 'cls_main';
    classes
      ..clear()
      ..add(ClassEntry(id: id, name: eng.className, eng: eng));
    currentClassId = id;
    await persistAll();
    return true;
  }

  // ── 持久化（原子写由 Store.saveRaw 承载）──

  Future<void> persistAll() async {
    final payload = <String, dynamic>{
      'app': Store.kAppTag,
      'format': kFormat,
      'exportedAt': DateTime.now().toIso8601String(),
      'classes': [
        for (final c in classes)
          {
            ...jsonDecode(jsonEncode(Store.encode(c.eng))),
            'classId': c.id,
            'className': c.name,
          },
      ],
      'currentClassId': currentClassId,
    };
    await Store.I.saveRaw(jsonEncode(payload));
  }

  // ── 班级操作（V9Engine 语义直译）──

  /// 切班：自愈（v29.14）→ promote 换血单例 → 存指针 → 广播
  Future<void> switchClass(String id) async {
    final entry = classes.where((c) => c.id == id).firstOrNull;
    if (entry == null) return;
    final fixed = entry.eng.repairDuplicateStudentIds();
    promote(entry.eng);
    currentClassId = id;
    await persistAll();
    AppLog.log('切班', '→ ${entry.name}（${entry.eng.students.length} 人）');
    if (fixed > 0) CheckInEngine.I.notifyRefresh();
  }

  /// 建班（空班，不带种子）
  Future<ClassEntry> createClass(String name) async {
    final id = 'cls_${DateTime.now().millisecondsSinceEpoch}';
    final eng = blank();
    eng.className = name;
    final entry = ClassEntry(id: id, name: name, eng: eng);
    classes.add(entry);
    await switchClass(id); // 新班即刻成为当前班
    return entry;
  }

  Future<void> renameClass(String id, String name) async {
    final entry = classes.where((c) => c.id == id).firstOrNull;
    if (entry == null || name.isEmpty) return;
    entry.name = name;
    entry.eng.className = name;
    await persistAll();
    if (id == currentClassId) CheckInEngine.I.notifyRefresh();
  }

  /// 删除：当前班删除后自动切到剩余第一班；全删光 → 空班（enterEmpty 语义）
  Future<void> deleteClass(String id) async {
    final wasCurrent = id == currentClassId;
    classes.removeWhere((c) => c.id == id);
    if (wasCurrent) {
      if (classes.isNotEmpty) {
        await switchClass(classes.first.id);
      } else {
        final eng = blank();
        eng.className = '空';
        classes.add(ClassEntry(id: 'cls_empty', name: '空', eng: eng));
        await switchClass('cls_empty');
      }
    } else {
      await persistAll();
    }
  }

  /// 多班完整备份文本（v3 结构原样）
  String backupAllText() {
    final payload = <String, dynamic>{
      'app': Store.kAppTag,
      'format': kFormat,
      'exportedAt': DateTime.now().toIso8601String(),
      'classes': [
        for (final c in classes)
          {
            ...jsonDecode(jsonEncode(Store.encode(c.eng))),
            'classId': c.id,
            'className': c.name,
          },
      ],
      'currentClassId': currentClassId,
    };
    return jsonEncode(payload);
  }
}
