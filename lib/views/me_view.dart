// ══════════════════════════════════════════════════════════════
// MeView · 我的页（M2-② 功能版）
// 数据管理：导出课时表/打卡记录/完整备份 + 从快照还原
// （file_picker 导入入口随 M3 打卡流一起实装；此处导出/还原全闭环）
// ══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../engine/checkin_engine.dart';
import '../engine/store.dart';
import '../engine/xlsx_kit.dart';
import '../theme/v9_tokens.dart';
import '../version.dart' show kVersionMark;

/// 导入入口（M3）：xlsx/csv 课时表 → 计划预览 → 重名询问 → 快照 → 落库 → 落盘
class _ImportResult {
  final int added, updated, skipped;
  const _ImportResult(this.added, this.updated, this.skipped);
}

class MeView extends StatefulWidget {
  const MeView({super.key});

  @override
  State<MeView> createState() => _MeViewState();
}

class _MeViewState extends State<MeView> {
  final CheckInEngine eng = CheckInEngine.I;
  bool _busy = false;
  List<FileSystemEntity> _snapshots = [];

  @override
  void initState() {
    super.initState();
    _refreshSnaps();
  }

  Future<void> _refreshSnaps() async {
    final docs = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    setState(() {
      _snapshots = docs
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('snapshot_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
    });
  }

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? V9Dark.saveBg : V9Dark.toastBg,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<Directory> _exportDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/export');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  // ── 从备份文件还原（v1.1.0 功能：选 JSON → 校验 app 标签 → 确认覆盖 → 全量重建）──
  Future<void> _restoreFromBackupFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    // 先校验再确认（不合法的文件不值得吓用户一次）
    final probe = CheckInEngine.I;
    if (Store.decodeToEngine(text, probe) == null) {
      _toast('不是有效的课点到备份文件', ok: false);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: V9Dark.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('从备份还原',
            style: TextStyle(color: V9Dark.warn, fontWeight: FontWeight.w700)),
        content: Text(
          '将用「${picked.name}」覆盖当前全部数据。\n还原前会自动生成快照。',
          style: const TextStyle(color: V9Dark.ink60, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: V9Dark.ink45)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: V9Dark.warn),
            child: const Text('确认还原'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final err = await Store.I.restoreFromText(text, CheckInEngine.I);
    _toast(err == null ? '已从备份还原' : '还原失败：$err', ok: err == null);
    await _refreshSnaps();
    if (mounted) setState(() => _busy = false);
  }

  // ── 导入课时表（口径 4.4：应用语义在引擎；此处只做文件读取/预览/重名询问/快照）──
  Future<_ImportResult?> _importRoster() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
    );
    if (picked == null) return null;
    final name = picked.name;
    final bytes = await picked.readAsBytes();
    if (!mounted) return null;
    List<List<String>>? matrix;
    if (name.toLowerCase().endsWith('.csv')) {
      matrix = XlsxKit.parseCsv(utf8.decode(bytes, allowMalformed: true));
    } else {
      matrix = XlsxKit.parseMatrixFromBytes(bytes);
    }
    if (matrix == null || matrix.length < 2) {
      _toast('导入失败，请检查文件格式', ok: false);
      return null;
    }
    // 预览（与应用同一匹配规则）
    final plan = eng.rosterPlan(matrix);
    bool skipConflicts = false;
    if (plan.fileDups.isNotEmpty) {
      final skip = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: V9Dark.surfCardSolid,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('发现重名学生',
              style:
                  TextStyle(color: V9Dark.ink, fontWeight: FontWeight.w700)),
          content: Text(
            '有 ${plan.fileDups.length} 名学生在文件内重名\n\n'
            '「跳过重名」：忽略这些学生\n「全部导入」：重名学生也导入',
            style: const TextStyle(color: V9Dark.ink60, height: 1.7),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('跳过重名',
                  style: TextStyle(color: V9Dark.warn)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: V9Dark.act2),
              child: const Text('全部导入'),
            ),
          ],
        ),
      );
      if (skip == null) return null; // 用户取消
      skipConflicts = !skip;
    }
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: V9Dark.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('导入课时',
            style: TextStyle(color: V9Dark.ink, fontWeight: FontWeight.w700)),
        content: Text(
          '解析成功：共 ${matrix!.length - 1} 名学生\n'
          '将新增 ${plan.added} 人，更新 ${plan.updated} 人'
          '${plan.skipped > 0 ? '，跳过 ${plan.skipped} 人' : ''}\n\n'
          '月结学生的已上课时不会被改动。',
          style: const TextStyle(color: V9Dark.ink60, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: V9Dark.ink45)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: V9Dark.act2),
            child: const Text('确定导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    await Store.I.snapshotBefore(); // 纪律5：导入前快照
    final r = eng.applyRosterImport(matrix, skipConflicts: skipConflicts);
    final ok = await Store.I.persist(eng);
    _toast(ok
        ? '导入完成：新增 ${r.added} 人，更新 ${r.updated} 人'
        : '导入完成，但落盘失败', ok: ok);
    return _ImportResult(r.added, r.updated, r.skipped);
  }

  // ── 导出课时表（口径 4.1/4.2：月列=月结次数/套餐加权）──
  Future<void> _exportRoster() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final year = DateTime.now().year.toString();
      final rows = [
        for (final s in eng.students)
          RosterExportRow(
            seq: s.id,
            name: s.name,
            type: s.payType == 'monthly' ? '月结' : '套餐',
            className: s.className,
            monthHours: [
              for (int m = 1; m <= 12; m++)
                XlsxKit.monthCell(
                    eng, s, '$year-${m.toString().padLeft(2, '0')}')
            ],
            totalHours: s.payType == 'semester' ? s.totalHours : null,
            usedHours: s.payType == 'semester' ? s.usedHours : null,
            remainingHours:
                s.payType == 'semester' ? s.remainingHours : null,
          ),
      ];
      final bytes = XlsxKit.buildRosterXlsx(rows);
      final f = File('${(await _exportDir()).path}/课时表_$year${_stamp()}.xlsx');
      await f.writeAsBytes(bytes, flush: true);
      _toast('已导出课时表：${f.path.split('/').last}');
    } catch (_) {
      _toast('导出失败', ok: false);
    }
    if (mounted) setState(() => _busy = false);
  }

  // ── 导出打卡记录（口径 4.3：逐日列）──
  Future<void> _exportRecords() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final key =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final dates = eng.records
          .where((r) => r.date.startsWith(key))
          .map((r) => r.date)
          .toSet()
          .toList()
        ..sort();
      final rows = [
        for (final s in eng.students)
          RecordsExportRow(
            seq: s.id,
            name: s.name,
            className: s.className,
            type: s.payType == 'monthly' ? '月结' : '学期',
            dates: [
              for (final d in dates)
                if (eng.records
                    .any((r) => r.studentId == s.id && r.date == d))
                  d
            ],
          ),
      ];
      final bytes = XlsxKit.buildRecordsXlsx(rows, dates);
      final f = File(
          '${(await _exportDir()).path}/打卡记录_${key}_${_stamp()}.xlsx');
      await f.writeAsBytes(bytes, flush: true);
      _toast('已导出打卡记录（$key，${dates.length} 天）');
    } catch (_) {
      _toast('导出失败', ok: false);
    }
    if (mounted) setState(() => _busy = false);
  }

  // ── 完整备份（口径 §5 同构 JSON）──
  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final f =
          File('${(await _exportDir()).path}/备份_${_stamp()}.json');
      await f.writeAsString(Store.I.backupText(eng), flush: true);
      _toast('已备份：${f.path.split('/').last}');
    } catch (_) {
      _toast('备份失败', ok: false);
    }
    if (mounted) setState(() => _busy = false);
  }

  // ── 从最近快照还原（纪律5 产品面：二次确认 + 成败如实）──
  Future<void> _restoreLatestSnapshot() async {
    if (_busy || _snapshots.isEmpty) return;
    final snap = _snapshots.first;
    final name = snap.path.split('/').last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: V9Dark.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('从快照还原',
            style: TextStyle(color: V9Dark.ink, fontWeight: FontWeight.w700)),
        content: Text(
          '将用快照覆盖当前全部数据：\n$name\n\n当前未保存的改动会丢失。',
          style: const TextStyle(color: V9Dark.ink60, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('取消', style: TextStyle(color: V9Dark.ink45)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: V9Dark.act2),
            child: const Text('确认还原'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final text = await (snap as File).readAsString();
      final err = await Store.I.restoreFromText(text, eng);
      if (err == null) {
        _toast('已从快照还原');
      } else {
        _toast('还原失败：$err', ok: false);
      }
    } catch (_) {
      _toast('还原失败：快照不可读', ok: false);
    }
    if (mounted) setState(() => _busy = false);
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
              _classCard(),
              const SizedBox(height: 16),
              _sectionTitle('数据管理'),
              _menuCard([
                _MenuItem(
                    icon: Icons.table_chart,
                    label: '导出课时表（Excel · 当年 12 个月）',
                    onTap: _exportRoster),
                _MenuItem(
                    icon: Icons.event_note,
                    label: '导出打卡记录（Excel · 本月）',
                    onTap: _exportRecords),
                _MenuItem(
                    icon: Icons.backup,
                    label: '完整备份（JSON · 含全部记录）',
                    onTap: _exportBackup),
                _MenuItem(
                    icon: Icons.upload_file,
                    label: '导入课时表（Excel / CSV）',
                    onTap: () => _importRoster()),
                _MenuItem(
                  icon: Icons.restore,
                  label: _snapshots.isEmpty
                      ? '从快照还原（暂无快照）'
                      : '从最近快照还原（${_snapshots.length} 份可用）',
                  onTap:
                      _snapshots.isEmpty ? null : _restoreLatestSnapshot,
                  danger: true,
                ),
                _MenuItem(
                  icon: Icons.folder_open,
                  label: '从备份文件还原（JSON）',
                  onTap: _restoreFromBackupFile,
                  danger: true,
                ),
              ]),
              const SizedBox(height: 16),
              _sectionTitle('关于'),
              _aboutCard(),
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
        const Text('我的',
            style: TextStyle(
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

  Widget _classCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V9Dark.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: V9Dark.bdSoft),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: V9Dark.avatarBg,
          ),
          child: Text(
            eng.className.isEmpty ? '班' : eng.className.substring(0, 1),
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: V9Dark.act2),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eng.className,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: V9Dark.ink)),
              const SizedBox(height: 4),
              Text(
                '${eng.students.length} 名学生 · ${eng.records.length} 条打卡记录',
                style:
                    const TextStyle(fontSize: 13, color: V9Dark.ink45),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 13,
              color: V9Dark.ink45,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _menuCard(List<_MenuItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: V9Dark.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: V9Dark.bdSoft),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 54, color: V9Dark.bdSoft),
            items[i].build(context, _busy),
          ],
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V9Dark.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: V9Dark.bdSoft),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('课点到 · Android',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: V9Dark.ink)),
          SizedBox(height: 6),
          Text(
            '体育老师的班级点名 / 课时统计工具\n纯本机存储 · 无网络权限 · 无遥测\n开源版将于 M5 发布（MIT License）',
            style: TextStyle(fontSize: 12, color: V9Dark.ink45, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  const _MenuItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
  });

  Widget build(BuildContext context, bool busy) {
    final enabled = onTap != null && !busy;
    final color = !enabled
        ? V9Dark.ink45.withValues(alpha: 0.4)
        : danger
            ? V9Dark.warn
            : V9Dark.ink;
    // ListTile 需要自己的 Material 承载墨水涟漪（外层 Container 有底色会触发断言）
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        enabled: enabled,
        onTap: onTap,
        leading: Icon(icon, size: 22, color: color),
        title: Text(label,
            style: TextStyle(
                fontSize: 14, color: color, fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.chevron_right,
            size: 20, color: V9Dark.ink45.withValues(alpha: 0.5)),
      ),
    );
  }
}
