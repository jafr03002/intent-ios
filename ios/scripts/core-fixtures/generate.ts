// Golden fixtures for IntentCore's parity tests, produced by running the web app's
// REAL TypeScript (artifacts/traintent/src/lib + the pure parts of src/hooks).
// Run through ./generate.sh, which bundles this with the repo's esbuild and writes
// one JSON file per module into ios/Packages/IntentKit/Tests/IntentCoreTests/Fixtures.
//
// Conventions the Swift side relies on:
// - Every Date is written as epoch milliseconds (null for Invalid Date).
// - Time-zone-dependent cases carry `tz`; the clock-dependent ones carry `now` (ms).
// - `undefined` fields are simply absent; Swift treats absent and null alike.

import { setNow, setTZ, storage, getNow } from "./env";
import * as fs from "node:fs";
import * as path from "node:path";

import * as workoutSession from "@/lib/workoutSession";
import * as sessionLogs from "@/lib/sessionLogs";
import * as nextSet from "@/lib/nextSet";
import * as sessionDuration from "@/lib/sessionDuration";
import * as fieldLimits from "@/lib/fieldLimits";
import * as muscles from "@/lib/muscles";
import * as exerciseLibrary from "@/lib/exerciseLibrary";
import * as checklist from "@/lib/checklistItems";
import * as trainingTargets from "@/lib/trainingTargets";
import * as independentTargets from "@/lib/independentTargets";
import * as programSchedule from "@/lib/programSchedule";
import * as calibration from "@/lib/calibration";
import * as nutritionPlan from "@/lib/nutritionPlan";
import * as greetingLines from "@/lib/greetingLines";
import * as phaseColors from "@/lib/phaseColors";
import * as dayColors from "@/lib/dayColors";
import { formatSplitType } from "@/lib/utils";
import { usePrDetection } from "@/hooks/usePrDetection";
import { useSessionTimers } from "@/hooks/useSessionTimers";

const OUT = process.argv[2];
if (!OUT) throw new Error("usage: node generate.mjs <fixtures dir>");
fs.mkdirSync(OUT, { recursive: true });

const TZS = ["Europe/Stockholm", "America/Los_Angeles", "Pacific/Auckland", "Asia/Kolkata", "UTC"];
const DEFAULT_NOW = Date.UTC(2026, 9, 25, 10, 30, 0);

const ms = (d: Date | null | undefined) => (d == null || Number.isNaN(d.getTime()) ? null : d.getTime());

function write(name: string, data: unknown) {
  const file = path.join(OUT, `${name}.json`);
  fs.writeFileSync(file, JSON.stringify(data, null, 1) + "\n");
  console.log(`wrote ${path.relative(process.cwd(), file)}`);
}

function eachTZ<T>(fn: (tz: string) => T[]): T[] {
  const out: T[] = [];
  for (const tz of TZS) {
    setTZ(tz);
    out.push(...fn(tz));
  }
  setTZ("UTC");
  return out;
}

// ─── JS primitives ──────────────────────────────────────────────────────────────
{
  const numberInputs = ["", " 42 ", "1e3", "0x1A", "0X1a", "0o17", "0b101", ".5", "5.", "-.5", "+5", "-0", "1,000", "80kg",
    "Infinity", "-Infinity", "infinity", "NaN", "1e", "1e+", "12.5e-1", "\t7\n", "0x", "1_000", "١٢", "00012", "1.2.3"];
  const parseFloatInputs = ["80kg", " 80", "abc", "", "1e3x", "0x10", ".5.", "-Infinityx", "+.5e1", "1e", "--1", "5.e2", "  12"];
  const parseIntInputs = ["10", "8-12", " 12abc", "abc", "-7", "+3", "0x1F", "", "3.9", "１２"];
  const toStringInputs = [0, -0, 1, -1, 80, 82.5, 0.1 + 0.2, 1.25, 1e21, 1.5e21, 123456789012345680000, 1e-7, 1.5e-7, 0.000001,
    0.0000015, 2 ** 53, 2 ** 53 + 2, 5e-324, 1.7976931348623157e308, 100, 1234.5678, -0.5, 0.5];
  const roundInputs = [0.5, 1.5, 2.5, -0.5, -1.5, -2.5, 0.49999999999999994, 2.4999999999999996, 1e16 + 1, -0.4];
  const dateStrings = ["2026-08-12", "2026-08-12T10:00", "2026-08-12 10:00", "2026-08-12T10:00:00.123456Z", "2026-08", "2026",
    "2026-08-12T10:00:00+02:00", "2026-08-12T10:00:00+0200", "2026-08-12t10:00z", "+002026-08-12", "2026-08-12T24:00:00Z",
    "2026-10-25T02:30:00", "2026-03-29T02:30:00", "2026-13-01", "garbage", "2026-10-24T22:00:00.000Z"];
  const localCtor: [number, number, number][] = [[2026, 0, 1], [2026, 11, 32], [2026, 12, 1], [2026, -1, 1], [26, 0, 1], [99, 5, 1],
    [100, 0, 1], [2026, 2, 29], [2026, 9, 25], [1500, 0, 1], [2026, 1, 29], [2026, 0, 0]];
  write("jsCompat", {
    number: numberInputs.map((s) => ({ in: s, out: Number(s) })).map((c) => ({ ...c, out: Number.isNaN(c.out) ? "NaN" : !Number.isFinite(c.out) ? String(c.out) : c.out })),
    parseFloat: parseFloatInputs.map((s) => { const v = parseFloat(s); return { in: s, out: Number.isNaN(v) ? "NaN" : !Number.isFinite(v) ? String(v) : v }; }),
    parseInt: parseIntInputs.map((s) => { const v = parseInt(s); return { in: s, out: Number.isNaN(v) ? "NaN" : v }; }),
    parseIntHex: ["ff", "0x1F", "-12345", "12345g", "g1", " 3b82f6", "3B82F6"].map((s) => { const v = parseInt(s, 16); return { in: s, out: Number.isNaN(v) ? "NaN" : v }; }),
    toString: toStringInputs.map((n) => ({ in: n, out: String(n) })),
    round: roundInputs.map((n) => ({ in: n, out: Math.round(n) })),
    trim: ["  a  ", " x ", "﻿y\n", "​z"].map((s) => ({ in: s, out: s.trim() })),
    dateParse: eachTZ((tz) => dateStrings.map((s) => ({ tz, in: s, out: ms(new Date(s)) }))),
    localCtor: eachTZ((tz) => localCtor.map(([y, m, d]) => ({ tz, in: [y, m, d], out: ms(new Date(y, m, d)) }))),
    utcCtor: localCtor.map(([y, m, d]) => ({ in: [y, m, d], out: Date.UTC(y, m, d) })),
    toISOString: [0, 1786528800123, -1, 253402300800000, -62198755200000].map((t) => ({ in: t, out: new Date(t).toISOString() })),
  });

  // Collation: Node's own sort of the printable ASCII range (the order string the
  // Swift implementation hard-codes), then pairwise comparisons of tricky strings.
  const chars: string[] = [];
  for (let c = 32; c < 127; c++) chars.push(String.fromCharCode(c));
  chars.push("\t");
  const strings = ["a-b", "ab", "a b", "aB", "Ab", "a_b", "A-b", "", "a", "A", "b", "Cable EZ-Bar Curl", "Cable D-Handle Curl",
    "45 Degree Hinge", "Y-Raise", "T-Bar Row", "Tricep Pushdown", "SA Bench Lat Pulldown", "Smith High Row",
    "2026-10-24T10:00:00.000Z", "2026-10-24T10:00:00Z", "2026-10-24T09:59:59.999Z", "2026-10-24", "abc1", "abc10", "abc2",
    "x.y", "x,y", "x(y", "x$y", "x~y", "Dips", "dips", "DIPS", "Dip s"];
  const pairs: { a: string; b: string; out: number }[] = [];
  for (const a of strings) for (const b of strings) pairs.push({ a, b, out: Math.sign(a.localeCompare(b)) });
  write("collation", {
    asciiOrder: [...chars].sort((a, b) => a.localeCompare(b)).join(""),
    pairs,
    sorted: [...strings].sort((a, b) => a.localeCompare(b)),
  });
}

