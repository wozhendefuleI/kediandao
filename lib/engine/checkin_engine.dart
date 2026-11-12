// ══════════════════════════════════════════════════════════════
// CheckInEngine · TrainingModel.ets (v1.1.10 @3870d4f) 直译
// 口径依据：docs/移植口径对照表.md §0-§2
// M1 阶段：纯内存单例（ChangeNotifier）；M2 换 sqflite 持久化，
//          本文件的方法签名与语义保持不变（await 落盘在 M2 引入）。
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

/// 导入结果统计（toast 文案与鸿蒙同构：「新增 X 人，更新 Y 人」）
class ImportResult {
  final int added;
  final int updated;
  final int skipped;
  const ImportResult(
      {required this.added, required this.updated, this.skipped = 0});
}

/// 口径 §0：Student（字段与鸿蒙 v1.1.10 一一同名对应）
class Student {
  int id;
  String name;
  String className;
  int totalSessions;
  int monthlySessions; // 兼容快照：展示/统计一律不消费（口径 §3.1）
  String payType; // 'monthly' | 'semester'
  double totalHours;
  double usedHours;
  double remainingHours;

  Student({
    required this.id,
    required this.name,
    required this.className,
    this.totalSessions = 0,
    this.monthlySessions = 0,
    this.payType = 'semester',
    this.totalHours = 30,
    this.usedHours = 8,
    this.remainingHours = 22,
  });
}

/// 口径 §0：CheckInRecord（每生每日唯一；hours 缺省按 1）
class CheckInRecord {
  String date; // 'YYYY-MM-DD'
  int studentId;
  String studentName;
  int timestamp;
  double hours;

  CheckInRecord({
    required this.date,
    required this.studentId,
    required this.studentName,
    required this.timestamp,
    this.hours = 1,
  });
}

/// 引擎单例：绑定一个班级（M1 单班；多班/UUID 随 M2 班级表引入）
class CheckInEngine extends ChangeNotifier {
  CheckInEngine._();
  static final CheckInEngine I = CheckInEngine._();

  String className = '示例班';
  final List<Student> students = [];
  final List<CheckInRecord> records = [];
  int studentIdCounter = 0;

  // ── 口径 §2.4 ID 分配：counter = max(counter, 现有最大id) 再 ++（v29.14 守卫）──
  Student addStudent(String name, String className, String payType,
      double totalHours, double usedHours) {
    int maxId = 0;
    for (final s in students) {
      if (s.id > maxId) maxId = s.id;
    }
    if (studentIdCounter <= maxId) studentIdCounter = maxId;
    studentIdCounter++;
    final s = Student(
      id: studentIdCounter,
      name: name,
      className: className,
      payType: payType,
      totalHours: totalHours,
      usedHours: usedHours,
      remainingHours: totalHours - usedHours,
    );
    students.add(s);
    notifyListeners();
    return s;
  }

  // ── 口径 §1.1 签到：每生每日唯一记录；月结也累计 usedHours（v1.1.1）──
  bool checkIn(int studentId, String dateStr, double weight) {
    final w = weight <= 0 ? 1.0 : weight;
    final idx = students.indexWhere((s) => s.id == studentId);
    if (idx < 0) return false;
    final student = students[idx];
    if (records.any((r) => r.studentId == studentId && r.date == dateStr)) {
      return false;
    }
    records.add(CheckInRecord(
      date: dateStr,
      studentId: studentId,
      studentName: student.name,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      hours: w,
    ));
    student.totalSessions++;
    student.monthlySessions++;
    student.usedHours = student.usedHours + w;
    // 口径 §1.2：仅 semester 回算 remaining
    if (student.payType == 'semester') {
      student.remainingHours = student.totalHours - student.usedHours;
    }
    notifyListeners();
    return true;
  }

  // ── 口径 §1.3 撤销：删该生该日期最后一条；计数器 max(0,…) 对称回退 ──
  bool uncheckIn(int studentId, String dateStr, double weight) {
    final w = weight <= 0 ? 1.0 : weight;
    int idx = -1;
    for (int i = records.length - 1; i >= 0; i--) {
      if (records[i].studentId == studentId && records[i].date == dateStr) {
        idx = i;
        break;
      }
    }
    if (idx < 0) return false;
    records.removeAt(idx);
    final idx2 = students.indexWhere((s) => s.id == studentId);
    if (idx2 >= 0) {
      final student = students[idx2];
      student.totalSessions = student.totalSessions > 0
          ? student.totalSessions - 1
          : 0;
      student.monthlySessions = student.monthlySessions > 0
          ? student.monthlySessions - 1
          : 0;
      student.usedHours =
          student.usedHours - w > 0 ? student.usedHours - w : 0;
      if (student.payType == 'semester') {
        student.remainingHours = student.totalHours - student.usedHours;
      }
    }
    notifyListeners();
    return true;
  }

  bool isCheckedIn(int studentId, String dateStr) =>
      records.any((r) => r.studentId == studentId && r.date == dateStr);

