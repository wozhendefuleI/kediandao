// ══════════════════════════════════════════════════════════════
// CheckinView · 点名页（M1-③）
// 对照鸿蒙 CheckinView.ets (v1.1.10 @3870d4f) 语义：
// - 搜索只过滤渲染，计数器/进度恒全量（v27.2 红线）
// - 全选/反选同钮，有过滤时只动命中项（v27.2.4）
// - 切日期全量重算进度（v29.16 语义：日期是视图态，引擎现算）
// - 完成 CTA 常驻；确认弹层出统计（M2 接 sqflite 后换真持久化）
// - 弹跳 420ms 移入已到的动效归 M3 打磨（本版直切）
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' show min;
import '../engine/checkin_engine.dart';
import '../engine/store.dart';
import '../theme/v9_tokens.dart';
import '../version.dart' show kVersionMark;

class CheckinView extends StatefulWidget {
  const CheckinView({super.key});

  @override
  State<CheckinView> createState() => _CheckinViewState();
}

class _CheckinViewState extends State<CheckinView> {
  final CheckInEngine eng = CheckInEngine.I;
  DateTime selectedDate = DateTime.now();
  double sessionWeight = 1;
  String searchKey = '';
  bool saving = false;
  int _pressedId = -1; // 签到按压态（M3 动效第一拍：0.97 缩放反馈）

  static const _weekDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  String get _dateStr {
    final d = selectedDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get _dateLabel {
    final wd = _weekDays[selectedDate.weekday - 1];
    return '${selectedDate.month}/${selectedDate.day} $wd';
  }

  bool get _isToday {
    final n = DateTime.now();
    return n.year == selectedDate.year &&
        n.month == selectedDate.month &&
        n.day == selectedDate.day;
  }

  // ── 全量计量（v27.2 红线：与搜索无关，恒全量）──
  int get _doneCount => eng.todayCount(_dateStr);
  int get _pctInt => eng.students.isEmpty
      ? 0
      : min(_doneCount * 100 / eng.students.length, 100).round();

  // ── 过滤（只影响渲染）──
  List<Student> get _filtered {
    final key = searchKey.trim();
    if (key.isEmpty) return List.unmodifiable(eng.students);
    return eng.students.where((s) => s.name.contains(key)).toList();
  }

  bool get _allSelected =>
      eng.students.isNotEmpty &&
      eng.students.every((s) => eng.isCheckedIn(s.id, _dateStr));

  @override
  void initState() {
    super.initState();
    // M2 启动链：先装载存档（失败/不存在→种子数据兜底），纪律2：装载不阻塞 UI
    Store.I.load(eng).then((loaded) {
      if (!loaded) eng.seedDemo();
      eng.notifyRefresh(); // v28.11 同构：保活视图（我的/统计）靠此广播拿到装载数据
      if (mounted) setState(() {});
    });
  }

  // ── 添加学生（v1.1.0 StudentFormSheet 简化版：姓名/类型/课时，落引擎+落盘）──
  Future<void> _showAddStudent() async {
    final nameCtl = TextEditingController();
    final totalCtl = TextEditingController(text: '30');
    final usedCtl = TextEditingController(text: '0');
    String payType = 'semester';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: V9Dark.surfCardSolid,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('添加学生',
              style:
                  TextStyle(color: V9Dark.ink, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              style: const TextStyle(fontSize: 15, color: V9Dark.ink),
              decoration: const InputDecoration(
                labelText: '姓名',
                labelStyle: TextStyle(color: V9Dark.ink45, fontSize: 13),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: V9Dark.bdSoft)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('类型',
                  style: TextStyle(fontSize: 13, color: V9Dark.ink45)),
              const SizedBox(width: 12),
              Expanded(
                child: Row(children: [
                  for (final (v, label) in [
                    ('semester', '学期'),
                    ('monthly', '月结'),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setD(() => payType = v),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            gradient: payType == v
                                ? LinearGradient(
                                    colors: V9G.segColors(true))
                                : null,
                            color: payType == v
                                ? null
                                : V9Dark.surfTrack,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: payType == v
                                      ? Colors.white
                                      : V9Dark.ink45,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            if (payType == 'semester')
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: totalCtl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 15, color: V9Dark.ink),
                    decoration: const InputDecoration(
                      labelText: '总课时',
                      labelStyle:
                          TextStyle(color: V9Dark.ink45, fontSize: 13),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: V9Dark.bdSoft)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: usedCtl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 15, color: V9Dark.ink),
                    decoration: const InputDecoration(
                      labelText: '已用课时',
                      labelStyle:
                          TextStyle(color: V9Dark.ink45, fontSize: 13),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: V9Dark.bdSoft)),
                    ),
                  ),
                ),
              ])
            else
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('月结：课时由打卡自动累计',
                    style: TextStyle(fontSize: 12, color: V9Dark.ink45)),
              ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('取消', style: TextStyle(color: V9Dark.ink45)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: V9Dark.act2),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final name = nameCtl.text.trim();
    if (name.isEmpty) {
      _toast('姓名不能为空', ok: false);
      return;
    }
    final total = double.tryParse(totalCtl.text) ?? 30;
    final used = double.tryParse(usedCtl.text) ?? 0;
    eng.addStudent(name, eng.className, payType, total, used);
    final ok = await Store.I.persist(eng);
    _toast(ok ? '已添加「$name」' : '已添加，但落盘失败', ok: ok);
  }