// ─── workoutSession ─────────────────────────────────────────────────────────────
{
  type Step = { op: string; args: any[]; now: number };
  const t0 = Date.UTC(2026, 9, 25, 8, 0, 0);
  const H = 3_600_000;
  const lift = (name: string): workoutSession.LoggedExercise => ({
    name, muscle: "Chest", isUnilateral: false, targetSets: 2, targetReps: "8-12", notes: "", showNotes: false,
    kind: "lift", targetType: null, targetSeconds: null, targetValue: null, targetUnit: null, category: null,
    completedRounds: 0, targetRounds: 2, timerEndsAt: null, timerPausedRemaining: null,
    sets: [
      { setNumber: 1, weight: 80, reps: 8, repsLeft: 0, repsRight: 0, completed: true, isNewPr: false },
      { setNumber: 2, weight: 0, reps: 0, repsLeft: 0, repsRight: 0, completed: false, isNewPr: false },
    ],
  });
  const scenarios: { name: string; steps: Step[] }[] = [
    {
      name: "start, resolve, expire",
      steps: [
        { op: "startSession", args: ["u1", 7, 2], now: t0 },
        { op: "resolveActiveSession", args: ["u1"], now: t0 + H },
        { op: "saveDraft", args: [workoutSession.draftKey("u1", 7, 2), [lift("Bench")], t0], now: t0 + 2 * H },
        { op: "resolveActiveSession", args: ["u1"], now: t0 + 2 * H + 24 * H },
        { op: "resolveActiveSession", args: ["u1"], now: t0 + 2 * H + 24 * H + 1 },
        { op: "loadActiveSession", args: ["u1"], now: t0 + 30 * H },
      ],
    },
    {
      name: "discard and restart",
      steps: [
        { op: "startSession", args: ["u2", 3, 1], now: t0 },
        { op: "saveDraft", args: [workoutSession.draftKey("u2", 3, 1), [lift("Squat")], t0], now: t0 + 1000 },
        { op: "startSession", args: ["u2", 3, 1], now: t0 + 5000 },
        { op: "loadDraft", args: [workoutSession.draftKey("u2", 3, 1)], now: t0 + 6000 },
        { op: "discardActiveSession", args: ["u2"], now: t0 + 7000 },
        { op: "resolveActiveSession", args: ["u2"], now: t0 + 8000 },
        { op: "discardActiveSession", args: ["u2"], now: t0 + 9000 },
      ],
    },
    {
      name: "pointer without draft self-heals",
      steps: [
        { op: "saveActiveSession", args: ["u3", { programId: 9, dayNumber: 4 }], now: t0 },
        { op: "resolveActiveSession", args: ["u3"], now: t0 },
        { op: "loadActiveSession", args: ["u3"], now: t0 },
        { op: "clearDraft", args: ["nothing-here"], now: t0 },
      ],
    },
    {
      name: "storage refuses writes",
      steps: [{ op: "refuse", args: [], now: t0 }, { op: "startSession", args: ["u4", 1, 1], now: t0 }],
    },
  ];
  const results = scenarios.map((s) => {
    storage.clear();
    storage.refuse = false;
    const out = s.steps.map((step) => {
      setNow(step.now);
      let result: unknown = null;
      if (step.op === "refuse") storage.refuse = true;
      else result = (workoutSession as any)[step.op](...step.args) ?? null;
      return { ...step, result, storage: storage.dump() };
    });
    storage.refuse = false;
    return { name: s.name, steps: out };
  });
  storage.clear();
  setNow(DEFAULT_NOW);
  write("workoutSession", {
    draftKey: [["u", 1, 1], ["user_2abc", 42, 7], ["", 0, 0]].map(([u, p, d]) => ({ in: [u, p, d], out: workoutSession.draftKey(u as string, p as number, d as number) })),
    activeSessionKey: ["u", "user_2abc"].map((u) => ({ in: u, out: workoutSession.activeSessionKey(u) })),
    draftMaxAgeMs: workoutSession.DRAFT_MAX_AGE_MS,
    scenarios: results,
  });
}

// ─── shared sample data ─────────────────────────────────────────────────────────
const exLift = (name: string, sets: number, reps: string, extra: Record<string, unknown> = {}) => ({ name, sets, reps, muscle: "Chest", ...extra });
const exItem = (name: string, sets: number, extra: Record<string, unknown> = {}) => ({ name, sets, reps: "", muscle: "", kind: "checklist", ...extra });
const set = (setNumber: number, weight: number, reps: number | null, extra: Record<string, unknown> = {}) => ({ setNumber, weight, reps, completed: true, ...extra });
const DAY = {
  dayNumber: 1, label: "Push", focus: "Chest",
  exercises: [
    exItem("Hip mobility", 2, { targetType: "duration", targetSeconds: 150, category: "mobility" }),
    exLift("Bench Press", 3, "6-8"),
    exLift("Single-arm Row", 2, "10-12", { isUnilateral: true, muscle: "Upper Back" }),
    exItem("Plank", 1, { targetType: "count", targetValue: 20, category: "nonsense" }),
    exLift("Lateral Raise", 0, "12-15"),
  ],
};

