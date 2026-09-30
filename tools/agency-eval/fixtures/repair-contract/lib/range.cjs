'use strict';

function sliceCodePoints(text, start, count) {
  if (start < 0 || count < 0 || start > text.length) return null;
  return text.slice(start, start + count);
}

module.exports = { sliceCodePoints };
