/* T1 「거위가 공 위에 앉았다」 — 글자층 컴포지션 (세로 1080×1920 · 13초 · 한국어)
 *
 * 영상층은 <video id="footage"> 하나(assets/gen/footage.mp4 — scripts/bake.py가 게임 창 캡처로 굽는다. 컷·카메라·풀백 포함).
 * 이 파일은 그 위의 글자·표시만 그린다. 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). GSAP 타임라인은 재생 헤드 역할만.
 * 난수·시계·네트워크 없음. 컷 경계는 data/cuts.js(window.CUTS, bake.py가 씀)를 그대로 쓴다 → 자막과 컷이 같은 프레임에 바뀐다.
 *
 * 비트 (초)
 *   0.0–1.9  훅: 거위가 공 위에 앉아 있다(첫 프레임부터, ×4.0). 자막 "거위가 / 공 위에 앉음." + 공에 빨간 동그라미(강조 한 점, ~1.4초)
 *   1.5–2.95 같은 샷: 거위 떼가 날아오르며 카메라가 ×3.2로 물러나고, 공 옆에 알이 남는다.
 *            훅 자막은 1.8–1.9초에 퇴장(3f), 거위가 화면 위로 빠져나간 2.24초부터 "알 낳고 감"(4f 입장) — 거위가 글자를 가로지르지 않게
 *   2.95–7.2 하드컷 몽타주(점점 짧게 1.05 → 0.95 → 0.85 → 0.75 → 0.65초): 새 · 핀 · 두더지 · 고양이 · 강아지. 공이 늘 같은 화면 점(x500)
 *   7.2–7.85 갤러리 환호 → 7.85–9.15 끊지 않고 데스크탑 전체로 풀백
 *   8.8–10.8 "다 내 바탕화면 / 맨 아래 띠에서 / 벌어진 일." + 화면 아래 띠에 흰 테두리(왼→오 쓸기)
 *   11.05–13.0 엔드카드(문장이 다 빠진 뒤 시작): mini-golf · macOS 메뉴바 앱 · 무료 · 오픈소스 · github 주소 (띠 안의 스틱맨은 계속 움직인다)
 */
