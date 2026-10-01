// 글꼴 감사: node scripts/fontscan.mjs <h|v> <ko|en> [step=15] → 시스템 글꼴(번들 아님)로 그려진 글자 목록(JSON). 0건이어야 한다.
// 헤드리스 Chrome은 기계마다 시스템 글꼴이 다르다 — 모든 글리프가 번들 웹폰트(Pretendard·JBM)에서 나와야 결정적이다.
import puppeteer from "puppeteer-core";
import path from "node:path";
const [o, lang, stepArg] = process.argv.slice(2); const step = Number(stepArg || 15);
const here = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const [W, H] = o === "h" ? [1920, 1080] : [1080, 1920];
const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: "new", args: ["--allow-file-access-from-files", "--disable-gpu"] });
const page = await browser.newPage(); await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
await page.goto(`file://${here}/${o === "h" ? "index.html" : "vertical.html"}?lang=${lang}`, { waitUntil: "load" });
await page.waitForFunction("window.__ready === true", { timeout: 20000 });
const cdp = await page.createCDPSession(); await cdp.send("DOM.enable"); await cdp.send("CSS.enable");
const seen = new Map(), bad = {};
for (let f = 0; f < 900; f += step) {
  await page.evaluate((t) => window.__render(t), f / 30);
  // 보이는(레이아웃 있는) 글자 요소마다 고유 표식 — 글자·글꼴 스택이 같으면 다시 묻지 않는다
  const els = await page.evaluate(() => { const out = []; let k = 0;
    for (const e of document.querySelectorAll("#root *")) { const own = [...e.childNodes].filter((n) => n.nodeType === 3 && n.textContent.trim()).map((n) => n.textContent).join("");
      if (!own) continue; if (!e.getClientRects().length) continue; const cs = getComputedStyle(e);
      e.setAttribute("data-fs", String(k)); out.push({ k, key: own + "|" + cs.fontFamily + "|" + cs.fontWeight, text: own.slice(0, 40) }); k++; }
    return out; });
  const doc = await cdp.send("DOM.getDocument", { depth: 0 });
  for (const e of els) { if (seen.has(e.key)) continue;
    const q = await cdp.send("DOM.querySelector", { nodeId: doc.root.nodeId, selector: `[data-fs="${e.k}"]` });
    const r = await cdp.send("CSS.getPlatformFontsForNode", { nodeId: q.nodeId });
    const sys = r.fonts.filter((x) => !x.isCustomFont).map((x) => `${x.familyName}:${x.glyphCount}`);
    seen.set(e.key, sys); if (sys.length) (bad[e.text] ||= { first: f, sys }); }
  await page.evaluate(() => document.querySelectorAll("[data-fs]").forEach((e) => e.removeAttribute("data-fs")));
}
console.log(JSON.stringify({ orient: o, lang, checked: seen.size, systemFontTexts: Object.keys(bad).length, bad }, null, 1));
await browser.close();
