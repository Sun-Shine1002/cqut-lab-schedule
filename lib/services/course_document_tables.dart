import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

const maxCourseDocumentBytes = 8 * 1024 * 1024;
const _maxPartBytes = 16 * 1024 * 1024;
const _maxPackageBytes = 64 * 1024 * 1024;
const _maxParts = 2048;
const _maxTables = 256;
const _maxRows = 4096;
const _maxColumns = 512;
const _maxCells = 1000000;
const _tableLimit = FormatException('文档中的课表超出支持的行列范围。');
const _invalidPackage = FormatException('无法读取文档，请检查文件是否完整且未加密。');

/// Reads Excel worksheets in workbook order or Word tables in document order.
/// Empty Excel cells keep their original column positions. A merged cell's
/// text is repeated in its covered positions so headers keep their alignment.
Map<String, List<List<String>>> readCourseDocumentTables(
  Uint8List bytes,
  String fileName,
) {
  final lowerName = fileName.toLowerCase();
  final isWorkbook = lowerName.endsWith('.xlsx');
  if (!isWorkbook && !lowerName.endsWith('.docx')) {
    throw const FormatException('请选择 .xlsx 或 .docx 文件。');
  }
  if (bytes.length > maxCourseDocumentBytes) {
    throw const FormatException('文件超过 8 MB，请精简课表后重试。');
  }
  try {
    final parts = _OfficeParts(bytes);
    return isWorkbook ? _readWorkbook(parts) : _readWord(parts);
  } on ArchiveException {
    throw _invalidPackage;
  } on RangeError {
    throw _invalidPackage;
  }
}

class _OfficeParts {
  final _headers = <String, ZipFileHeader>{};
  int _cells = 0;

  _OfficeParts(Uint8List bytes) {
    final directory = ZipDirectory();
    var total = 0;
    for (final header in directory.headers(
      InputMemoryStream(bytes),
      verify: true,
    )) {
      final size = header.uncompressedSize;
      total += size;
      if (_headers.length >= _maxParts ||
          size < 0 ||
          size > _maxPartBytes ||
          total > _maxPackageBytes) {
        throw const FormatException('文档解压后过大，请精简课表后重试。');
      }
      if (_headers.containsKey(header.filename)) throw _invalidPackage;
      _headers[header.filename] = header;
    }
    if (_headers.isEmpty) throw _invalidPackage;
  }

  void reserveCells(int count) {
    _cells += count;
    if (_cells > _maxCells) throw _tableLimit;
  }

  bool contains(String path) => _headers.containsKey(path);

  XmlElement readXml(String path) {
    final header = _headers[path];
    if (header == null ||
        header.generalPurposeBitFlag & 1 != 0 ||
        (header.compressionMethod != 0 && header.compressionMethod != 8)) {
      throw _invalidPackage;
    }
    final file = header.file;
    if (file == null ||
        file.flags & 1 != 0 ||
        file.uncompressedSize != header.uncompressedSize ||
        (file.compressionMethod != CompressionType.none &&
            file.compressionMethod != CompressionType.deflate)) {
      throw _invalidPackage;
    }
    file.verify = true;
    file.throwOnError = true;
    final output = OutputMemoryStream();
    file.decompress(output);
    final bytes = output.getBytes();
    if (bytes.length != header.uncompressedSize) throw _invalidPackage;

    try {
      final source = _decodeXml(bytes);
      if (source.contains('<!DOCTYPE') || source.contains('<!ENTITY')) {
        throw const FormatException('文档包含不支持的 XML 声明。');
      }
      return XmlDocument.parse(source).rootElement;
    } on XmlException {
      throw const FormatException('文档中的课表结构无法识别。');
    }
  }
}

String _decodeXml(Uint8List bytes) {
  if (bytes.length >= 2) {
    final marker = (bytes[0] << 8) | bytes[1];
    final little = marker == 0xfffe || marker == 0x3c00;
    final big = marker == 0xfeff || marker == 0x003c;
    if (little || big) {
      if (bytes.length.isOdd) throw _invalidPackage;
      final start = marker == 0xfffe || marker == 0xfeff ? 2 : 0;
      final data = ByteData.sublistView(bytes);
      final endian = little ? Endian.little : Endian.big;
      return String.fromCharCodes([
        for (var i = start; i < bytes.length; i += 2) data.getUint16(i, endian),
      ]);
    }
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw _invalidPackage;
  }
}

Iterable<XmlElement> _children(XmlElement element, String name) =>
    element.childElements.where((child) => child.name.local == name);

XmlElement? _child(XmlElement element, String name) =>
    _children(element, name).firstOrNull;

String? _attribute(XmlElement element, String name) => element.attributes
    .where((attribute) => attribute.name.local == name)
    .firstOrNull
    ?.value;

