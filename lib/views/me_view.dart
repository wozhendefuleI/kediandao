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
import '../engine/class_store.dart';
import '../engine/store.dart';
import '../engine/xlsx_kit.dart';
import '../theme/v9_tokens.dart';
import '../theme/v9_palette.dart';
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
  V9Palette get c => V9ThemeScope.of(context);

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
      backgroundColor: ok ? c.saveBg : V9Dark.toastBg,
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

  // ═══ 赞助作者（对齐鸿蒙 SponsorDialog：hero 光晕圆 + 二维码容器强制纯白保扫码）═══

  Future<void> _showSponsorDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dlgCtx) {
        final cc = V9ThemeScope.of(dlgCtx);
        final accentPair = V9G.finishColors(cc.dark);
        return AlertDialog(
          backgroundColor: cc.surfCardSolid,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // hero 光晕圆（96 光晕 + 64 渐变圆 + 咖）
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cc.tint,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: accentPair,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text('咖',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              Text('赞助作者',
                  style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      color: cc.ink)),
              const SizedBox(height: 14),
              // 二维码 180px，容器强制纯白（深底扫码失败，不主题化）
              Container(
                width: 180,
                height: 180,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.asset('assets/images/sponsor_qrcode.png',
                    fit: BoxFit.contain),
              ),
              const SizedBox(height: 14),
              Text('如果课点到帮到了你，欢迎扫码支持一下\n一杯奶茶的钱，支持持续更新～',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: cc.ink60, height: 1.5)),
              const SizedBox(height: 8),
              Text('仅限个人开发者自用，无任何强制消费',
                  style: TextStyle(fontSize: 9, color: cc.ink45)),
              const SizedBox(height: 16),
              // 关闭按钮（渐变胶囊，对齐鸿蒙）
              GestureDetector(
                onTap: () => Navigator.pop(dlgCtx),
                child: Container(
                  width: double.infinity,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(19),
                    gradient: LinearGradient(colors: accentPair),
                  ),
                  alignment: Alignment.center,
                  child: const Text('关闭',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══ 班级管理（鸿蒙 ClassManagePage 语义直译）═══

  /// 班级管理弹窗：列表 + 当前班标记 + 新建/重命名/删除
  Future<void> _showClassManager() async {
    final cs = ClassStore.I;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = V9ThemeScope.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            backgroundColor: c.surfCardSolid,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('班级管理',
                style: TextStyle(
                    color: V9Dark.ink, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 300,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final entry in cs.classes)
                  InkWell(
                    onTap: entry.id == cs.currentClassId
                        ? null
                        : () async {
                            await cs.switchClass(entry.id);
                            if (ctx.mounted) Navigator.pop(ctx);
                            _toast('已切换到「${entry.name}」');
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 8),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: entry.id == cs.currentClassId
                            ? c.tint
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Icon(
                          entry.id == cs.currentClassId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 16,
                          color: entry.id == cs.currentClassId
                              ? c.act2
                              : c.ink45,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.name,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: c.ink)),
                                Text(
                                    '${entry.studentCount} 名学生 · ${entry.recordCount} 条记录',
                                    style: TextStyle(
                                        fontSize: 11, color: c.ink45)),
                              ]),
                        ),
                        // 行内动作：重命名 / 删除（当前班才可重命名同步内存态）
                        GestureDetector(
                          onTap: () => _renameClass(ctx, entry, setD),
                          child: Icon(Icons.edit_outlined,
                              size: 18, color: c.ink45),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _deleteClassFlow(ctx, entry, setD),
                          child: Icon(Icons.delete_outline,
                              size: 18, color: c.warn),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _newClass(ctx, setD),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建班级'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.act2,
                    side: BorderSide(color: c.saveBd),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭',
                    style: TextStyle(color: V9Dark.ink45)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _newClass(dynamic ctx, dynamic setD) async {
    final nameCtl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('新建班级'),
        content: TextField(
          controller: nameCtl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '班级名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dlgCtx, nameCtl.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ClassStore.I.createClass(name);
    if (!mounted) return;
    Navigator.pop(context); // 关管理弹窗（已切到新班）
    _toast('已创建「$name」');
  }

  Future<void> _renameClass(
      dynamic mgrCtx, dynamic entry, dynamic setD) async {
    final nameCtl = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('重命名班级'),
        content: TextField(
          controller: nameCtl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dlgCtx, nameCtl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ClassStore.I.renameClass(entry.id, name);
    if (!context.mounted) return;
    setD(() {}); // 刷新管理弹窗列表
    _toast('已重命名为「$name」');
  }

  /// 删除班级确认（两步：警示 → 输入固定文案「确定删除」解锁永久删除；对齐鸿蒙三重确认语义）
  Future<void> _deleteClassFlow(
      dynamic mgrCtx, dynamic entry, dynamic setD) async {
    // 第一步：警示
    final step1 = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) {
        final c = V9ThemeScope.of(dlgCtx);
        return AlertDialog(
          backgroundColor: c.surfCardSolid,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('删除班级',
              style:
                  TextStyle(color: V9Dark.warn, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                '「${entry.name}」· ${entry.studentCount} 名学生 · ${entry.recordCount} 条打卡记录',
                style: TextStyle(fontSize: 12, color: c.ink45)),
            const SizedBox(height: 12),
            Text('删除后数据不可恢复。继续吗？',
                style: TextStyle(fontSize: 13, color: c.ink)),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, false),
              child: const Text('取消', style: TextStyle(color: V9Dark.ink45)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              style: FilledButton.styleFrom(backgroundColor: c.warn),
              child: const Text('继续'),
            ),
          ],
        );
      },
    );
    if (step1 != true) return;
    if (!mounted) return;
    // 第二步：输入固定文案解锁删除
    final textCtl = TextEditingController();
    final finalOk = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) {
        final c = V9ThemeScope.of(dlgCtx);
        return StatefulBuilder(
          builder: (dlgCtx, setV) => AlertDialog(
            backgroundColor: c.surfCardSolid,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('最后确认',
                style:
                    TextStyle(color: V9Dark.warn, fontWeight: FontWeight.w700)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('请输入「确定删除」以解锁删除按钮',
                  style: TextStyle(fontSize: 13, color: c.ink)),
              const SizedBox(height: 10),
              TextField(
                controller: textCtl,
                autofocus: true,
                onChanged: (_) => setV(() {}),
                decoration: const InputDecoration(hintText: '输入：确定删除'),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, false),
                child:
                    const Text('取消', style: TextStyle(color: V9Dark.ink45)),
              ),
              FilledButton(
                onPressed: textCtl.text.trim() == '确定删除'
                    ? () => Navigator.pop(dlgCtx, true)
                    : null,
                style: FilledButton.styleFrom(backgroundColor: V9Dark.warn),
                child: const Text('永久删除'),
              ),
            ],
          ),
        );
      },
    );
    if (finalOk != true) return;
    if (!mounted) return;
    final name = entry.name;
    await ClassStore.I.deleteClass(entry.id);
    if (!mounted) return;
    setD(() {});
    _toast('已删除「$name」');
  }

  /// 赞助作者卡片（外观卡同构：ListTile 包 Material）
  Widget _sponsorCard() {
    return Container(
      decoration: BoxDecoration(
        color: c.surfCardSolid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.bdSoft),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: _showSponsorDialog,
          leading: Icon(Icons.local_cafe_outlined, size: 22, color: c.ink),
          title: Text('赞助作者',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.ink)),
          subtitle: Text('如果觉得有帮助，请作者喝一杯咖啡吧',
              style: TextStyle(fontSize: 11, color: c.ink45)),
          trailing: Icon(Icons.chevron_right, size: 18, color: c.ink45),
        ),
      ),
    );
  }

  // ── 外观三模式（对齐鸿蒙 MeView 外观弹窗：跟随系统/浅色/深色 + 勾选圈）──
  Future<void> _showThemeSheet() async {
    final t = ThemeController.I;
    // 局部 pending：弹窗内不碰控制器（否则 setMode 的等值短路会吞掉持久化+广播）
    String pending = t.mode;
    final applied = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = V9ThemeScope.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            backgroundColor: c.surfCardSolid,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('外观',
                style: TextStyle(
                    color: V9Dark.ink, fontWeight: FontWeight.w700)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (mode, title, sub) in [
                ('system', '跟随系统', '随系统深浅模式自动切换'),
                ('light', '浅色', '奶油纸面'),
                ('dark', '深色', '暗夜葡萄（默认）'),
              ])
                InkWell(
                  onTap: () => setD(() => pending = mode),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 6),
                    child: Row(children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: pending == mode
                                  ? LinearGradient(
                                      colors: V9G.checkColors)
                                  : null,
                              border: pending == mode
                                  ? null
                                  : Border.all(
                                      color: c.ink45, width: 1.5),
                            ),
                          ),
                          if (pending == mode)
                            const Icon(Icons.check,
                                size: 14, color: Colors.white),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.ink)),
                            Text(sub,
                                style: TextStyle(
                                    fontSize: 11, color: c.ink45)),
                          ]),
                    ]),
                  ),
                ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('取消', style: TextStyle(color: V9Dark.ink45)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'apply'),
                style:
                    FilledButton.styleFrom(backgroundColor: c.act2),
                child: const Text('应用'),
              ),
            ],
          ),
        );
      },
    );
    if (applied == 'apply' && pending != t.mode) {
      await t.setMode(pending); // 持久化 + 全局广播（v28.11 同构语义）
      _toast('外观已切换');
    }
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
        backgroundColor: c.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('从备份还原',
            style: TextStyle(color: c.warn, fontWeight: FontWeight.w700)),
        content: Text(
          '将用「${picked.name}」覆盖当前全部数据。\n还原前会自动生成快照。',
          style: TextStyle(color: c.ink60, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: c.ink45)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: c.warn),
            child: Text('确认还原'),
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
          backgroundColor: c.surfCardSolid,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('发现重名学生',
              style:
                  TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
          content: Text(
            '有 ${plan.fileDups.length} 名学生在文件内重名\n\n'
            '「跳过重名」：忽略这些学生\n「全部导入」：重名学生也导入',
            style: TextStyle(color: c.ink60, height: 1.7),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('跳过重名',
                  style: TextStyle(color: c.warn)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: c.act2),
              child: Text('全部导入'),
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
        backgroundColor: c.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('导入课时',
            style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
        content: Text(
          '解析成功：共 ${matrix!.length - 1} 名学生\n'
          '将新增 ${plan.added} 人，更新 ${plan.updated} 人'
          '${plan.skipped > 0 ? '，跳过 ${plan.skipped} 人' : ''}\n\n'
          '月结学生的已上课时不会被改动。',
          style: TextStyle(color: c.ink60, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: c.ink45)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: c.act2),
            child: Text('确定导入'),
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
        backgroundColor: c.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('从快照还原',
            style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
        content: Text(
          '将用快照覆盖当前全部数据：\n$name\n\n当前未保存的改动会丢失。',
          style: TextStyle(color: c.ink60, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('取消', style: TextStyle(color: c.ink45)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: c.act2),
            child: Text('确认还原'),
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
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ListenableBuilder(
        listenable: eng,
        builder: (context, _) => SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              _header(),
              SizedBox(height: 16),
              _classCard(),
              SizedBox(height: 16),
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
              SizedBox(height: 16),
              _sectionTitle('外观'),
              _themeCard(),
              const SizedBox(height: 16),
              _sectionTitle('支持'),
              _sponsorCard(),
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
        Text('我的',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: c.ink)),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: c.tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(kVersionMark,
              style: TextStyle(fontSize: 11, color: c.ink60)),
        ),
      ],
    );
  }

  Widget _classCard() {
    return GestureDetector(
      onTap: _showClassManager,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.surfCardSolid,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.bdSoft),
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.avatarBg,
            ),
            child: Text(
              eng.className.isEmpty ? '班' : eng.className.substring(0, 1),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: c.act2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(eng.className,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: c.ink)),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 18, color: c.ink45),
                ]),
                const SizedBox(height: 4),
                Text(
                  '${eng.students.length} 名学生 · ${eng.records.length} 条打卡记录\n点击管理班级（${ClassStore.I.classes.length} 个班）',
                  style:
                      TextStyle(fontSize: 13, color: c.ink45, height: 1.5),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: TextStyle(
              fontSize: 13,
              color: c.ink45,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _menuCard(List<_MenuItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: c.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.bdSoft),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 54, color: c.bdSoft),
            items[i].build(context, _busy),
          ],
        ],
      ),
    );
  }

  Widget _themeCard() {
    final t = ThemeController.I;
    final label = switch (t.mode) {
      'light' => '浅色 · 奶油纸面',
      'system' => '跟随系统',
      _ => '深色 · 暗夜葡萄',
    };
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.bdSoft),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: _showThemeSheet,
          leading: Icon(Icons.palette_outlined, size: 22, color: c.ink),
          title: Text('外观',
              style: TextStyle(
                  fontSize: 14, color: c.ink, fontWeight: FontWeight.w500)),
          trailing: Text(label,
              style: TextStyle(fontSize: 12, color: c.ink45)),
        ),
      ),
    );
  }

  Widget _aboutCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.bdSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('课点到 · Android',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.ink)),
          const SizedBox(height: 6),
          Text(
            '老师的班级点名 / 课时统计工具\n纯本机存储 · 无网络权限 · 无遥测\n开源版发布（MIT License）',
            style: TextStyle(fontSize: 12, color: c.ink45, height: 1.7),
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
    final c = V9ThemeScope.of(context);
    final enabled = onTap != null && !busy;
    final color = !enabled
        ? c.ink45.withValues(alpha: 0.4)
        : danger
            ? c.warn
            : c.ink;
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
            size: 20, color: c.ink45.withValues(alpha: 0.5)),
      ),
    );
  }
}