// ─── sessionLogs ────────────────────────────────────────────────────────────────
{
  setNow(DEFAULT_NOW);
  const fresh = sessionLogs.buildFreshLogs(DAY);
  const draft = fresh.map((e) => JSON.parse(JSON.stringify(e)));
  draft[0].completedRounds = 5;
  draft[0].timerEndsAt = DEFAULT_NOW + 60_000;
  draft[0].timerPausedRemaining = 12;
  draft[0].notes = "tight hips";
  draft[0].showNotes = true;
  draft[1].sets = [
    { setNumber: 9, weight: 100, reps: 6, repsLeft: 0, repsRight: 0, completed: true, isNewPr: true },
    { setNumber: 9, weight: 102.5, reps: 5, repsLeft: 0, repsRight: 0, completed: true, isNewPr: false },
    { setNumber: 9, weight: 0, reps: 0, repsLeft: 0, repsRight: 0, completed: false, isNewPr: false },
    { setNumber: 9, weight: 1, reps: 1, repsLeft: 0, repsRight: 0, completed: true, isNewPr: false },
  ];
  draft[1].name = "BENCH PRESS";
  draft[1].notes = "felt strong";
  draft[2].sets = [{ setNumber: 1, weight: 20, reps: 0, repsLeft: 10, repsRight: 9, completed: true, isNewPr: false }];
  const expiredTimer = JSON.parse(JSON.stringify(draft));
  expiredTimer[0].timerEndsAt = DEFAULT_NOW; // not in the future -> dropped
  const stray = [{ ...draft[1], name: "Deadlift" }, { ...draft[1], name: "" }];
  const kindSwap = JSON.parse(JSON.stringify(draft));
  kindSwap[3].kind = "lift"; // Plank was saved as a lift, program now says checklist
  kindSwap[3].sets = [{ setNumber: 1, weight: 5, reps: 5, repsLeft: 0, repsRight: 0, completed: true, isNewPr: false }];
  kindSwap[1].kind = "checklist";

  const history = [
    { id: 3, userId: "u", date: "2026-10-20", dayNumber: 1, weekNumber: 3, mode: "ai", loggingMode: "full", createdAt: "x",
      exercisesLogged: [
        { name: "Bench Press", muscle: "Chest", sets: [set(1, 0, 0), set(2, 0, null)], notes: "empty session" },
        { name: "Squat", muscle: "Quads", sets: [set(1, 120, 5), set(2, 120, 4)], notes: "  depth ok  " },
        { name: "Row", muscle: "Upper Back", sets: [set(1, 30, null, { repsLeft: 10, repsRight: 8 })], notes: "   " },
        { name: "Plank", muscle: "", sets: [], kind: "checklist", completedRounds: 1 },
      ] },
    { id: 2, userId: "u", date: "2026-10-13T18:00:00.000Z", dayNumber: 1, weekNumber: 2, mode: "ai", loggingMode: "full", createdAt: "x",
      exercisesLogged: [
        { name: "bench press", muscle: "Chest", sets: [set(1, 80, 8), set(2, 80, 7)], notes: "pause reps" },
        { name: "Squat", muscle: "Quads", sets: [set(1, 200, 1)], notes: "older" },
        { name: "", muscle: "", sets: [set(1, 1, 1)] },
      ] },
    { id: 1, userId: "u", date: "2026-10-06", dayNumber: 1, weekNumber: 1, mode: "ai", loggingMode: "full", createdAt: "x",
      exercisesLogged: [{ name: "Curl", muscle: "Biceps", sets: [set(1, 12.5, 12)] }] },
  ];

  const prevSets = [
    null, set(1, 0, 0), set(1, 80, 8), set(1, 82.5, null), set(1, 20, null, { repsLeft: 10, repsRight: null }),
    set(1, 0, 12), set(1, 0, null, { repsLeft: 0, repsRight: 3 }), set(1, 0.1 + 0.2, 3),
  ];
  write("sessionLogs", {
    isEmptySet: prevSets.map((s) => ({ in: s, out: sessionLogs.isEmptySet(s) })),
    formatShortDate: eachTZ((tz) => [null, "", "2026-08-12", "2026-09-03T23:30:00Z", "2026-12-31T23:59:59.999Z", "2026-01-01T00:00:00",
      "garbage", "2026-10-25T00:30:00+02:00"].map((d) => ({ tz, in: d, out: sessionLogs.formatShortDate(d) }))),
    dayStructureKey: [{ in: DAY, out: sessionLogs.dayStructureKey(DAY) }, { in: null, out: sessionLogs.dayStructureKey(null) },
      { in: { dayNumber: 2, label: "", focus: "", exercises: [] }, out: sessionLogs.dayStructureKey({ exercises: [] }) }],
    buildFreshLogs: [{ in: DAY, out: fresh }],
    reconcileDraftLogs: [
      { name: "full", now: DEFAULT_NOW, draft, day: DAY, out: sessionLogs.reconcileDraftLogs(draft, DAY) },
      { name: "expired timer", now: DEFAULT_NOW, draft: expiredTimer, day: DAY, out: sessionLogs.reconcileDraftLogs(expiredTimer, DAY) },
      { name: "stray entries", now: DEFAULT_NOW, draft: stray, day: DAY, out: sessionLogs.reconcileDraftLogs(stray, DAY) },
      { name: "kind swap", now: DEFAULT_NOW, draft: kindSwap, day: DAY, out: sessionLogs.reconcileDraftLogs(kindSwap, DAY) },
      { name: "empty draft", now: DEFAULT_NOW, draft: [], day: DAY, out: sessionLogs.reconcileDraftLogs([], DAY) },
    ],
    estimatedOneRepMax: [[100, 5], [80, 0], [0, 10], [62.5, 12], [1, 30]].map(([w, r]) => ({ in: [w, r], out: sessionLogs.estimatedOneRepMax(w, r) })),
    formatPrevSet: prevSets.flatMap((s) => ["kg", "lbs"].flatMap((unit) => [false, true].map((uni) => ({ in: { set: s, unit, isUnilateral: uni }, out: sessionLogs.formatPrevSet(s, unit, uni) })))),
    buildLastSessionLookup: [{ in: history, out: sessionLogs.buildLastSessionLookup(history) }, { in: [], out: sessionLogs.buildLastSessionLookup(undefined) }],
  });

  // PR detection: run the real hook (react is stubbed so effects run inline).
  const prs = [{ exercise: "Deadlift", maxWeight: 180, reps: 3, date: "2025-01-01" }, { exercise: "Curl", maxWeight: 10, reps: null, date: "2025-01-01" }];
  const judgeCalls: [string, boolean, { weight: number; reps: number; repsLeft: number; repsRight: number }, boolean][] = [
    ["Bench Press", false, { weight: 80, reps: 8, repsLeft: 0, repsRight: 0 }, false],
    ["Bench Press", false, { weight: 80, reps: 9, repsLeft: 0, repsRight: 0 }, false],
    ["bench press", false, { weight: 80, reps: 9, repsLeft: 0, repsRight: 0 }, false],
    ["Bench Press", false, { weight: 80, reps: 10, repsLeft: 0, repsRight: 0 }, true],
    ["Bench Press", false, { weight: 82, reps: 10, repsLeft: 0, repsRight: 0 }, false],
    ["Squat", false, { weight: 300, reps: 1, repsLeft: 0, repsRight: 0 }, false],
    ["Row", true, { weight: 30, reps: 0, repsLeft: 12, repsRight: 8 }, false],
    ["Row", true, { weight: 30, reps: 0, repsLeft: 12, repsRight: 9 }, false],
    ["Row", false, { weight: 30, reps: 9, repsLeft: 0, repsRight: 0 }, false],
    ["Never Logged", false, { weight: 500, reps: 10, repsLeft: 0, repsRight: 0 }, false],
    ["Deadlift", false, { weight: 185, reps: 1, repsLeft: 0, repsRight: 0 }, false],
    ["Deadlift", false, { weight: 185, reps: 3, repsLeft: 0, repsRight: 0 }, false],
    ["Curl", false, { weight: 12.5, reps: 13, repsLeft: 0, repsRight: 0 }, false],
    ["Plank", false, { weight: 1, reps: 1, repsLeft: 0, repsRight: 0 }, false],
  ];
  const prScenario = (h: any[] | undefined, p: any[] | undefined) => {
    const { judgeSet } = usePrDetection(h, p);
    return judgeCalls.map(([name, uni, s, wasPr]) => ({ in: { name, isUnilateral: uni, set: s, wasPr }, out: judgeSet(name, uni, s, wasPr) }));
  };
  write("prDetection", {
    scenarios: [
      { name: "history + prs", history, personalRecords: prs, calls: prScenario(history, prs) },
      { name: "history only", history, personalRecords: [], calls: prScenario(history, undefined) },
      { name: "nothing", history: [], personalRecords: [], calls: prScenario(undefined, undefined) },
    ],
  });

  // Session timers: the real hook, with setLogs captured.
  const timerItem = (over: Record<string, unknown>) => ({ ...fresh[0], ...over });
  const runTimers = (logs: any[], now: number, action: null | ["startTimer" | "pauseTimer" | "resetTimer", number]) => {
    setNow(now);
    let current = logs;
    const setLogs = (u: any) => { current = typeof u === "function" ? u(current) : u; };
    const hook = useSessionTimers(logs, setLogs as any, null);
    if (action) (hook as any)[action[0]](action[1]);
    return current;
  };
  const N = DEFAULT_NOW;
  const timerCases: { name: string; logs: any[]; now: number; action: any }[] = [
    { name: "expired completes a round", logs: [timerItem({ timerEndsAt: N - 1, completedRounds: 0 }), timerItem({ timerEndsAt: N + 5000 })], now: N, action: null },
    { name: "expiry exactly now", logs: [timerItem({ timerEndsAt: N, completedRounds: 2, targetRounds: 2 })], now: N, action: null },
    { name: "nothing running", logs: [timerItem({})], now: N, action: null },
    { name: "start fresh", logs: [timerItem({}), fresh[1]], now: N, action: ["startTimer", 0] },
    { name: "start from paused", logs: [timerItem({ timerPausedRemaining: 42 })], now: N, action: ["startTimer", 0] },
    { name: "start with no target", logs: [timerItem({ targetSeconds: null })], now: N, action: ["startTimer", 0] },
    { name: "start zero paused falls through", logs: [timerItem({ timerPausedRemaining: 0 })], now: N, action: ["startTimer", 0] },
    { name: "pause rounds up", logs: [timerItem({ timerEndsAt: N + 61_001 })], now: N, action: ["pauseTimer", 0] },
    { name: "pause idle is a no-op", logs: [timerItem({})], now: N, action: ["pauseTimer", 0] },
    { name: "reset", logs: [timerItem({ timerEndsAt: N + 1000, timerPausedRemaining: 3 })], now: N, action: ["resetTimer", 0] },
  ];
  write("sessionTimers", { cases: timerCases.map((c) => ({ ...c, out: runTimers(c.logs, c.now, c.action) })) });
  setNow(DEFAULT_NOW);
}

