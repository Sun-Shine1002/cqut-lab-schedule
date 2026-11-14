class TermCalendar {
  TermCalendar(DateTime firstWeekDate, {this.totalWeeks})
    : firstMonday = _mondayOf(firstWeekDate);

  // 重庆理工大学 2026–2027 学年第一学期校历，第 11 周为 11 月 9 日至 15 日。
  static final cqutFall2026 = TermCalendar(
    DateTime.utc(2026, 8, 31),
    totalWeeks: 21,
  );

  final DateTime firstMonday;
  final int? totalWeeks;

  static TermCalendar? fromConfig(Object? config) {
    if (config is! Map<String, dynamic>) return null;
    final start = config['semesterStartDate'];
    if (start is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(start)) {
      return null;
    }
    final date = DateTime.tryParse(start);
    if (date == null || _formatDate(date) != start) return null;

    final weeks = config['semesterTotalWeeks'];
    return TermCalendar(
      date,
      totalWeeks: weeks is int && weeks >= 1 && weeks <= 53 ? weeks : null,
    );
  }

  Map<String, Object?> toConfig() => {
    'semesterStartDate': _formatDate(firstMonday),
    if (totalWeeks != null) 'semesterTotalWeeks': totalWeeks,
  };

  int weekOf(DateTime date) =>
      1 +
      _mondayOf(date).difference(firstMonday).inDays ~/ DateTime.daysPerWeek;

  DateTime mondayForWeek(int week) =>
      firstMonday.add(Duration(days: (week - 1) * DateTime.daysPerWeek));

  // Store civil dates in UTC so week arithmetic is independent of clock changes.
  static DateTime _mondayOf(DateTime date) => DateTime.utc(
    date.year,
    date.month,
    date.day - (date.weekday - DateTime.monday),
  );

  static String _formatDate(DateTime date) =>
      date.toIso8601String().split('T').first;
}
