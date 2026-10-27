// pi 事件 → 桌面宠物档位。纯逻辑，无 QML 依赖（QML 用 import 引入，node 可直接单测）。
//
// 档位顺序与 animations.events.workStatus 索引、workStatusTexts 索引一致：
//   0 thinking / 1 working / 2 result / 3 waiting / 4 success / 5 error
//
// 单一生产者（pi 宿主扩展），所以没有 agent 前缀；key = pi 的 session id。

export const STATES = ['thinking', 'working', 'result', 'waiting', 'success', 'error'];

/** 多个 pi 会话同时活跃时展示哪一个：越需要人看的越优先 */
const PRIORITY = { waiting: 6, error: 5, working: 4, thinking: 3, result: 2, success: 1 };

/** 终态（success / error）只展示一会儿，过后让位给其他会话或回到随机动画链 */
export const TERMINAL_TTL_MS = 15 * 1000;
/** 非终态会话多久没有新事件就当作已失联（终端被直接关掉时收不到 session_shutdown） */
export const STALE_TTL_MS = 10 * 60 * 1000;

/** 上下文占用分成 6 档，复用 dsh-pet 的余额动画（钱袋满溢 → 分文不剩） */
export function ctxTier(percent) {
  if (!(percent >= 0)) return -1;
  if (percent >= 1) return 5;
  return Math.min(4, Math.floor(percent * 5));
}

export const isTerminal = (state) => state === 'success' || state === 'error';
export const stateIndex = (state) => STATES.indexOf(state);

export function createStore() {
  return { sessions: {} };
}

/** 事件 → 档位。返回 null 表示这个事件不改档位。 */
function stateOf(ev) {
  switch (ev.e) {
    case 'think':
      return 'thinking';
    case 'tool':
      return 'working';
    case 'tooled':
      return 'result';
    case 'wait':
      return 'waiting';
    case 'done':
      return 'success';
    case 'fail':
      return 'error';
    default:
      return null;
  }
}

/**
 * 应用一个 host 事件。返回 { changed, entered, entry }：
 * entered = 本次进入的新档位（档位没变时为 null，供通知去重）。
 */
export function applyEvent(store, ev, now) {
  const ignored = { changed: false, entered: null, entry: null };
  if (!ev || ev.src !== 'host' || !ev.s) return ignored;

  const key = String(ev.s);
  const prev = store.sessions[key];

  if (ev.e === 'bye') {
    if (!prev) return ignored;
    delete store.sessions[key];
    return { changed: true, entered: null, entry: null };
  }

  // 只有 begin 能开一条会话；其余事件没有 begin 就不认领
  if (!prev) {
    if (ev.e !== 'begin') return ignored;
    const fresh = touch(baseEntry(ev, now), ev, now);
    store.sessions[key] = fresh;
    return { changed: true, entered: null, entry: fresh };
  }

  touch(prev, ev, now);

  if (ev.e === 'unwait') {
    if (prev.state !== 'waiting') return { changed: true, entered: null, entry: prev };
    prev.state = prev.resumeState || 'working';
    return { changed: true, entered: prev.state, entry: prev };
  }

  const nextState = stateOf(ev);
  // begin / ctx 不改变档位，但已经刷新了活跃时间
  if (!nextState) return { changed: true, entered: null, entry: prev };

  if (ev.e === 'wait' && prev.state !== 'waiting') prev.resumeState = prev.state;
  const before = prev.state;
  prev.state = nextState;
  if (ev.e === 'done') prev.aborted = ev.aborted === true;
  if (ev.e === 'fail') prev.lastLine = String(ev.m || '').slice(0, 200);

  return { changed: true, entered: before !== nextState ? nextState : null, entry: prev };
}

function baseEntry(ev, now) {
  return {
    key: String(ev.s),
    cwd: String(ev.cwd || ''),
    transcript: String(ev.tr || ''),
    state: 'thinking',
    at: now,
    tool: '',
    detail: '',
    prompt: '',
    lastLine: '',
    ctxPercent: -1,
    ctxTokens: null,
    ctxWindow: 0,
    focused: false,
    // 等待结束后回到哪个档位
    resumeState: 'working',
    aborted: false,
  };
}

