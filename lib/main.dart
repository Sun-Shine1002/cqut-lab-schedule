import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'models/course.dart';
import 'models/term_calendar.dart';
import 'screens/schedule_screen.dart';
import 'services/course_backup_service.dart';
import 'services/demo_regular_courses.dart';
import 'services/imported_course_store.dart';
import 'services/schedule_parser.dart';
import 'services/school_lab_schedule_import.dart';
import 'theme/schedule_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final source = await rootBundle.loadString('assets/demo_schedule.html');
  final schedule = ScheduleParser().parse(source);
  final labs = ImportedCourseStore(CourseKind.lab);
  final regular = ImportedCourseStore(CourseKind.regular);
  final [importedLabs, importedRegular] = await Future.wait([
    _loadImportedCourses(labs),
    _loadImportedCourses(regular),
  ]);
  runApp(
    MaterialApp(
      title: '课程表',
      debugShowCheckedModeBanner: false,
      theme: scheduleTheme,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ScheduleScreen(
        courses: demoRegularCourses(),
        demoLabs: schedule.courses,
        importedLabs: importedLabs.courses,
        importedRegular: importedRegular.courses,
        termCalendar: importedRegular.calendar,
        saveLabs: labs.add,
        readSchoolLabs: supportsSchoolLabScheduleImport
            ? importSchoolLabSchedule
            : null,
        saveRegular: (imported) =>
            regular.replace(imported.courses, calendar: imported.calendar),
        backup: const CourseBackupService(),
        isDemo: true,
      ),
    ),
  );
}

Future<({List<Course> courses, TermCalendar? calendar})> _loadImportedCourses(
  ImportedCourseStore store,
) async {
  try {
    return await store.loadWithCalendar();
  } on Exception {
    return (courses: <Course>[], calendar: null);
  } on TypeError {
    return (courses: <Course>[], calendar: null);
  } on StateError {
    return (courses: <Course>[], calendar: null);
  }
}
