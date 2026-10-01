// 디버그·미리보기: node scripts/shot.mjs <h|v> <ko|en> <outdir> <frame...>  — 콘솔 오류를 출력하고 프레임별 PNG를 찍는다 (puppeteer-core + 시스템 Chrome)
import puppeteer from "puppeteer-core";
import path from "node:path";
const [o, lang, out, ...frames] = process.argv.slice(2);
const here = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const page0 = o === "h" ? "index.html" : "vertical.html";
const [W, H] = o === "h" ? [1920, 1080] : [1080, 1920];
const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: "new",
  args: ["--allow-file-access-from-files", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1"] });
const page = await browser.newPage();
await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
page.on("console", (m) => console.log("console:", m.type(), m.text()));
page.on("pageerror", (e) => console.log("pageerror:", e.message));
await page.goto(`file://${here}/${page0}?lang=${lang}`, { waitUntil: "load" });
await page.waitForFunction("window.__ready === true", { timeout: 20000 });
for (const f of frames) {
  await page.evaluate((t) => window.__render(t), Number(f) / 30);
  await page.screenshot({ path: `${out}/p-${o}-${lang}-f${String(f).padStart(3, "0")}.png` });
}
await browser.close();
