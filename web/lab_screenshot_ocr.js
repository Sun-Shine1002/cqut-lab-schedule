(() => {
  const cdn = 'https://cdn.jsdelivr.net/npm';
  const tesseractPath = `${cdn}/tesseract.js@7.0.0/dist`;
  let loadingScript;

  class ScreenshotRecognitionError extends Error {}

  function loadTesseract() {
    loadingScript ??= new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = `${tesseractPath}/tesseract.min.js`;
      script.integrity = 'sha384-2BQ3U3OdKOb0Uczxqr41I9UvZkzr4V9Hv8uSzMMZAlmhsFClvdZX5wi5fDCzG+tM';
      script.crossOrigin = 'anonymous';
      script.referrerPolicy = 'no-referrer';
      const fail = () => {
        clearTimeout(timeout);
        script.remove();
        reject(new ScreenshotRecognitionError('无法加载截图识别组件，请检查网络后重试。'));
      };
      const timeout = setTimeout(fail, 30000);
      script.onerror = fail;
      script.onload = () => {
        if (!globalThis.Tesseract) {
          fail();
          return;
        }
        clearTimeout(timeout);
        resolve(globalThis.Tesseract);
      };
      document.head.append(script);
    }).catch(error => {
      loadingScript = undefined;
      throw error;
    });
    return loadingScript;
  }

  function ocrWords(tsv) {
    return tsv.split('\n').flatMap(line => {
      const columns = line.split('\t');
      const text = columns[11]?.trim();
      if (columns[0] !== '5' || !text) return [];
      const [left, top, width, height] = columns.slice(6, 10).map(Number);
      if (![left, top, width, height].every(Number.isFinite) || height <= 0) {
        return [];
      }
      return [{text, left, right: left + width, middle: top + height / 2, height}];
    });
  }

  function tableRows(words) {
    if (words.length === 0) return '';

    const heights = words.map(word => word.height).sort((a, b) => a - b);
    const typicalHeight = heights[Math.floor(heights.length / 2)];
    const rows = [];
    words.sort((a, b) => a.middle - b.middle);
    for (const word of words) {
      const last = rows.at(-1);
      if (last && word.middle - last.middle <= typicalHeight * 0.6) {
        last.words.push(word);
        continue;
      }
      rows.push({middle: word.middle, words: [word]});
    }

    return rows.map(row => rowText(row.words, typicalHeight)).join('\n');
  }

  function rowText(words, typicalHeight) {
      words.sort((a, b) => a.left - b.left);
      let value = words[0]?.text ?? '';
      for (let index = 1; index < words.length; index++) {
        const previous = words[index - 1];
        const current = words[index];
        const gap = current.left - previous.right;
        // A wide gap usually means a new cell. Within a cell keep Latin word
        // spacing and join the individual Han glyphs returned by Tesseract.
        if (gap > typicalHeight * 0.75) {
          value += '\t';
        } else if (/[a-z]$/i.test(previous.text) && /^[a-z]/i.test(current.text)) {
          value += ' ';
        }
        value += current.text;
      }
      return value;
  }

  async function readSplitDetails(bytes, words, worker, tesseract) {
    const days = words.filter(word => /^星\s*期/.test(word.text));
    const times = words.filter(word => /\d{1,2}:\d{2}[-–—~至]\d{1,2}:\d{2}/.test(word.text));
    if (days.length < 3 || days.length !== times.length) return '';
    times.sort((a, b) => a.middle - b.middle);
    days.sort((a, b) => a.middle - b.middle);
    const rowHeight = (times.at(-1).middle - times[0].middle) / (times.length - 1);
    if (rowHeight < times[0].height * 2 || times.some((time, index) =>
      Math.abs(days[index].middle - time.middle) > rowHeight * .22 ||
      (index > 0 && Math.abs(time.middle - times[index - 1].middle - rowHeight) > rowHeight * .18))) return '';

    const gap = times[0].left - days[0].left;
    if (gap < 55 || days[0].left - gap * .95 < 0) return '';
    const left = Math.round(Math.max(0, days[0].left - gap * 1.06));
    const width = Math.round(gap * .88);
    const top = Math.round(times[0].middle - rowHeight / 2);
    const height = Math.round(rowHeight * times.length);
    if (words.some(word => word.left < left && /[A-Za-z\p{Script=Han}]/u.test(word.text) &&
      word.middle > top && word.middle < top + height)) return '';
    const image = await createImageBitmap(new Blob([bytes]));
    try {
      if (top < 0 || top + height > image.height) return '';
      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      const ctx = canvas.getContext('2d', {willReadFrequently: true});
      ctx.drawImage(image, left, top, width, height, 0, 0, width, height);
      const pixels = ctx.getImageData(0, 0, width, height);
      for (let i = 0; i < pixels.data.length; i += 4) {
        const value = pixels.data[i] < 148 ? 0 : 255;
        pixels.data[i] = pixels.data[i + 1] = pixels.data[i + 2] = value;
      }
      ctx.putImageData(pixels, 0, 0);
      await worker.setParameters({
        tessedit_pageseg_mode: tesseract.PSM.SINGLE_BLOCK,
        tessedit_char_whitelist: '0123456789',
      });
      const {data} = await worker.recognize(canvas, {}, {tsv: true});
      const weekWords = ocrWords(data.tsv ?? '');
      const rows = times.map((time, index) => {
        const day = days[index];
        const halfRow = rowHeight / 2;
        const row = words.filter(word => Math.abs(word.middle - time.middle) < halfRow);
        const week = weekWords.find(word => Math.abs(word.middle + top - time.middle) < halfRow)?.text ?? '';
        const middle = row.filter(word => word.left >= time.right && Math.abs(word.middle - time.middle) < halfRow);
        const building = middle.filter(word => word.middle < time.middle - time.height * .36);
        const room = middle.filter(word => word.middle > time.middle + time.height * .36);
        const teacher = middle.filter(word => Math.abs(word.middle - time.middle) <= time.height * .36);
        const weekday = row.filter(word => word.left >= day.left && word.left < time.left);
        return [week, rowText(weekday, time.height), time.text,
          rowText(building, time.height) + rowText(room, time.height), rowText(teacher, time.height)].join('\t');
      });
      return rows.every(row => /^\d{1,2}\t/.test(row)) ? rows.join('\n') : '';
    } finally {
      image.close();
    }
  }

  async function recognizeScreenshot(bytes) {
    const tesseract = await loadTesseract();
    let worker;
    let timeout;
    let finished = false;
    let reportFailure;
    const failure = new Promise((_, reject) => {
      reportFailure = reject;
      timeout = setTimeout(() => reject(new ScreenshotRecognitionError('截图识别超时，请重试。')), 90000);
    });
    const recognition = (async () => {
      worker = await tesseract.createWorker('chi_sim', tesseract.OEM.LSTM_ONLY, {
        workerPath: `${tesseractPath}/worker.min.js`,
        corePath: `${cdn}/tesseract.js-core@7.0.0`,
        langPath: `${cdn}/@tesseract.js-data/chi_sim@1.0.0/4.0.0_best_int`,
        errorHandler: reportFailure,
      });
      if (finished) {
        await worker.terminate();
        return '';
      }
      await worker.setParameters({tessedit_pageseg_mode: tesseract.PSM.SPARSE_TEXT});
      const {data} = await worker.recognize(bytes, {}, {text: true, tsv: true});
      const words = ocrWords(data.tsv ?? '');
      return await readSplitDetails(bytes, words, worker, tesseract) || tableRows(words) || data.text || '';
    })();
    try {
      return await Promise.race([recognition, failure]);
    } finally {
      finished = true;
      clearTimeout(timeout);
      if (worker) await worker.terminate();
    }
  }

  globalThis.cqutRecognizeLabScreenshot = async bytes => {
    try {
      return {text: await recognizeScreenshot(bytes)};
    } catch (error) {
      const message = error instanceof ScreenshotRecognitionError
        ? error.message
        : '截图识别失败，请检查图片或重试。';
      return {error: message};
    }
  };
})();
