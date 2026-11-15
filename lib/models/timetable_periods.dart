/// Start and end times in minutes since midnight for the Liangjiang campus.
const twoRiversPeriods = <(int, int)>[
  (510, 555), // 08:30–09:15
  (565, 610), // 09:25–10:10
  (630, 675), // 10:30–11:15
  (685, 730), // 11:25–12:10
  (860, 905), // 14:20–15:05
  (915, 960), // 15:15–16:00
  (980, 1025), // 16:20–17:05
  (1035, 1080), // 17:15–18:00
  (1140, 1185), // 19:00–19:45
  (1190, 1235), // 19:50–20:35
];

String timetableClockText(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}
