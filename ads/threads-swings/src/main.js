/* mini-golf 스레드 T4 「스윙 3종」 — 세로 1080×1920, 15초 (450프레임 @30fps)
 *
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). GSAP 타임라인은 재생 헤드 역할만. Math.random·Date·네트워크 없음.
 * 스틱맨은 전부 실제 리그 덤프(60Hz, data/rigs.js)를 게임 StickmanNode 렌더 규칙(선 굵기 6·트레일 팔 5.5·샤프트 3·머리 r10)
 * 그대로 SVG로 그린다. 칸마다 리그 시각을 따로 리맵해(단조 3차 보간) 같은 프레임에 임팩트를 맞추고, 한 칸씩 슬로모로 살린다.
 *
 * 비트 (프레임) — 자세한 근거는 plan.md
 *   f0–14    훅: 세 칸 트립틱, 셋 다 톱 근처에서 실속도 다운스윙 → f14 동시 임팩트, 칸마다 공 자리에서 흰 번쩍 2프레임
 *   f14–26   임팩트 정지(거의 멈춘 시간)
 *   f26–86   1칸 '뛴다'   — 임팩트 점프 12pt를 슬로모로(다른 칸은 어둡게 멈춤)
 *   f86–148  2칸 '돌린다' — 피니시 → 리코일 → 그립 축 트월 한 바퀴
 *   f148–206 3칸 '고정'   — 곧은 팔 팔로스루 → 피니시
 *   f206–230 3칸이 화면을 채운다(핸드오프) · f222–236 벡터 → 같은 자세 실캡처로 교차
 *   f236–290 실캡처 위에 리그 관절선이 그려진다 — "프로 영상에서 / 뽑은 관절"
 *   f290–318 되돌아와 세 칸이 위로 물러난다 → "스윙 스타일 3가지 / ⛳ 메뉴에서 고른다"
 *   f372–450 엔드카드: mini-golf · macOS 메뉴바 앱 / 무료 · 오픈소스 · github.com/w0uldy0udaestar/mini-golf
 */