// ─── nextSet ────────────────────────────────────────────────────────────────────
{
  const fresh = sessionLogs.buildFreshLogs(DAY);
  const done = (logs: any[], marks: [number, number][]) => {
    const copy = JSON.parse(JSON.stringify(logs));
    for (const [e, s] of marks) copy[e].sets[s].completed = true;
    return copy;
  };
  const cases = [fresh, done(fresh, [[1, 0]]), done(fresh, [[1, 0], [1, 1], [1, 2]]), done(fresh, [[1, 1]]),
    done(fresh, [[1, 0], [1, 1], [1, 2], [2, 0], [2, 1]]), []];
  write("nextSet", {
    cases: cases.map((logs) => ({ in: logs, next: nextSet.findNextUnloggedSet(logs), any: nextSet.hasAnyLoggedSet(logs) })),
  });
}

// ─── sessionDuration ────────────────────────────────────────────────────────────
{
  const ex = (sets: any[], kind?: string) => ({ name: "x", muscle: "", sets, ...(kind ? { kind } : {}) });
  const ok = set(1, 50, 10);
  const countCases = [
    { durationSeconds: 1200, exercisesLogged: [ex([ok, ok, ok])] },
    { durationSeconds: 179, exercisesLogged: [ex([ok, ok, ok])] },
    { durationSeconds: 180, exercisesLogged: [ex([ok, ok, ok])] },
    { durationSeconds: 1441, exercisesLogged: [ex([ok, ok, ok])] },
    { durationSeconds: 1440, exercisesLogged: [ex([ok, ok, ok])] },
    { durationSeconds: null, exercisesLogged: [ex([ok])] },
    { durationSeconds: 600, exercisesLogged: [] },
    { durationSeconds: 600, exercisesLogged: [ex([ok, ok]), ex([], "checklist")] },
    { durationSeconds: 600, exercisesLogged: [ex([ok, ok]), ex([])] },
    { durationSeconds: 600, exercisesLogged: [ex([ok, set(2, 0, 0)])] },
    { durationSeconds: 600, exercisesLogged: [ex([ok, set(2, 0, null, { repsLeft: 3 })])] },
    { durationSeconds: 600, exercisesLogged: [ex([set(1, 0, 0)], "checklist"), ex([set(1, 0, 0)], "checklist")] },
    { durationSeconds: 14400, exercisesLogged: [ex(Array.from({ length: 40 }, () => ok))] },
    { durationSeconds: 14401, exercisesLogged: [ex(Array.from({ length: 40 }, () => ok))] },
  ];
  const clocks = [0, 0.9, 59, 60, 61.7, 3599, 3600, 3661, 36000, -5, 359999];
  const lengths = [0, 29, 30, 89, 90, 2879, 2880, 3569, 3570, 3599, 3600, 3629, 3630, 7199, 7170, -10, 59.5, 0.5];
  write("sessionDuration", {
    constants: { MIN_SESSION_SECONDS: sessionDuration.MIN_SESSION_SECONDS, MAX_SESSION_SECONDS: sessionDuration.MAX_SESSION_SECONDS,
      MIN_SECONDS_PER_SET: sessionDuration.MIN_SECONDS_PER_SET, MAX_SECONDS_PER_SET: sessionDuration.MAX_SECONDS_PER_SET,
      MIN_SESSIONS_FOR_AVERAGE: sessionDuration.MIN_SESSIONS_FOR_AVERAGE },
    plausibleBand: [-1, 0, 1, 3, 4, 5, 10, 30, 31, 100, 320, 321, 400].map((n) => ({ in: n, out: sessionDuration.plausibleBand(n) })),
    countsTowardAverage: countCases.map((c) => ({ in: c, out: sessionDuration.countsTowardAverage(c) })),
    formatClock: clocks.map((s) => ({ in: s, out: sessionDuration.formatClock(s) })),
    formatSessionLength: lengths.map((s) => ({ in: s, out: sessionDuration.formatSessionLength(s) })),
    formatStartTime: eachTZ((tz) => ["2026-10-25T00:30:00.000Z", "2026-10-25T01:30:00.000Z", "2026-06-01T17:05:00Z", "2026-06-01T23:59:59",
      "garbage", "", "2026-03-29T01:00:00Z"].map((s) => ({ tz, in: s, out: sessionDuration.formatStartTime(s) }))),
  });
}