String? _workbookTarget(String target) {
  final uri = Uri.tryParse(target);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      target.contains('\\')) {
    return null;
  }
  final path = Uri.parse('/xl/workbook.xml').resolveUri(uri).pathSegments;
  if (path.isEmpty ||
      path.first != 'xl' ||
      path.any((segment) => segment == '..' || segment.contains('/'))) {
    return null;
  }
  return path.join('/');
}

Map<String, List<List<String>>> _readWorkbook(_OfficeParts parts) {
  final workbook = parts.readXml('xl/workbook.xml');
  final relations = parts.readXml('xl/_rels/workbook.xml.rels');
  if (workbook.name.local != 'workbook' ||
      relations.name.local != 'Relationships') {
    throw _invalidPackage;
  }
  final worksheets = <String, String>{};
  String? sharedPath;
  for (final relation in _children(relations, 'Relationship')) {
    if (_attribute(relation, 'TargetMode') == 'External') continue;
    final type = _attribute(relation, 'Type')?.split('/').last;
    final target = _workbookTarget(_attribute(relation, 'Target') ?? '');
    final id = _attribute(relation, 'Id');
    if (id == null || target == null) continue;
    if (type == 'worksheet') worksheets[id] = target;
    if (type == 'sharedStrings') sharedPath = target;
  }
  if (sharedPath == null && parts.contains('xl/sharedStrings.xml')) {
    sharedPath = 'xl/sharedStrings.xml';
  }
  final sharedStrings = sharedPath == null
      ? const <String>[]
      : _children(parts.readXml(sharedPath), 'si').map(_richText).toList();
  final result = <String, List<List<String>>>{};
  final seenPaths = <String>{};
  final sheets = _child(workbook, 'sheets');
  if (sheets == null) return result;
  for (final sheet in _children(sheets, 'sheet')) {
    final path = worksheets[_attribute(sheet, 'id')];
    if (path == null) continue;
    final name = _attribute(sheet, 'name');
    if (name == null || result.containsKey(name) || !seenPaths.add(path)) {
      throw _invalidPackage;
    }
    if (result.length >= _maxTables) throw _tableLimit;
    result[name] = _readWorksheet(parts, parts.readXml(path), sharedStrings);
  }
  return result;
}

String _richText(XmlElement element) {
  final buffer = StringBuffer();
  for (final child in element.childElements) {
    if (child.name.local == 't') buffer.write(child.innerText);
    if (child.name.local == 'r')
      buffer.write(_child(child, 't')?.innerText ?? '');
  }
  return buffer.toString();
}

final _cellAddress = RegExp(r'^([A-Z]{1,3})([1-9][0-9]{0,6})$');

(int, int)? _address(String reference) {
  final match = _cellAddress.firstMatch(reference);
  if (match == null) return null;
  var column = 0;
  for (final letter in match.group(1)!.codeUnits) {
    column = column * 26 + letter - 64;
  }
  return (int.parse(match.group(2)!) - 1, column - 1);
}

String _spreadsheetCell(XmlElement cell, List<String> sharedStrings) {
  final value = _child(cell, 'v')?.innerText ?? '';
  switch (_attribute(cell, 't')) {
    case 's':
      final index = int.tryParse(value.trim());
      if (index == null || index < 0 || index >= sharedStrings.length) {
        throw _invalidPackage;
      }
      return sharedStrings[index];
    case 'inlineStr':
      final inline = _child(cell, 'is');
      return inline == null ? '' : _richText(inline);
    case 'e':
      return '';
    default:
      return value;
  }
}

void _putCell(_OfficeParts parts, List<String> row, int column, String value) {
  if (column >= _maxColumns) throw _tableLimit;
  final extra = column + 1 - row.length;
  if (extra > 0) {
    parts.reserveCells(extra);
    row.addAll(List.filled(extra, ''));
  }
  row[column] = value;
}

