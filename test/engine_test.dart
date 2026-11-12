// ══════════════════════════════════════════════════════════════
// M2 数据安全测试 · 方案 v4 验收硬项自动化
// ① 导入不清零月结 usedHours（红线 4.4）
// ② ID 单调不回退（2.4）
// ③ 打卡/撤销对称回退（1.1-1.3）
// ④ 存档 JSON 往返（5）
// ⑤ xlsx 导出→导入解析往返（4.1）
// ⑥ 月列口径：月结=次数、套餐=加权课时（4.2）
// ══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kediandao/engine/checkin_engine.dart';
import 'package:kediandao/engine/store.dart';
import 'package:kediandao/engine/xlsx_kit.dart';

CheckInEngine freshEngine() {
  final e = CheckInEngine.I;
  e.students.clear();
  e.records.clear();
  e.studentIdCounter = 0;
  return e;
}

void main() {
  test('红线4.4：导入更新月结学生 → usedHours/remaining 不变、payType 改写', () {
    final eng = freshEngine();
    final s = eng.addStudent('王小明', '示例班', 'monthly', 0, 0);
    s.usedHours = 12.5; // 打卡累计的真实数据
    s.remainingHours = 0; // 月结无剩余概念
    // 课时表写「月结 总30 累计0 剩30」——若覆写就是事故
    final matrix = [
      ['序号', '姓名', '类型', '班级', ...List.filled(12, '0'), '总课时', '累计', '剩余课时'],
      ['1', '王小明', '月结', '示例班', ...List.filled(12, '0'), '30', '0', '30'],
    ];
    final r = eng.applyRosterImport(matrix);
    expect(r.updated, 1);
    expect(s.payType, 'monthly');
    expect(s.usedHours, 12.5, reason: '月结 usedHours 被覆写 = 红线事故');
    expect(s.remainingHours, 0, reason: '月结 remainingHours 被覆写 = 红线事故');
  });

  test('红线4.4：导入更新学期学生 → 三课时按表覆写', () {
    final eng = freshEngine();
    eng.addStudent('李小红', '示例班', 'semester', 30, 3);
    final matrix = [
      ['序号', '姓名', '类型', '班级', ...List.filled(12, '0'), '总课时', '累计', '剩余课时'],
      ['1', '李小红', '套餐', '示例班', ...List.filled(12, '0'), '40', '10', '30'],
    ];
    eng.applyRosterImport(matrix);
    final s = eng.students.first;
    expect(s.payType, 'semester');
    expect(s.totalHours, 40);
    expect(s.usedHours, 10);
    expect(s.remainingHours, 30);
  });

  test('口径2.4：新增学生 ID 单调递增，删除后不复用', () {
    final eng = freshEngine();
    final a = eng.addStudent('A', '班', 'semester', 30, 0);
    final b = eng.addStudent('B', '班', 'semester', 30, 0);
    expect(b.id, a.id + 1);
    eng.deleteStudent(b.id);
    final c = eng.addStudent('C', '班', 'semester', 30, 0);
    expect(c.id, greaterThan(b.id), reason: 'ID 复用 = v29.14 撞号事故重现');
  });

  test('口径2.3：删除学生连带清除其打卡记录', () {
    final eng = freshEngine();
    final s = eng.addStudent('删我', '班', 'semester', 30, 0);
    eng.checkIn(s.id, '2026-11-12', 1);
    expect(eng.deleteStudent(s.id), isTrue);
    expect(eng.students.where((x) => x.id == s.id), isEmpty);
    expect(eng.records.where((r) => r.studentId == s.id), isEmpty,
        reason: '孤儿记录 = v1.1.0 前的旧疾');
    expect(eng.deleteStudent(s.id), isFalse);
  });

  test('口径1.1-1.3：签到/撤销对称回退；月结也累计课时；重复签到拒绝', () {
    final eng = freshEngine();
    final m = eng.addStudent('月结生', '班', 'monthly', 30, 8);
    final s = eng.addStudent('学期生', '班', 'semester', 30, 8);
    final d = '2026-11-12';
    expect(eng.checkIn(m.id, d, 1), isTrue);
    expect(eng.checkIn(m.id, d, 1), isFalse, reason: '每生每日唯一');
    expect(eng.checkIn(s.id, d, 1), isTrue);
    // 月结：usedHours 也涨（v1.1.1），remaining 不动
    expect(m.usedHours, 9);
    expect(m.remainingHours, 22); // 构造时 30-8，月结不回算
    // 学期：remaining 回算
    expect(s.usedHours, 9);
    expect(s.remainingHours, 21);
    // 撤销对称
    expect(eng.uncheckIn(s.id, d, 1), isTrue);
    expect(s.usedHours, 8);
    expect(s.remainingHours, 22);
    expect(eng.todayCount(d), 1);
  });

  test('口径5：存档 JSON 往返（encode→decode 字段保全 + 自愈）', () {
    final eng = freshEngine();
    final s = eng.addStudent('往返生', '班2', 'semester', 30, 7.5);
    eng.checkIn(s.id, '2026-11-12', 0.5);
    final text = jsonEncode(Store.encode(eng));
    final back = freshEngine();
    expect(Store.decodeToEngine(text, back), isNotNull);
    expect(back.students.length, 1);
    final rs = back.students.first;
    expect(rs.name, '往返生');
    expect(rs.usedHours, 8); // 7.5 + 0.5 落盘后保全
    expect(back.records.first.hours, 0.5);
    expect(back.studentIdCounter, greaterThanOrEqualTo(rs.id));
  });

  test('口径4.1：xlsx 导出→解析往返（19 列对齐）', () {
    final eng = freshEngine();
    final s1 = eng.addStudent('套餐生', '班X', 'semester', 30, 8);
    eng.checkIn(s1.id, '2026-11-03', 1);
    eng.checkIn(s1.id, '2026-11-10', 0.5);
    final s2 = eng.addStudent('月结生', '班X', 'monthly', 0, 0);
    eng.checkIn(s2.id, '2026-11-05', 1);
    // 预算月列（口径4.2：套餐=加权、月结=次数）
    final rows = [
      for (final s in eng.students)
        RosterExportRow(
          seq: s.id,
          name: s.name,
          type: s.payType == 'monthly' ? '月结' : '套餐',
          className: s.className,
          monthHours: [
            for (int m = 1; m <= 12; m++)
              XlsxKit.monthCell(eng, s, '2026-${m.toString().padLeft(2, '0')}')
          ],
          totalHours: s.payType == 'semester' ? s.totalHours : null,
          usedHours: s.payType == 'semester' ? s.usedHours : null,
          remainingHours: s.payType == 'semester' ? s.remainingHours : null,
        ),
    ];
    final bytes = XlsxKit.buildRosterXlsx(rows);
    final matrix = XlsxKit.parseMatrixFromBytes(bytes);
    expect(matrix, isNotNull);
    expect(matrix!.first[0], '序号');
    expect(matrix.first[16], '总课时');
    final row1 = matrix[1];
    expect(row1[1], '套餐生');
    expect(row1[2], '套餐');
    expect(row1[13], '0', reason: '十月列无记录');
    expect(row1[14], '1.5', reason: '十一月列 = 加权课时 1+0.5（列索引 14）');
    expect(row1[16], '30');
    expect(row1[17], '9.5', reason: '累计=构造8+打卡1.5，引擎如实累计（口径1.1）');
    final row2 = matrix[2];
    expect(row2[2], '月结');
    expect(row2[14], '1', reason: '月结月列 = 次数');
    // 解析结果可直接回灌导入
    final target = freshEngine();
    final r = target.applyRosterImport(matrix);
    expect(r.added, 2);
    expect(target.students.first.name, '套餐生');
  });
}
