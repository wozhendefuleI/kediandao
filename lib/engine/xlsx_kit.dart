// ══════════════════════════════════════════════════════════════
// XlsxKit · Excel 读写（M2）—— XlsxKit.ets (v1.1.10) 直译
// 口径 §4：19 列课时表 / 逐日列打卡记录 / 单解析器
// 导出：archive 包 zip-store + inlineStr XML（与鸿蒙同构）
// 导入：archive 解包 → sheet1 + sharedStrings → 矩阵解析
// ══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'checkin_engine.dart';

class RosterExportRow {
  final int seq;
  final String name;
  final String type; // '套餐' | '月结'
  final String className;
  final List<double> monthHours; // 12 个月
  final double? totalHours;
  final double? usedHours;
  final double? remainingHours;
  RosterExportRow({
    required this.seq,
    required this.name,
    required this.type,
    required this.className,
    required this.monthHours,
    this.totalHours,
    this.usedHours,
    this.remainingHours,
  });
}

class RecordsExportRow {
  final int seq;
  final String name;
  final String className;
  final String type; // '学期' | '月结'
  final List<String> dates;
  RecordsExportRow({
    required this.seq,
    required this.name,
    required this.className,
    required this.type,
    required this.dates,
  });
}

class XlsxKit {
  // ── XML 片段常量（与 XlsxKit.ets L143-185 一致）──
  static const String _contentTypes = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
      "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
      "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
      "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
      "<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
      "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
      "</Types>";
  static const String _rels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
      "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
      "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
      "</Relationships>";
  static const String _workbook = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
      "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" "
      "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
      "<sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>";
  static const String _workbookRels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
      "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
      "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>"
      "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
      "</Relationships>";
  static const String _styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
      "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
      "<fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>"
      "<fills count=\"1\"><fill><patternFill patternType=\"none\"/></fill></fills>"
      "<borders count=\"1\"><border/></borders>"
      "<cellStyleXfs count=\"1\"><xf/></cellStyleXfs>"
      "<cellXfs count=\"1\"><xf/></cellXfs>"
      "</styleSheet>";

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _colName(int n) {
    String s = '';
    int v = n;
    while (v > 0) {
      final rem = (v - 1) % 26;
      s = String.fromCharCode(65 + rem) + s;
      v = (v - 1) ~/ 26;
    }
    return s;
  }

  static int _colIndex(String col) {
    int idx = 0;
    for (int i = 0; i < col.length; i++) {
      idx = idx * 26 + (col.codeUnitAt(i) - 64);
    }
    return idx - 1;
  }

  static String _textCell(String ref, String val) =>
      '<c r="$ref" t="inlineStr"><is><t>${_esc(val)}</t></is></c>';

  /// 鸿蒙 JS number 序列化对齐：整数不带 .0（30.0→'30'），小数保留（1.5→'1.5'）
  static String _numStr(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static String _numCell(String ref, num val) =>
      '<c r="$ref"><v>${_numStr(val)}</v></c>';

  /// zip-store 打包（store 模式，与鸿蒙 makeZip 同构：无压缩、CRC32 由 archive 计算）
  static Uint8List buildXlsx(String sheetXml) {
    final encoder = ZipEncoder();
    final archive = Archive();
    void addFile(String name, String content) {
      final bytes = utf8.encode(content);
      archive.add(ArchiveFile.bytes(name, bytes));
    }

    for (final e in [
      ['[Content_Types].xml', _contentTypes],
      ['_rels/.rels', _rels],
      ['xl/workbook.xml', _workbook],
      ['xl/_rels/workbook.xml.rels', _workbookRels],
      ['xl/worksheets/sheet1.xml', sheetXml],
      ['xl/styles.xml', _styles],
    ]) {
      addFile(e[0], e[1]);
    }
    return Uint8List.fromList(encoder.encode(archive));
  }

  // ── 口径 §4.1：课时表（19 列）──
  static const List<String> _rosterHeaders = [
    '序号', '姓名', '类型', '班级',
    '一月', '二月', '三月', '四月', '五月', '六月',
    '七月', '八月', '九月', '十月', '十一月', '十二月',
    '总课时', '累计', '剩余课时',
  ];

  /// 口径 §4.2：monthly 月列=次数；semester 月列=加权课时求和
  /// （调用方按此为学生预算 monthHours 后传入 buildRosterXlsx）
  static double monthCell(CheckInEngine eng, Student s, String yearMonth) =>
      s.payType == 'monthly'
          ? eng.records
              .where((r) =>
                  r.studentId == s.id && r.date.startsWith(yearMonth))
              .length
              .toDouble()
          : eng.records
              .where((r) =>
                  r.studentId == s.id && r.date.startsWith(yearMonth))
              .fold(0.0, (acc, r) => acc + r.hours);

  static Uint8List buildRosterXlsx(List<RosterExportRow> rows) {
    String xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>';
    xml += '<row r="1">';
    for (int c = 1; c <= _rosterHeaders.length; c++) {
      xml += _textCell('${_colName(c)}1', _rosterHeaders[c - 1]);
    }
    xml += '</row>';
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      final rn = i + 2;
      xml += '<row r="$rn">';
      xml += _numCell('A$rn', r.seq);
      xml += _textCell('B$rn', r.name);
      xml += _textCell('C$rn', r.type);
      xml += _textCell('D$rn', r.className);
      for (int m = 0; m < 12; m++) {
        xml += _numCell('${_colName(5 + m)}$rn', r.monthHours[m]);
      }
      if (r.totalHours != null) xml += _numCell('Q$rn', r.totalHours!);
      if (r.usedHours != null) xml += _numCell('R$rn', r.usedHours!);
      if (r.remainingHours != null) {
        xml += _numCell('S$rn', r.remainingHours!);
      }
      xml += '</row>';
    }
    xml += '</sheetData></worksheet>';
    return buildXlsx(xml);
  }

