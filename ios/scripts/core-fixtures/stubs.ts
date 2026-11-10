// Aliased in place of packages the pure modules import but never need here:
// `react` (so the hooks' pure logic can run without a renderer) and the class-name
// helpers lib/utils.ts pulls in.

// --- react: effects run immediately, state is a plain slot, refs are boxes.
export function useRef<T>(v: T) {
  return { current: v };
}
export function useState<T>(v: T | (() => T)) {
  const init = typeof v === "function" ? (v as () => T)() : v;
  const slot = { value: init };
  const set = (x: any) => {
    slot.value = typeof x === "function" ? x(slot.value) : x;
  };
  return [init, set] as const;
}
export function useEffect(fn: () => void | (() => void)) {
  fn();
}

// --- clsx / tailwind-merge
export function clsx(...xs: unknown[]) {
  return xs.filter(Boolean).join(" ");
}
export function twMerge(s: string) {
  return s;
}