(() => {
  const FPS = 30, DUR = 15;
  const root = document.getElementById("root");
  const RIGS = window.RIGS, CAP = RIGS.capture;
  const q = new URLSearchParams(location.search);
  const NS = "http://www.w3.org/2000/svg";

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const smooth = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
  const seg = (f, a, b) => clamp((f - a) / (b - a));
  const bez = (x1, y1, x2, y2) => (p) => { if (p <= 0) return 0; if (p >= 1) return 1; let a = 0, b = 1, t = p;
    for (let i = 0; i < 30; i++) { t = (a + b) / 2; const x = 3 * x1 * (1 - t) ** 2 * t + 3 * x2 * (1 - t) * t * t + t ** 3; x < p ? a = t : b = t; }
    return 3 * y1 * (1 - t) ** 2 * t + 3 * y2 * (1 - t) * t * t + t ** 3; };
  const camEase = bez(0.65, 0, 0.3, 1);
  const SPR = { calm: [0.78, 2.7], settle: [0.62, 3.2] };
  const step = (t, z, f) => { const w = 2 * Math.PI * f, d = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(d * t) + z * w / d * Math.sin(d * t)); };
  const Sk = (t, n) => { if (t <= 0) return 0; const [z, f] = SPR[n]; const D = 6 / (z * 2 * Math.PI * f); return t >= D ? 1 : step(t, z, f) / step(D, z, f); };
  // 단조 3차 에르미트(Fritsch–Carlson): 키프레임 [프레임, 리그 시각] → 속도가 매끄럽게 바뀌는 시간 리맵 (역행 없음)
  function mono(keys) {
    const n = keys.length, x = keys.map((k) => k[0]), y = keys.map((k) => k[1]), d = [], m = new Array(n);
    for (let i = 0; i < n - 1; i++) d.push((y[i + 1] - y[i]) / (x[i + 1] - x[i]));
    m[0] = d[0]; m[n - 1] = d[n - 2];
    for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    for (let i = 0; i < n - 1; i++) {
      if (d[i] === 0) { m[i] = 0; m[i + 1] = 0; continue; }
      const a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
      if (s > 9) { const k = 3 / Math.sqrt(s); m[i] = k * a * d[i]; m[i + 1] = k * b * d[i]; }
    }
    return (f) => {
      if (f <= x[0]) return y[0]; if (f >= x[n - 1]) return y[n - 1];
      let i = 0; while (f > x[i + 1]) i++;
      const h = x[i + 1] - x[i], t = (f - x[i]) / h, t2 = t * t, t3 = t2 * t;
      return (2 * t3 - 3 * t2 + 1) * y[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * y[i + 1] + (t3 - t2) * h * m[i + 1];
    };
  }

  /* ── 배치 (px) ── */
  const PH = 484, PY = [124, 618, 1112];      // 세 칸: y 124–1596 (세로 안전 영역 100–1620), 칸 사이 10px
  const GL = 466, SC = 3.85, SX = 388;         // 칸 안 지면선 y(칸 바닥 18px 위) · pt당 px(몸 키 89pt → 341px = 칸 높이 70%) · 스틱 x
  const FF = { X: 608, G: 1150, S: CAP.scale }; // 3칸 전체 화면: 몸 키 89pt × 10.4 = 926px (실캡처도 같은 배율로 미리 확대)
  const ORDER = ["jump", "lock", "twirl"];
  const WORDS = ["뛴다", "고정", "돌린다"];
  const WORD = { right: 916, dy: 34, size: 124 };   // 칸 안 오른쪽 위, 오른쪽 끝 x 916(스레드 UI 150px 밖)
  const EXP = "twirl";                         // 화면을 채우는 칸
  const F_IMP = 14;
  const SPOT = [[26, 84], [84, 140], [140, 212]];   // 칸별 주인공 구간
  const F_EXP = [204, 232], F_BACK = [278, 308], F_X = [222, 236], RIGF0 = 240;
  const F_OUT = [328, 340], F_LA = 338, F_LB = 348, F_SWAP = 382;   // 꽉 찬 트립틱으로 돌아와 요약(f302–326) → 칸이 물러나고 글자만

  // 칸별 리그 시각 리맵: 훅은 실속도(임팩트 f14), 임팩트 뒤는 키프레임 사이 단조 3차 — 주인공 구간에서만 슬로모로 흐른다
  const KEYS = {
    jump: [[14, 0], [26, 0.008], [34, 0.03], [52, 0.085], [70, 0.26], [84, 0.6], [108, 1.05], [450, 1.45]],
    lock: [[14, 0], [26, 0.008], [84, 0.02], [94, 0.06], [118, 0.38], [140, 0.9], [450, 1.7]],
    twirl: [[14, 0], [26, 0.008], [140, 0.02], [150, 0.06], [164, 0.45], [170, 0.57], [204, 1.37], [230, CAP.rigT], [450, CAP.rigT]],
  };
  const REMAP = Object.fromEntries(ORDER.map((n) => [n, mono(KEYS[n])]));
  const rigT = (n, f) => (f <= F_IMP ? (f - F_IMP) / FPS : REMAP[n](f));

  /* ── 리그 표본 보간 ── */
  function sampleAt(S, t) {
    let lo = 0, hi = S.length - 1;
    if (t <= S[0].t) return S[0]; if (t >= S[hi].t) return S[hi];
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (S[mid].t <= t) lo = mid; else hi = mid; }
    const a = S[lo], b = S[hi], u = (t - a.t) / (b.t - a.t);
    return { p: a.p.map((pa, k) => [lerp(pa[0], b.p[k][0], u), lerp(pa[1], b.p[k][1], u)]), h: [lerp(a.h[0], b.h[0], u), lerp(a.h[1], b.h[1], u)],
      phi: lerp(a.phi, b.phi, u), len: lerp(a.len, b.len, u), butt: lerp(a.butt, b.butt, u), c: u < 0.5 ? a.c : b.c, m: u < 0.5 ? a.m : b.m };
  }
  // 관절 → 화면 좌표 (facing 로컬 × 오른쪽 보기, 지면 G, 배율 s)
  function joints(r, X, G, s) {
    const T = (p) => [X + p[0] * s, G - p[1] * s];
    const [hip, sh, f1, f2, k1, k2, grip, ht, el, et] = r.p.map(T);
    const sp = Math.sin(r.phi), cp = Math.cos(r.phi);
    return { hip, sh, f1, f2, k1, k2, grip, ht, el, et, sp, cp,
      tip: [grip[0] + sp * r.len * s, grip[1] + cp * r.len * s], butt: [grip[0] - sp * r.butt * s, grip[1] - cp * r.butt * s],
      hd: [sh[0] + r.h[0] * s, sh[1] - r.h[1] * s] };
  }
  const fp = (p) => p[0].toFixed(2) + " " + p[1].toFixed(2);

  /* ── DOM ── */
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const mk = (tag, a) => { const e = document.createElementNS(NS, tag); for (const k in a) e.setAttribute(k, a[k]); return e; };
  const stage = h("div"); stage.id = "stage"; root.appendChild(stage);

  const FLAG = (w, hh) => `<svg width="${w}" height="${hh}" viewBox="0 0 14 16"><ellipse cx="3.2" cy="15" rx="3.1" ry="0.9" fill="#5C5D59"/><line x1="3.2" y1="1.2" x2="3.2" y2="14.8" stroke="#E6E6E2" stroke-width="1.5" stroke-linecap="round"/><path d="M3.9 1.5 L12.6 4.4 L3.9 7.3 Z" fill="#D94D3D"/></svg>`;


  const panels = ORDER.map((name, i) => {
    const el = h("div", "panel"); stage.appendChild(el);
    const content = h("div", "content"); el.appendChild(content);
    const svg = mk("svg", { width: 1080, height: 1920 }); content.appendChild(svg);
    let cap = null;
    if (name === EXP) { cap = h("img", "cap"); cap.src = CAP.file; content.insertBefore(cap, svg); }
    const ground = mk("path", { fill: "none", stroke: "rgba(226,226,222,.92)", "stroke-linecap": "round", "stroke-linejoin": "round" });
    const rough = mk("path", { fill: "none", stroke: "rgba(176,176,172,.85)", "stroke-linecap": "round" });
    const trailLine = mk("line", { stroke: "rgba(205,205,200,.42)", "stroke-linecap": "round" });
    const smear = mk("polyline", { fill: "none", stroke: "rgba(242,242,242,.38)", "stroke-linecap": "round", "stroke-linejoin": "round" });
    const tee = mk("path", { fill: "rgba(255,255,255,.9)" });
    const ball = mk("circle", { fill: "#FAFAF8" });
    const anno = mk("g", { opacity: 0 });
    const man = mk("g", {});
    const M = {
      trail: mk("path", { fill: "none", stroke: "rgba(224,224,224,.52)", "stroke-linecap": "round", "stroke-linejoin": "round" }),
      body: mk("path", { fill: "none", stroke: "rgba(224,224,224,.95)", "stroke-linecap": "round", "stroke-linejoin": "round" }),
      shaft: mk("path", { fill: "none", stroke: "rgba(194,194,194,.9)", "stroke-linecap": "round" }),
      chead: mk("path", { fill: "none", stroke: "rgba(237,237,237,.95)", "stroke-linecap": "round" }),
      grip: mk("path", { fill: "none", stroke: "rgba(153,153,153,.9)", "stroke-linecap": "round" }),
      head: mk("circle", { fill: "rgba(224,224,224,.95)" }),
    };
    for (const k of ["trail", "body", "shaft", "chead", "grip", "head"]) man.appendChild(M[k]);
    for (const e of [ground, rough, trailLine, tee, ball, anno, smear, man]) svg.appendChild(e);
    const rig = mk("g", { opacity: 0 }); svg.appendChild(rig);
    const word = h("div", "word", WORDS[i]); word.style.fontSize = WORD.size + "px"; word.style.letterSpacing = (-0.03 * WORD.size) + "px";
    content.appendChild(word);
    const flash = h("div", "flash"); el.appendChild(flash);
    const shade = h("div", "shade"); el.appendChild(shade);
    return { name, i, el, content, svg, cap, ground, rough, trailLine, smear, tee, ball, anno, man, M, rig, word, flash, shade, S: RIGS[name].samples };
  });

  // 주석(크래프트 디테일): 뛴다 = 발밑 치수선, 돌린다 = 헤드가 그린 원, 고정 = 어깨–그립 직선 자
  const A = {};
  { const g = panels[0].anno;
    A.jl = mk("path", { fill: "none", stroke: "#B9BAB6", "stroke-width": 4.2, "stroke-linecap": "round" }); g.appendChild(A.jl);
    A.jt = mk("text", {}); }   // 숫자 라벨은 폰에서 안 읽혀 뺐다(2차 수정) — 치수선만
  const PN = Object.fromEntries(panels.map((P) => [P.name, P]));
  { const g = PN.twirl.anno;
    A.ta = mk("polyline", { fill: "none", stroke: "#B9BAB6", "stroke-width": 4.2, "stroke-dasharray": "3 13", "stroke-linecap": "round" }); g.appendChild(A.ta);
    A.tt = mk("text", {}); }
  { const g = PN.lock.anno;
    A.ll = mk("path", { fill: "none", stroke: "#B9BAB6", "stroke-width": 4.2, "stroke-linecap": "round" }); g.appendChild(A.ll);
    A.lt = mk("text", {}); }

  // 3칸 전체 화면 캡션
  const ffcap = h("div", "ffcap", "프로 영상에서<br>뽑은 관절"); ffcap.style.cssText += ";left:96px;top:1236px;font-size:100px;letter-spacing:-3px";
  root.appendChild(ffcap);

  // 마무리 글자층 (화면 고정)
  const closing = h("div"); closing.id = "closing"; root.appendChild(closing);
  const maskEl = h("div", "mask"); maskEl.style.cssText = "left:90px;top:690px;width:930px;height:560px"; closing.appendChild(maskEl);
  const line = (cls, html, top, size, extra = "") => { const e = h("div", "ln " + cls, html); e.style.cssText += `;top:${top}px;font-size:${size}px;${extra}`; maskEl.appendChild(e); return e; };
  const LA = line("la", "스윙 스타일 3가지", 40, 104, "letter-spacing:-3.4px");
  const LB = line("lb", `${FLAG(56, 64)}<span style="margin-left:18px">메뉴에서 고른다</span>`, 196, 72, "letter-spacing:-1.8px");
  const EW = line("wm", "mini-golf", 40, 128, "letter-spacing:-4.4px");
  const EM = line("meta", "macOS 메뉴바 앱<br>무료 · 오픈소스", 200, 64, "letter-spacing:-1.4px");
  const EU = line("url", "github.com/w0uldy0udaestar/mini-golf", 380, 38, "letter-spacing:-0.4px");

  /* ── 공 자리: 임팩트 표본의 헤드 중심 (칸마다) ── */
  const BALL = {};
  for (const n of ORDER) { const r0 = sampleAt(RIGS[n].samples, 0); const j = joints(r0, 0, 0, 1); BALL[n] = [j.tip[0] + Math.cos(r0.phi) * 4.5, -5.6]; }
  const V_BALL = 230, LAUNCH = 13 * Math.PI / 180;   // 게임 화면에서 드라이버 공 속도(pt/s) 근사 · 발사각

  /* ── 한 칸 그리기 ── */
  function drawMan(P, r, X, G, s) {
    const j = joints(r, X, G, s), M = P.M;
    const ctl = [(j.sh[0] + j.hip[0]) / 2 - 0.8 * s, (j.sh[1] + j.hip[1]) / 2];
    const arm = (a, e, b) => r.c ? `M${fp(a)} Q${fp(e)} ${fp(b)}` : `M${fp(a)} L${fp(e)} L${fp(b)}`;
    M.body.setAttribute("d", `M${fp(j.sh)} Q${fp(ctl)} ${fp(j.hip)} M${fp(j.hip)} L${fp(j.k1)} L${fp(j.f1)} M${fp(j.hip)} L${fp(j.k2)} L${fp(j.f2)} ${arm(j.sh, j.el, j.grip)}`);
    M.trail.setAttribute("d", arm(j.sh, j.et, j.ht));
    M.shaft.setAttribute("d", `M${fp(j.butt)} L${fp(j.tip)}`);
    M.grip.setAttribute("d", `M${fp(j.butt)} L${fp([j.grip[0] + j.sp * 8 * s, j.grip[1] + j.cp * 8 * s])}`);
    const pr = [Math.cos(r.phi), -Math.sin(r.phi)], c = [j.tip[0] + pr[0] * 4.5 * s, j.tip[1] + pr[1] * 4.5 * s], half = 1.7 * s;
    M.chead.setAttribute("d", `M${fp([c[0] - pr[0] * half, c[1] - pr[1] * half])} L${fp([c[0] + pr[0] * half, c[1] + pr[1] * half])}`);
    M.head.setAttribute("cx", j.hd[0].toFixed(2)); M.head.setAttribute("cy", j.hd[1].toFixed(2)); M.head.setAttribute("r", (10 * s).toFixed(2));
    M.body.setAttribute("stroke-width", 6 * s); M.trail.setAttribute("stroke-width", 5.5 * s); M.shaft.setAttribute("stroke-width", 3 * s);
    M.chead.setAttribute("stroke-width", 13.6 * s); M.grip.setAttribute("stroke-width", 4.6 * s);
    return j;
  }
  // 게임의 헤드 잔상 호(알파 .38, 2.5pt, 0.13s): 빠른 구간에서만
  // 재생 속도(리그 초/광고 초): 슬로모·정지에서는 잔상 호를 거둔다 — 최근 5프레임 최대값이 선형으로 잦아든다
  const rate = (n, f) => (rigT(n, f + 0.5) - rigT(n, f - 0.5)) * FPS;
  const smearGain = (n, f) => { let g = 0; for (let k = 0; k < 5; k++) g = Math.max(g, clamp((rate(n, f - k) - 0.12) / 0.5) * (1 - k / 5)); return g; };
  function drawSmear(P, t, X, G, s) {
    const pts = [];
    for (let k = 0; k <= 14; k++) { const tt = t - 0.09 + 0.09 * k / 14; const r = sampleAt(P.S, tt); const j = joints(r, X, G, s); pts.push(j.tip); }
    const sp = Math.hypot(pts[14][0] - pts[13][0], pts[14][1] - pts[13][1]) / (0.09 / 14) / s;   // pt/s
    const on = clamp((sp - 250) / 250);
    P.smear.setAttribute("points", pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" "));
    P.smear.setAttribute("stroke-width", 2.5 * s); P.smear.setAttribute("opacity", on.toFixed(3));
  }

  function drawPanel(P, f, X, G, s) {
    const t = rigT(P.name, f), r = sampleAt(P.S, t);
    // 실제 지형선(조준 스틸에서 벡터화, 지면 기준 높이 pt) + 러프 틱 — 범위 밖은 수평으로 잇는다
    const TR = RIGS[P.name].terrain, ty = TR.y, n = ty.length;
    let d = `M${fp([X - 3000, G - ty[0] * s])}`;
    for (let k = 0; k < n; k += 2) d += ` L${fp([X + (TR.x0 + k * TR.dx) * s, G - ty[k] * s])}`;
    d += ` L${fp([X + 3000, G - ty[n - 1] * s])}`;
    P.ground.setAttribute("d", d); P.ground.setAttribute("stroke-width", (1.5 * s).toFixed(2));
    const yAt = (rx) => { const k = clamp(Math.round((rx - TR.x0) / TR.dx), 0, n - 1); return ty[k]; };
    P.rough.setAttribute("d", TR.ticks.map(([rx, hh]) => { const b = [X + rx * s, G - (yAt(rx) + 0.75) * s]; return `M${fp(b)} L${fp([b[0], b[1] - hh * s])}`; }).join(" "));
    P.rough.setAttribute("stroke-width", (0.9 * s).toFixed(2));
    // 티·공
    const b0 = [X + BALL[P.name][0] * s, G + BALL[P.name][1] * s];
    P.tee.setAttribute("d", `M${fp([b0[0] - 0.7 * s, G])} h${1.4 * s} v${-4 * s} h${-1.4 * s} Z M${fp([b0[0] - 2.6 * s, G - 4.6 * s])} h${5.2 * s} v${-1.1 * s} h${-5.2 * s} Z`);
    const tb = Math.max(0, t), dx = V_BALL * tb * Math.cos(LAUNCH), dy = V_BALL * tb * Math.sin(LAUNCH) - 0.5 * 9.8 * 3.2 * tb * tb * 0.35;
    const bp = [b0[0] + dx * s, b0[1] - dy * s];
    P.ball.setAttribute("cx", bp[0].toFixed(2)); P.ball.setAttribute("cy", bp[1].toFixed(2)); P.ball.setAttribute("r", (4.5 * s).toFixed(2));
    P.trailLine.setAttribute("x1", b0[0].toFixed(2)); P.trailLine.setAttribute("y1", b0[1].toFixed(2));
    P.trailLine.setAttribute("x2", bp[0].toFixed(2)); P.trailLine.setAttribute("y2", bp[1].toFixed(2)); P.trailLine.setAttribute("stroke-width", (1.1 * s).toFixed(2));
    const j = drawMan(P, r, X, G, s);
    drawSmear(P, t, X, G, s);
    P.smear.setAttribute("opacity", (+P.smear.getAttribute("opacity") * smearGain(P.name, f)).toFixed(3));
    return { t, r, j, b0 };
  }

  /* ── render(t) ── */
  function render(time) {
    const f = Math.round(time * FPS);
    // 무대 카메라 (마무리에서 한 번: 세 칸이 위로 물러난다)
    // 무대: 카메라 없음(칸마다 자기 프레이밍). 요약 뒤 칸 전체가 어둠으로 물러난다(12프레임)
    stage.style.opacity = (1 - smooth(seg(f, F_OUT[0], F_OUT[1]))).toFixed(3);

    // 3칸 확장 진행도
    const e = camEase(seg(f, F_EXP[0], F_EXP[1])) * (1 - camEase(seg(f, F_BACK[0], F_BACK[1] - 4)));
    const out = {};
    panels.forEach((P, i) => {
      let top = PY[i], hh = PH, X = SX, G = PY[i] + GL, s = SC;
      if (P.name === EXP) { top = lerp(PY[i], 0, e); hh = lerp(PH, 1920, e); X = lerp(SX, FF.X, e); G = lerp(PY[i] + GL, FF.G, e); s = lerp(SC, FF.S, e); }
      P.el.style.top = top.toFixed(2) + "px"; P.el.style.height = hh.toFixed(2) + "px"; P.el.style.zIndex = P.name === EXP ? 3 : 1;
      P.content.style.top = (-top).toFixed(2) + "px";
      out[P.name] = drawPanel(P, f, X, G, s);
      out[P.name].X = X; out[P.name].G = G; out[P.name].s = s;
      // 주인공 그림자: 훅·마무리는 셋 다 밝게, 본편은 한 칸만
      const [a0, a1] = SPOT[i];
      // 훅(셋 다 밝음) → 본편(한 칸만) → 마무리(셋 다): 전부 연속 함수로 이어 붙인다 (계단 없음)
      const hookMix = 1 - smooth(seg(f, 20, 30));
      let spot = smooth(seg(f, a0 - 4, a0 + 4)) * (P.name === EXP ? 1 : 1 - smooth(seg(f, a1 - 4, a1 + 4)));
      if (i === 0) spot = 1 - smooth(seg(f, a1 - 4, a1 + 4));   // 1칸은 훅에서 주인공을 그대로 넘겨받는다
      const back = smooth(seg(f, F_BACK[0], F_BACK[0] + 12));
      const lit = Math.max(hookMix, spot, back);
      P.shade.style.opacity = (0.64 * (1 - lit)).toFixed(3);
      // 임팩트 번쩍: 칸마다 공 자리 중심 흰 빛, f14 → f15 → 0 (2프레임)
      const fl = f === F_IMP ? 1 : f === F_IMP + 1 ? 0.38 : 0;
      const bx = out[P.name].b0[0], by = out[P.name].b0[1] - top;
      P.flash.style.background = `radial-gradient(circle at ${bx.toFixed(1)}px ${by.toFixed(1)}px, rgba(255,255,255,.34) 0px, rgba(255,255,255,.13) 160px, rgba(255,255,255,.04) 420px, rgba(255,255,255,0) 720px)`;
      P.flash.style.opacity = fl;
      // 한 단어: 주인공이 될 때 들어와 그대로 남는다(그림자와 함께 어두워짐). 3칸은 전체 화면 동안 비켜났다가 마무리에 돌아온다
      const wi = Sk((f - (a0 + 4)) / FPS, "calm");
      let wo = wi;
      if (P.name === EXP) wo = wi * (1 - smooth(seg(f, F_EXP[0], F_EXP[0] + 8))) + smooth(seg(f, F_BACK[1] - 10, F_BACK[1])) * (f >= F_BACK[0] ? 1 : 0);
      P.word.style.opacity = wo.toFixed(3);
      P.word.style.right = (1080 - WORD.right) + "px"; P.word.style.top = (PY[i] + WORD.dy + 16 * (1 - wi)).toFixed(2) + "px";
    });

    // 주석
    const fade = (a, b) => smooth(seg(f, a, a + 6)) * (1 - smooth(seg(f, b - 6, b)));
    { const o = out.jump, j = o.j, s = o.s, lift = Math.max(0, Math.min(o.r.p[2][1], o.r.p[3][1]));
      const x = o.X - 52 * s, g0 = o.G, g1 = o.G - lift * s;
      A.jl.setAttribute("d", `M${fp([x - 15, g0])} L${fp([x + 15, g0])} M${fp([x, g0])} L${fp([x, g1])} M${fp([x - 15, g1])} L${fp([x + 15, g1])}`);
      A.jt.setAttribute("x", (x - 18).toFixed(1)); A.jt.setAttribute("y", (g1 - 4).toFixed(1)); A.jt.textContent = `+${Math.round(lift)}px`;
      PN.jump.anno.setAttribute("opacity", (fade(40, SPOT[0][1]) * clamp(lift / 3)).toFixed(3));
      const peak = Math.max(...RIGS.jump.samples.filter((q) => q.t > -0.1 && q.t < 0.3).map((q) => Math.min(q.p[2][1], q.p[3][1])));
      if (o.t > 0.081) { A.jt.textContent = `+${Math.round(peak)}px`; const pk = o.G - peak * s;   // 정점 뒤엔 최고 높이를 남긴다
        A.jl.setAttribute("d", `M${fp([x - 15, g0])} L${fp([x + 15, g0])} M${fp([x, g0])} L${fp([x, pk])} M${fp([x - 15, pk])} L${fp([x + 15, pk])}`);
        A.jt.setAttribute("y", (pk - 4).toFixed(1)); PN.jump.anno.setAttribute("opacity", fade(40, SPOT[0][1]).toFixed(3)); }
    }
    { const o = out.twirl, s = o.s, tw = RIGS.twirl.twirl, r0 = sampleAt(RIGS.twirl.samples, tw[0]);
      const pts = [], g = o.j.grip, L = o.r.len * s;
      for (let ph = r0.phi; ph <= o.r.phi + 1e-6; ph += 0.06) pts.push([g[0] + Math.sin(ph) * L, g[1] + Math.cos(ph) * L]);
      A.ta.setAttribute("points", pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" "));
      const sw = Math.max(0, o.r.phi - r0.phi) * 180 / Math.PI;
      A.tt.textContent = `${Math.min(360, Math.round(sw / 10) * 10)}°`;
      A.tt.setAttribute("x", (g[0] + L * 0.78).toFixed(1)); A.tt.setAttribute("y", (g[1] - L * 0.78).toFixed(1));
      PN.twirl.anno.setAttribute("opacity", (fade(166, F_EXP[0] + 4) * clamp(sw / 20)).toFixed(3));
    }
    { const o = out.lock, j = o.j, dx = j.grip[0] - j.sh[0], dy = j.grip[1] - j.sh[1], L = Math.hypot(dx, dy), ux = dx / L, uy = dy / L;
      const a = [j.sh[0] - ux * 34, j.sh[1] - uy * 34], b = [j.grip[0] + ux * 34, j.grip[1] + uy * 34], nx = -uy * 14, ny = ux * 14;
      const tick = (p) => `M${fp([p[0] - nx, p[1] - ny])} L${fp([p[0] + nx, p[1] + ny])}`;
      A.ll.setAttribute("d", `M${fp(a)} L${fp(b)} ${tick(j.sh)} ${tick(j.el)} ${tick(j.grip)}`);
      const ang = (p, c, q) => { const v1 = [p[0] - c[0], p[1] - c[1]], v2 = [q[0] - c[0], q[1] - c[1]]; return Math.acos(clamp((v1[0] * v2[0] + v1[1] * v2[1]) / (Math.hypot(...v1) * Math.hypot(...v2)), -1, 1)) * 180 / Math.PI; };
      A.lt.textContent = `${Math.round(ang(j.sh, j.el, j.grip))}°`;
      A.lt.setAttribute("x", (j.el[0] + 4).toFixed(1)); A.lt.setAttribute("y", (j.el[1] + 46).toFixed(1));
      PN.lock.anno.setAttribute("opacity", fade(114, SPOT[1][1]).toFixed(3));
    }

    // 3칸: 벡터 → 같은 자세 실캡처 교차, 관절선 그리기
    const P3 = PN[EXP], o3 = out[EXP];
    const xc = smooth(seg(f, F_X[0], F_X[1])) * (1 - smooth(seg(f, F_BACK[0], F_BACK[0] + 10)));
    const s3 = o3.s;
    P3.cap.style.left = (o3.X + CAP.rel[0] * s3).toFixed(2) + "px";
    P3.cap.style.top = (o3.G + CAP.rel[1] * s3).toFixed(2) + "px";
    P3.cap.style.width = (CAP.size[0] * s3).toFixed(2) + "px"; P3.cap.style.height = (CAP.size[1] * s3).toFixed(2) + "px";
    const dimCap = 1 - 0.58 * smooth(seg(f, F_X[1] + 2, F_X[1] + 14));
    P3.cap.style.opacity = (xc * dimCap).toFixed(3); P3.cap.style.display = xc > 0.001 ? "block" : "none";
    P3.man.setAttribute("opacity", (1 - xc).toFixed(3));
    P3.ground.setAttribute("opacity", (1 - xc).toFixed(3)); P3.rough.setAttribute("opacity", (1 - xc).toFixed(3));
    const away = 1 - smooth(seg(f, F_EXP[0], F_X[0])) * (1 - smooth(seg(f, F_BACK[0], F_BACK[1])));   // 공·궤적은 교차 전에 비켜난다(실캡처 궤적선과 겹치지 않게)
    for (const k of ["ball", "trailLine", "tee"]) P3[k].setAttribute("opacity", Math.min(1 - xc, away).toFixed(3));
    P3.smear.setAttribute("opacity", (+P3.smear.getAttribute("opacity") * (1 - xc)).toFixed(3));
    drawRig(f, o3);
    const ci = Sk((f - (RIGF0 + 10)) / FPS, "calm"), co = 1 - smooth(seg(f, F_BACK[0] - 2, F_BACK[0] + 6));
    ffcap.style.opacity = (ci * co).toFixed(3); ffcap.style.transform = `translateY(${(14 * (1 - ci)).toFixed(2)}px)`;


    // 마무리 글자: A·B → (마스크 밀어 올리기) 엔드카드
    const sw = smooth(seg(f, F_SWAP, F_SWAP + 7));
    const inL = (el, f0, base) => { const k = Sk((f - f0) / FPS, "calm"); el.style.opacity = (k * (1 - sw)).toFixed(3); el.style.transform = `translateY(${(18 * (1 - k) - 70 * sw).toFixed(2)}px)`; };
    inL(LA, F_LA); inL(LB, F_LB);
    const inE = (el, f0) => { const k = Sk((f - f0) / FPS, "calm"); el.style.opacity = k.toFixed(3); el.style.transform = `translateY(${(40 * (1 - k)).toFixed(2)}px)`; };
    inE(EW, F_SWAP + 3); inE(EM, F_SWAP + 10); inE(EU, F_SWAP + 16);
    return out;
  }

  // 관절선: 뼈마다 부모 관절에서 뻗어 나가며 그려지고, 관절 점은 뼈가 닿을 때 잡힌다
  const BONES = [["hip", "sh", 0], ["hip", "k1", 4], ["k1", "f1", 8], ["hip", "k2", 4], ["k2", "f2", 8], ["sh", "el", 6], ["el", "grip", 10], ["sh", "et", 6], ["et", "ht", 10], ["grip", "tip", 14]];
  const JOINTS = { hip: 0, sh: 4, k1: 8, k2: 8, f1: 12, f2: 12, el: 10, et: 10, grip: 14, ht: 14 };
  const rigEls = { bones: [], joints: {}, head: null };
  function buildRig() {
    const g = PN[EXP].rig;
    for (const [a, b] of BONES) { const l = mk("line", { stroke: b === "tip" ? "rgba(214,215,210,.9)" : "#F4F4F1", "stroke-width": b === "tip" ? 2.6 : 3.4, "stroke-linecap": "round" }); if (b === "tip") l.setAttribute("stroke-dasharray", "10 9"); g.appendChild(l); rigEls.bones.push(l); }
    rigEls.head = mk("circle", { fill: "none", stroke: "#F4F4F1", "stroke-width": 3, "stroke-dasharray": "4 8" }); g.appendChild(rigEls.head);
    for (const k in JOINTS) { const c = mk("circle", { fill: "rgb(40,40,40)", stroke: "#F4F4F1", "stroke-width": 3.2 }); g.appendChild(c); rigEls.joints[k] = c; }
  }
  buildRig();
  function drawRig(f, o) {
    const g = PN[EXP].rig, j = o.j, s = o.s;
    const vis = f >= RIGF0 - 1 && f < F_BACK[0] + 8;
    g.setAttribute("opacity", vis ? (1 - smooth(seg(f, F_BACK[0] - 2, F_BACK[0] + 6))).toFixed(3) : 0);
    if (!vis) return;
    BONES.forEach(([a, b, d0], k) => {
      const l = rigEls.bones[k], p = j[a], q = j[b], u = smooth(seg(f, RIGF0 + d0, RIGF0 + d0 + 8));
      l.setAttribute("x1", p[0].toFixed(2)); l.setAttribute("y1", p[1].toFixed(2));
      l.setAttribute("x2", lerp(p[0], q[0], u).toFixed(2)); l.setAttribute("y2", lerp(p[1], q[1], u).toFixed(2));
      l.setAttribute("opacity", u > 0.001 ? 1 : 0);
    });
    const hu = smooth(seg(f, RIGF0 + 12, RIGF0 + 20));
    rigEls.head.setAttribute("cx", j.hd[0].toFixed(2)); rigEls.head.setAttribute("cy", j.hd[1].toFixed(2)); rigEls.head.setAttribute("r", (10 * s).toFixed(2)); rigEls.head.setAttribute("opacity", hu.toFixed(3));
    for (const k in JOINTS) { const c = rigEls.joints[k], d0 = JOINTS[k] + (k === "hip" ? 0 : 6), sc = Sk((f - (RIGF0 + d0)) / FPS, "settle");
      c.setAttribute("cx", j[k][0].toFixed(2)); c.setAttribute("cy", j[k][1].toFixed(2)); c.setAttribute("r", (8.5 * clamp(sc, 0, 1.2)).toFixed(2)); }
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;

  // ?audit=1 : 3프레임 간격으로 글자·스틱맨 화면 사각형을 모아 <pre id="audit">에 JSON (scripts/qa.py가 읽는다)
  function audit() {
    const res = { frames: [] };
    const vis = (e) => { let o = 1, n = e; while (n && n !== document.body) { const c = getComputedStyle(n); if (c.visibility === "hidden" || c.display === "none") return 0; o *= parseFloat(c.opacity); n = n.parentElement; } return o; };
    const textRects = (e) => { const outR = []; const rg = document.createRange(); const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT);
      let n; while ((n = w.nextNode())) { if (!n.textContent.trim()) continue; rg.selectNodeContents(n); for (const r of rg.getClientRects()) outR.push([r.left, r.top, r.right, r.bottom].map(Math.round)); } return outR; };
    const crit = [["word1", panels[0].word], ["word2", panels[1].word], ["word3", panels[2].word], ["ffcap", ffcap], ["lineA", LA], ["lineB", LB], ["wordmark", EW], ["meta", EM], ["url", EU]];
    for (let f = 0; f < 450; f += 3) {
      const o = render(f / FPS); const fr = { f, items: [] };
      for (const [name, el] of crit) { const v = vis(el); if (v > 0.05) for (const r of textRects(el)) fr.items.push({ name, o: +v.toFixed(2), r }); }
      for (const P of panels) { if (P.name === EXP && +P.man.getAttribute("opacity") < 0.05) continue;
        const b = P.man.getBoundingClientRect(), pad = 6 * (P.name === EXP ? o[EXP].s : SC) * 0.5 * (b.width ? 1 : 0);
        if (b.width) fr.items.push({ name: "man-" + P.name, o: 1, r: [b.left - pad, b.top - pad, b.right + pad, b.bottom + pad].map(Math.round) }); }
      res.frames.push(fr);
    }
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(res); document.body.appendChild(pre);
  }
  // 감사 모드는 이미지가 필요 없다(헤드리스 덤프가 디코드를 기다리지 않아 감사가 빠질 수 있었다)
  Promise.all([document.fonts.ready, q.has("audit") ? null : PN[EXP].cap.decode().catch(() => null)]).then(() => { if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); window.__ready = true; });
})();