function touch(entry, ev, now) {
  entry.at = now;
  if (ev.cwd) entry.cwd = String(ev.cwd);
  if (ev.tr) entry.transcript = String(ev.tr);
  if (ev.p !== undefined && ev.e === 'think') entry.prompt = String(ev.p || '').slice(0, 300);
  if (ev.e === 'tool') {
    entry.tool = String(ev.n || '');
    entry.detail = String(ev.d || '');
  }
  if (ev.e === 'tooled') {
    entry.tool = '';
    entry.detail = '';
  }
  if (ev.e === 'ctx') {
    // 压缩后 pi 会给出 tokens:null；这时保持上一档，别把仪表打到 0
    const percent = Number(ev.pct);
    if (ev.pct !== null && ev.pct !== undefined && Number.isFinite(percent)) entry.ctxPercent = percent;
    if (ev.tok !== null && ev.tok !== undefined) entry.ctxTokens = Number(ev.tok);
    if (Number(ev.win) > 0) entry.ctxWindow = Number(ev.win);
  }
  if (typeof ev.focused === 'boolean') entry.focused = ev.focused;
  return entry;
}

/** 清掉过期会话，返回是否有删除 */
export function prune(store, now) {
  let removed = false;
  for (const key of Object.keys(store.sessions)) {
    const s = store.sessions[key];
    const ttl = isTerminal(s.state) ? TERMINAL_TTL_MS : STALE_TTL_MS;
    if (now - s.at > ttl) {
      delete store.sessions[key];
      removed = true;
    }
  }
  return removed;
}

/** 当前该展示的会话（优先级最高，同级取最新）；没有活跃会话返回 null */
export function current(store) {
  let best = null;
  for (const key of Object.keys(store.sessions)) {
    const s = store.sessions[key];
    if (!best || PRIORITY[s.state] > PRIORITY[best.state] || (PRIORITY[s.state] === PRIORITY[best.state] && s.at > best.at))
      best = s;
  }
  return best;
}

/** 非终态会话是否存在（定时碎碎念据此跳过，避免和正在干活的 pi 抢资源） */
export function anyBusy(store) {
  return Object.keys(store.sessions).some((k) => !isTerminal(store.sessions[k].state));
}

/** cwd → 项目名（气泡前缀） */
export function projectName(cwd) {
  if (!cwd) return '';
  const parts = String(cwd).replace(/\/+$/, '').split('/');
  return parts[parts.length - 1] || '';
}

/**
 * 工具参数 → 气泡里的一行短文本：去掉 shell 包装，项目内路径改成相对路径，压缩空白，超长截断。
 * 例：("bash", "npm run build") → "bash · npm run build"
 */
export function formatDetail(tool, detail, cwd, max = 48) {
  let d = String(detail || '')
    .replace(/^(\/usr)?(\/bin\/)?(ba|z)?sh\s+-l?c\s+/, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (cwd && d.indexOf(cwd + '/') === 0) d = d.slice(cwd.length + 1);
  if (d.length > max) d = d.slice(0, max - 1) + '…';
  if (!tool) return d;
  return d ? tool + ' · ' + d : tool;
}

/** 给 pet_state 工具的一份快照：只说"主人在干什么"，不带 prompt 原文 */
export function snapshot(store, now, extra = {}) {
  const cur = current(store);
  if (!cur) return Object.assign({ state: 'idle', sessions: 0 }, extra);
  return Object.assign(
    {
      state: cur.state,
      project: projectName(cur.cwd),
      tool: cur.tool || '',
      detail: cur.detail || '',
      ctxPercent: cur.ctxPercent >= 0 ? Math.round(cur.ctxPercent * 100) : null,
      ctxTokens: cur.ctxTokens,
      ctxWindow: cur.ctxWindow,
      aborted: cur.aborted === true,
      sessions: Object.keys(store.sessions).length,
      ageSec: Math.round((now - cur.at) / 1000),
    },
    extra,
  );
}
