/// A weekly rate at two decimals with its sign, "+0.12" or "-0.18"; one
/// that rounds to nothing is "0.00", never "-0.00".
String signedRate(double rate) {
  final text = rate.toStringAsFixed(2);
  if (double.parse(text) == 0) return '0.00';
  return rate > 0 ? '+$text' : text;
}