  /// 切换（tap 语义 = 鸿蒙 V9Engine.toggleCheckIn）
  bool toggleCheckIn(int studentId, String dateStr, double weight) =>
      isCheckedIn(studentId, dateStr)
          ? uncheckIn(studentId, dateStr, weight)
          : checkIn(studentId, dateStr, weight);

  int todayCount(String dateStr) => records
      .where((r) => r.date == dateStr)
      .map((r) => r.studentId)
      .toSet()
      .length;

  /// 口径 §2.3 删除连带：records 级联清（ID 永不复用，counter 只增）──
  bool deleteStudent(int studentId) {
    final idx = students.indexWhere((s) => s.id == studentId);
    if (idx < 0) return false;
    students.removeAt(idx);
    records.removeWhere((r) => r.studentId == studentId);
    notifyListeners();
    return true;
  }

  // ── 口径 §4.4 导入应用（MeView confirmImport L995-1021 直译）──

  /// 按**姓名**匹配：更新路径 payType 必写、仅 semester 覆写三课时（**月结三课时永不覆写**，
  /// v1.0.20 P2-2 红线）；新增路径 counter 递增、className 缺失回退当前班名。
  /// [matrix] 为 xlsx 课时表矩阵（首行表头）；[skipConflicts] 对应「取消新建」。
  ImportResult applyRosterImport(List<List<String>> matrix,
      {bool skipConflicts = false}) {
    int added = 0, updated = 0, skipped = 0;
    // 文件内重名检测（第二次出现的名字标记为冲突）
    final seenInFile = <String>{};
    final conflictNames = <String>{};
    for (final row in matrix.skip(1)) {
      final name = row.length > 1 ? row[1].trim() : '';
      if (name.isEmpty) continue;
      if (!seenInFile.add(name)) conflictNames.add(name);
    }
    String col(List<String> row, int i) =>
        i < row.length ? row[i].trim() : '';
    for (final row in matrix.skip(1)) {
      final name = col(row, 1);
      if (name.isEmpty) continue;
      if (conflictNames.contains(name) && skipConflicts) {
        skipped++;
        continue;
      }
      final typeStr = col(row, 2);
      final payType = typeStr == '月结' ? 'monthly' : 'semester';
      final total = double.tryParse(col(row, 16)) ?? 0;
      final used = double.tryParse(col(row, 17)) ?? 0;
      final existIdx = students.indexWhere((s) => s.name == name);
      if (existIdx >= 0) {
        // 更新路径（红线区）
        final s = students[existIdx];
        s.payType = payType; // 必写
        if (payType == 'semester') {
          s.totalHours = total;
          s.usedHours = used;
          s.remainingHours = total - used > 0 ? total - used : 0;
        }
        // monthly：三课时一概不动
        updated++;
      } else {
        // 新增路径：counter 递增（先 max 守卫再 ++，v29.14 同构）
        int maxId = 0;
        for (final s in students) {
          if (s.id > maxId) maxId = s.id;
        }
        if (studentIdCounter <= maxId) studentIdCounter = maxId;
        studentIdCounter++;
        final s = Student(
          id: studentIdCounter,
          name: name,
          className: col(row, 3).isEmpty ? className : col(row, 3),
          payType: payType,
          totalHours: total,
          usedHours: used,
          remainingHours: total - used > 0 ? total - used : 0,
        );
        students.add(s);
        added++;
      }
    }
    notifyListeners();
    return ImportResult(added: added, updated: updated, skipped: skipped);
  }

  /// 口径 §2.4 v29.14 自愈：重复 id 后出现者重派，其记录按名字顺延重挂，counter 推最大
  int repairDuplicateStudentIds() {
    final seen = <int>{};
    int maxId = 0;
    for (final s in students) {
      if (s.id > maxId) maxId = s.id;
    }
    int fixed = 0;
    for (final s in students) {
      if (seen.contains(s.id)) {
        maxId++;
        final oldId = s.id;
        final newId = maxId;
        for (final r in records) {
          if (r.studentId == oldId && r.studentName == s.name) {
            r.studentId = newId;
          }
        }
        s.id = newId;
        fixed++;
      }
      seen.add(s.id);
    }
    if (studentIdCounter < maxId) studentIdCounter = maxId;
    return fixed;
  }

  /// M1 种子数据（化名示例班，纪律：真实学生名单严禁入库）
  void seedDemo() {
    if (students.isNotEmpty) return;
    className = '示例班';
    final demo = [
      ('学生01', 'monthly', 30.0, 8.0),
      ('学生02', 'semester', 30.0, 8.0),
      ('学生03', 'semester', 20.0, 5.0),
      ('学生04', 'monthly', 24.0, 3.5),
      ('学生05', 'semester', 30.0, 12.0),
      ('学生06', 'semester', 16.0, 2.0),
    ];
    for (final d in demo) {
      addStudent(d.$1, '示例班', d.$2, d.$3, d.$4);
    }
  }
}