// ─── fieldLimits ────────────────────────────────────────────────────────────────
{
  const raws = ["", "   ", "abc", "50", "13", "12", "120", "121", "12.5", "80.5", "1e3", "0x10", "-5", "1,000", "Infinity", "10000",
    "10001", "799", "800", " 900 ", "100000", "100001", "0", "-0", ".5", "20", "19.99", "1000", "1000.01", "200000", "1440", "1441", "50", "51", "1"];
  const out: any[] = [];
  for (const [key, limit] of Object.entries(fieldLimits.FIELD_LIMITS)) for (const raw of raws) out.push({ key, raw, out: fieldLimits.rangeError(raw, limit) });
  write("fieldLimits", {
    limits: fieldLimits.FIELD_LIMITS,
    loggedSetBounds: fieldLimits.LOGGED_SET_BOUNDS,
    maxLengths: { MAX_EXERCISE_NAME: fieldLimits.MAX_EXERCISE_NAME, MAX_DAY_LABEL: fieldLimits.MAX_DAY_LABEL, MAX_PROFILE_NAME: fieldLimits.MAX_PROFILE_NAME },
    rangeError: out,
    clampToBounds: [[-1, 0, 10], [5, 0, 10], [11, 0, 10], [NaN, 3, 10], [Infinity, 0, 10], [-Infinity, 2, 10], [2000.5, 0, 2000]].map(([v, min, max]) => ({ in: [Number.isNaN(v) ? "NaN" : !Number.isFinite(v) ? String(v) : v, min, max], out: fieldLimits.clampToBounds(v, { min, max }) })),
    allInRange: [
      { in: [["", "age"], ["30", "age"]], out: fieldLimits.allInRange([["", fieldLimits.FIELD_LIMITS.age], ["30", fieldLimits.FIELD_LIMITS.age]]) },
      { in: [["30", "age"], ["5", "weight"]], out: fieldLimits.allInRange([["30", fieldLimits.FIELD_LIMITS.age], ["5", fieldLimits.FIELD_LIMITS.weight]]) },
      { in: [], out: fieldLimits.allInRange([]) },
    ],
  });
}

// ─── muscles + exerciseLibrary ──────────────────────────────────────────────────
{
  const queries = ["", "  ", "chest", "Chest pre", "bell", "dumbbell press", "d", "dips", "curl", "row", "45", "ez", "lat pull", "zzz",
    "smith", "s", "e", "a b", "hamstring curl", "CABLE", "press machine", "-", "y-r", "raise", "\tleg press "];
  write("exerciseLibrary", {
    muscleOptions: muscles.MUSCLE_OPTIONS,
    muscleColors: muscles.MUSCLE_COLORS,
    library: exerciseLibrary.EXERCISE_LIBRARY,
    all: exerciseLibrary.ALL_EXERCISES,
    groups: exerciseLibrary.LIBRARY_GROUPS,
    search: [
      ...queries.map((q) => ({ query: q, limit: null, out: exerciseLibrary.searchExercises(q) })),
      { query: "e", limit: 5, out: exerciseLibrary.searchExercises("e", 5) },
      { query: "e", limit: 0, out: exerciseLibrary.searchExercises("e", 0) },
    ],
  });
}

// ─── checklistItems ─────────────────────────────────────────────────────────────
{
  const targets = [
    { targetType: "duration", targetSeconds: 150 }, { targetType: "duration", targetSeconds: 0 }, { targetType: "duration", targetSeconds: null },
    { targetType: "duration", targetSeconds: 3725 }, { targetType: "count", targetValue: 20 }, { targetType: "count", targetValue: 0 },
    { targetType: "count", targetValue: null }, { targetType: "count", targetValue: 2.5 }, { targetType: "distance", targetValue: 400 },
    { targetType: "distance", targetValue: 1.5, targetUnit: "km" }, { targetType: "distance", targetValue: null }, { targetType: "none" },
    { targetType: null }, {},
  ];
  const withRounds = targets.flatMap((t) => [undefined, null, 0, 1, 2, 3].map((rounds) => ({ ...t, rounds })));
  write("checklistItems", {
    categories: checklist.CHECKLIST_CATEGORIES,
    accent: checklist.CHECKLIST_ACCENT,
    targetTypeOptions: checklist.TARGET_TYPE_OPTIONS,
    distanceUnits: checklist.DISTANCE_UNITS,
    maxWheel: { minutes: checklist.MAX_WHEEL_MINUTES, seconds: checklist.MAX_WHEEL_SECONDS },
    parseCategory: ["stretch", "mobility", "core", "breathing", "other", "cardio", "", null, "Stretch"].map((v) => ({ in: v, out: checklist.parseCategory(v) })),
    formatDuration: [0, 1, 59, 60, 150, 599, 3599, 3600, 3725, 86400, -3, 12.9].map((s) => ({ in: s, out: checklist.formatDuration(s) })),
    describeTarget: targets.map((t) => ({ in: t, out: checklist.describeTarget(t) })),
    describeTargetWithRounds: withRounds.map((t) => ({ in: t, out: checklist.describeTargetWithRounds(t) })),
    clampTargetValue: [[-1, "count"], [5, "count"], [1001, "count"], [1001, "distance"], [100001, "distance"], [NaN, "count"], [2.5, "duration"]].map(([v, t]) => ({ in: [Number.isNaN(v) ? "NaN" : v, t], out: checklist.clampTargetValue(v as number, t as checklist.TargetType) })),
  });
}

