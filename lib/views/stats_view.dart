// ══════════════════════════════════════════════════════════════
// StatsView · 统计页（M4）
// 口径 §3.1：本月次数从 records 按 'YYYY-MM' 前缀实时计算，
// monthlySessions 累计器字段一律不消费（P2-1 修复形态）。
// 记录详情：点学生卡弹当月打卡日期列表。
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/checkin_engine.dart';
import '../theme/v9_tokens.dart';
import '../version.dart' show kVersionMark;

class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  final CheckInEngine eng = CheckInEngine.I;

  String get _monthKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  List<CheckInRecord> _monthRecordsOf(int studentId) => eng.records
      .where((r) => r.studentId == studentId && r.date.startsWith(_monthKey))
      .toList();

  /// 口径 §4.2 同款分流：月结记次数、套餐记加权课时
  double _monthValueOf(Student s) {
    final rs = _monthRecordsOf(s.id);
    return s.payType == 'monthly'
        ? rs.length.toDouble()
        : rs.fold(0.0, (acc, r) => acc + r.hours);
  }

  int get _monthSessionCount => eng.records
      .where((r) => r.date.startsWith(_monthKey))
      .map((r) => r.studentId)
      .toSet()
      .length;

  double get _monthTotalHours => eng.records
      .where((r) => r.date.startsWith(_monthKey))
      .fold(0.0, (acc, r) => acc + r.hours);

  /// 本月按星期分布（一~日）
  List<int> get _weekdayDist {
    final dist = List<int>.filled(7, 0);
    for (final r in eng.records.where((r) => r.date.startsWith(_monthKey))) {
      final d = DateTime.parse(r.date);
      dist[d.weekday - 1]++;
    }
    return dist;
  }

  void _showDetail(Student s) {
    final rs = _monthRecordsOf(s.id)..sort((a, b) => a.date.compareTo(b.date));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: V9Dark.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${s.name} · $_monthKey',
            style: const TextStyle(
                color: V9Dark.ink, fontWeight: FontWeight.w700, fontSize: 17)),
        content: SizedBox(
          width: 280,
          child: rs.isEmpty
              ? const Text('本月暂无打卡记录',
                  style: TextStyle(color: V9Dark.ink45, fontSize: 13))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in rs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: V9Dark.act2),
                          const SizedBox(width: 8),
                          Text(r.date,
                              style: const TextStyle(
                                  fontSize: 13, color: V9Dark.ink)),
                          const Spacer(),
                          Text('${r.hours} 课时',
                              style: const TextStyle(
                                  fontSize: 12, color: V9Dark.ink45)),
                        ]),
                      ),
                    const Divider(color: V9Dark.bdSoft),
                    Text(
                        '${s.payType == 'monthly' ? '本月次数' : '本月课时'}：${_monthValueOf(s)}',
                        style: const TextStyle(
                            fontSize: 13,
                            color: V9Dark.act2,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭', style: TextStyle(color: V9Dark.ink45)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ListenableBuilder(
        listenable: eng,
        builder: (context, _) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              _header(),
              const SizedBox(height: 16),
              _monthCard(),
              const SizedBox(height: 16),
              _weekdayCard(),
              const SizedBox(height: 16),
              const Text('本月学生明细',
                  style: TextStyle(
                      fontSize: 13,
                      color: V9Dark.ink45,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...eng.students.map(_studentRow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('统计 · ${eng.className}',
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: V9Dark.ink)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: V9Dark.tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(kVersionMark,
              style: const TextStyle(fontSize: 11, color: V9Dark.ink60)),
        ),
      ],
    );
  }

  Widget _monthCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V9Dark.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: V9Dark.bdSoft),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_monthSessionCount',
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: V9Dark.ink)),
                const Text('本月课次（去重人数）',
                    style: TextStyle(fontSize: 12, color: V9Dark.ink45)),
              ]),
        ),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmt(_monthTotalHours),
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: V9Dark.act2)),
                const Text('本月总课时（加权）',
                    style: TextStyle(fontSize: 12, color: V9Dark.ink45)),
              ]),
        ),
      ]),
    );
  }

  Widget _weekdayCard() {
    final dist = _weekdayDist;
    final maxV = dist.reduce((a, b) => a > b ? a : b);
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: V9Dark.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: V9Dark.bdSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本月按星期分布',
              style: TextStyle(fontSize: 13, color: V9Dark.ink45)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < 7; i++)
                Expanded(
                  child: Column(children: [
                    SizedBox(
                      height: 64,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 14,
                          height: maxV == 0
                              ? 2
                              : 4 + 56 * dist[i] / maxV,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: V9G.finishColors(true)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i],
                        style: TextStyle(
                            fontSize: 11,
                            color: dist[i] > 0 ? V9Dark.ink : V9Dark.ink45)),
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _studentRow(Student s) {
    final count = _monthRecordsOf(s.id).length;
    final value = _monthValueOf(s);
    return GestureDetector(
      onTap: () => _showDetail(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: V9Dark.surfCardSolid,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: V9Dark.bdSoft),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: V9Dark.ink)),
                const SizedBox(height: 3),
                Text(
                  s.payType == 'monthly'
                      ? '月结 · 本月 $count 次'
                      : '学期 · 本月 $count 次 / ${_fmt(value)} 课时',
                  style: const TextStyle(fontSize: 12, color: V9Dark.ink45),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: V9Dark.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              s.payType == 'monthly' ? '$count 次' : '${_fmt(value)} 课时',
              style: const TextStyle(fontSize: 11, color: V9Dark.act2),
            ),
          ),
        ]),
      ),
    );
  }

  /// 鸿蒙 JS number 序列化对齐：整数不带 .0（30.0→'30'），小数保留（1.5→'1.5'）
  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
