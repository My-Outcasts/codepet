/**
 * The formula language a `sheet` output is written in (CP-002 D).
 *
 * A sheet used to be four fixed inputs and six outputs whose maths lived in the app. Now the
 * model declares its own inputs and writes each output as a formula over them, and the app
 * computes it live as the founder moves a slider — so the formula is the model, and the number
 * is never just what the model claimed.
 *
 * Deliberately tiny, and parsed here rather than evaluated with anything like `eval`: numbers,
 * names, `+ - * / ^`, parentheses, and five functions. The Swift client has a line-for-line twin
 * (`SheetFormula.swift`), and both are held to one table of cases
 * (`__tests__/fixtures/sheetFormulaCases.json`) so a formula can never compute one number on the
 * server and another in the app.
 *
 * `×`, `÷` and `−` are accepted because that is how the viewer PRINTS a formula, and a revise
 * pass hands the model back what the founder saw.
 */

export type FormulaNode =
  | { t: "num"; v: number }
  | { t: "ref"; name: string }
  | { t: "neg"; x: FormulaNode }
  | { t: "bin"; op: "+" | "-" | "*" | "/" | "^"; a: FormulaNode; b: FormulaNode }
  | { t: "call"; fn: string; args: FormulaNode[] };

/** Arity per function: [min, max]. */
const FUNCS: Record<string, readonly [number, number]> = {
  min: [2, 8], max: [2, 8], round: [1, 1], ceil: [1, 1], floor: [1, 1],
};

type Tok = { k: "num"; v: number } | { k: "id"; v: string } | { k: "op"; v: string };

function tokenize(src: string): Tok[] | null {
  const s = src.replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-");
  const out: Tok[] = [];
  let i = 0;
  while (i < s.length) {
    const c = s[i] as string;
    if (c === " " || c === "\t") { i++; continue; }
    if ("+-*/^(),".includes(c)) { out.push({ k: "op", v: c }); i++; continue; }
    const num = /^\d+(?:\.\d+)?/.exec(s.slice(i));
    if (num) {
      // `1e3` would otherwise read as the number 1 followed by the name `e3`.
      if (/^[A-Za-z_]/.test(s.slice(i + num[0].length))) return null;
      out.push({ k: "num", v: Number(num[0]) }); i += num[0].length; continue;
    }
    const id = /^[a-z][a-z0-9_]*/.exec(s.slice(i));
    if (id) { out.push({ k: "id", v: id[0] }); i += id[0].length; continue; }
    return null;
  }
  return out;
}

/** The parsed formula, or null when it is not one: a syntax error, or an unknown function. */
export function parseFormula(src: string): FormulaNode | null {
  const toks = tokenize(src);
  if (!toks || !toks.length) return null;
  let p = 0;
  const peek = () => toks[p];
  const isOp = (v: string) => { const t = peek(); return !!t && t.k === "op" && t.v === v; };

  // expr := term (("+"|"-") term)* ; term := unary (("*"|"/") unary)*
  // unary := "-" unary | power ; power := atom ("^" unary)?   (right-assoc, binds tighter than -)
  const expr = (): FormulaNode | null => {
    let a = term(); if (!a) return null;
    while (isOp("+") || isOp("-")) {
      const op = (toks[p++] as { v: string }).v as "+" | "-";
      const b = term(); if (!b) return null;
      a = { t: "bin", op, a, b };
    }
    return a;
  };
  const term = (): FormulaNode | null => {
    let a = unary(); if (!a) return null;
    while (isOp("*") || isOp("/")) {
      const op = (toks[p++] as { v: string }).v as "*" | "/";
      const b = unary(); if (!b) return null;
      a = { t: "bin", op, a, b };
    }
    return a;
  };
  const unary = (): FormulaNode | null => {
    if (isOp("-")) { p++; const x = unary(); return x ? { t: "neg", x } : null; }
    return power();
  };
  const power = (): FormulaNode | null => {
    const a = atom(); if (!a) return null;
    if (isOp("^")) { p++; const b = unary(); return b ? { t: "bin", op: "^", a, b } : null; }
    return a;
  };
  const atom = (): FormulaNode | null => {
    const t = peek(); if (!t) return null;
    if (t.k === "num") { p++; return { t: "num", v: t.v }; }
    if (t.k === "op" && t.v === "(") {
      p++; const x = expr(); if (!x || !isOp(")")) return null; p++; return x;
    }
    if (t.k === "id") {
      p++;
      if (!isOp("(")) return { t: "ref", name: t.v };
      const arity = FUNCS[t.v]; if (!arity) return null;
      p++;
      const args: FormulaNode[] = [];
      if (!isOp(")")) {
        for (;;) {
          const x = expr(); if (!x) return null; args.push(x);
          if (isOp(",")) { p++; continue; }
          break;
        }
      }
      if (!isOp(")")) return null; p++;
      if (args.length < arity[0] || args.length > arity[1]) return null;
      return { t: "call", fn: t.v, args };
    }
    return null;
  };

  const root = expr();
  return root && p === toks.length ? root : null;
}

/** Every name a formula reads. */
export function formulaRefs(n: FormulaNode, into = new Set<string>()): Set<string> {
  if (n.t === "ref") into.add(n.name);
  else if (n.t === "neg") formulaRefs(n.x, into);
  else if (n.t === "bin") { formulaRefs(n.a, into); formulaRefs(n.b, into); }
  else if (n.t === "call") n.args.forEach((a) => formulaRefs(a, into));
  return into;
}

/** `round` is half-up (`floor(x + 0.5)`) on both sides, so -2.5 → -2 everywhere. */
export function evalFormula(n: FormulaNode, env: Record<string, number>): number {
  switch (n.t) {
    case "num": return n.v;
    case "ref": return n.name in env ? (env[n.name] as number) : NaN;
    case "neg": return -evalFormula(n.x, env);
    case "bin": {
      const a = evalFormula(n.a, env), b = evalFormula(n.b, env);
      return n.op === "+" ? a + b : n.op === "-" ? a - b : n.op === "*" ? a * b : n.op === "/" ? a / b : Math.pow(a, b);
    }
    case "call": {
      const xs = n.args.map((a) => evalFormula(a, env));
      switch (n.fn) {
        case "min": return Math.min(...xs);
        case "max": return Math.max(...xs);
        case "round": return Math.floor((xs[0] as number) + 0.5);
        case "ceil": return Math.ceil(xs[0] as number);
        default: return Math.floor(xs[0] as number);
      }
    }
  }
}
