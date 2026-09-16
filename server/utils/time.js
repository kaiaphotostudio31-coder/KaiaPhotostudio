const JAKARTA_OFFSET_MINUTES = 7 * 60;

function toMinutes(hhmm) {
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(String(hhmm || ''))) throw new Error('INVALID_TIME');
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

function toHHMM(mins) {
  const h = Math.floor(mins / 60).toString().padStart(2, '0');
  const m = (mins % 60).toString().padStart(2, '0');
  return `${h}:${m}`;
}

function nowInJakarta() {
  const now = new Date();
  const utcMs = now.getTime() + now.getTimezoneOffset() * 60000;
  return new Date(utcMs + JAKARTA_OFFSET_MINUTES * 60000);
}

function todayJakartaStr() { return nowInJakarta().toISOString().slice(0, 10); }
function overlaps(aStart, aEnd, bStart, bEnd) { return aStart < bEnd && aEnd > bStart; }

module.exports = { toMinutes, toHHMM, nowInJakarta, todayJakartaStr, overlaps };