List<List<String>> _readWorksheet(
  _OfficeParts parts,
  XmlElement sheet,
  List<String> sharedStrings,
) {
  if (sheet.name.local != 'worksheet') throw _invalidPackage;
  final rows = <List<String>>[];
  final sheetData = _child(sheet, 'sheetData');
  if (sheetData == null) return rows;
  var nextRow = 0;
  for (final row in _children(sheetData, 'row')) {
    final cells = _children(row, 'c');
    final firstCell = cells.firstOrNull;
    final firstReference = firstCell == null
        ? null
        : _attribute(firstCell, 'r');
    final rowNumber = int.tryParse(_attribute(row, 'r') ?? '');
    final index = rowNumber != null
        ? rowNumber - 1
        : (firstReference == null ? null : _address(firstReference)?.$1) ??
              nextRow;
    nextRow = index + 1;
    if (index < 0) throw _invalidPackage;
    var nextColumn = 0;
    for (final cell in cells) {
      final reference = _attribute(cell, 'r');
      final address = reference == null ? null : _address(reference);
      if (reference != null && (address == null || address.$1 != index)) {
        throw _invalidPackage;
      }
      final column = address?.$2 ?? nextColumn;
      nextColumn = column + 1;
      final value = _spreadsheetCell(cell, sharedStrings).trim();
      if (value.isEmpty) continue;
      if (index >= _maxRows || column >= _maxColumns) throw _tableLimit;
      while (rows.length <= index) {
        rows.add(<String>[]);
      }
      _putCell(parts, rows[index], column, value);
    }
  }

  final merges = _child(sheet, 'mergeCells');
  if (merges == null) return rows;
  var mergeCells = 0;
  for (final merge in _children(merges, 'mergeCell')) {
    final range = (_attribute(merge, 'ref') ?? '').split(':');
    if (range.length != 2) continue;
    final start = _address(range.first);
    final end = _address(range.last);
    if (start == null || end == null || start.$1 >= rows.length) continue;
    final first = rows[start.$1];
    if (start.$2 >= first.length || first[start.$2].isEmpty) continue;
    final value = first[start.$2];
    if (end.$1 >= _maxRows || end.$2 >= _maxColumns) throw _tableLimit;
    if (end.$1 < start.$1 || end.$2 < start.$2) throw _invalidPackage;
    mergeCells += (end.$1 - start.$1 + 1) * (end.$2 - start.$2 + 1);
    if (mergeCells > _maxCells) throw _tableLimit;
    while (rows.length <= end.$1) {
      rows.add(<String>[]);
    }
    for (var y = start.$1; y <= end.$1; y++) {
      for (var x = start.$2; x <= end.$2; x++) {
        if (x >= rows[y].length || rows[y][x].isEmpty) {
          _putCell(parts, rows[y], x, value);
        }
      }
    }
  }
  return rows;
}

final _wordClassCaption = RegExp(r'^(?:专业|行政)?班级\s*[:：]\s*\S');

Map<String, List<List<String>>> _readWord(_OfficeParts parts) {
  final document = parts.readXml('word/document.xml');
  final body = _child(document, 'body');
  if (document.name.local != 'document' || body == null) throw _invalidPackage;
  final result = <String, List<List<String>>>{};
  for (final table in body.descendants.whereType<XmlElement>()) {
    if (table.name.local != 'tbl') continue;
    final rows = _readWordTable(parts, table);
    if (rows.isEmpty) continue;
    if (result.length >= _maxTables) throw _tableLimit;
    final previous = table.previousElementSibling;
    if (identical(table.parent, body) && previous?.name.local == 'p') {
      final caption = _wordParagraph(previous!).trim();
      if (_wordClassCaption.hasMatch(caption)) {
        parts.reserveCells(1);
        rows.insert(0, [caption]);
      }
    }
    result['表格 ${result.length + 1}'] = rows;
  }
  return result;
}

List<List<String>> _readWordTable(_OfficeParts parts, XmlElement table) {
  final rows = <List<String>>[];
  var previousMerges = <int, String>{};
  for (final row in _children(table, 'tr')) {
    if (rows.length >= _maxRows) throw _tableLimit;
    final rowProperties = _child(row, 'trPr');
    final gridBefore = rowProperties == null
        ? null
        : _child(rowProperties, 'gridBefore');
    var column = gridBefore == null
        ? 0
        : int.tryParse(_attribute(gridBefore, 'val') ?? '') ?? 0;
    if (column < 0 || column > _maxColumns) throw _tableLimit;
    final values = <String>[];
    final merges = <int, String>{};
    for (final cell in _children(row, 'tc')) {
      final properties = _child(cell, 'tcPr');
      final gridSpan = properties == null
          ? null
          : _child(properties, 'gridSpan');
      final span = gridSpan == null
          ? 1
          : int.tryParse(_attribute(gridSpan, 'val') ?? '') ?? 1;
      if (span < 1 || span > _maxColumns - column) throw _tableLimit;
      final merge = properties == null ? null : _child(properties, 'vMerge');
      final continuing = merge != null && _attribute(merge, 'val') != 'restart';
      final text = _children(cell, 'p').map(_wordParagraph).join('\n').trim();
      for (var offset = 0; offset < span; offset++) {
        final value = continuing ? previousMerges[column] ?? text : text;
        _putCell(parts, values, column, value);
        if (merge != null) merges[column] = value;
        column++;
      }
    }
    previousMerges = merges;
    rows.add(values);
  }
  return rows;
}

String _wordParagraph(XmlElement paragraph) {
  final buffer = StringBuffer();
  for (final element in paragraph.descendants.whereType<XmlElement>()) {
    switch (element.name.local) {
      case 't':
        buffer.write(element.innerText);
      case 'br':
      case 'cr':
        buffer.writeln();
      case 'tab':
        buffer.write('\t');
    }
  }
  return buffer.toString();
}