// ─── trainingTargets ────────────────────────────────────────────────────────────
{
  const names = [...exerciseLibrary.ALL_EXERCISES.map((e) => e.name), "Face Pulls", "Ab Wheel", "CALF RAISE", "Wrist Roller", "Squat", "", "Flyes", "Skullcrusher"];
  const sets: any[] = [];
  for (const name of ["Barbell Squat", "Leg Extension"])
    for (const lastWeight of [0, 20, 60, 80, 100, 101, 140, 200, 47.5])
      for (const lastReps of [0, 5, 8, 9, 11, 12, 13])
        for (const targetReps of ["8-12", "6", "AMRAP", null, "15-20"])
          for (const weightUnit of ["kg", "lbs"])
            sets.push({ in: { name, lastWeight, lastReps, targetReps, weightUnit }, out: trainingTargets.computeSetTarget({ name, lastWeight, lastReps, targetReps, weightUnit }) });
  const prev = [null, set(1, 80, 9), set(1, 80, null, { repsLeft: 12, repsRight: 10 }), set(1, 80, null, { repsLeft: 12 }), set(1, 0, 0), set(1, 0, 12)];
  write("trainingTargets", {
    classifyExercise: names.map((n) => ({ in: n, out: trainingTargets.classifyExercise(n) })),
    repRangeFloor: ["8-12", "8–12", "8 to 12", "10", "AMRAP", "", null, "0-5", "x12", "12.5", "99999999999", "rep 007"].map((r) => ({ in: r, out: trainingTargets.repRangeFloor(r) })),
    computeSetTarget: sets,
    targetFromPreviousSet: prev.flatMap((p) => ["Bench Press", "Cable Curl"].map((name) => ({ in: { prev: p, name, targetReps: "8-12", weightUnit: "kg" }, out: trainingTargets.targetFromPreviousSet(p, { name, targetReps: "8-12", weightUnit: "kg" }) }))),
  });
}

// ─── independentTargets ─────────────────────────────────────────────────────────
{
  const goalCases: any[] = [];
  for (const phase of ["bulk", "maintenance", "diet"] as const)
    for (const current of [80, 80.5, null, undefined])
      for (const goal of ["", "  ", "abc", "85", "75", "80", "80.5", "10", "1001", "85kg", "1e2", "-50", "0x55", " 90 "])
        goalCases.push({ in: { phase, current: current ?? null, goal, unit: "kg" }, out: independentTargets.phaseGoalWeightError(phase, current, goal, "kg") });
  write("independentTargets", {
    phaseOptions: independentTargets.PHASE_OPTIONS,
    goalToPhase: ["gain_weight", "lose_weight", "general", "maintain", "", null, "GAIN_WEIGHT"].map((g) => ({ in: g, out: independentTargets.goalToPhase(g) })),
    phaseGoalWeightError: goalCases,
    cardioDays: independentTargets.CARDIO_DAYS,
    orderCardioDays: [["Sun", "Mon"], ["Fri", "Tue", "Fri"], ["mon", "Xyz"], []].map((d) => ({ in: d, out: independentTargets.orderCardioDays(d) })),
  });
}

// ─── programSchedule ────────────────────────────────────────────────────────────
{
  const dates = ["2026-08-03", "2026-08-09", "2026-10-25", "2026-03-29", "2026-02-29", "2026-02-30", "2026-13-45", "0026-01-01",
    "2026-8-3", "", "garbage", "2026-00-00", "1969-12-31", "2026-12-31"];
  const fixed = { mode: "fixed", slots: [1, null, 2, null, 3, null, null] };
  const short = { mode: "fixed", slots: [1, 2] };
  const rot = { mode: "rotating", slots: [1, 2, null] };
  const schedules = [fixed, short, rot, { mode: "rotating", slots: [] }, null];
  const starts = ["2026-08-01", null, "2026-10-30"];
  const resolve: any[] = [];
  for (const s of schedules) for (const st of starts) for (const d of ["2026-08-01", "2026-08-03", "2026-10-26", "2026-07-31", "bad"])
    resolve.push({ in: { schedule: s, startDate: st, date: d }, out: programSchedule.resolveDayForDate(s as any, st, d) });
  write("programSchedule", {
    weekdayLabels: programSchedule.WEEKDAY_LABELS,
    mondayIndexOf: eachTZ((tz) => dates.map((d) => ({ tz, in: d, out: programSchedule.mondayIndexOf(d) }))),
    daysBetween: [["2026-08-01", "2026-08-03"], ["2026-08-03", "2026-08-01"], ["2026-03-28", "2026-03-30"], ["2026-01-01", "2027-01-01"],
      ["bad", "2026-01-01"], ["0026-01-01", "2026-01-01"], ["2026-02-30", "2026-03-02"]].map(([a, b]) => ({ in: [a, b], out: programSchedule.daysBetween(a, b) })),
    todayDateString: eachTZ((tz) => [Date.UTC(2026, 9, 24, 22, 30), Date.UTC(2026, 9, 25, 10, 30), Date.UTC(2026, 0, 1, 0, 0), Date.UTC(926, 0, 5, 12)]
      .map((t) => ({ tz, in: t, out: programSchedule.todayDateString(new Date(t)) }))),
    resolveDayForDate: resolve,
    upcomingSlots: eachTZ((tz) => [
      { schedule: fixed, startDate: null, from: "2026-10-22", count: 10 },
      { schedule: rot, startDate: "2026-10-20", from: "2026-10-18", count: 7 },
      { schedule: rot, startDate: null, from: "2026-03-27", count: 4 },
      { schedule: fixed, startDate: null, from: "2026-12-30", count: 4 },
      { schedule: fixed, startDate: null, from: "garbage", count: 2 },
      { schedule: fixed, startDate: null, from: "2026-10", count: 2 },
      { schedule: null, startDate: null, from: "2026-10-22", count: 3 },
      { schedule: fixed, startDate: null, from: "2026-10-22", count: 0 },
    ].map((c) => ({ tz, in: c, out: programSchedule.upcomingSlots(c.schedule as any, c.startDate, c.from, c.count) }))),
  });
}