  /// 下载用的课时表模板（表头 + 2 行示例，与鸿蒙 buildRosterTemplate 同构）
  static Uint8List buildRosterTemplate() {
    final rows = [
      RosterExportRow(
        seq: 1, name: '张三', type: '套餐', className: '三年级1班',
        monthHours: [0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0],
        totalHours: 30, usedHours: 8, remainingHours: 22,
      ),
      RosterExportRow(
        seq: 2, name: '李四', type: '月结', className: '三年级1班',
        monthHours: [0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0],
      ),
    ];
    return buildRosterXlsx(rows);
  }

  // ── 口径 §4.3：打卡记录（逐日列）──
  static Uint8List buildRecordsXlsx(
      List<RecordsExportRow> rows, List<String> dates) {
    String xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>';
    final headers = ['序号', '姓名', '班级', '类型', ...dates];
    xml += '<row r="1">';
    for (int c = 1; c <= headers.length; c++) {
      xml += _textCell('${_colName(c)}1', headers[c - 1]);
    }
    xml += '</row>';
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      final rn = i + 2;
      xml += '<row r="$rn">';
      xml += _numCell('A$rn', r.seq);
      xml += _textCell('B$rn', r.name);
      xml += _textCell('C$rn', r.className);
      xml += _textCell('D$rn', r.type);
      for (int d = 0; d < dates.length; d++) {
        if (r.dates.contains(dates[d])) {
          xml += _textCell('${_colName(5 + d)}$rn', dates[d]);
        }
      }
      xml += '</row>';
    }
    xml += '</sheetData></worksheet>';
    return buildXlsx(xml);
  }

  // ── 导入解析（单解析器；兼容 sharedStrings 与 inlineStr）──

  static String _decodeEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');

  static List<String> parseSharedStrings(String ssXml) {
    final list = <String>[];
    final si = RegExp(r'<si[\s\S]*?</si>');
    for (final m in si.allMatches(ssXml)) {
      String val = '';
      for (final t in RegExp(r'<t[^>]*>([\s\S]*?)</t>').allMatches(m.group(0)!)) {
        val += t.group(1)!;
      }
      list.add(_decodeEntities(val));
    }
    return list;
  }

  /// 解析 sheet XML 为行列矩阵（A 列 = 0）
  static List<List<String>> parseSheetMatrix(String sheetXml,
      [List<String> sharedStrings = const []]) {
    final matrix = <List<String>>[];
    for (final rm in RegExp(r'<row[^>]*>([\s\S]*?)</row>').allMatches(sheetXml)) {
      final cells = <String>[];
      for (final cm in RegExp(r'<c\s+([^>]*?)/>|<c\s+([^>]*?)>([\s\S]*?)</c>')
          .allMatches(rm.group(1)!)) {
        final attrs = cm.group(2) ?? cm.group(1) ?? '';
        final body = cm.group(3) ?? '';
        final ref =
            RegExp(r'r="([A-Z]+)(\d+)"').firstMatch(attrs)?.group(1);
        if (ref == null) continue;
        final colIdx = _colIndex(ref);
        final type = RegExp(r't="([^"]+)"').firstMatch(attrs)?.group(1) ?? '';
        String val = '';
        if (type == 'inlineStr' || type == 'str') {
          val = RegExp(r'<t[^>]*>([\s\S]*?)</t>').firstMatch(body)?.group(1) ?? '';
          val = _decodeEntities(val);
        } else if (type == 's') {
          final vm = RegExp(r'<v>([\s\S]*?)</v>').firstMatch(body)?.group(1);
          final idx = vm != null ? int.tryParse(vm) : null;
          if (idx != null && idx >= 0 && idx < sharedStrings.length) {
            val = sharedStrings[idx];
          }
        } else {
          val = RegExp(r'<t[^>]*>([\s\S]*?)</t>').firstMatch(body)?.group(1) ??
              RegExp(r'<v>([\s\S]*?)</v>').firstMatch(body)?.group(1) ??
              '';
          val = _decodeEntities(val);
        }
        // Dart 的 List.length= 扩容会填 null，非空 String 直接炸 → 用 add 循环补位
        while (cells.length <= colIdx) {
          cells.add('');
        }
        cells[colIdx] = val;
      }
      matrix.add(cells);
    }
    return matrix;
  }

  /// 从 xlsx 字节解析矩阵（推荐入口，对齐鸿蒙 unzipSheetBundle）
  /// 返回 null = 非 zip/解包失败/无 sheet
  static List<List<String>>? parseMatrixFromBytes(Uint8List bytes) {
    try {
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
      final tar = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? sheet;
      ArchiveFile? ss;
      for (final f in tar) {
        if (f.name == 'xl/worksheets/sheet1.xml' ||
            f.name == 'xl/worksheets/sheet.xml') {
          sheet = f;
        } else if (f.name == 'xl/sharedStrings.xml') {
          ss = f;
        }
      }
      if (sheet == null) return null;
      final List<String> shared = ss != null
          ? parseSharedStrings(utf8.decode(ss.content))
          : const <String>[];
      return parseSheetMatrix(utf8.decode(sheet.content), shared);
    } catch (_) {
      return null;
    }
  }
}