(() => {
  const FPS = 30, DUR = 13, NF = 390;
  const root = document.getElementById("root");
  const q = new URLSearchParams(location.search);
  const CUTS = window.CUTS, PULL = window.PULL, SCR = window.SCR;
  const cut = (id) => CUTS.find((c) => c.id === id);

  /* ── 문구 (2~5자 밈 자막) ── */
  const CAPS = [
    { id: "hook", t0: 0.0, t1: 1.9, lines: ["거위가", "공 위에 앉음."], size: 136, top: 340, enter: false, fadeOut: 3 },
    { id: "egg", t0: 2.24, t1: cut("geese").t1, lines: ["알 낳고 감"], size: 136, top: 392, fadeIn: 4 },
    { id: "bird", t0: cut("bird").t0, t1: cut("bird").t1, lines: ["새가 물어감"], size: 136, top: 392 },
    { id: "pin", t0: cut("pin").t0, t1: cut("pin").t1, lines: ["핀이 도망감"], size: 136, top: 392 },
    { id: "mole", t0: cut("mole").t0, t1: cut("mole").t1, lines: ["두더지 등장"], size: 136, top: 392 },
    { id: "cat", t0: cut("cat").t0, t1: cut("cat").t1, lines: ["커서 사냥 중"], size: 136, top: 392 },
    { id: "dog", t0: cut("dog").t0, t1: cut("dog").t1, lines: ["물고 튐"], size: 136, top: 392 },
    { id: "gal", t0: cut("gallery").t0, t1: PULL[0] + 0.2, lines: ["관중 환호"], size: 136, top: 392, exit: true },
  ];
  const REVEAL = { t0: 8.8, t1: 10.8, html: `다 내 바탕화면<br><b>맨 아래 띠</b>에서<br>벌어진 일.`, size: 104, top: 330 };
  const END = { t0: 11.05 };   // 문장이 다 빠진 뒤(10.8+7f=11.03) — 두 층이 겹쳐 읽히지 않게
  const URL_TEXT = "github.com/w0uldy0udaestar/mini-golf";

  /* ── 요소 ── */
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const capEls = CAPS.map((c) => {
    const e = h("div", "cap", c.lines.map((l) => `<span class="l">${l}</span>`).join(""));
    e.style.fontSize = c.size + "px"; e.style.top = c.top + "px"; root.appendChild(e); return e;
  });
  const reveal = h("div", "reveal", REVEAL.html); reveal.style.fontSize = REVEAL.size + "px"; reveal.style.top = REVEAL.top + "px"; root.appendChild(reveal);
  // 훅의 빨간 동그라미: 손으로 그린 듯 살짝 열린 고리 (공 = 훅 앵커 (500,1100) — 그 위에 앉은 거위 밑)
  const ring = document.createElementNS("http://www.w3.org/2000/svg", "svg"); ring.id = "ring"; ring.setAttribute("viewBox", "0 0 1080 1920");
  ring.innerHTML = `<path d="M 578 1078 C 572 1038 530 1030 496 1034 C 450 1040 426 1072 430 1110 C 434 1150 476 1172 520 1168 C 562 1164 588 1138 586 1102 C 585 1086 577 1070 562 1060"
    fill="none" stroke="#D94D3D" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>`;
  root.appendChild(ring);
  // 데스크탑 화면(풀백 끝) 아래 띠 테두리 — 게임 띠: 원본 y 1500~2160 → 화면 y SCR.y + 1500·배율
  const z1 = SCR.w / 3840;
  const strip = h("div"); strip.id = "strip"; root.appendChild(strip);
  const SB = { x: SCR.x - 8, y: Math.round(SCR.y + 1500 * z1) - 6, w: SCR.w + 16, h: Math.round(SCR.h - 1500 * z1) + 14 };
  Object.assign(strip.style, { left: SB.x + "px", top: SB.y + "px", width: SB.w + "px", height: SB.h + "px" });
  const end = h("div"); end.id = "end"; end.style.top = "352px";
  end.innerHTML = `<div class="wm">mini-golf</div><div class="l2">macOS 메뉴바 앱 · 무료 · 오픈소스</div><div class="url">${URL_TEXT}</div>`;
  root.appendChild(end);
  const endParts = [...end.children];

  /* ── 시간 함수 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const prog = (t, a, d) => clamp((t - a) / d);
  const outCubic = (u) => 1 - Math.pow(1 - u, 3);
  const inOut = (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
  const F = (n) => n / FPS;

  function render(t) {
    // 몽타주 자막: 컷과 같은 프레임에 바뀐다. 들어올 때 5프레임 동안 18px 올라와 앉는다(불투명 — 하드컷의 박자는 그대로)
    CAPS.forEach((c, i) => {
      const e = capEls[i];
      const on = t >= c.t0 - 1e-6 && t < c.t1 - 1e-6;
      if (!on) { e.style.opacity = 0; return; }
      let y = 0, o = 1;
      if (c.enter !== false) y = 18 * (1 - outCubic(prog(t, c.t0, F(5))));
      // 같은 샷 안의 자막 교대(훅 → 알)는 하드 스왑 대신 3f 퇴장 + 4f 입장으로 넘긴다(프레임 차분 스파이크 방지)
      if (c.fadeIn) o *= outCubic(prog(t, c.t0, F(c.fadeIn)));
      if (c.fadeOut) { const u = prog(t, c.t1 - F(c.fadeOut), F(c.fadeOut)); o *= 1 - u; y -= 14 * u; }
      if (c.exit) { const u = prog(t, PULL[0] - 0.02, F(6)); o = 1 - u; y -= 22 * inOut(u); }
      e.style.opacity = o; e.style.transform = `translateY(${y.toFixed(2)}px)`;
    });
    // 훅 동그라미: 0~1.4초 그대로, 1.4~1.5초 사라짐 (거위가 날아오르기 직전)
    ring.style.opacity = (1 - prog(t, 1.4, F(3))).toFixed(3);
    // 풀백 뒤 문장
    const rIn = outCubic(prog(t, REVEAL.t0, F(10))), rOut = inOut(prog(t, REVEAL.t1, F(7)));
    reveal.style.opacity = (rIn * (1 - rOut)).toFixed(3);
    reveal.style.transform = `translateY(${(24 * (1 - rIn) - 26 * rOut).toFixed(2)}px)`;
    // 띠 테두리: 왼→오 쓸기(12프레임), 엔드카드에선 물러난다
    const sw = inOut(prog(t, REVEAL.t0 + 0.2, F(12)));
    strip.style.clipPath = `inset(-6px ${((1 - sw) * 100).toFixed(2)}% -6px -6px)`;
    strip.style.opacity = (sw > 0 ? 1 - 0.5 * prog(t, END.t0, F(10)) : 0).toFixed(3);
    // 엔드카드: 세 줄이 4프레임 간격으로 올라와 앉는다
    endParts.forEach((p, i) => {
      const u = outCubic(prog(t, END.t0 + i * F(4), F(12)));
      p.style.opacity = u.toFixed(3); p.style.transform = `translateY(${(30 * (1 - u)).toFixed(2)}px)`;
    });
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;
  window.__ready = false;

  // ?audit=1 : 3프레임마다 보이는 글자·표시의 화면 사각형을 모아 <pre id="audit">에 JSON (scripts/qa.py가 읽는다)
  function audit() {
    const out = { frames: [], fonts: ["500 46px Pretendard", "600 64px Pretendard", "800 136px Pretendard"].map((f) => document.fonts.check(f)) };
    const vis = (e) => { let o = 1, n = e; while (n && n !== document.body) { const cs = getComputedStyle(n); if (cs.display === "none" || cs.visibility === "hidden") return 0; o *= parseFloat(cs.opacity); n = n.parentElement; } return o; };
    const textRects = (e) => { const r = []; const rg = document.createRange(); const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT); let n;
      while ((n = w.nextNode())) { if (!n.textContent.trim()) continue; rg.selectNodeContents(n); for (const b of rg.getClientRects()) r.push([b.left, b.top, b.right, b.bottom].map(Math.round)); } return r; };
    const items = [...CAPS.map((c, i) => ["cap:" + c.id, capEls[i]]), ["reveal", reveal], ["end", end]];
    for (let f = 0; f < NF; f += 3) {
      render(f / FPS); const fr = { f, items: [] };
      for (const [name, el] of items) { const o = vis(el); if (o > 0.05) for (const r of textRects(el)) fr.items.push({ name, o: +o.toFixed(2), r, px: parseFloat(getComputedStyle(el.querySelector("div,span,b") || el).fontSize) }); }
      if (+ring.style.opacity > 0.05) { const b = ring.querySelector("path").getBoundingClientRect(); fr.items.push({ name: "ring", o: 1, r: [b.left, b.top, b.right, b.bottom].map(Math.round) }); }
      out.frames.push(fr);
    }
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  document.fonts.ready.then(() => { if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); window.__ready = true; });
  render(0);
})();