// ─── calibration ────────────────────────────────────────────────────────────────
{
  const row = (shortTermPhase: string | null, generatedAt: string, extra: Record<string, unknown> = {}) => ({ shortTermPhase, generatedAt, aiGenerated: true, ...extra });
  const scenarios: { name: string; programs: any[]; onboardingCompletedAt: string | null; latestCheckinAt: string | null }[] = [
    { name: "calibration only, start date set", onboardingCompletedAt: "2026-10-05T09:00:00.000Z", latestCheckinAt: null,
      programs: [row("calibration", "2026-10-04T18:00:00.000Z", { startDate: "2026-10-05", weekInPhase: 1 })] },
    { name: "review passed into bulk, then check-ins", onboardingCompletedAt: "2026-09-28T09:00:00.000Z", latestCheckinAt: "2026-10-20T08:00:00.000Z",
      programs: [
        row("calibration", "2026-09-27T18:00:00.000Z", { startDate: "2026-09-28", weekInPhase: 1 }),
        row("bulk", "2026-10-06T19:00:00.000Z", { weekInPhase: 1 }),
        row("bulk", "2026-10-13T19:00:00.000Z", { weekInPhase: 2 }),
        row("bulk", "2026-10-13T20:00:00.000Z", { weekInPhase: 2 }),
        row("diet", "2026-10-20T19:00:00.000Z", { weekInPhase: 1 }),
        { shortTermPhase: "maintenance", generatedAt: "2026-10-21T00:00:00.000Z", aiGenerated: false },
      ] },
    { name: "no start date, onboarding fallback", onboardingCompletedAt: "2026-10-14T22:30:00.000Z", latestCheckinAt: null,
      programs: [row("calibration", "2026-10-14T22:00:00.000Z"), row("bulk", "2026-10-22T10:00:00.000Z")] },
    { name: "goal change back into calibration", onboardingCompletedAt: null, latestCheckinAt: "2026-10-01T00:00:00.000Z",
      programs: [
        row("calibration", "2026-08-31T10:00:00.000Z", { startDate: "2026-09-01" }),
        row("maintenance", "2026-09-08T10:00:00.000Z"),
        row("maintenance", "2026-09-15T10:00:00.000Z"),
        row("calibration", "2026-09-30T10:00:00.000Z", { weekInPhase: 1 }),
        row("calibration", "2026-10-07T10:00:00.000Z", { weekInPhase: 2 }),
        row("bulk", "2026-10-09T10:00:00.000Z"),
      ] },
    { name: "review written late", onboardingCompletedAt: null, latestCheckinAt: null,
      programs: [row("calibration", "2026-10-01T10:00:00.000Z", { startDate: "2026-10-01" }), row("bulk", "2026-10-21T10:00:00.000Z")] },
    { name: "unparseable generatedAt", onboardingCompletedAt: "2026-10-01T00:00:00.000Z", latestCheckinAt: null,
      programs: [row("calibration", "2026-10-01T10:00:00.000Z"), row("bulk", "not a date")] },
    { name: "unparseable generatedAt, then fresh start", onboardingCompletedAt: "2026-10-01T00:00:00.000Z", latestCheckinAt: null,
      programs: [row("bulk", "not a date"), row("calibration", "2026-10-08T10:00:00.000Z")] },
    { name: "manual only", onboardingCompletedAt: "2026-10-01T00:00:00.000Z", latestCheckinAt: null,
      programs: [{ shortTermPhase: "bulk", generatedAt: "2026-10-01T00:00:00.000Z", aiGenerated: false }] },
    { name: "nothing", onboardingCompletedAt: null, latestCheckinAt: null, programs: [] },
    { name: "legacy calibration_review rows", onboardingCompletedAt: "2026-09-01T00:00:00.000Z", latestCheckinAt: null,
      programs: [row("calibration", "2026-09-01T10:00:00.000Z"), row("calibration_review", "2026-09-08T10:00:00.000Z"), row("bulk", "2026-09-15T10:00:00.000Z")] },
    { name: "future start date", onboardingCompletedAt: "2026-10-20T00:00:00.000Z", latestCheckinAt: null,
      programs: [row("calibration", "2026-10-20T10:00:00.000Z", { startDate: "2026-11-02" })] },
  ];
  const todays = [Date.UTC(2026, 9, 25, 10, 30), Date.UTC(2026, 9, 12, 23, 30), Date.UTC(2026, 9, 1, 12), Date.UTC(2026, 10, 9, 12)];
  const probes = (ranges: calibration.PhaseRange[]) => {
    const pts = new Set<number>();
    for (const r of ranges) for (const d of [-1, 0, 6, 7, 8, 13, 14]) {
      pts.add(calibration.addDays(r.start, d).getTime());
      pts.add(calibration.addDays(r.start, d).getTime() + 12 * 3_600_000);
    }
    return [...pts].sort((a, b) => a - b);
  };
  const serRange = (r: { phase?: string; start: Date; end: Date } | undefined) => (r ? { ...r, start: ms(r.start), end: ms(r.end) } : null);
  const out = eachTZ((tz) =>
    scenarios.flatMap((s) =>
      todays.map((today) => {
        setNow(today);
        const ranges = calibration.buildPhaseRanges(s.programs, s.onboardingCompletedAt, new Date(today));
        const groups = calibration.buildCalibrationGroups(ranges);
        const points = probes(ranges);
        const gate = calibration.checkinGate(s.programs, s.latestCheckinAt, new Date(today));
        return {
          tz, scenario: s.name, today,
          trainingStart: ms(calibration.trainingStart(s.programs, s.onboardingCompletedAt)),
          ranges: ranges.map(serRange),
          groups: groups.map(serRange),
          probes: points.map((p) => {
            const g = calibration.findCalibrationGroup(groups, new Date(p));
            return { at: p, phase: calibration.findPhaseRange(ranges, new Date(p))?.phase ?? null, group: serRange(g),
              reviewPossible: g ? calibration.isReviewPossible(g, new Date(p)) : null };
          }),
          gate: { ...gate, opensAt: "opensAt" in gate ? ms(gate.opensAt) : undefined },
          walkthrough: [null, "2026-10-01T00:00:00Z"].map((seen) => calibration.shouldShowCalibrationWalkthrough(s.programs, s.onboardingCompletedAt, seen, new Date(today))),
          // The walkthrough's ranges are built against the real clock, not `today`.
          walkthroughAtOtherNow: (() => {
            setNow(Date.UTC(2026, 11, 20, 12));
            const v = calibration.shouldShowCalibrationWalkthrough(s.programs, s.onboardingCompletedAt, null, new Date(today));
            setNow(today);
            return { now: Date.UTC(2026, 11, 20, 12), out: v };
          })(),
          locked: s.programs.map((p) => calibration.isPreCalibrationLocked(p, new Date(today))),
        };
      })
    )
  );
  setNow(DEFAULT_NOW);
  write("calibration", {
    scenarios: scenarios.map((s) => ({ name: s.name, programs: s.programs, onboardingCompletedAt: s.onboardingCompletedAt, latestCheckinAt: s.latestCheckinAt })),
    results: out,
    addDays: eachTZ((tz) => [[Date.UTC(2026, 9, 24, 22), 1], [Date.UTC(2026, 9, 24, 22), 7], [Date.UTC(2026, 2, 28, 23), 1], [Date.UTC(2026, 0, 31, 12), 30], [Date.UTC(2026, 0, 31, 12), -31]]
      .map(([t, n]) => ({ tz, in: [t, n], out: ms(calibration.addDays(new Date(t), n)) }))),
    localDateString: eachTZ((tz) => [Date.UTC(2026, 9, 24, 22, 30), Date.UTC(2026, 9, 25, 11), Date.UTC(2026, 11, 31, 23, 59)].map((t) => ({ tz, in: t, out: calibration.localDateString(new Date(t)) }))),
    parseLocalDateString: eachTZ((tz) => ["2026-10-25", "2026-10-25T23:00:00Z", "2026-3-9", "0026-01-01", "garbage", "2026-02-30"].map((s) => ({ tz, in: s, out: ms(calibration.parseLocalDateString(s)) }))),
    isCalibrationProgram: [null, { aiGenerated: true, shortTermPhase: "calibration" }, { aiGenerated: false, shortTermPhase: "calibration" }, { aiGenerated: true, shortTermPhase: "bulk" }, { aiGenerated: true }]
      .map((p) => ({ in: p, out: calibration.isCalibrationProgram(p as any) })),
    calibrationBriefingHref: [1, 3].map((d) => ({ in: d, out: calibration.calibrationBriefingHref(d) })),
    isPreCalibrationLocked: eachTZ((tz) => [
      { aiGenerated: true, startDate: "2026-10-26" }, { aiGenerated: true, startDate: "2026-10-25" }, { aiGenerated: true, startDate: "2026-10-26T00:00:00Z" },
      { aiGenerated: false, startDate: "2030-01-01" }, { aiGenerated: true, startDate: null }, null,
    ].map((p) => ({ tz, in: { program: p, today: Date.UTC(2026, 9, 25, 10, 30) }, out: calibration.isPreCalibrationLocked(p, new Date(Date.UTC(2026, 9, 25, 10, 30))) }))),
    firstCheckinAfterReviewDays: calibration.FIRST_CHECKIN_AFTER_REVIEW_DAYS,
  });
}

