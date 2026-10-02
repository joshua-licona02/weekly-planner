(() => {
'use strict';

/* ───────────── Page geometry (portrait week page, logical units) ───────────── */
const PW = 1000, PH = 1400;
const GX = 36, GY = 104, GW = 928;          // grid origin + width
const DAY_H = 160, NOTES_H = 140;           // seven day rows + notes
const LINES = 4, LINE_H = DAY_H / LINES;    // writing lines per day
const LAB = 104;                            // day label column
const LANES = 3, LANE_W = 14;               // lanes for multi-day bars
const WX = GX + LAB + LANES * LANE_W + 6;   // writing area left edge
const WR = GX + GW;                         // writing area right edge
const rowY = i => GY + i * DAY_H;

const PEN_W = [2.2, 3.6, 6], HL_W = [16, 26, 38];
const PEN_COLORS = ['auto', '#2563eb', '#dc2626', '#16a34a', '#ea580c', '#7c3aed'];
const HL_COLORS = ['#facc15', '#f472b6', '#4ade80', '#38bdf8', '#fb923c'];
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/* ───────────── Themes ───────────── */
const THEMES = {
  classic:  { name: 'Classic',  paper: '#fffdf8', line: '#d8d3c6', border: '#2b3a4a', headerFill: '#e9edf2', accent: '#2f5d8a', ink: '#1b2a41', muted: '#6b7685', chrome: '#2b3a4a', desk: '#bfc6d0', font: 'Georgia, "Times New Roman", serif' },
  blush:    { name: 'Blush',    paper: '#fffafb', line: '#f1d3dc', border: '#b04870', headerFill: '#fde6ee', accent: '#d9537f', ink: '#4a2335', muted: '#9a6f80', chrome: '#c0426c', desk: '#f0cfd9', font: 'Didot, "Bodoni 72", Georgia, serif' },
  lavender: { name: 'Lavender', paper: '#fcfaff', line: '#e0d7f2', border: '#5f4796', headerFill: '#ece5fa', accent: '#7a59c9', ink: '#31214f', muted: '#7d6f9b', chrome: '#5f4796', desk: '#d6cdea', font: '"Avenir Next", "Segoe UI", sans-serif' },
  sage:     { name: 'Sage',     paper: '#fbfcf6', line: '#d3dcc5', border: '#43623f', headerFill: '#e5eed9', accent: '#5a8554', ink: '#1f3320', muted: '#66795f', chrome: '#43623f', desk: '#c8d4bb', font: '"Avenir Next", "Segoe UI", sans-serif' },
  ocean:    { name: 'Ocean',    paper: '#fbfdff', line: '#cddfec', border: '#1c5a86', headerFill: '#e0eef8', accent: '#1f78b4', ink: '#0b2c47', muted: '#5f7f96', chrome: '#1c5a86', desk: '#b9d0e0', font: '"Helvetica Neue", Arial, sans-serif' },
  kraft:    { name: 'Kraft',    paper: '#ecdcbc', line: '#cdb68b', border: '#4e331a', headerFill: '#dcc79c', accent: '#8a5522', ink: '#2b1a0b', muted: '#7d6747', chrome: '#4e331a', desk: '#b79f78', font: '"American Typewriter", "Courier New", monospace' },
  charcoal: { name: 'Charcoal', paper: '#1e2125', line: '#363b42', border: '#98a1ab', headerFill: '#2a2f35', accent: '#3dbba8', ink: '#eef0f2', muted: '#8c96a0', chrome: '#121417', desk: '#0b0c0e', font: '"Avenir Next", "Segoe UI", sans-serif', dark: true },
  mono:     { name: 'Mono',     paper: '#ffffff', line: '#dedede', border: '#111111', headerFill: '#f1f1f1', accent: '#111111', ink: '#111111', muted: '#707070', chrome: '#111111', desk: '#d4d4d4', font: '"Helvetica Neue", Arial, sans-serif' }
};

const DEFAULT_CATEGORIES = [
  { id: 'work',    name: 'Work',             color: '#3b82f6' },
  { id: 'family',  name: 'Family',           color: '#ec4899' },
  { id: 'health',  name: 'Health & Fitness', color: '#22c55e' },
  { id: 'faith',   name: 'Church & Faith',   color: '#8b5cf6' },
  { id: 'social',  name: 'Social',           color: '#f59e0b' },
  { id: 'errands', name: 'Errands',          color: '#14b8a6' },
  { id: 'study',   name: 'School / Study',   color: '#ef4444' },
  { id: 'hobby',   name: 'Hobbies',          color: '#f97316' }
];
const DEFAULT_SETTINGS = { theme: 'classic', weekStartsOn: 0, fingerDraws: false };

/* ───────────── State ───────────── */
const S = {
  view: 'planner',
  weekStart: '',            // week shown on the left (or only) page
  n: 1,                     // pages visible: 1 (portrait) or 2 (landscape spread)
  tool: 'pen',
  color: 'auto', hcolor: HL_COLORS[0],
  size: { pen: 1, hl: 1 },
  cat: 'work',
  zoom: 1,
  settings: { ...DEFAULT_SETTINGS },
  categories: DEFAULT_CATEGORIES.map(c => ({ ...c })),
  events: [],               // {id, date, days, line, lines, cat, title, hrs}
  preview: null,            // {id, ev} while dragging an event
  inkWeeks: new Set(),
  undo: [], redo: [],
  statsRange: 'week', statsMetric: 'days', statsAnchor: '', monthAnchor: ''
};

const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
const theme = () => THEMES[S.settings.theme] || THEMES.classic;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

/* ───────────── Dates ───────────── */
const pad = n => String(n).padStart(2, '0');
const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const parse = s => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
const addDays = (s, n) => { const d = parse(s); d.setDate(d.getDate() + n); return iso(d); };
const dayDiff = (a, b) => Math.round((parse(b) - parse(a)) / 864e5);
const weekStartOf = s => { const d = parse(s); d.setDate(d.getDate() - ((d.getDay() - S.settings.weekStartsOn + 7) % 7)); return iso(d); };
const todayISO = () => iso(new Date());
const shortDate = d => `${MONTHS[d.getMonth()].slice(0, 3)} ${d.getDate()}`;

function weekLabels(ws, span = 7) {
  const a = parse(ws), b = parse(addDays(ws, span - 1));
  const main = a.getMonth() === b.getMonth()
    ? `${MONTHS[a.getMonth()]} ${a.getFullYear()}`
    : a.getFullYear() === b.getFullYear()
      ? `${MONTHS[a.getMonth()].slice(0, 3)} – ${MONTHS[b.getMonth()].slice(0, 3)} ${b.getFullYear()}`
      : `${MONTHS[a.getMonth()].slice(0, 3)} ${a.getFullYear()} – ${MONTHS[b.getMonth()].slice(0, 3)} ${b.getFullYear()}`;
  return { main, sub: `${shortDate(a)} – ${shortDate(b)}` };
}

/* ───────────── Storage (IndexedDB, with in-memory fallback) ───────────── */
const DB = {
  db: null, mem: new Map(), persistent: true,
  async open() {
    try {
      this.db = await new Promise((res, rej) => {
        const r = indexedDB.open('weekly-planner-v2', 1);
        r.onupgradeneeded = () => r.result.createObjectStore('kv');
        r.onsuccess = () => res(r.result);
        r.onerror = () => rej(r.error);
      });
      navigator.storage && navigator.storage.persist && navigator.storage.persist();
    } catch (e) { this.persistent = false; }
  },
  req(mode, fn) {
    return new Promise((res, rej) => {
      const t = this.db.transaction('kv', mode), st = t.objectStore('kv');
      const r = fn(st);
      t.oncomplete = () => res(r && r.result);
      t.onerror = t.onabort = () => rej(t.error);
    });
  },
  async get(k) { return this.db ? this.req('readonly', st => st.get(k)) : this.mem.get(k); },
  async set(k, v) { return this.db ? this.req('readwrite', st => st.put(v, k)) : void this.mem.set(k, v); },
  async clear() { return this.db ? this.req('readwrite', st => st.clear()) : void this.mem.clear(); },
  async all() {
    if (!this.db) return [...this.mem.entries()];
    return new Promise((res, rej) => {
      const out = [], t = this.db.transaction('kv', 'readonly');
      t.objectStore('kv').openCursor().onsuccess = e => {
        const c = e.target.result;
        if (c) { out.push([c.key, c.value]); c.continue(); }
      };
      t.oncomplete = () => res(out);
      t.onerror = () => rej(t.error);
    });
  }
};
const saveEvents = () => DB.set('events', S.events);
const saveCategories = () => DB.set('categories', S.categories);
const saveSettings = () => DB.set('settings', S.settings);

/* ───────────── Pages (one or two canvas stacks) ───────────── */
function makePage(el) {
  const cv = [...el.querySelectorAll('canvas')];
  return { el, bg: cv[0], ink: cv[1], live: cv[2], bgx: cv[0].getContext('2d'), inkx: cv[1].getContext('2d'), livex: cv[2].getContext('2d'), weekStart: '', strokes: [], timer: 0, inkRaf: 0 };
}
const pgL = makePage($('pgL')), pgR = makePage($('pgR'));
const visiblePages = () => (S.n === 2 ? [pgL, pgR] : [pgL]);
const scroller = $('scroller'), book = $('book');

const catById = id => S.categories.find(c => c.id === id);
const catColor = id => (catById(id) || { color: '#9ca3af' }).color;
const catName = id => (catById(id) || { name: 'Other' }).name;
const inkColor = c => (c === 'auto' ? theme().ink : c);
const rgba = (hex, a) => {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${a})`;
};

function layout() {
  const aw = scroller.clientWidth - 16, ah = scroller.clientHeight - 16;
  const n = aw / ah >= 1.3 ? 2 : 1, changed = n !== S.n;
  S.n = n;
  pgR.el.hidden = n === 1;
  scroller.style.overflow = S.zoom > 1 ? 'auto' : 'hidden';
  const scale = Math.max(Math.min(aw / (n * PW), ah / PH), 0.05) * S.zoom;
  const w = Math.round(PW * scale), h = Math.round(PH * scale), dpr = window.devicePixelRatio || 1;
  for (const pg of [pgL, pgR]) {
    pg.el.style.width = w + 'px';
    pg.el.style.height = h + 'px';
    for (const [c, x] of [[pg.bg, pg.bgx], [pg.ink, pg.inkx], [pg.live, pg.livex]]) {
      c.width = Math.round(w * dpr); c.height = Math.round(h * dpr);
      c.style.width = w + 'px'; c.style.height = h + 'px';
      x.setTransform(c.width / PW, 0, 0, c.height / PH, 0, 0);
    }
  }
  if (changed && S.weekStart) return showWeeks(S.weekStart, false);
  for (const pg of visiblePages()) if (pg.weekStart) { drawBg(pg.bgx, pg.weekStart, S.tool === 'event'); redrawInk(pg); }
  return Promise.resolve();
}

/* ───────────── Event geometry (shared by drawing and hit-testing) ───────────── */
function eventList() {
  const p = S.preview;
  if (!p) return S.events;
  return S.events.some(e => e.id === p.id) ? S.events.map(e => (e.id === p.id ? p.ev : e)) : [...S.events, p.ev];
}

function geometry(ws) {
  const we = addDays(ws, 6);
  const list = eventList().filter(e => e.date <= we && addDays(e.date, e.days - 1) >= ws)
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : b.days - a.days));
  const laneEnd = Array(LANES).fill(-1), out = [];
  for (const ev of list) {
    const off = dayDiff(ws, ev.date), si = Math.max(0, off), ei = Math.min(6, off + ev.days - 1);
    let lane = laneEnd.findIndex(v => v < si);
    if (lane < 0) lane = LANES - 1;
    laneEnd[lane] = Math.max(laneEnd[lane], ei);
    const startsHere = off >= 0, endsHere = off + ev.days - 1 <= 6;
    const top = startsHere ? rowY(si) + ev.line * LINE_H + 3 : rowY(0);
    const bottom = endsHere ? rowY(ei) + (ev.line + ev.lines) * LINE_H - 3 : rowY(6) + DAY_H;
    const lx = GX + LAB + lane * LANE_W + 2, lw = LANE_W - 4;
    const bands = [];
    for (let d = si; d <= ei; d++) bands.push({ x: WX, y: rowY(d) + ev.line * LINE_H, w: WR - WX, h: ev.lines * LINE_H, first: d === si && startsHere });
    out.push({ ev, lane: { x: lx, y: top, w: lw, h: Math.max(bottom - top, 10) }, bands, startsHere, endsHere, grip: endsHere ? { x: lx + lw / 2, y: bottom } : null });
  }
  return out;
}

function drawEvents(c, T, geo, grips) {
  c.save();
  c.textBaseline = 'alphabetic';
  for (const g of geo) {
    const col = catColor(g.ev.cat);
    for (const b of g.bands) {
      c.fillStyle = rgba(col, b.first ? (T.dark ? .32 : .22) : (T.dark ? .16 : .1));
      c.fillRect(b.x, b.y, b.w, b.h);
      if (b.first) {
        c.fillStyle = col; c.fillRect(b.x, b.y, 4, b.h);
        if (g.ev.title) {
          c.fillStyle = T.ink; c.textAlign = 'left'; c.font = `600 21px ${T.font}`;
          let t = g.ev.title; const max = b.w - 30;
          while (c.measureText(t).width > max && t.length > 1) t = t.slice(0, -1);
          if (t !== g.ev.title) t = t.trimEnd() + '…';
          c.fillText(t, b.x + 14, b.y + Math.min(LINE_H * .7, 27));
        } else {
          c.globalAlpha = .55; c.fillStyle = T.ink; c.textAlign = 'right'; c.font = `italic 600 14px ${T.font}`;
          c.fillText(catName(g.ev.cat), b.x + b.w - 8, b.y + 16);
          c.globalAlpha = 1;
        }
      }
    }
    const l = g.lane;
    c.fillStyle = col;
    c.beginPath(); if (c.roundRect) c.roundRect(l.x, l.y, l.w, l.h, 4); else c.rect(l.x, l.y, l.w, l.h); c.fill();
    if (!g.endsHere) { c.beginPath(); c.moveTo(l.x - 2, l.y + l.h); c.lineTo(l.x + l.w + 2, l.y + l.h); c.lineTo(l.x + l.w / 2, l.y + l.h + 9); c.fill(); }
    if (!g.startsHere) { c.beginPath(); c.moveTo(l.x - 2, l.y); c.lineTo(l.x + l.w + 2, l.y); c.lineTo(l.x + l.w / 2, l.y - 9); c.fill(); }
    if (g.ev.title && l.h >= 80) {
      c.save();
      c.translate(l.x + l.w / 2 + 4, l.y + 8); c.rotate(Math.PI / 2);
      c.fillStyle = '#fff'; c.textAlign = 'left'; c.font = `700 10px ${T.font}`;
      let t = g.ev.title; const max = l.h - 16;
      while (c.measureText(t).width > max && t.length > 1) t = t.slice(0, -1);
      c.fillText(t, 0, 0);
      c.restore();
    }
    if (grips && g.grip) {
      c.fillStyle = T.paper; c.strokeStyle = col; c.lineWidth = 3;
      c.beginPath(); c.arc(g.grip.x, g.grip.y, 8, 0, Math.PI * 2); c.fill(); c.stroke();
    }
  }
  c.restore();
}

/* ───────────── Background: paper, header, day rows ───────────── */
function drawBg(c, ws, grips) {
  const T = theme(), today = todayISO();
  c.clearRect(0, 0, PW, PH);
  c.fillStyle = T.paper; c.fillRect(0, 0, PW, PH);

  const lab = weekLabels(ws);
  c.textBaseline = 'alphabetic';
  c.fillStyle = T.ink; c.textAlign = 'left'; c.font = `700 44px ${T.font}`;
  c.fillText(lab.main, GX, 70);
  c.textAlign = 'right'; c.fillStyle = T.muted; c.font = `500 24px ${T.font}`;
  c.fillText(lab.sub, PW - GX, 70);

  const onAccent = T.dark ? '#0b0c0e' : '#ffffff';
  for (let i = 0; i < 7; i++) {
    const y = rowY(i), date = addDays(ws, i), d = parse(date), isToday = date === today;
    c.fillStyle = isToday ? T.accent : T.headerFill;
    c.fillRect(GX, y, LAB, DAY_H);
    if (d.getDay() === 0 || d.getDay() === 6) { c.fillStyle = rgba(T.dark ? '#ffffff' : '#000000', .03); c.fillRect(WX, y, WR - WX, DAY_H); }
    c.fillStyle = isToday ? onAccent : T.ink; c.textAlign = 'left';
    c.font = `700 17px ${T.font}`; c.fillText(DAY_NAMES[d.getDay()].slice(0, 3).toUpperCase(), GX + 14, y + 32);
    c.font = `600 52px ${T.font}`; c.fillText(String(d.getDate()), GX + 14, y + 90);
    if (i === 0 || d.getDate() === 1) { c.globalAlpha = .75; c.font = `600 15px ${T.font}`; c.fillText(MONTHS[d.getMonth()].slice(0, 3).toUpperCase(), GX + 14, y + 118); c.globalAlpha = 1; }

    c.strokeStyle = T.line; c.lineWidth = 1.4;
    c.beginPath();
    for (let l = 1; l < LINES; l++) { c.moveTo(GX + LAB, y + l * LINE_H); c.lineTo(WR, y + l * LINE_H); }
    c.moveTo(WX - 3, y); c.lineTo(WX - 3, y + DAY_H);
    c.stroke();
  }
  // notes
  const ny = rowY(7);
  c.fillStyle = T.headerFill; c.fillRect(GX, ny, GW, 30);
  c.fillStyle = T.ink; c.textAlign = 'left'; c.font = `700 16px ${T.font}`; c.fillText('NOTES', GX + 14, ny + 22);
  c.strokeStyle = T.line; c.lineWidth = 1.4; c.beginPath();
  for (let y = ny + 30 + LINE_H; y < ny + NOTES_H; y += LINE_H) { c.moveTo(GX, y); c.lineTo(WR, y); }
  c.stroke();

  drawEvents(c, T, geometry(ws), grips);

  // dark borders
  c.strokeStyle = T.border; c.lineWidth = 2;
  c.beginPath();
  for (let i = 1; i <= 7; i++) { c.moveTo(GX, rowY(i)); c.lineTo(WR, rowY(i)); }
  c.moveTo(GX, ny + 30); c.lineTo(WR, ny + 30);
  c.moveTo(GX + LAB, GY); c.lineTo(GX + LAB, ny);
  c.stroke();
  c.lineWidth = 4; c.strokeRect(GX, GY, GW, 7 * DAY_H + NOTES_H);
}

/* ───────────── Ink rendering ───────────── */
const mid = (u, v) => [(u[0] + v[0]) / 2, (u[1] + v[1]) / 2];

function drawDot(c, s) {
  const p = s.p[0], hl = s.t === 'h';
  c.save();
  if (hl) c.globalAlpha = .35;
  c.fillStyle = hl ? s.c : inkColor(s.c);
  c.beginPath();
  c.arc(p[0], p[1], (hl ? s.w : s.w * (.45 + 1.1 * p[2])) / 2, 0, Math.PI * 2);
  c.fill();
  c.restore();
}
function drawSeg(c, s, i) {
  const p = s.p, n = p.length;
  let a, ctrl = null, b;
  if (i === 0) { a = p[0]; b = mid(p[0], p[1]); }
  else if (i === n - 1) { a = mid(p[n - 2], p[n - 1]); b = p[n - 1]; }
  else { a = mid(p[i - 1], p[i]); ctrl = p[i]; b = mid(p[i], p[i + 1]); }
  c.strokeStyle = inkColor(s.c);
  c.lineCap = c.lineJoin = 'round';
  c.lineWidth = s.w * (.45 + 1.1 * p[i][2]);
  c.beginPath();
  c.moveTo(a[0], a[1]);
  if (ctrl) c.quadraticCurveTo(ctrl[0], ctrl[1], b[0], b[1]); else c.lineTo(b[0], b[1]);
  c.stroke();
}
function drawHighlight(c, s) {
  const p = s.p;
  if (p.length < 2) return drawDot(c, s);
  c.save();
  c.globalAlpha = .35; c.strokeStyle = s.c; c.lineWidth = s.w;
  c.lineCap = c.lineJoin = 'round';
  c.beginPath();
  c.moveTo(p[0][0], p[0][1]);
  for (let i = 1; i < p.length - 1; i++) { const m = mid(p[i], p[i + 1]); c.quadraticCurveTo(p[i][0], p[i][1], m[0], m[1]); }
  c.lineTo(p[p.length - 1][0], p[p.length - 1][1]);
  c.stroke();
  c.restore();
}
function drawStroke(c, s) {
  if (s.t === 'h') return drawHighlight(c, s);
  if (s.p.length === 1) return drawDot(c, s);
  for (let i = 0; i < s.p.length; i++) drawSeg(c, s, i);
}
function redrawInk(pg) {
  pg.inkRaf = 0;
  pg.inkx.clearRect(0, 0, PW, PH);
  for (const s of pg.strokes) drawStroke(pg.inkx, s);
}
const queueInk = pg => { if (!pg.inkRaf) pg.inkRaf = requestAnimationFrame(() => redrawInk(pg)); };
let bgRaf = 0;
function queueBg() {
  if (bgRaf) return;
  bgRaf = requestAnimationFrame(() => {
    bgRaf = 0;
    for (const pg of visiblePages()) drawBg(pg.bgx, pg.weekStart, S.tool === 'event');
  });
}

/* ───────────── Ink saving ───────────── */
function pageDirty(pg) { clearTimeout(pg.timer); pg.timer = setTimeout(() => flushPage(pg), 400); }
function flushPage(pg) {
  clearTimeout(pg.timer);
  if (!pg.weekStart) return Promise.resolve();
  if (pg.strokes.length) S.inkWeeks.add(pg.weekStart); else S.inkWeeks.delete(pg.weekStart);
  return DB.set('ink:' + pg.weekStart, pg.strokes);
}
const flushAll = () => Promise.all([flushPage(pgL), flushPage(pgR)]);

/* ───────────── Undo / redo ───────────── */
function push(op) { S.undo.push(op); S.redo = []; syncHistoryBtns(); }
function syncHistoryBtns() { $('undoBtn').disabled = !S.undo.length; $('redoBtn').disabled = !S.redo.length; }
function eventsChanged() { saveEvents(); queueBg(); if (S.view === 'month') renderMonth(); }
function inkChanged(pg) { queueInk(pg); pageDirty(pg); }

function apply(op, undoing) {
  switch (op.k) {
    case 'stroke':
      if (undoing) op.pg.strokes = op.pg.strokes.filter(s => s.id !== op.s.id); else op.pg.strokes.push(op.s);
      inkChanged(op.pg); break;
    case 'erase':
      if (undoing) { for (const it of [...op.items].sort((a, b) => a.i - b.i)) op.pg.strokes.splice(it.i, 0, it.s); }
      else { const ids = new Set(op.items.map(it => it.s.id)); op.pg.strokes = op.pg.strokes.filter(s => !ids.has(s.id)); }
      inkChanged(op.pg); break;
    case 'clear':
      for (const [pg, strokes] of op.pages) { pg.strokes = undoing ? strokes.slice() : []; inkChanged(pg); }
      break;
    case 'eedit': {
      const state = undoing ? op.before : op.after;
      S.events = state ? [...S.events.filter(e => e.id !== op.id), state] : S.events.filter(e => e.id !== op.id);
      eventsChanged(); break;
    }
  }
}
function undo() { const op = S.undo.pop(); if (!op) return; apply(op, true); S.redo.push(op); syncHistoryBtns(); }
function redo() { const op = S.redo.pop(); if (!op) return; apply(op, false); S.undo.push(op); syncHistoryBtns(); }
// before/after of null means "didn't exist" / "was deleted"
function commitEvent(before, after) {
  push({ k: 'eedit', id: (after || before).id, before, after });
  S.events = after ? [...S.events.filter(e => e.id !== after.id), after] : S.events.filter(e => e.id !== before.id);
  eventsChanged();
}

/* ───────────── Pointer input ───────────── */
let cur = null, flipping = false;
const pageOfEl = el => (el === pgL.el ? pgL : pgR);
function toPage(e, pg) {
  const r = pg.el.getBoundingClientRect();
  return [(e.clientX - r.left) / r.width * PW, (e.clientY - r.top) / r.height * PH];
}
const pressureOf = e => (e.pointerType === 'pen' && e.pressure > 0 ? e.pressure : .5);
function distSeg(px, py, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1], l2 = dx * dx + dy * dy;
  const t = l2 ? clamp(((px - a[0]) * dx + (py - a[1]) * dy) / l2, 0, 1) : 0;
  return Math.hypot(px - (a[0] + t * dx), py - (a[1] + t * dy));
}
function eraseAt(pt) {
  const pg = cur.pg;
  for (const s of pg.strokes) {
    if (cur.hit.has(s.id)) continue;
    const w = (s.t === 'h' ? s.w / 2 : 0) + 14, p = s.p;
    let hit = p.length === 1 && Math.hypot(pt[0] - p[0][0], pt[1] - p[0][1]) < w;
    for (let k = 1; !hit && k < p.length; k++) hit = distSeg(pt[0], pt[1], p[k - 1], p[k]) < w;
    if (hit) { cur.hit.add(s.id); cur.items.push({ i: cur.orig.indexOf(s), s }); }
  }
  if (cur.items.length) { pg.strokes = pg.strokes.filter(s => !cur.hit.has(s.id)); queueInk(pg); }
}

// which row/date is under a screen point (works across both pages; clamps to the nearest row)
function targetAt(clientX, clientY) {
  let best = null, bd = 1e9;
  for (const pg of visiblePages()) {
    const r = pg.el.getBoundingClientRect(), dx = clientX < r.left ? r.left - clientX : clientX > r.right ? clientX - r.right : 0;
    if (dx < bd) { bd = dx; best = pg; }
  }
  const r = best.el.getBoundingClientRect(), ly = (clientY - r.top) / r.height * PH;
  const row = clamp(Math.floor((ly - GY) / DAY_H), 0, 6);
  const line = clamp(Math.floor(((ly - GY) - row * DAY_H) / LINE_H), 0, LINES - 1);
  return { pg: best, row, line, date: addDays(best.weekStart, row) };
}

function hitEvent(pg, pt) {
  const geo = geometry(pg.weekStart);
  for (const g of geo) if (g.grip && Math.hypot(pt[0] - g.grip.x, pt[1] - g.grip.y) < 20) return { g, grip: true };
  for (const g of [...geo].reverse()) {
    const l = g.lane;
    if (pt[0] >= l.x - 4 && pt[0] <= l.x + l.w + 4 && pt[1] >= l.y && pt[1] <= l.y + l.h) return { g };
    if (g.bands.some(b => pt[0] >= b.x && pt[0] <= b.x + b.w && pt[1] >= b.y && pt[1] <= b.y + b.h)) return { g };
  }
  return null;
}

function onDown(e) {
  const pg = pageOfEl(e.currentTarget);
  if (flipping) return;
  if (cur) {
    if (cur.type === 'nav' && e.pointerType === 'pen') cur = null; // pen wins over a resting palm
    else return;
  }
  e.preventDefault();
  closePop();
  const isTouch = e.pointerType === 'touch';
  const canAct = !isTouch || S.settings.fingerDraws || S.tool === 'event';
  pg.el.setPointerCapture(e.pointerId);

  if (!canAct) {
    cur = { pid: e.pointerId, type: 'nav', x0: e.clientX, y0: e.clientY, t0: performance.now(), sl: scroller.scrollLeft, st: scroller.scrollTop };
    return;
  }
  const pt = toPage(e, pg);

  if (S.tool === 'pen' || S.tool === 'hl') {
    const hl = S.tool === 'hl';
    const s = { id: uid(), t: hl ? 'h' : 'p', c: hl ? S.hcolor : S.color, w: hl ? HL_W[S.size.hl] : PEN_W[S.size.pen], p: [[pt[0], pt[1], pressureOf(e)]] };
    cur = { pid: e.pointerId, type: 'draw', pg, s, pr: pressureOf(e) };
    if (hl) pg.livex.clearRect(0, 0, PW, PH);
  } else if (S.tool === 'eraser') {
    cur = { pid: e.pointerId, type: 'erase', pg, items: [], hit: new Set(), orig: pg.strokes.slice() };
    eraseAt(pt);
  } else {
    const hit = hitEvent(pg, pt), tg = targetAt(e.clientX, e.clientY);
    if (hit && hit.grip) cur = { pid: e.pointerId, type: 'eresize', ev: hit.g.ev, x0: e.clientX, y0: e.clientY };
    else if (hit) cur = { pid: e.pointerId, type: 'emove', ev: hit.g.ev, grabDay: dayDiff(hit.g.ev.date, tg.date), grabLine: tg.line - hit.g.ev.line, x0: e.clientX, y0: e.clientY, moved: false };
    else {
      const row = Math.floor((pt[1] - GY) / DAY_H);
      if (row < 0 || row > 6 || pt[0] < WX || pt[0] > WR) { cur = { pid: e.pointerId, type: 'none' }; return; }
      cur = { pid: e.pointerId, type: 'ecreate', pg, row, line0: tg.line, x0: e.clientX, y0: e.clientY, moved: false };
    }
  }
}

function onMove(e) {
  if (!cur || e.pointerId !== cur.pid) return;
  e.preventDefault();

  if (cur.type === 'nav') {
    if (S.zoom > 1) { scroller.scrollLeft = cur.sl - (e.clientX - cur.x0); scroller.scrollTop = cur.st - (e.clientY - cur.y0); }
    return;
  }
  if (cur.type === 'draw') {
    const s = cur.s, pg = cur.pg, hl = s.t === 'h';
    const evs = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
    for (const ev of (evs.length ? evs : [e])) {
      const pt = toPage(ev, pg), last = s.p[s.p.length - 1];
      if (Math.hypot(pt[0] - last[0], pt[1] - last[1]) < .6) continue;
      cur.pr = cur.pr * .6 + pressureOf(ev) * .4;
      s.p.push([pt[0], pt[1], cur.pr]);
      if (!hl) { const n = s.p.length; drawSeg(pg.inkx, s, n === 2 ? 0 : n - 2); }
    }
    if (hl) { pg.livex.clearRect(0, 0, PW, PH); drawHighlight(pg.livex, s); }
  } else if (cur.type === 'erase') {
    const evs = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
    for (const ev of (evs.length ? evs : [e])) eraseAt(toPage(ev, cur.pg));
  } else if (cur.type === 'emove') {
    if (!cur.moved && Math.hypot(e.clientX - cur.x0, e.clientY - cur.y0) < 8) return;
    cur.moved = true;
    const tg = targetAt(e.clientX, e.clientY), ev = cur.ev;
    S.preview = { id: ev.id, ev: { ...ev, date: addDays(tg.date, -cur.grabDay), line: clamp(tg.line - cur.grabLine, 0, LINES - ev.lines) } };
    queueBg();
  } else if (cur.type === 'eresize') {
    const tg = targetAt(e.clientX, e.clientY), ev = cur.ev;
    S.preview = { id: ev.id, ev: { ...ev, days: clamp(dayDiff(ev.date, tg.date) + 1, 1, 60) } };
    cur.moved = true;
    queueBg();
  } else if (cur.type === 'ecreate') {
    if (!cur.moved && Math.hypot(e.clientX - cur.x0, e.clientY - cur.y0) < 8) return;
    cur.moved = true;
    const pt = toPage(e, cur.pg), l1 = clamp(Math.floor(((pt[1] - GY) - cur.row * DAY_H) / LINE_H), 0, LINES - 1);
    const a = Math.min(cur.line0, l1), b = Math.max(cur.line0, l1);
    S.preview = { id: 'draft', ev: { id: 'draft', date: addDays(cur.pg.weekStart, cur.row), days: 1, line: a, lines: b - a + 1, cat: S.cat, title: '', hrs: 0 } };
    queueBg();
  }
}

function onUp(e) {
  if (!cur || e.pointerId !== cur.pid) return;
  const c = cur; cur = null;
  const cancelled = e.type === 'pointercancel';

  if (c.type === 'nav') {
    const dx = e.clientX - c.x0, dy = e.clientY - c.y0;
    if (S.zoom === 1 && !cancelled && performance.now() - c.t0 < 800 && Math.abs(dx) > 110 && Math.abs(dx) > 2.5 * Math.abs(dy)) flip(dx < 0 ? 1 : -1);
  } else if (c.type === 'draw') {
    const s = c.s, n = s.p.length, pg = c.pg;
    if (cancelled && n < 2) return;
    if (s.t === 'h') { drawHighlight(pg.inkx, s); pg.livex.clearRect(0, 0, PW, PH); }
    else if (n === 1) drawDot(pg.inkx, s);
    else drawSeg(pg.inkx, s, n - 1);
    s.p = s.p.map(p => [Math.round(p[0] * 10) / 10, Math.round(p[1] * 10) / 10, Math.round(p[2] * 100) / 100]);
    pg.strokes.push(s);
    push({ k: 'stroke', pg, s });
    pageDirty(pg);
  } else if (c.type === 'erase') {
    if (c.items.length) { push({ k: 'erase', pg: c.pg, items: c.items }); pageDirty(c.pg); }
  } else if (c.type === 'emove' || c.type === 'eresize') {
    const p = S.preview; S.preview = null;
    if (cancelled) return queueBg();
    if (c.type === 'emove' && !c.moved) { queueBg(); openEventCard(c.ev, false, e.clientX, e.clientY); }
    else if (p && JSON.stringify(p.ev) !== JSON.stringify(c.ev)) commitEvent(c.ev, p.ev);
    else queueBg();
  } else if (c.type === 'ecreate') {
    const p = S.preview; S.preview = null;
    if (cancelled) return queueBg();
    if (c.moved && p) commitEvent(null, { ...p.ev, id: uid() });
    else {
      queueBg();
      openEventCard({ id: uid(), date: addDays(c.pg.weekStart, c.row), days: 1, line: c.line0, lines: 1, cat: S.cat, title: '', hrs: 0 }, true, e.clientX, e.clientY);
    }
  }
}
for (const pg of [pgL, pgR]) {
  pg.el.addEventListener('pointerdown', onDown);
  pg.el.addEventListener('pointermove', onMove);
  pg.el.addEventListener('pointerup', onUp);
  pg.el.addEventListener('pointercancel', onUp);
  pg.el.addEventListener('contextmenu', e => e.preventDefault());
}

/* ───────────── Event card (typed events + editing) ───────────── */
function closePop() { $('pop').hidden = true; }
const HRS = [0, 1, 2, 3, 4, 6, 8];
function openEventCard(ev0, isNew, x, y) {
  const pop = $('pop'), d = { cat: ev0.cat, days: ev0.days, lines: ev0.lines, hrs: ev0.hrs || 0 };
  pop.innerHTML = `<input class="pop-title" type="text" maxlength="80" placeholder="Type an event (optional)" value="${esc(ev0.title || '')}">
    <div class="pop-l">Category</div>
    <div class="pop-cats">${S.categories.map(c => `<button data-cat="${c.id}"><i style="background:${c.color}"></i>${esc(c.name)}</button>`).join('')}</div>
    <div class="pop-l">Lasts</div>
    <div class="stepper"><button data-step="-1" aria-label="Fewer days">&minus;</button><b id="daysOut"></b><button data-step="1" aria-label="More days">+</button></div>
    <div class="pop-l">Lines tall</div>
    <div class="pop-lens">${[1, 2, 3, 4].map(l => `<button data-lines="${l}">${l}</button>`).join('')}</div>
    <div class="pop-l">Hours (optional, for stats)</div>
    <div class="pop-lens">${HRS.map(h => `<button data-hrs="${h}">${h ? h + 'h' : 'none'}</button>`).join('')}</div>
    <div class="pop-act">${isNew ? '' : '<button class="danger" data-del="1">Delete</button>'}<button class="primary" data-save="1">${isNew ? 'Add' : 'Save'}</button></div>`;
  const mark = () => {
    pop.querySelectorAll('[data-cat]').forEach(b => b.classList.toggle('on', b.dataset.cat === d.cat));
    pop.querySelectorAll('[data-lines]').forEach(b => b.classList.toggle('on', +b.dataset.lines === d.lines));
    pop.querySelectorAll('[data-hrs]').forEach(b => b.classList.toggle('on', +b.dataset.hrs === d.hrs));
    pop.querySelector('#daysOut').textContent = d.days === 1 ? '1 day' : d.days + ' days';
  };
  mark();
  pop.hidden = false;
  const w = pop.offsetWidth, h = pop.offsetHeight;
  pop.style.left = clamp(x - w / 2, 8, innerWidth - w - 8) + 'px';
  pop.style.top = clamp(Math.min(y + 12, 90), 8, Math.max(8, innerHeight - h - 8)) + 'px';
  const input = pop.querySelector('input');
  const save = () => {
    const lines = d.lines, line = Math.min(ev0.line, LINES - lines);
    const after = { id: ev0.id, date: ev0.date, days: d.days, line, lines, cat: d.cat, title: input.value.trim(), hrs: d.hrs };
    if (isNew) commitEvent(null, after);
    else if (JSON.stringify(after) !== JSON.stringify({ ...ev0, hrs: ev0.hrs || 0 })) commitEvent(ev0, after);
    closePop();
  };
  pop.onclick = ev => {
    const t = ev.target.closest('button'); if (!t) return;
    if (t.dataset.cat) d.cat = t.dataset.cat;
    else if (t.dataset.lines) d.lines = +t.dataset.lines;
    else if (t.dataset.hrs) d.hrs = +t.dataset.hrs;
    else if (t.dataset.step) d.days = clamp(d.days + +t.dataset.step, 1, 60);
    else if (t.dataset.save) return save();
    else if (t.dataset.del) { commitEvent(ev0, null); return closePop(); }
    mark();
  };
  input.onkeydown = ev => { if (ev.key === 'Enter') save(); };
  if (isNew) setTimeout(() => input.focus(), 30);
}
document.addEventListener('keydown', e => { if (e.key === 'Escape') closePop(); });
document.addEventListener('pointerdown', e => { if (!$('pop').hidden && !e.target.closest('#pop') && !e.target.closest('.pg')) closePop(); });

/* ───────────── Toolbar ───────────── */
function renderCtx() {
  const el = $('ctx');
  document.querySelectorAll('#tools [data-tool]').forEach(b => b.classList.toggle('on', b.dataset.tool === S.tool));
  if (S.tool === 'pen') {
    el.innerHTML = PEN_COLORS.map(c => `<button class="sw ${c === S.color ? 'on' : ''}" data-color="${c}" style="background:${c === 'auto' ? theme().ink : c}" aria-label="Ink ${c}"></button>`).join('') +
      '<span class="sep"></span>' + PEN_W.map((w, i) => `<button class="sz ${i === S.size.pen ? 'on' : ''}" data-size="${i}" aria-label="Pen size ${i + 1}"><i style="width:${4 + i * 4}px;height:${4 + i * 4}px"></i></button>`).join('');
  } else if (S.tool === 'hl') {
    el.innerHTML = HL_COLORS.map(c => `<button class="sw ${c === S.hcolor ? 'on' : ''}" data-hcolor="${c}" style="background:${c}" aria-label="Highlight ${c}"></button>`).join('') +
      '<span class="sep"></span>' + HL_W.map((w, i) => `<button class="sz ${i === S.size.hl ? 'on' : ''}" data-size="${i}" aria-label="Highlighter size ${i + 1}"><i style="width:${6 + i * 4}px;height:${6 + i * 4}px"></i></button>`).join('');
  } else if (S.tool === 'eraser') {
    el.innerHTML = '<span class="hint">Touch a stroke with the pen to erase it</span>';
  } else {
    el.innerHTML = '<span class="hint">Tap a line to type &middot; drag down over writing to tag it &middot; drag an event to move it &middot; drag its &#9679; to stretch days &middot; category:</span>' +
      S.categories.map(c => `<button class="chip ${c.id === S.cat ? 'on' : ''}" data-cat="${c.id}" style="--c:${c.color}"><i></i>${esc(c.name)}</button>`).join('');
  }
}
$('tools').addEventListener('click', e => {
  const b = e.target.closest('[data-tool]');
  if (!b) return;
  S.tool = b.dataset.tool; S.preview = null; renderCtx(); queueBg();
});
$('ctx').addEventListener('click', e => {
  const t = e.target.closest('button'); if (!t) return;
  if (t.dataset.color) S.color = t.dataset.color;
  else if (t.dataset.hcolor) S.hcolor = t.dataset.hcolor;
  else if (t.dataset.size) S.size[S.tool === 'hl' ? 'hl' : 'pen'] = +t.dataset.size;
  else if (t.dataset.cat) S.cat = t.dataset.cat;
  renderCtx();
});
$('undoBtn').onclick = undo;
$('redoBtn').onclick = redo;
$('zoomBtn').onclick = () => {
  S.zoom = S.zoom === 1 ? 1.5 : S.zoom === 1.5 ? 2 : 1;
  $('zoomBtn').textContent = S.zoom + '×';
  layout();
};

/* ───────────── Week navigation + book flip ───────────── */
async function loadInto(pg, ws) {
  const strokes = (await DB.get('ink:' + ws)) || [];
  pg.weekStart = ws; pg.strokes = strokes;
  drawBg(pg.bgx, ws, S.tool === 'event');
  redrawInk(pg);
}
let navToken = 0;
async function showWeeks(ws, flush = true) {
  const token = ++navToken;
  if (flush) await flushAll();
  const [a, b] = await Promise.all([DB.get('ink:' + ws), DB.get('ink:' + addDays(ws, 7))]);
  if (token !== navToken) return;
  S.weekStart = ws;
  pgL.weekStart = ws; pgL.strokes = a || [];
  pgR.weekStart = addDays(ws, 7); pgR.strokes = b || [];
  S.undo = []; S.redo = []; syncHistoryBtns();
  closePop();
  renderTitle();
  for (const pg of visiblePages()) { drawBg(pg.bgx, pg.weekStart, S.tool === 'event'); redrawInk(pg); }
}
const gotoWeek = ws => showWeeks(ws);

function snapPage(pg) {
  const c = document.createElement('canvas');
  c.width = pg.bg.width; c.height = pg.bg.height;
  const x = c.getContext('2d');
  x.drawImage(pg.bg, 0, 0); x.drawImage(pg.ink, 0, 0);
  return c;
}
async function snapWeek(ws, w, h) {
  const have = visiblePages().find(p => p.weekStart === ws);
  const strokes = have ? have.strokes : (await DB.get('ink:' + ws)) || [];
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const x = c.getContext('2d');
  x.setTransform(w / PW, 0, 0, h / PH, 0, 0);
  drawBg(x, ws, false);
  for (const s of strokes) drawStroke(x, s);
  return c;
}

async function flip(dir) {
  if (flipping || S.view !== 'planner') return;
  flipping = true;
  closePop();
  try {
    await flushAll();
    const n = S.n, newWs = addDays(S.weekStart, dir * 7 * n), w = pgL.bg.width, h = pgL.bg.height;
    let front, back = null, finish;
    const target = n === 2 ? pgR : pgL;
    if (n === 2 && dir > 0) {
      front = snapPage(pgR); back = await snapWeek(newWs, w, h);
      await loadInto(pgR, addDays(newWs, 7)); finish = () => loadInto(pgL, newWs);
    } else if (n === 2) {
      front = await snapWeek(addDays(newWs, 7), w, h); back = snapPage(pgL);
      await loadInto(pgL, newWs); finish = () => loadInto(pgR, addDays(newWs, 7));
    } else if (dir > 0) {
      front = snapPage(pgL); await loadInto(pgL, newWs); finish = async () => {};
    } else {
      front = await snapWeek(newWs, w, h); finish = () => loadInto(pgL, newWs);
    }
    const leaf = document.createElement('div');
    leaf.className = 'leaf';
    leaf.style.cssText = `left:${target.el.offsetLeft}px;top:${target.el.offsetTop}px;width:${target.el.offsetWidth}px;height:${target.el.offsetHeight}px`;
    const face = (cls, cv) => {
      const f = document.createElement('div'); f.className = 'face ' + cls;
      if (cv) { cv.style.cssText = 'width:100%;height:100%;display:block'; f.appendChild(cv); } else f.style.background = theme().paper;
      leaf.appendChild(f);
    };
    face('front', front); face('back', back);
    book.appendChild(leaf);
    const turn = n === 2
      ? [{ transform: 'rotateY(0deg)' }, { transform: 'rotateY(-180deg)' }]
      : [{ transform: 'rotateY(0deg)', opacity: 1 }, { transform: 'rotateY(-100deg)', opacity: 0 }];
    await leaf.animate(dir > 0 ? turn : [...turn].reverse(), { duration: 620, easing: 'ease-in-out', fill: 'both' }).finished;
    await finish();
    S.weekStart = newWs;
    S.undo = []; S.redo = []; syncHistoryBtns();
    renderTitle();
    leaf.remove();
  } finally { flipping = false; }
}

function renderTitle() {
  if (S.view === 'planner') {
    const l = weekLabels(S.weekStart, S.n === 2 ? 14 : 7);
    $('titleMain').textContent = l.main;
    $('titleSub').textContent = l.sub;
  } else if (S.view === 'month') {
    const d = parse(S.monthAnchor), w = monthWindow();
    const n = S.events.filter(e => e.date >= w.first && e.date <= w.last).length;
    $('titleMain').textContent = `${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
    $('titleSub').textContent = n + (n === 1 ? ' event' : ' events');
  } else {
    $('titleMain').textContent = 'Where my time goes';
    $('titleSub').textContent = statsWindow().label;
  }
}

const shiftMonth = n => { const a = parse(S.monthAnchor); a.setMonth(a.getMonth() + n, 1); S.monthAnchor = iso(a); renderMonth(); };
$('prevBtn').onclick = () => S.view === 'planner' ? flip(-1) : S.view === 'month' ? shiftMonth(-1) : shiftStats(-1);
$('nextBtn').onclick = () => S.view === 'planner' ? flip(1) : S.view === 'month' ? shiftMonth(1) : shiftStats(1);
$('todayBtn').onclick = () => {
  if (S.view === 'planner') gotoWeek(weekStartOf(todayISO()));
  else if (S.view === 'month') { S.monthAnchor = todayISO(); renderMonth(); }
  else { S.statsAnchor = todayISO(); renderStats(); }
};
$('jumpDate').onchange = e => {
  if (!e.target.value) return;
  if (S.view === 'planner') gotoWeek(weekStartOf(e.target.value));
  else if (S.view === 'month') { S.monthAnchor = e.target.value; renderMonth(); }
  else { S.statsAnchor = e.target.value; renderStats(); }
  e.target.value = '';
};

document.querySelectorAll('.tabs [data-view]').forEach(b => b.onclick = () => showView(b.dataset.view));
function showView(v) {
  S.view = v;
  document.querySelectorAll('.tabs [data-view]').forEach(b => b.classList.toggle('on', b.dataset.view === v));
  $('plannerView').hidden = v !== 'planner';
  $('monthView').hidden = v !== 'month';
  $('statsView').hidden = v !== 'stats';
  syncNavVisibility();
  if (v === 'stats') { S.statsAnchor = S.weekStart; renderStats(); }
  else if (v === 'month') { S.monthAnchor = addDays(S.weekStart, 3); renderMonth(); }
  else { layout(); renderTitle(); }
}
function syncNavVisibility() {
  const hide = S.view === 'stats' && (S.statsRange === '12w' || S.statsRange === 'all');
  $('prevBtn').style.visibility = $('nextBtn').style.visibility = hide ? 'hidden' : 'visible';
}

/* ───────────── Month view (multi-day events show as bars) ───────────── */
function monthWindow() {
  const d = parse(S.monthAnchor);
  const first = iso(new Date(d.getFullYear(), d.getMonth(), 1)), last = iso(new Date(d.getFullYear(), d.getMonth() + 1, 0));
  return { first, last, gs: weekStartOf(first), ge: addDays(weekStartOf(last), 6) };
}
function renderMonth() {
  renderTitle();
  const w = monthWindow(), today = todayISO(), cur = parse(S.monthAnchor).getMonth();
  const weeks = Math.round((dayDiff(w.gs, w.ge) + 1) / 7), maxLanes = weeks > 5 ? 3 : 4;
  let html = '<div class="mhead">' + Array.from({ length: 7 }, (_, i) => `<div>${DAY_NAMES[(S.settings.weekStartsOn + i) % 7].slice(0, 3)}</div>`).join('') + '</div><div class="mgrid">';
  for (let wi = 0; wi < weeks; wi++) {
    const ws = addDays(w.gs, wi * 7), we = addDays(ws, 6);
    const evs = S.events.filter(e => e.date <= we && addDays(e.date, e.days - 1) >= ws)
      .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : b.days - a.days));
    const laneEnd = [], hidden = Array(7).fill(0);
    let bars = '';
    for (const e of evs) {
      const off = dayDiff(ws, e.date), si = Math.max(0, off), ei = Math.min(6, off + e.days - 1);
      let lane = laneEnd.findIndex(v => v < si);
      if (lane < 0) lane = laneEnd.length;
      laneEnd[lane] = ei;
      if (lane >= maxLanes) { for (let d = si; d <= ei; d++) hidden[d]++; continue; }
      const starts = off >= 0, ends = off + e.days - 1 <= 6;
      bars += `<div class="mbar${starts ? ' st' : ''}${ends ? ' en' : ''}${e.title ? '' : ' tag'}" style="--c:${catColor(e.cat)};grid-column:${si + 1}/${ei + 2};grid-row:${lane + 1}"><span>${esc(e.title || catName(e.cat))}${e.hrs ? ' · ' + e.hrs + 'h' : ''}</span></div>`;
    }
    html += '<div class="mweek"><div class="mcells">';
    for (let d = 0; d < 7; d++) {
      const date = addDays(ws, d), dt = parse(date);
      html += `<div class="mcell${dt.getMonth() !== cur ? ' dim' : ''}${date === today ? ' today' : ''}" data-date="${date}"><span class="mnum">${dt.getDate()}</span>${hidden[d] ? `<span class="mmore">+${hidden[d]} more</span>` : ''}</div>`;
    }
    html += `</div><div class="mevs" style="--lanes:${maxLanes}">${bars}</div></div>`;
  }
  $('monthView').innerHTML = html + '</div>';
}
$('monthView').addEventListener('click', e => {
  const c = e.target.closest('[data-date]');
  if (!c) return;
  showView('planner');
  gotoWeek(weekStartOf(c.dataset.date));
});

