import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One sheet or CSV file: its name and its rows of cells, as text. An
/// XLSX number stays a number written out ("45292"), which is how a date
/// cell arrives; [HistoryFile] reads it as one.
class SheetTable {
  final String name;
  final List<List<String>> rows;

  const SheetTable(this.name, this.rows);
}

/// The tables in an export file: a CSV, an XLSX workbook (each sheet in
/// order), or a ZIP holding either (each in name order).
List<SheetTable> readTables(String name, Uint8List bytes) {
  if (!_isZip(bytes)) return [SheetTable(name, readCsv(_text(bytes)))];
  final archive = ZipDecoder().decodeBytes(bytes);
  if (archive.findFile('xl/workbook.xml') != null) return _readXlsx(archive);
  final files = [
    for (final f in archive.files)
      if (f.isFile && !f.name.split('/').last.startsWith('.')) f,
  ]..sort((a, b) => a.name.compareTo(b.name));
  return [
    for (final f in files)
      if (f.name.toLowerCase().endsWith('.csv') ||
          f.name.toLowerCase().endsWith('.xlsx'))
        ...readTables(f.name, f.content),
  ];
}

bool _isZip(Uint8List b) =>
    b.length > 3 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 3 && b[3] == 4;

String _text(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

/// Rows of [text], split on the delimiter its first line uses most: a
/// comma, a semicolon (Europe's spreadsheets) or a tab. Quoted cells may
/// hold delimiters, `""` and line breaks.
List<List<String>> readCsv(String text) {
  final firstLine = text.split('\n').first;
  final delimiter = [',', ';', '\t'].reduce(
    (a, b) =>
        b.allMatches(firstLine).length > a.allMatches(firstLine).length ? b : a,
  );
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  void endCell() {
    row.add(cell.toString().trim());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch != '"') {
        cell.write(ch);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = false;
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == delimiter) {
      endCell();
    } else if (ch == '\n') {
      endRow();
    } else if (ch != '\r') {
      cell.write(ch);
    }
  }
  endRow();
  return rows;
}

List<SheetTable> _readXlsx(Archive archive) {
  String? part(String path) {
    final file = archive.findFile(path);
    return file == null ? null : utf8.decode(file.content);
  }

  final shared = [
    for (final si in RegExp(
      r'<si>(.*?)</si>',
      dotAll: true,
    ).allMatches(part('xl/sharedStrings.xml') ?? ''))
      _runs(si.group(1)!),
  ];
  final names = [
    for (final m in RegExp(
      r'<sheet\b[^>]*\bname="([^"]*)"',
    ).allMatches(part('xl/workbook.xml')!))
      _unescape(m.group(1)!),
  ];
  int number(String path) =>
      int.parse(RegExp(r'sheet(\d+)\.xml$').firstMatch(path)!.group(1)!);
  final sheets = [
    for (final f in archive.files)
      if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)) f.name,
  ]..sort((a, b) => number(a).compareTo(number(b)));
  return [
    for (final (i, path) in sheets.indexed)
      SheetTable(
        i < names.length ? names[i] : path,
        _sheetRows(part(path)!, shared),
      ),
  ];
}

final _cellPattern = RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);

List<List<String>> _sheetRows(String xml, List<String> shared) {
  final rows = <List<String>>[];
  for (final r in RegExp(
    r'<row\b[^>]*>(.*?)</row>',
    dotAll: true,
  ).allMatches(xml)) {
    final row = <String>[];
    for (final c in _cellPattern.allMatches(r.group(1)!)) {
      final attributes = c.group(1)!;
      final body = c.group(2) ?? '';
      final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attributes);
      final column = ref == null ? row.length : _columnIndex(ref.group(1)!);
      while (row.length < column) {
        row.add('');
      }
      final type = RegExp(r'\bt="(\w+)"').firstMatch(attributes)?.group(1);
      final value = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body);
      row.add(
        switch (type) {
          's' => shared[int.parse(value!.group(1)!)],
          'inlineStr' => _runs(body),
          _ => _unescape(value?.group(1) ?? ''),
        }.trim(),
      );
    }
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
  }
  return rows;
}

int _columnIndex(String letters) =>
    letters.codeUnits.fold(0, (n, c) => n * 26 + c - 64) - 1;

/// The text of a shared or inline string: its runs joined.
String _runs(String xml) => _unescape(
  RegExp(
    r'<t\b[^>]*>(.*?)</t>',
    dotAll: true,
  ).allMatches(xml).map((m) => m.group(1)!).join(),
);

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
