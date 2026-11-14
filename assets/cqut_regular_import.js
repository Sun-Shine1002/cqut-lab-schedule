/*!
 * School adapter reference: ShiGuangSchedule/shiguang_warehouse/resources/CQUT/cqut_01.js
 *
 * MIT License
 *
 * Copyright (c) 2025 星河欲转
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
(() => {
  const timetableOrigin = 'https://timetable-cfc.cqut.edu.cn';
  const timeoutMs = 45000;
  const weekBatchSize = 3;

  function normalizedText(value) {
    return typeof value === 'string' ? value.trim() : '';
  }

  function positiveIntegers(values, max = Number.MAX_SAFE_INTEGER) {
    return [...new Set((Array.isArray(values) ? values : [])
      .map(Number)
      .filter(value => Number.isSafeInteger(value) && value > 0 && value <= max))]
      .sort((first, second) => first - second);
  }

  function clock(value) {
    const match = /^(\d{1,2}):([0-5]\d)$/.exec(normalizedText(value));
    if (!match || Number(match[1]) > 23) return '';
    return `${match[1].padStart(2, '0')}:${match[2]}`;
  }

  function readTimeSlots(data) {
    const byNumber = new Map();
    for (const slot of Array.isArray(data) ? data : []) {
      const number = Number(slot?.sessionNum);
      const startTime = clock(slot?.startTime);
      const endTime = clock(slot?.endTime);
      if (!Number.isSafeInteger(number) || number < 1 || !startTime || startTime >= endTime) continue;
      const previous = byNumber.get(number);
      if (previous && (previous.startTime !== startTime || previous.endTime !== endTime)) {
        throw new Error('学校课表返回了冲突的节次时间。');
      }
      byNumber.set(number, {number, startTime, endTime});
    }
    if (!byNumber.size) throw new Error('未能读取校区的节次时间。');
    return byNumber;
  }

  function readSemesterStartDate(yearTerm, firstWeek) {
    const term = /^(\d{4})-(\d{4})-([12])$/.exec(yearTerm);
    const day = /^(\d{1,2})\/(\d{1,2})$/.exec(normalizedText(firstWeek?.weekDayList?.[0]?.weekDate));
    if (!term || !day) return null;

    const year = Number(term[3] === '1' ? term[1] : term[2]);
    const month = Number(day[1]);
    const dateOfMonth = Number(day[2]);
    const date = new Date(Date.UTC(year, month - 1, dateOfMonth));
    if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
        date.getUTCDate() !== dateOfMonth) return null;
    return date.toISOString().split('T')[0];
  }

  function readSemesterCourses(weekRecords, byNumber) {
    const merged = new Map();
    for (const [week, record] of weekRecords) {
      if (!Array.isArray(record?.eventList)) throw new Error(`未能读取第 ${week} 周的课表。`);
      for (const event of record.eventList) {
        const declaredWeeks = positiveIntegers(event?.weekList, 53);
        if (declaredWeeks.length && !declaredWeeks.includes(week)) continue;

        const name = normalizedText(event?.eventName);
        const day = Number(event?.weekDay);
        const sections = positiveIntegers(event?.sessionList);
        const declaredStart = Number(event?.sessionStart);
        const declaredLength = Number(event?.sessionLast);
        const startSection = Number.isSafeInteger(declaredStart) && declaredStart > 0
          ? declaredStart : sections[0];
        const length = Number.isSafeInteger(declaredLength) && declaredLength > 0 ? declaredLength : 1;
        const endSection = sections.at(-1) ?? startSection + length - 1;
        const start = byNumber.get(startSection)?.startTime;
        const end = byNumber.get(endSection)?.endTime;
        if (!name || !Number.isInteger(day) || day < 1 || day > 7 ||
            !start || !end || endSection < startSection || start >= end) {
          throw new Error(`第 ${week} 周存在无法核对的课程或节次，请先在学校课表中核对。`);
        }

        const teacher = normalizedText(event?.memberName);
        const position = normalizedText(event?.address);
        const key = JSON.stringify([name, teacher, position, day, startSection, endSection]);
        if (merged.has(key)) {
          merged.get(key).weeks.add(week);
        } else {
          merged.set(key, {name, teacher, position, day, startSection, endSection, weeks: new Set([week])});
        }
      }
    }
    return [...merged.values()].map(course => ({...course, weeks: [...course.weeks]}));
  }

  async function readSchedule(signal) {
    // Endpoint shapes follow the public CQUT adapter maintained by ShiGuangSchedule.
    // https://github.com/ShiGuangSchedule/shiguang_warehouse/blob/main/resources/CQUT/cqut_01.js
    async function request(endpoint, body) {
      let response;
      try {
        response = await fetch(`${timetableOrigin}/api/courseSchedule/${endpoint}`, {
          method: 'POST',
          mode: 'same-origin',
          credentials: 'same-origin',
          redirect: 'error',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify(body),
          signal,
        });
      } catch (error) {
        if (signal.aborted) throw error;
        throw new Error('无法连接学校课表，请检查网络和登录状态后重试。');
      }
      if (response.status === 401 || response.status === 403) {
        throw new Error('请在学校页面登录后重新读取课表。');
      }
      if (response.status === 429) throw new Error('学校课表请求过于频繁，请稍后重试。');
      if (!response.ok) throw new Error('学校课表暂时无法读取，请稍后重试。');
      try {
        return await response.json();
      } catch (error) {
        if (signal.aborted) throw error;
        throw new Error('学校没有返回课表数据，请确认已登录个人课表。');
      }
    }

    const profile = await request('getUserInfo', {});
    const username = profile?.username;
    const userID = typeof username === 'number' ? String(username) : normalizedText(username);
    const campusName = normalizedText(profile?.userCustomSetting?.campusName);
    if (!userID || !campusName) throw new Error('请在学校页面登录并确认个人课表已显示。');

    const getWeek = (weekNum, yearTerm) => request('listWeekEvents', {userID, weekNum, yearTerm});
    const [overview, slotData] = await Promise.all([
      getWeek(null, null),
      request('getCampusTimeInfo', {campusName}),
    ]);
    const yearTerm = normalizedText(overview?.yearTerm);
    const weeks = positiveIntegers(overview?.weekList, 53);
    const currentWeek = Number(overview?.weekNum);
    if (!yearTerm || !weeks.length || !weeks.includes(currentWeek)) {
      throw new Error('未能确认当前学期和教学周，请打开学校个人课表后重试。');
    }
    const byNumber = readTimeSlots(slotData);

    const weekRecords = [];
    for (let offset = 0; offset < weeks.length; offset += weekBatchSize) {
      const results = await Promise.all(weeks.slice(offset, offset + weekBatchSize).map(async week => {
        const record = week === currentWeek ? overview : await getWeek(String(week), yearTerm);
        const returnedTerm = normalizedText(record?.yearTerm);
        const returnedWeek = Number(record?.weekNum);
        if ((returnedTerm && returnedTerm !== yearTerm) || (returnedWeek && returnedWeek !== week)) {
          throw new Error(`学校课表返回的学期或第 ${week} 周数据不匹配，请重新读取。`);
        }
        return [week, record];
      }));
      weekRecords.push(...results);
    }

    const courses = readSemesterCourses(weekRecords, byNumber);
    if (!courses.length) throw new Error('当前学期没有可导入的正课。');
    const firstWeek = weekRecords.find(([week]) => week === 1)?.[1];
    return {
      courses,
      timeSlots: [...byNumber.values()].sort((first, second) => first.number - second.number),
      config: {
        yearTerm,
        currentWeek,
        semesterStartDate: readSemesterStartDate(yearTerm, firstWeek),
        semesterTotalWeeks: weeks.at(-1),
      },
    };
  }

  window.cqutImportRegularSchedule = async function () {
    if (window.location.origin !== timetableOrigin) {
      throw new Error('请先在重庆理工大学的个人课表页面登录。');
    }
    const controller = new AbortController();
    let didTimeOut = false;
    const timeout = setTimeout(() => {
      didTimeOut = true;
      controller.abort();
    }, timeoutMs);
    try {
      return await readSchedule(controller.signal);
    } catch (error) {
      if (didTimeOut) throw new Error('读取学校课表超时，请稍后重试。');
      throw error;
    } finally {
      clearTimeout(timeout);
      controller.abort();
    }
  };
})();
