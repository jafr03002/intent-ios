// Deterministic runtime for the fixture generator. Imported FIRST by generate.ts,
// before any app module, so everything below is in place when they load.
//
// - Date: `new Date()` / `Date.now()` read a settable frozen clock (setNow), so
//   functions that default to "now" produce reproducible output.
// - Time zone: setTZ switches process.env.TZ, which Node honours at runtime.
// - localeCompare: pinned to the "en" collator. The app calls it with the
//   browser's default locale; Node's default is the machine's (sv-SE here), so
//   without this the fixtures would depend on who generated them.
// - window / localStorage / timers: a minimal in-memory stand-in for the parts of
//   the browser the lib files and hooks touch.

const RealDate = Date;
let nowMs = RealDate.UTC(2026, 9, 25, 10, 30, 0);

export function setNow(ms: number) {
  nowMs = ms;
}
export function getNow() {
  return nowMs;
}

class FrozenDate extends RealDate {
  constructor(...args: any[]) {
    if (args.length === 0) super(nowMs);
    else super(...(args as [any]));
  }
  static now() {
    return nowMs;
  }
}
(globalThis as any).Date = FrozenDate;

export function setTZ(tz: string) {
  process.env.TZ = tz;
}

const collator = new Intl.Collator("en");
// eslint-disable-next-line no-extend-native
String.prototype.localeCompare = function (that: string) {
  return collator.compare(String(this), String(that));
};

export class FakeStorage {
  map = new Map<string, string>();
  refuse = false;
  getItem(k: string) {
    return this.map.has(k) ? this.map.get(k)! : null;
  }
  setItem(k: string, v: string) {
    if (this.refuse) throw new Error("QuotaExceededError");
    this.map.set(k, String(v));
  }
  removeItem(k: string) {
    this.map.delete(k);
  }
  clear() {
    this.map.clear();
  }
  dump(): Record<string, unknown> {
    const out: Record<string, unknown> = {};
    for (const [k, v] of [...this.map.entries()].sort()) out[k] = JSON.parse(v);
    return out;
  }
}

export const storage = new FakeStorage();
const noop = () => 0;
(globalThis as any).window = {
  localStorage: storage,
  dispatchEvent: () => true,
  setInterval: noop,
  clearInterval: noop,
  location: { search: "" },
};
(globalThis as any).setInterval = noop;
(globalThis as any).clearInterval = noop;
(globalThis as any).setTimeout = noop;