/* ───────────── Statistics ───────────── */
function eventSpan() {
  if (!S.events.length) return [todayISO(), todayISO()];
  return [S.events.map(e => e.date).sort()[0], S.events.map(e => addDays(e.date, e.days - 1)).sort().pop()];
}
function statsWindow() {
  const a = S.statsAnchor || S.weekStart, r = S.statsRange;
  if (r === 'week') {
    const f = weekStartOf(a);
    return { from: f, to: addDays(f, 6), label: weekLabels(f).sub + ', ' + parse(f).getFullYear(), mode: 'day' };
  }
  if (r === 'month') {
    const d = parse(a), f = iso(new Date(d.getFullYear(), d.getMonth(), 1)), t = iso(new Date(d.getFullYear(), d.getMonth() + 1, 0));
    return { from: f, to: t, label: `${MONTHS[d.getMonth()]} ${d.getFullYear()}`, mode: 'day' };
  }
  if (r === '12w') {
    const t = addDays(weekStartOf(todayISO()), 6);
    return { from: addDays(t, -83), to: t, label: 'Last 12 weeks', mode: 'week' };
  }
  const [f, t] = eventSpan();
  return { from: f, to: t, label: 'All time', mode: dayDiff(f, t) / 7 > 26 ? 'month' : 'week' };
}
function records() {
  const out = [], m = S.statsMetric;
  for (const e of S.events) {
    if (m === 'days') for (let k = 0; k < e.days; k++) out.push({ date: addDays(e.date, k), cat: e.cat, v: 1 });
    else if (m === 'events') out.push({ date: e.date, cat: e.cat, v: 1 });
    else if (e.hrs) out.push({ date: e.date, cat: e.cat, v: e.hrs });
  }
  return out;
}
function shiftStats(n) {
  const a = parse(S.statsAnchor || S.weekStart);
  if (S.statsRange === 'week') a.setDate(a.getDate() + 7 * n);
  else if (S.statsRange === 'month') a.setMonth(a.getMonth() + n, 1);
  S.statsAnchor = iso(a);
  renderStats();
}
const r1 = v => Math.round(v * 10) / 10;
function fmtV(v) {
  if (S.statsMetric === 'hours') return r1(v) + ' h';
  if (S.statsMetric === 'events') return v + (v === 1 ? ' event' : ' events');
  return r1(v) + (v === 1 ? ' day' : ' days');
}
function buckets(win) {
  const out = [];
  const add = (key, label, title) => out.push({ key, label, title, by: {} });
  if (win.mode === 'day') {
    for (let d = win.from; d <= win.to; d = addDays(d, 1)) {
      const dt = parse(d);
      add(d, S.statsRange === 'week' ? DAY_NAMES[dt.getDay()].slice(0, 3) : String(dt.getDate()), `${DAY_NAMES[dt.getDay()]} ${shortDate(dt)}`);
    }
    return { out, keyOf: d => d };
  }
  if (win.mode === 'week') {
    for (let d = weekStartOf(win.from); d <= win.to; d = addDays(d, 7)) add(d, shortDate(parse(d)), 'Week of ' + shortDate(parse(d)));
    return { out, keyOf: d => weekStartOf(d) };
  }
  const a = parse(win.from), z = parse(win.to);
  for (let y = a.getFullYear(), m = a.getMonth(); y < z.getFullYear() || (y === z.getFullYear() && m <= z.getMonth()); m++) {
    if (m > 11) { m = 0; y++; }
    add(`${y}-${pad(m + 1)}`, MONTHS[m].slice(0, 3), `${MONTHS[m]} ${y}`);
  }
  return { out, keyOf: d => d.slice(0, 7) };
}

