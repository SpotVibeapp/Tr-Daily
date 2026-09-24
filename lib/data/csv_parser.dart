import 'models.dart';

/// Tolerant OHLCV CSV parser.
///
/// Accepts a header row containing (case-insensitive) time/date, open, high,
/// low, close and optional volume columns. Time may be ISO-8601 or
/// `yyyy-MM-dd HH:mm(:ss)`.
class CsvParser {
  static List<Candle> parse(String csv, {required String symbol}) {
    final lines = csv
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    if (lines.length < 2) return <Candle>[];

    final header = lines.first.toLowerCase().split(',').map((h) => h.trim()).toList();
    int col(String names) {
      for (final n in names.split('|')) {
        final i = header.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    final timeCol = col('time|date|datetime|timestamp');
    final openCol = col('open');
    final highCol = col('high');
    final lowCol = col('low');
    final closeCol = col('close|adj close|adj_close');
    final volCol = col('volume|vol');

    if (timeCol < 0 || openCol < 0 || highCol < 0 || lowCol < 0 || closeCol < 0) {
      throw FormatException(
        'CSV header must contain time, open, high, low, close columns. '
        'Got: ${lines.first}',
      );
    }

    final out = <Candle>[];
    for (final line in lines.skip(1)) {
      final parts = line.split(',');
      if (parts.length <= closeCol) continue;
      final time = _parseTime(parts[timeCol].trim());
      if (time == null) continue;
      final open = double.tryParse(parts[openCol].trim());
      final high = double.tryParse(parts[highCol].trim());
      final low = double.tryParse(parts[lowCol].trim());
      final close = double.tryParse(parts[closeCol].trim());
      if (open == null || high == null || low == null || close == null) continue;
      final volume = volCol >= 0 && volCol < parts.length
          ? (double.tryParse(parts[volCol].trim()) ?? 0)
          : 0.0;
      out.add(Candle(
        symbol: symbol,
        time: time,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ));
    }
    return out;
  }

  static DateTime? _parseTime(String raw) {
    if (raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toLocal();
    // yyyy-MM-dd HH:mm:ss or yyyy-MM-dd
    final normalized = raw.replaceFirst(' ', 'T');
    final dt = DateTime.tryParse(normalized);
    if (dt != null) return dt.toLocal();
    return null;
  }
}