// ─── nutritionPlan ──────────────────────────────────────────────────────────────
{
  const foods = [
    { name: "a", amount: 0.5, unit: "medium" }, { name: "b", amount: 1, unit: "medium" }, { name: "c", amount: 2, unit: "medium" },
    { name: "d", amount: 1, unit: "bowl" }, { name: "e", amount: 2, unit: "bowl" }, { name: "f", amount: 0.5, unit: "bowl" },
    { name: "g", amount: 85, unit: "g" }, { name: "h", amount: 12.5, unit: "ml" }, { name: "i", amount: 3, unit: "pcs" },
  ];
  write("nutritionPlan", {
    samplePlan: nutritionPlan.SAMPLE_PLAN,
    planTotals: nutritionPlan.planTotals(nutritionPlan.SAMPLE_PLAN),
    kcalOf: [{ protein: 42, carbs: 68, fat: 14 }, { protein: 0.1, carbs: 0.1, fat: 0.1 }, { protein: 0, carbs: 0, fat: 0.5 / 9 }].map((m) => ({ in: m, out: nutritionPlan.kcalOf(m) })),
    scalePlan: [null, 0, -5, 1, 1200, 2450, 2451, 3000, 5000, 1800.5].map((t) => ({ in: t, out: nutritionPlan.scalePlan(nutritionPlan.SAMPLE_PLAN, t) })),
    formatAmount: foods.map((f) => ({ in: f, out: nutritionPlan.formatAmount(f as any) })),
  });
}

// ─── greetingLines ──────────────────────────────────────────────────────────────
{
  const ats = [Date.UTC(2026, 0, 1, 0, 30), Date.UTC(2026, 0, 1, 12), Date.UTC(2025, 11, 31, 23, 30), Date.UTC(2026, 2, 29, 0, 30),
    Date.UTC(2026, 2, 29, 23, 30), Date.UTC(2026, 9, 25, 0, 30), Date.UTC(2026, 9, 25, 23, 30), Date.UTC(2028, 11, 31, 12), Date.UTC(2026, 5, 15, 7)];
  const days = [{ dayNumber: 1, label: "Push" }, { dayNumber: 2, label: "Pull" }, { dayNumber: 4, label: "Legs" }];
  write("greetingLines", {
    greetingLine: eachTZ((tz) => ats.flatMap((at) => [null, "", "Push"].map((label) => ({ tz, in: { label, at }, out: greetingLines.greetingLine(label, new Date(at)) })))),
    nextSessionDay: [
      { days, last: null }, { days, last: 1 }, { days, last: 2 }, { days, last: 4 }, { days, last: 3 }, { days: [], last: 1 }, { days: [days[0]], last: 1 },
    ].map((c) => ({ in: c, out: greetingLines.nextSessionDay(c.days, c.last) })),
  });
}

// ─── colours ────────────────────────────────────────────────────────────────────
{
  const phases = [...Object.keys(phaseColors.PHASE_HUES), "unknown", ""];
  const hexes = [...dayColors.DAY_PALETTE, "#fff", "#000", "abc", "#12345g", "#g12345", "nope", "", " #3B82F6 ", "#-12345", "#0x1234", "#ffffffff", "#808080", "##123456"];
  write("colors", {
    phaseHues: phaseColors.PHASE_HUES,
    phases: phases.map((p) => ({ in: p, solid: phaseColors.phaseSolid(p), soft: phaseColors.phaseSoft(p), label: phaseColors.phaseLabel(p) })),
    dayPalette: dayColors.DAY_PALETTE,
    dayTones: hexes.map((h) => ({ in: h, out: dayColors.dayTones(h) })),
    buildDayColorOrder: [
      { program: ["Push", "Pull", "Legs"], extra: [] }, { program: ["Push", null, "Push", "", "Legs"], extra: ["Old Day", "Pull", undefined] }, { program: [], extra: ["x"] },
    ].map((c) => ({ in: c, out: dayColors.buildDayColorOrder(c.program, c.extra) })),
    dayColorHex: [
      { label: "Push", order: { Push: 0 }, custom: {} }, { label: "Legs", order: { Legs: 12 }, custom: {} }, { label: "Legs", order: {}, custom: { Legs: "#123456" } },
      { label: "Orphan Day", order: {}, custom: {} }, { label: "", order: {}, custom: {} }, { label: "Ünïcode 💪", order: {}, custom: {} },
      { label: "A very long label that wraps the hash around many times", order: {}, custom: { Other: "#fff" } },
    ].map((c) => ({ in: c, out: dayColors.dayColorHex(c.label, c.order, c.custom) })),
    dayColorAt: [0, 1, 9, 10, 23].map((i) => ({ in: i, out: dayColors.dayColorAt(i) })),
  });
}

// ─── utils ──────────────────────────────────────────────────────────────────────
write("utils", {
  formatSplitType: ["push_pull_legs", "PPL", "upper-lower", "U/L split", "  full   body  ", "__", "", "Push pull", "ßtrength", "a__B-c"]
    .map((s) => ({ in: s, out: formatSplitType(s) })),
});

console.log(`done (now restored to ${new Date(getNow()).toISOString()})`);
