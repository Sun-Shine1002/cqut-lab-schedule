import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cqut_lab_schedule/services/course_document_tables.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _package(Map<String, String> parts) {
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.string(part.key, part.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('reads workbook order, rich strings, gaps, and merged headers', () {
    final data = _package({
      'xl/workbook.xml': '''
        <workbook xmlns:r="urn:example:relationships">
          <sheets>
            <sheet name="课内实验" sheetId="8" r:id="rId2"/>
            <sheet name="其他" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>''',
      'xl/_rels/workbook.xml.rels': '''
        <Relationships>
          <Relationship Id="rId1" Type="urn:type/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="urn:type/worksheet" Target="/xl/worksheets/sheet2.xml"/>
          <Relationship Id="rId3" Type="urn:type/sharedStrings" Target="strings.xml"/>
        </Relationships>''',
      'xl/strings.xml': '''
        <sst><si><r><t>实验</t></r><r><t>名称</t></r><rPh><t>拼音</t></rPh></si></sst>''',
      'xl/worksheets/sheet1.xml': '<worksheet><sheetData/></worksheet>',
      'xl/worksheets/sheet2.xml': '''
        <worksheet>
          <sheetData>
            <row r="2"><c r="A2" t="s"><v>0</v></c><c r="C2" t="inlineStr"><is><t>开课</t></is></c></row>
            <row r="3"><c r="C3" t="inlineStr"><is><r><t>周</t></r><r><t>次</t></r></is></c></row>
            <row r="4"><c r="A4" t="str"><f>ignored()</f><v>电子实验</v></c><c r="C4"><v>8</v></c></row>
          </sheetData>
          <mergeCells><mergeCell ref="A2:A3"/></mergeCells>
        </worksheet>''',
    });

    final tables = readCourseDocumentTables(data, '课表.XLSX');
    expect(tables.keys, ['课内实验', '其他']);
    expect(tables['课内实验'], [
      <String>[],
      ['实验名称', '', '开课'],
      ['实验名称', '', '周次'],
      ['电子实验', '', '8'],
    ]);
    expect(tables['其他'], isEmpty);
  });

  test('reads Word column spans, vertical merges, and cell line breaks', () {
    final data = _package({
      'word/document.xml': '''
        <w:document xmlns:w="urn:example:word"><w:body>
          <w:tbl>
            <w:tr>
              <w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge w:val="restart"/></w:tcPr><w:p><w:r><w:t>实验</w:t></w:r></w:p></w:tc>
              <w:tc><w:p><w:r><w:t>开课</w:t></w:r></w:p></w:tc>
            </w:tr>
            <w:tr>
              <w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge/></w:tcPr><w:p/></w:tc>
              <w:tc><w:p><w:r><w:t>周次</w:t><w:br/><w:t>7</w:t></w:r></w:p><w:p><w:r><w:t>8</w:t></w:r></w:p></w:tc>
            </w:tr>
          </w:tbl>
          <w:tbl><w:tr><w:tc><w:p><w:r><w:t>第二张表</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        </w:body></w:document>''',
    });

    final tables = readCourseDocumentTables(data, '课表.docx');
    expect(tables.keys, ['表格 1', '表格 2']);
    expect(tables['表格 1'], [
      ['实验', '实验', '开课'],
      ['实验', '实验', '周次\n7\n8'],
    ]);
    expect(tables['表格 2'], [
      ['第二张表'],
    ]);
  });

  test('rejects non-Office files and document type declarations', () {
    expect(
      () => readCourseDocumentTables(Uint8List(0), '课表.xlsx'),
      throwsFormatException,
    );
    final withDoctype = _package({
      'word/document.xml': '<!DOCTYPE document><document><body/></document>',
    });
    expect(
      () => readCourseDocumentTables(withDoctype, '课表.docx'),
      throwsFormatException,
    );
  });

  test(
    'applies a standalone class caption to the adjacent Word table only',
    () {
      final data = _package({
        'word/document.xml': '''
        <w:document xmlns:w="urn:example:word"><w:body>
          <w:p><w:r><w:t>专业班级：</w:t></w:r><w:r><w:t>计算机 2501</w:t></w:r></w:p>
          <w:tbl><w:tr><w:tc><w:p><w:r><w:t>课程名称</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
          <w:tbl><w:tr><w:tc><w:p><w:r><w:t>其他内容</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        </w:body></w:document>''',
      });

      final tables = readCourseDocumentTables(data, '课表.docx');
      expect(tables['表格 1'], [
        ['专业班级：计算机 2501'],
        ['课程名称'],
      ]);
      expect(tables['表格 2'], [
        ['其他内容'],
      ]);
    },
  );
}