function renderStats() {
  renderTitle();
  const win = statsWindow(), recs = records().filter(r => r.date >= win.from && r.date <= win.to);
  const total = recs.reduce((s, r) => s + r.v, 0), T = theme();
  const seg = (items, attr, cur) => `<div class="seg">${items.map(([k, l]) => `<button data-${attr}="${k}" class="${cur === k ? 'on' : ''}">${l}</button>`).join('')}</div>`;
  let html = `<div class="stats-wrap"><div class="seg-row">${seg([['week', 'Week'], ['month', 'Month'], ['12w', '12 weeks'], ['all', 'All time']], 'range', S.statsRange)}
    ${seg([['days', 'Days'], ['events', 'Events'], ['hours', 'Hours']], 'metric', S.statsMetric)}</div>`;

  if (!total) {
    html += `<div class="empty"><h3>Nothing to show here yet</h3><p>${S.statsMetric === 'hours'
      ? 'Hours only count when you add them to an event (open an event and pick an hours option).'
      : 'On the Planner, choose the <b>Events</b> tool, pick a category, then tap a line to type an event or drag down over your handwriting to tag it. Events count here.'}</p></div></div>`;
    $('statsView').innerHTML = html;
    return bindStats();
  }

  const byCat = {};
  for (const r of recs) byCat[r.cat] = (byCat[r.cat] || 0) + r.v;
  const ranked = Object.entries(byCat).sort((a, b) => b[1] - a[1]);
  const span = Math.max(1, dayDiff(win.from, win.to) + 1);
  const nEvents = S.events.filter(e => e.date <= win.to && addDays(e.date, e.days - 1) >= win.from).length;

  html += `<div class="tiles">
    <div class="tile"><span>Total</span><b>${fmtV(total)}</b></div>
    <div class="tile"><span>Events</span><b>${nEvents}</b></div>
    <div class="tile"><span>Average per day</span><b>${r1(total / span)}</b></div>
    <div class="tile"><span>Top category</span><b style="color:${catColor(ranked[0][0])}">${esc(catName(ranked[0][0]))}</b></div>
  </div>`;

  const R = 70, C = 2 * Math.PI * R;
  let off = 0, arcs = '';
  for (const [id, m] of ranked) {
    const len = m / total * C;
    arcs += `<circle r="${R}" cx="100" cy="100" fill="none" stroke="${catColor(id)}" stroke-width="30" stroke-dasharray="${len} ${C - len}" stroke-dashoffset="${-off}" transform="rotate(-90 100 100)"><title>${esc(catName(id))}: ${fmtV(m)}</title></circle>`;
    off += len;
  }
  const rows = ranked.map(([id, m]) => `<div class="row"><i style="background:${catColor(id)}"></i><span class="nm">${esc(catName(id))}</span>
    <span class="bar"><u style="width:${m / ranked[0][1] * 100}%;background:${catColor(id)}"></u></span>
    <span class="v">${fmtV(m)} <em>${Math.round(m / total * 100)}%</em></span></div>`).join('');
  html += `<div class="card split"><svg viewBox="0 0 200 200" class="donut"><circle r="${R}" cx="100" cy="100" fill="none" stroke="${T.line}" stroke-width="30"/>${arcs}
    <text x="100" y="97" text-anchor="middle" class="dn">${r1(total)}</text><text x="100" y="116" text-anchor="middle" class="dl">${S.statsMetric}</text></svg>
    <div class="rows">${rows}</div></div>`;

  const bk = buckets(win), map = Object.fromEntries(bk.out.map(b => [b.key, b]));
  for (const r of recs) { const b = map[bk.keyOf(r.date)]; if (b) b.by[r.cat] = (b.by[r.cat] || 0) + r.v; }
  const sums = bk.out.map(b => Object.values(b.by).reduce((a, c) => a + c, 0));
  const mx = Math.max(...sums, 1), top = mx <= 4 ? 4 : Math.ceil(mx / 4) * 4;
  const W = 900, H = 240, L = 40, B = 28, n = bk.out.length, bw = (W - L) / n, step = Math.ceil(n / 14);
  let svg = '';
  for (let g = 0; g <= 4; g++) {
    const y = H - B - (H - B - 10) * g / 4;
    svg += `<line x1="${L}" x2="${W}" y1="${y}" y2="${y}" stroke="${T.line}"/><text x="${L - 6}" y="${y + 4}" text-anchor="end" class="ax">${r1(top * g / 4)}</text>`;
  }
  bk.out.forEach((b, i) => {
    let y = H - B;
    for (const [id, m] of Object.entries(b.by).sort()) {
      const h = m / top * (H - B - 10);
      y -= h;
      svg += `<rect x="${L + i * bw + bw * .15}" y="${y}" width="${bw * .7}" height="${h}" fill="${catColor(id)}"><title>${esc(b.title)} · ${esc(catName(id))}: ${fmtV(m)}</title></rect>`;
    }
    if (i % step === 0) svg += `<text x="${L + i * bw + bw / 2}" y="${H - 8}" text-anchor="middle" class="ax">${esc(b.label)}</text>`;
  });
  html += `<div class="card"><h3>${S.statsMetric === 'days' ? 'Days' : S.statsMetric === 'hours' ? 'Hours' : 'Events'} over time</h3><svg viewBox="0 0 ${W} ${H}" class="bars">${svg}</svg></div></div>`;
  $('statsView').innerHTML = html;
  bindStats();
}
function bindStats() {
  $('statsView').querySelectorAll('[data-range]').forEach(b => b.onclick = () => { S.statsRange = b.dataset.range; syncNavVisibility(); renderStats(); });
  $('statsView').querySelectorAll('[data-metric]').forEach(b => b.onclick = () => { S.statsMetric = b.dataset.metric; renderStats(); });
}

