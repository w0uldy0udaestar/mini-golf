// 안전 영역·글자 크기 감사: node scripts/audit.mjs <h|v> <ko|en> [step=3] → JSON (위반 목록: 3프레임 간격 표본, 보이는 글자 요소의 화면 사각형)
// 가로: 5% 여백 (x 96–1824, y 54–1026) · 세로: x 70–1010, y 300–1500. 데스크탑 속 창 글자(배경)는 판정하지 않는다 — 광고 글자(자막·HUD 라벨·토스트·엔드·텔레메트리·태그)와 헤드라인·터미널 명령만.
import puppeteer from "puppeteer-core";
import path from "node:path";
const [o, lang, stepArg] = process.argv.slice(2); const step = Number(stepArg || 3);
const here = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const [W, H] = o === "h" ? [1920, 1080] : [1080, 1920];
const Z = o === "h" ? [96, 54, 1824, 1026] : [70, 300, 1010, 1500];
const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: "new", args: ["--allow-file-access-from-files", "--disable-gpu"] });
const page = await browser.newPage(); await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
await page.goto(`file://${here}/${o === "h" ? "index.html" : "vertical.html"}?lang=${lang}`, { waitUntil: "load" });
await page.waitForFunction("window.__ready === true", { timeout: 20000 });
const out = { orient: o, lang, zone: Z, violations: [], sizes: {} };
for (let f = 0; f < 900; f += step) {
  const items = await page.evaluate((t) => {
    window.__render(t);
    const vis = (e) => { let op = 1, n = e; while (n && n !== document.body) { const cs = getComputedStyle(n); if (cs.visibility === "hidden" || cs.display === "none") return 0; op *= parseFloat(cs.opacity); n = n.parentElement; } return op; };
    const rects = (e) => { const r = document.createRange(), res = []; const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT); let n;
      while ((n = w.nextNode())) { if (!n.textContent.trim()) continue; r.selectNodeContents(n); for (const b of r.getClientRects()) res.push([b.left, b.top, b.right, b.bottom].map(Math.round)); } return res; };
    const sel = [["caption", "#screen .cap"], ["hud", "#screen .hud"], ["toast", "#screen .toast"], ["end", "#end"], ["tele", "#screen > div:not([class]):not(#end)"], ["tag", "#screen > .tele"], ["headline", ".sent"], ["kicker", ".kick"], ["terminal", ".term"]];
    const res = [];
    for (const [name, q] of sel) for (const e of document.querySelectorAll(q)) { const op = vis(e); if (op < 0.05) continue;
      let rs = rects(e);
      if (name === "caption") { const m = e.getBoundingClientRect(); rs = rs.map((b) => [Math.max(b[0], m.left), Math.max(b[1], m.top), Math.min(b[2], m.right), Math.min(b[3], m.bottom)].map(Math.round)).filter((b) => b[3] - b[1] > 4); }
      for (const b of rs) if (b[2] > 0 && b[0] < innerWidth && b[3] > 0 && b[1] < innerHeight) res.push({ name, op: +op.toFixed(2), r: b, fs: parseFloat(getComputedStyle(e).fontSize) });
    }
    // 비글자 핵심 요소: 벡터 스틱맨(svg 그룹)·공·벡터 시계 — 보이는 데스크탑 안의 것만
    for (const d of document.querySelectorAll(".desk")) { if (getComputedStyle(d).display === "none") continue;
      for (const g of d.querySelectorAll("svg.fx > g")) { if (vis(g) < 0.05) continue; const b = g.getBoundingClientRect(); if (b.width < 2) continue;
        const r = [b.left, b.top, b.right, b.bottom].map(Math.round); if (r[2] > 0 && r[0] < innerWidth && r[3] > 0 && r[1] < innerHeight) res.push({ name: "vector", op: 1, r }); }
      for (const e of d.querySelectorAll(".ball")) { if (vis(e) < 0.05) continue; const b = e.getBoundingClientRect(); const r = [b.left, b.top, b.right, b.bottom].map(Math.round);
        if (r[2] > 0 && r[0] < innerWidth && r[3] > 0 && r[1] < innerHeight) res.push({ name: "ball", op: 1, r }); } }
    return res;
  }, f / 30);
  for (const it of items) {
    const [x0, y0, x1, y1] = it.r;
    if (x0 < Z[0] || y0 < Z[1] || x1 > Z[2] || y1 > Z[3]) out.violations.push({ f, ...it });
  }
}
// 이름별 요약: 연속 위반 구간
const by = {}; for (const v of out.violations) (by[v.name] ||= []).push(v);
out.summary = Object.fromEntries(Object.entries(by).map(([k, vs]) => [k, { samples: vs.length, frames: [vs[0].f, vs[vs.length - 1].f], first: vs[0].r, worst: vs.reduce((a, b) => Math.max(a, Math.max(Z[0] - b.r[0], Z[1] - b.r[1], b.r[2] - Z[2], b.r[3] - Z[3])), 0) }]));
out.vio = out.violations.filter((v) => !["headline", "kicker"].includes(v.name)).map((v) => [v.f, v.name, v.r]); delete out.violations;
console.log(JSON.stringify(out, null, 1));
await browser.close();
