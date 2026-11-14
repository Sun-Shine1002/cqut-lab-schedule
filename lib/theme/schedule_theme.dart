import 'package:material_ui/material_ui.dart';

const scheduleBackground = Color(0xFFF6F3EE);
const scheduleInk = Color(0xFF261D31);
const scheduleMuted = Color(0xFF665C6C);
const schedulePurple = Color(0xFF614487);
const scheduleLine = Color(0xFFE8E0E7);
const scheduleLavender = Color(0xFFF0E8F8);
const timetableRegularFill = Color(0xFFDCEEF5);
const timetableRegularInk = Color(0xFF204D61);
const timetableLabFill = Color(0xFFEBDEF6);
const timetableLabInk = Color(0xFF563376);

final scheduleTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: schedulePurple,
    surface: const Color(0xFFFFFCFA),
    onSurface: scheduleInk,
  ),
  scaffoldBackgroundColor: scheduleBackground,
  fontFamilyFallback: const ['Noto Sans SC', 'Microsoft YaHei', 'sans-serif'],
  bottomSheetTheme: const BottomSheetThemeData(
    showDragHandle: true,
    constraints: BoxConstraints(maxWidth: 560),
  ),
);

const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