/* ───────────── Settings drawer ───────────── */
function applyTheme() {
  const T = theme(), r = document.documentElement.style;
  const set = (k, v) => r.setProperty(k, v);
  set('--paper', T.paper); set('--line', T.line); set('--border', T.border); set('--accent', T.accent);
  set('--ink', T.ink); set('--muted', T.muted); set('--chrome', T.chrome); set('--desk', T.desk);
  set('--head', T.headerFill); set('--font', T.font);
  set('--on-accent', T.dark ? '#0b0c0e' : '#ffffff');
  const light = c => { const n = parseInt(c.slice(1), 16); return ((n >> 16) * 299 + ((n >> 8) & 255) * 587 + (n & 255) * 114) / 1000 > 150; };
  set('--chrome-text', light(T.chrome) ? '#111' : '#fff');
  document.querySelector('meta[name=theme-color]').content = T.chrome;
  document.body.classList.toggle('dark', !!T.dark);
}
const hasData = () => S.inkWeeks.size > 0 || S.events.length > 0 || pgL.strokes.length > 0 || pgR.strokes.length > 0;

function renderSettings() {
  const dr = $('settings'), locked = hasData();
  const themes = Object.entries(THEMES).map(([id, t]) => `<button class="theme ${id === S.settings.theme ? 'on' : ''}" data-theme="${id}" style="background:${t.paper};color:${t.ink};border-color:${t.border}">
      <span class="tp"><i style="background:${t.border}"></i><i style="background:${t.accent}"></i><i style="background:${t.headerFill}"></i></span>${t.name}</button>`).join('');
  const cats = S.categories.map(c => {
    const used = S.events.some(e => e.cat === c.id);
    return `<div class="cat-row" data-id="${c.id}"><input type="color" value="${c.color}" data-f="color"><input type="text" value="${esc(c.name)}" maxlength="28" data-f="name"><button data-del-cat="${c.id}" ${used ? 'disabled title="In use by events"' : ''} aria-label="Delete category">&times;</button></div>`;
  }).join('');
  dr.innerHTML = `<div class="drawer-in">
    <div class="drawer-h"><h2>Settings</h2><button id="closeSettings" aria-label="Close">Done</button></div>
    <h3>Look</h3><div class="themes">${themes}</div>
    <h3>Page</h3>
    <label class="field">Week starts on
      <select id="setWeekStart" ${locked ? 'disabled' : ''}><option value="0" ${S.settings.weekStartsOn === 0 ? 'selected' : ''}>Sunday</option><option value="1" ${S.settings.weekStartsOn === 1 ? 'selected' : ''}>Monday</option></select></label>
    ${locked ? '<p class="note">This locks once you have written or added events, so existing pages keep lining up.</p>' : ''}
    <label class="field check"><input type="checkbox" id="setFinger" ${S.settings.fingerDraws ? 'checked' : ''}> Let my finger draw too (otherwise only Apple Pencil writes, and fingers swipe pages)</label>
    <h3>Categories</h3>
    <div id="catList">${cats}</div>
    <button id="addCat" class="plain">+ Add category</button>
    <h3>Page &amp; data</h3>
    <div class="btns">
      <button id="saveImg" class="plain">Save what I'm viewing as an image</button>
      <button id="clearInk" class="plain">Clear handwriting on the visible page${S.n === 2 ? 's' : ''}</button>
      <button id="exportData" class="plain">Export backup</button>
      <button id="importData" class="plain">Import backup</button>
    </div>
    <p class="note">${DB.persistent ? 'Everything is stored on this device. Export a backup now and then; browsers can clear site data.' : '<b>Storage is unavailable in this browser mode: nothing will be saved after you close it.</b>'}</p>
  </div>`;
}
$('settingsBtn').onclick = () => { renderSettings(); $('settings').hidden = false; };
$('settings').addEventListener('click', async e => {
  const t = e.target;
  if (t === $('settings') || t.id === 'closeSettings') { $('settings').hidden = true; return; }
  const th = t.closest('[data-theme]');
  if (th) {
    S.settings.theme = th.dataset.theme; saveSettings(); applyTheme(); renderSettings(); renderCtx();
    for (const pg of visiblePages()) { drawBg(pg.bgx, pg.weekStart, S.tool === 'event'); redrawInk(pg); }
    if (S.view === 'stats') renderStats();
    return;
  }
  const del = t.closest('[data-del-cat]');
  if (del && !del.disabled) {
    S.categories = S.categories.filter(c => c.id !== del.dataset.delCat);
    if (!catById(S.cat)) S.cat = S.categories[0] ? S.categories[0].id : '';
    saveCategories(); renderSettings(); renderCtx(); return;
  }
  if (t.id === 'addCat') { S.categories.push({ id: uid(), name: 'New category', color: '#64748b' }); saveCategories(); renderSettings(); renderCtx(); return; }
  if (t.id === 'saveImg') return saveImage();
  if (t.id === 'clearInk') {
    const pages = visiblePages().filter(p => p.strokes.length);
    if (pages.length && confirm('Clear all handwriting on the visible page(s)? (You can Undo right after.)')) {
      push({ k: 'clear', pages: pages.map(p => [p, p.strokes.slice()]) });
      for (const p of pages) { p.strokes = []; inkChanged(p); }
      $('settings').hidden = true;
    }
    return;
  }
  if (t.id === 'exportData') return exportData();
  if (t.id === 'importData') return $('importFile').click();
});
$('settings').addEventListener('change', e => {
  const t = e.target;
  if (t.id === 'setWeekStart') { S.settings.weekStartsOn = +t.value; saveSettings(); gotoWeek(weekStartOf(todayISO())); }
  else if (t.id === 'setFinger') { S.settings.fingerDraws = t.checked; saveSettings(); }
});
$('settings').addEventListener('input', e => {
  const t = e.target, row = t.closest('.cat-row');
  if (!row || !t.dataset.f) return;
  const c = catById(row.dataset.id);
  if (!c) return;
  c[t.dataset.f] = t.value;
  saveCategories(); renderCtx(); queueBg();
  if (S.view === 'month') renderMonth();
});

