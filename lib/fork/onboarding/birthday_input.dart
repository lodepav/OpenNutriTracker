import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A birth date typed as digits, in the order and with the separator of the
/// locale's short date (seam S95): "22111990" reads "22.11.1990" in German
/// and "11221990" "11/22/1990" in American English. Day and month take two
/// digits each, the year four, so a separator can go in as each part fills.
class BirthdayFormat {
  /// 'd', 'M' and 'y' in the locale's order.
  final List<String> order;
  final String separator;

  const BirthdayFormat(this.order, this.separator);

  /// Read off how [localizations] writes a date whose parts all differ.
  factory BirthdayFormat.of(MaterialLocalizations localizations) {
    final sample = localizations.formatCompactDate(DateTime(2033, 11, 22));
    final at = {
      'y': sample.indexOf('2033'),
      'M': sample.indexOf('11'),
      'd': sample.indexOf('22'),
    };
    if (at.values.any((i) => i < 0)) {
      return const BirthdayFormat(['M', 'd', 'y'], '/');
    }
    final order = at.keys.toList()..sort((a, b) => at[a]!.compareTo(at[b]!));
    final separator = sample.replaceAll(RegExp(r'[0-9]'), '');
    return BirthdayFormat(order, separator.isEmpty ? '/' : separator[0]);
  }

  static int _width(String part) => part == 'y' ? 4 : 2;

  /// The help text: "DD.MM.YYYY".
  String get hint => order
      .map(
        (p) => switch (p) {
          'd' => 'DD',
          'M' => 'MM',
          _ => 'YYYY',
        },
      )
      .join(separator);

  /// [digits] with a separator after each part as it fills, but the last.
  String format(String digits) {
    final out = StringBuffer();
    var from = 0;
    for (final (i, part) in order.indexed) {
      if (from >= digits.length) break;
      final take = (digits.length - from).clamp(0, _width(part));
      out.write(digits.substring(from, from + take));
      from += take;
      if (take == _width(part) && i < order.length - 1) out.write(separator);
    }
    return out.toString();
  }

  String write(DateTime date) => format(
    order
        .map(
          (p) => switch (p) {
            'd' => date.day.toString().padLeft(2, '0'),
            'M' => date.month.toString().padLeft(2, '0'),
            _ => date.year.toString().padLeft(4, '0'),
          },
        )
        .join(),
  );

  /// The date [text] names when complete and real (no 31 February), else
  /// null.
  DateTime? parse(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 8) return null;
    final parts = <String, int>{};
    var from = 0;
    for (final part in order) {
      parts[part] = int.parse(digits.substring(from, from + _width(part)));
      from += _width(part);
    }
    final date = DateTime(parts['y']!, parts['M']!, parts['d']!);
    if (date.year != parts['y'] ||
        date.month != parts['M'] ||
        date.day != parts['d']) {
      return null;
    }
    return date;
  }
}

/// Keeps the text to digits, at most eight, with [format]'s separators put
/// in as they are typed; deleting a separator deletes the digit before it.
class BirthdayInputFormatter extends TextInputFormatter {
  final BirthdayFormat format;

  BirthdayInputFormatter(this.format);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final oldDigits = oldValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    // A backspace that only took a separator away.
    if (newValue.text.length < oldValue.text.length && digits == oldDigits) {
      digits = digits.isEmpty ? '' : digits.substring(0, digits.length - 1);
    }
    if (digits.length > 8) digits = digits.substring(0, 8);
    final text = format.format(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
