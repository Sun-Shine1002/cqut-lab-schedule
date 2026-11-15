(() => {
  'use strict';

  const origin = 'https://syxk.cqut.edu.cn';
  if (window.location.origin !== origin) return null;

  const headings = ['实验名称', '实验周次', '实验星期', '实验时间', '实验地点', '任课教师'];
  const emptyMessages = new Set(['暂无数据', '没有数据', '没有记录', '无记录', '暂无课程', '没有课程', '暂无实验课程', '没有实验课程']);
  const normalize = (text) => text.replace(/[\s\u00a0\u3000]+/g, ' ').trim();
  const isVisible = (element) => element.getClientRects().length > 0 &&
    element.ownerDocument.defaultView.getComputedStyle(element).visibility === 'visible';

  function courseRows(doc) {
    const table = doc.getElementById('RpCourse');
    if (!table || table.localName !== 'table' || !isVisible(table)) return null;

    const rows = table.rows;
    const header = rows[0];
    if (!header || header.cells.length !== 9 || !headings.every((heading, index) => {
      const cell = header.cells[index];
      return isVisible(cell) && normalize(cell.innerText).replace(/ /g, '') === heading;
    })) return null;

    // A table drawn before its rows arrive is not evidence of an empty schedule.
    if (rows.length === 1) return null;
    if (rows.length > 201) return [[]];

    const result = [];
    for (let index = 1; index < rows.length; index++) {
      const row = rows[index];
      if (!isVisible(row)) continue;
      const cells = row.cells;
      if (rows.length === 2 && cells.length === 1 && cells[0].colSpan === 9) {
        const message = normalize(cells[0].innerText).replace(/[。！!]$/, '');
        if (emptyMessages.has(message)) return [];
      }
      if (cells.length !== 9) {
        result.push([]);
        continue;
      }

      const fields = [];
      for (let column = 0; column < headings.length; column++) {
        const cell = cells[column];
        if (cell.localName !== 'td' || cell.colSpan !== 1 || cell.rowSpan !== 1 ||
            !isVisible(cell) || cell.querySelector('form, input, textarea, select, button, table, iframe, frame, object, embed, template')) break;
        const field = normalize(cell.innerText);
        if (field.length > 160) break;
        fields.push(field);
      }
      result.push(fields.length === headings.length ? fields : []);
    }
    return result.length === 0 ? null : result;
  }

  const pending = [document];
  let emptyOrInvalid = null;
  for (let index = 0; index < pending.length; index++) {
    const doc = pending[index];
    if (doc.location.origin !== origin) continue;
    const rows = courseRows(doc);
    if (rows !== null) {
      if (rows.some((row) => row.length !== 0)) return rows;
      if (emptyOrInvalid === null || rows.length !== 0) emptyOrInvalid = rows;
    }
    for (const frame of doc.querySelectorAll('iframe, frame')) {
      // Same-origin policy makes contentDocument null for any SSO frame.
      const embedded = frame.contentDocument;
      if (embedded !== null) pending.push(embedded);
    }
  }
  return emptyOrInvalid;
})()