  // ── 删除学生（v1.1.0 功能；口径 §2.3 连带清记录；先确认后删 + 即时落盘）──
  Future<void> _confirmDelete(Student s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: V9Dark.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除学生',
            style: TextStyle(color: V9Dark.warn, fontWeight: FontWeight.w700)),
        content: Text(
          '将删除「${s.name}」及其全部打卡记录。\n此操作不可撤销（导入/还原前会自动快照）。',
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    eng.deleteStudent(s.id);
    final ok = await Store.I.persist(eng);
    _toast(ok ? '已删除「${s.name}」' : '已删除，但落盘失败', ok: ok);
  }

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? V9Dark.saveBg : V9Dark.toastBg,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── 口径 §2.4 全选/反选：批量落引擎，过滤时只动命中项 ──
  void _toggleSelectAll() {
    final targets =
        searchKey.trim().isEmpty ? eng.students : _filtered;
    if (targets.isEmpty) return;
    final goingAll = !_allSelected;
    for (final s in targets) {
      final checked = eng.isCheckedIn(s.id, _dateStr);
      if (goingAll && !checked) {
        eng.checkIn(s.id, _dateStr, sessionWeight);
      } else if (!goingAll && checked) {
        eng.uncheckIn(s.id, _dateStr, sessionWeight);
      }
    }
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => selectedDate = picked); // v29.16：计量全部 getter 现算，天然联动
    }
  }

  // ── 完成 CTA（M1 内存版；M2 换 sqflite persist + 失败 toast）──
  Future<void> _finishSession() async {
    if (saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: V9Dark.surfCardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('完成本节课签到',
            style: TextStyle(color: V9Dark.ink, fontWeight: FontWeight.w700)),
        content: Text(
          '${eng.className} · $_dateLabel\n到课 $_doneCount / ${eng.students.length} 人\n'
          '本次课时权重 $sessionWeight',
          style: const TextStyle(color: V9Dark.ink60, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续点名',
                style: TextStyle(color: V9Dark.ink45)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: V9Dark.act2,
            ),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => saving = true);
    // 纪律1：await 落盘成功才算完成；失败保留内存态 + toast（P1-6 教训）
    final ok = await Store.I.persist(eng);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '已保存：$_doneCount 人到课'
            : '保存失败，请重试（内存数据未丢失）'),
        backgroundColor: ok ? V9Dark.saveBg : V9Dark.toastBg,
        behavior: SnackBarBehavior.floating,
      ));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ListenableBuilder(
        listenable: eng,
        builder: (context, _) => SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDateBar(),
                            const SizedBox(height: 12),
                            _buildProgressCard(),
                            const SizedBox(height: 12),
                            _buildSearchBar(),
                            const SizedBox(height: 16),
                            _buildTodoSection(),
                            const SizedBox(height: 16),
                            if (_filtered.any(
                                (s) => eng.isCheckedIn(s.id, _dateStr)))
                              _buildDoneSection(),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 12, // body 已被底部导航槽让位，这里贴槽上方即可（鸿蒙 bottom96 是整屏语义）
                      child: _buildFinishCta(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(eng.className,
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
      ),
    );
  }

  Widget _buildDateBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: V9Dark.dfBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.event, size: 16, color: V9Dark.act),
              const SizedBox(width: 6),
              Text(_dateLabel,
                  style: const TextStyle(
                      fontSize: 14, color: V9Dark.ink)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down,
                  size: 16, color: V9Dark.ink45),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        if (!_isToday)
          GestureDetector(
            onTap: () =>
                setState(() => selectedDate = DateTime.now()),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: V9Dark.tint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('回到今天',
                  style: TextStyle(fontSize: 13, color: V9Dark.act2)),
            ),
          ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            setState(() => sessionWeight = sessionWeight == 1 ? 0.5 : 1);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: V9G.segColors(true)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('$sessionWeight 课时',
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V9Dark.surfCardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: V9Dark.bdSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$_doneCount',
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: V9Dark.ink)),
              Text(' / ${eng.students.length} 人已到',
                  style: const TextStyle(
                      fontSize: 14, color: V9Dark.ink45)),
              const Spacer(),
              Text('$_pctInt%',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: V9Dark.act2)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _pctInt / 100),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              builder: (ctx, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: V9Dark.surfTrack,
                valueColor: AlwaysStoppedAnimation(
                    V9G.finishColors(true).last),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: V9Dark.searchBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.search, size: 18, color: V9Dark.ink45),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  style: const TextStyle(
                      fontSize: 14, color: V9Dark.ink),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '搜索学生',
                    hintStyle: TextStyle(color: V9Dark.ink45),
                  ),
                  onChanged: (v) => setState(() => searchKey = v),
                ),
              ),
              if (searchKey.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => searchKey = ''),
                  child: const Icon(Icons.close,
                      size: 16, color: V9Dark.ink45),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _toggleSelectAll,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: V9Dark.tint,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(_allSelected ? '反选' : '全选',
                style: const TextStyle(
                    fontSize: 13,
                    color: V9Dark.act2,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── 待到名单（学生卡：空心圈；点击即到）──
  Widget _buildTodoSection() {
    final todo = _filtered
        .where((s) => !eng.isCheckedIn(s.id, _dateStr))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('待到 ${todo.length}',
            style: const TextStyle(
                fontSize: 13,
                color: V9Dark.ink45,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _showAddStudent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: V9Dark.tint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('+ 添加',
                style: TextStyle(
                    fontSize: 12,
                    color: V9Dark.act2,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        if (todo.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: V9Dark.surfCardSolid,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text('全部到齐',
                textAlign: TextAlign.center,
                style: TextStyle(color: V9Dark.ink45, fontSize: 14)),
          )
        else
          ...todo.map(_buildStudentCard),
      ],
    );
  }

  // ── 已到区（chip 平铺，不可再点；撤销走点名学生卡的反向或长按，M3 打磨）──
  Widget _buildDoneSection() {
    final done = _filtered
        .where((s) => eng.isCheckedIn(s.id, _dateStr))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已到 ${done.length}',
            style: const TextStyle(
                fontSize: 13,
                color: V9Dark.act2,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: done
              .map((s) => GestureDetector(
                    onTap: () =>
                        eng.uncheckIn(s.id, _dateStr, sessionWeight),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: V9Dark.tint,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: V9Dark.saveBd),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle,
                            size: 14, color: V9Dark.act2),
                        const SizedBox(width: 6),
                        Text(s.name,
                            style: const TextStyle(
                                fontSize: 13, color: V9Dark.ink)),
                      ]),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Student s) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressedId = s.id),
      onTapCancel: () => setState(() => _pressedId = -1),
      onTapUp: (_) => setState(() => _pressedId = -1),
      onTap: () => eng.checkIn(s.id, _dateStr, sessionWeight),
      onLongPress: () => _confirmDelete(s),
      child: AnimatedScale(
        scale: _pressedId == s.id ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: V9Dark.surfCardSolid,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: V9Dark.bdSoft),
        ),
        child: Row(
          children: [
            // 空心勾圈（鸿蒙 stu-card 空心描边勾圈降级实色）
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: V9Dark.act2, width: 2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: V9Dark.ink)),
                  const SizedBox(height: 3),
                  Text(_metaCore(s),
                      style: const TextStyle(
                          fontSize: 12, color: V9Dark.ink45)),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// 口径 metaCore（CheckinView.ets L277-285 直译）
  String _metaCore(Student s) {
    double r1(double v) => (v * 10).roundToDouble() / 10;
    if (s.payType == 'monthly') {
      return '本月 ${s.monthlySessions} 次 · 已用 ${r1(s.usedHours)} 课时';
    }
    return '总 ${r1(s.totalHours)} · 已用 ${r1(s.usedHours)} · 剩 ${r1(s.remainingHours)} 课时';
  }

  Widget _buildFinishCta() {
    return GestureDetector(
      onTap: _finishSession,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: V9G.finishColors(true)),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: V9Dark.act2.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text('完成本节课签到（$_doneCount/${eng.students.length}）',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
      ),
    );
  }
}
