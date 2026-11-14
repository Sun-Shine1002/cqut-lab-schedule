import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/services/lab_screenshot_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps complementary screenshot columns in their original order', () {
    final names = parseLabScreenshot('08:24\n实验名称\n测量误差与实验数据处理\n数字示波器的使用');
    final details = parseLabScreenshot(
      '4\t星期四\t19:00-21:15\t弘远楼A0313\t程时葵\n'
      '10\t星期四\t13:50-16:05\t崇文楼406\t彭川黔',
    );
    expect(names, hasLength(2));
    expect(details, hasLength(2));
    expect(names.map((draft) => draft.isNameOnly), everyElement(isTrue));
    expect(details.map((draft) => draft.isDetailsOnly), everyElement(isTrue));
    final first = details.first.withNameFrom(names.first).toCourse()!;
    expect(
      (first.name, first.week, first.endTime, first.location),
      ('测量误差与实验数据处理', 4, '21:15', '弘远楼A0313'),
    );
    final second = details.last.withNameFrom(names.last).toCourse()!;
    expect((second.name, second.week, second.teacher), ('数字示波器的使用', 10, '彭川黔'));
  });

  test('reads tabular OCR with spaced Chinese and fullwidth numbers', () {
    final drafts = parseLabScreenshot(
      '实验名称\t实验周次\t实验星期\t实验时间\t实验地点\t任课教师\t成绩\t评教\n'
      '扭摆 法测物体转动惯量\t第４周\t星 期 三\t１６：２０–１８：３５\t明理楼 ２０１\t张 明\t\t未评教\n'
      '双棱镜干涉\t４\t４\t１３：５０\t１６：０５\t明理楼３０２\t李华\t９５\t已评教',
    );

    expect(drafts.map((draft) => draft.name), ['扭摆法测物体转动惯量', '双棱镜干涉']);
    final first = drafts.first.toCourse()!;
    expect(first.kind, CourseKind.lab);
    expect((first.week, first.weekday), (4, 3));
    expect((first.startTime, first.endTime), ('16:20', '18:35'));
    expect((first.location, first.teacher), ('明理楼 201', '张明'));
    expect((first.grade, first.evaluation), (null, '未评教'));
    final second = drafts.last.toCourse()!;
    expect((second.week, second.weekday), (4, 4));
    expect((second.startTime, second.endTime), ('13:50', '16:05'));
    expect((second.grade, second.evaluation), ('95', '已评教'));
  });

  test(
    'reads flattened or cell-by-cell OCR and ignores header or status text',
    () {
      final drafts = parseLabScreenshot('''
物理实验课表
波尔共振5星期三13:50至16:05 明理楼305 李华
更新时间: 08:15-09:30
光学综合实验
第7周
周二
8:20－10:35
明理楼211
张明
96
已评教
''');

      expect(drafts.map((draft) => draft.name), ['波尔共振', '光学综合实验']);
      expect((drafts.first.week, drafts.first.weekday), (5, 3));
      expect(drafts.first.teacher, '李华');
      expect((drafts.last.startTime, drafts.last.endTime), ('08:20', '10:35'));
      expect((drafts.last.grade, drafts.last.evaluation), ('96', '已评教'));
      expect(parseLabScreenshot('通知：校园网络维护\n第4周 星期三 08:00-12:00'), isEmpty);
    },
  );

  test('keeps useful partial rows and validates drafts before conversion', () {
    final drafts = parseLabScreenshot(
      '光栅衍射\t7\t星期三\t下午\t明理楼301\t陈静\n'
      'RLC串联谐振\t6\t星期三\t16:30-13:15\t明理楼106\t张明\n'
      '5\t星期五\t13:50-16:05\t明理楼210',
    );

    expect(drafts, hasLength(3));
    expect(drafts.first.name, '光栅衍射');
    expect(drafts.first.startTime, isNull);
    expect(drafts.first.location, '明理楼301');
    expect(drafts.last.name, isEmpty);
    expect(drafts.map((draft) => draft.toCourse()), everyElement(isNull));
    final manual = LabCourseDraft(
      name: drafts.first.name,
      week: drafts.first.week,
      weekday: drafts.first.weekday,
      startTime: '9:05',
      endTime: '１１：２０',
    ).toCourse();
    expect((manual?.startTime, manual?.endTime), ('09:05', '11:20'));
  });
}
