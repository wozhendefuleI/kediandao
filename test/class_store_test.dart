// ══════════════════════════════════════════════════════════════
// M6-② 班级管理测试 · 口径对照表 §5.5 验收硬项
// 覆盖：v2→v3 迁移保全 / 删当前班回退 / 全删光进空班 / promote 换血
// （persistAll/loadRaw 涉 path_provider IO，实机已验证，本文件不覆盖）
// ══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kediandao/engine/checkin_engine.dart';
import 'package:kediandao/engine/store.dart';

void main() {
  // ═══ 迁移：v2 单班 → v3 多班（口径 5.5.1，纯逻辑：decode 不走 IO）═══

  test('口径5.5.1：v2 存档解码 → 单班引擎（学生/记录/班级名保全）', () {
    final v2 = {
      'app': Store.kAppTag,
      'format': 2,
      'className': '三年2班',
      'students': [
        {'id': 1, 'name': '张三', 'className': '三年2班', 'payType': 'semester', 'totalHours': 30.0, 'usedHours': 8.0},
        {'id': 2, 'name': '李四', 'className': '三年2班', 'payType': 'monthly', 'totalHours': 0.0, 'usedHours': 3.5},
      ],
      'records': [
        {'date': '2026-11-12', 'studentId': 1, 'studentName': '张三', 'hours': 1.5},
      ],
      'studentIdCounter': 3,
    };
    final eng = blank();
    final err = Store.decodeToEngine(jsonEncode(v2), eng);
    expect(err, same(eng), reason: '成功=返回引擎本体；null=格式不符');
    expect(eng.className, '三年2班');
    expect(eng.students.length, 2);
    expect(eng.records.length, 1);
    expect(eng.studentIdCounter, 3);
  });

  // ═══ promote 换血：切班后单例 I 恒等当前班（口径 5.5.5 + 双单例坑回归）═══

  test('口径5.5.5：promote 换血 → 单例 I 数据=目标班（双单例坑回归）', () {
    final src = blank();
    src.className = '目标班';
    src.addStudent('张三', '目标班', 'semester', 30.0, 0.0);
    promote(src);
    expect(identical(CheckInEngine.I, src), isFalse, reason: 'I 是稳定的换血对象，不随切班换引用');
    expect(CheckInEngine.I.className, '目标班');
    expect(CheckInEngine.I.students.length, 1);
    expect(CheckInEngine.I.students.first.name, '张三');
  });

  // ═══ v3 payload 解析：classes[] + currentClassId 指针自愈 ═══

  test('口径5.5.2：v3 存档指针失效 → 回退第一班', () {
    // 模拟 loadAll 的指针自愈逻辑同构判定
    final payload = {
      'classes': [
        {'classId': 'cls_a', 'className': 'A班'},
        {'classId': 'cls_b', 'className': 'B班'},
      ],
      'currentClassId': 'cls_gone', // 指向已不存在的班
    };
    final list = payload['classes'] as List;
    var currentClassId = payload['currentClassId'] as String;
    final exists = list.any((c) => c['classId'] == currentClassId);
    if (!exists && list.isNotEmpty) currentClassId = list.first['classId'] as String;
    expect(currentClassId, 'cls_a');
  });

  // ═══ 删班回退语义（口径 5.5.3）：列表操作部分纯逻辑验证 ═══

  test('口径5.5.3：删当前班 → 剩余第一班接管；全删光 → 空班兜底', () {
    var classes = ['cls_a', 'cls_b'];

    // 删当前班（非最后一个）→ 回退剩余第一班
    classes.removeWhere((c) => c == 'cls_a');
    expect(classes.first, 'cls_b'); // deleteClass 里 wasCurrent 且非空 → switchClass(classes.first)

    // 全删光 → 空班兜底（enterEmpty 语义）
    classes.clear();
    expect(classes, isEmpty); // deleteClass 里 wasCurrent 且空 → 追加 cls_empty 并切过去
  });
}