/* ───────────── Export / import / image ───────────── */
function download(blob, name) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob); a.download = name;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}
function saveImage() {
  const pages = visiblePages(), c = document.createElement('canvas');
  c.width = pages.length * pgL.bg.width; c.height = pgL.bg.height;
  const x = c.getContext('2d');
  pages.forEach((pg, i) => { x.drawImage(pg.bg, i * pgL.bg.width, 0); x.drawImage(pg.ink, i * pgL.bg.width, 0); });
  c.toBlob(b => download(b, `planner-${S.weekStart}.png`));
}
async function exportData() {
  await flushAll();
  const entries = Object.fromEntries(await DB.all());
  download(new Blob([JSON.stringify({ format: 'weekly-planner', version: 2, entries })], { type: 'application/json' }), `planner-backup-${todayISO()}.json`);
}
$('importFile').onchange = async e => {
  const f = e.target.files[0]; e.target.value = '';
  if (!f) return;
  try {
    const data = JSON.parse(await f.text());
    if (data.format !== 'weekly-planner' || data.version !== 2 || !data.entries) throw new Error('bad file');
    if (!confirm('Replace everything in this planner with the backup?')) return;
    await DB.clear();
    for (const [k, v] of Object.entries(data.entries)) await DB.set(k, v);
    location.reload();
  } catch (err) { toast('That file is not a planner backup.'); }
};
let toastTimer = 0;
function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { t.hidden = true; }, 3500);
}

/* ───────────── Boot ───────────── */
async function boot() {
  await DB.open();
  for (const [k, v] of await DB.all()) {
    if (k === 'settings') S.settings = { ...DEFAULT_SETTINGS, ...v };
    else if (k === 'categories' && Array.isArray(v) && v.length) S.categories = v;
    else if (k === 'events' && Array.isArray(v)) S.events = v;
    else if (k.startsWith('ink:') && v.length) S.inkWeeks.add(k.slice(4));
  }
  if (!catById(S.cat)) S.cat = S.categories[0].id;
  applyTheme();
  renderCtx();
  syncHistoryBtns();
  if (!DB.persistent) toast('Storage is unavailable here, so changes will not be saved.');
  S.weekStart = weekStartOf(todayISO());
  layout();
  await showWeeks(S.weekStart, false);

  new ResizeObserver(() => { if (S.view === 'planner' && !flipping) layout(); }).observe(scroller);
  addEventListener('pagehide', flushAll);
  document.addEventListener('visibilitychange', () => { if (document.hidden) flushAll(); });
  if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost')) {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
}
boot();
})();
