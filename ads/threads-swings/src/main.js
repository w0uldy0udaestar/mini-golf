/* mini-golf 스레드 T4 「스윙 3종」 — 세로 1080×1920, 15초 (450프레임 @30fps) · 3차: 포스터 컬러 + 모션 기법
 *
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). GSAP 타임라인은 재생 헤드 역할만. Math.random·Date·네트워크 없음.
 * 스틱맨은 전부 실제 리그 덤프(60Hz, data/rigs.js)를 게임 StickmanNode 규칙(선 6·트레일 팔 5.5·샤프트 3·머리 r10 + 어두운 림)대로 SVG로 그린다.
 * 칸 색: 뛴다 민트 · 고정 주황 · 돌린다 보라(단색, 그라데이션 없음). 선·공·지형은 흰색 100%, 단어는 칸 색과 대비가 큰 쪽(검정/흰색).
 *
 * 모션 기법
 *   ① 히트스톱 + 흔들림 + 반전: f14 동시 임팩트에서 2프레임 정지, 세 칸 함께 ±10px 감쇠 흔들림(10프레임), 칸이 1프레임 흰색으로 반전
 *   ② 속도 램프: 칸마다 속도 키(0 · 0.1배 · 1배)를 6프레임 smoothstep으로 잇고 적분해 리그 시각을 만든다
 *   ③ 키네틱 타이포: 단어가 칸 밖 오른쪽에서 날아들어 −4°→0 회전과 함께 스프링으로 멈춘다
 *   ④ 줌 펀치: 3칸이 back-out(오버슈트) 12프레임으로 화면을 채운다
 *   ⑤ 관절선 stroke reveal: 힙에서 바깥으로 빠르고 굵게(검정 선·점)
 *   ⑥ 트립틱 복귀: 1칸 위에서 낙하, 2칸 오른쪽에서, 3칸은 화면 크기에서 아래 자리로 → 이어서 칸들이 엇갈려 빠지며 흰 바탕
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
  const inOut = bez(0.65, 0, 0.35, 1);
  const easeIn = (u) => { u = clamp(u); return u * u * u; };
  const backOut = (u, s) => { u = clamp(u); const v = u - 1; return 1 + (s + 1) * v * v * v + s * v * v; };
  const SPR = { calm: [0.78, 2.7], settle: [0.55, 3.0], land: [0.74, 3.2], snap: [0.5, 4.4] };
  const step = (t, z, f) => { const w = 2 * Math.PI * f, d = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(d * t) + z * w / d * Math.sin(d * t)); };
  const Sk = (t, n) => { if (t <= 0) return 0; const [z, f] = SPR[n]; const D = 6 / (z * 2 * Math.PI * f); return t >= D ? 1 : step(t, z, f) / step(D, z, f); };

  /* ── 배치 (px) ── */
  const PH = 484, PY = [124, 618, 1112];      // 세 칸: y 124–1596 (세로 안전 영역 100–1620), 칸 사이 10px
  const GL = 466, SC = 3.85, SX = 394;         // 칸 안 지면선 y · pt당 px(몸 키 341px = 칸 70%) · 스틱 x
  const FF = { X: 608, G: 1150, S: CAP.scale }; // 3칸 전체 화면: 몸 키 926px (실캡처도 같은 배율)
  const ORDER = ["jump", "lock", "twirl"];
  const WORDS = ["뛴다", "고정", "돌린다"];
  const COL = { jump: "#22CFA0", lock: "#FF7A1C", twirl: "#6F45FF" };    // 민트 · 주황 · 보라 (포스터 단색)
  const INK = { jump: "#0A0A0A", lock: "#0A0A0A", twirl: "#FFFFFF" };    // 칸 색과 대비가 큰 쪽 (민트·주황 = 검정, 보라 = 흰색)
  const RIM = "rgba(0,0,0,.26)";                                         // 게임 StickmanNode의 림(흰 선 바깥 어두운 테두리)
  const WORD = { right: 916, dy: 34, size: 128 };
  const EXP = "twirl";
  const F_IMP = 14;
  const SPOT = [[24, 84], [84, 140], [140, 212]];
  const F_WORD = [26, 86, 142];
  const F_EXP = [212, 224], F_X = [224, 228], RIGF0 = 234;   // 벡터↔실캡처는 같은 자세라 4프레임에 바꾼다(겹친 반투명 유령을 줄인다)
  const F_REC = [276, 300], F_OUT = [326, 340], F_LA = 340, F_LB = 350, F_SWAP = 384;

  // ② 속도 램프: [프레임, 배속] 키 사이를 smoothstep(6프레임)으로 잇는다. 임팩트 f14–16은 히트스톱(0배)
  const SPEED = {
    jump: [[14, 0], [16, 0], [17, 0.1], [48, 0.1], [54, 1], [74, 1], [80, 0]],
    lock: [[14, 0], [16, 0], [17, 0.1], [22, 0.1], [28, 0], [84, 0], [85, 0.1], [104, 0.1], [110, 1], [118, 1], [124, 0]],
    twirl: [[14, 0], [16, 0], [17, 0.1], [22, 0.1], [28, 0], [140, 0], [146, 1], [168, 1], [174, 0.1], [188, 0.1], [194, 1], [204, 1], [210, 0]],
  };
  const speedAt = (keys, f) => { if (f <= keys[0][0]) return keys[0][1];
    for (let i = 1; i < keys.length; i++) if (f <= keys[i][0]) { const [f0, v0] = keys[i - 1], [f1, v1] = keys[i]; return v0 + (v1 - v0) * smooth((f - f0) / (f1 - f0)); }
    return keys[keys.length - 1][1]; };
  const TT = {};   // 임팩트 이후 리그 시각 표 (프레임마다 8분할 적분 — 상수만 보므로 결정적)
  for (const n of ORDER) { const tb = new Float64Array(462); let t = 0;
    for (let f = 14; f < 461; f++) { for (let k = 0; k < 8; k++) t += speedAt(SPEED[n], f + (k + 0.5) / 8) / FPS / 8; tb[f + 1] = t; } TT[n] = tb; }
  const rigT = (n, f) => {
    if (f <= F_IMP) return (f - F_IMP) / FPS;                       // 훅: 실속도
    if (n === EXP && f >= F_EXP[0]) return CAP.rigT;                 // 트월 뒤 정지 자세 = 실캡처 자세 (차이 0.1pt)
    const i = Math.min(460, Math.floor(f)), u = f - Math.floor(f);
    return lerp(TT[n][Math.max(14, i)], TT[n][Math.min(461, i + 1)], u);
  };

  /* ── 리그 표본 보간 ── */
  function sampleAt(S, t) {
    let lo = 0, hi = S.length - 1;
    if (t <= S[0].t) return S[0]; if (t >= S[hi].t) return S[hi];
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (S[mid].t <= t) lo = mid; else hi = mid; }
    const a = S[lo], b = S[hi], u = (t - a.t) / (b.t - a.t);
    return { p: a.p.map((pa, k) => [lerp(pa[0], b.p[k][0], u), lerp(pa[1], b.p[k][1], u)]), h: [lerp(a.h[0], b.h[0], u), lerp(a.h[1], b.h[1], u)],
      phi: lerp(a.phi, b.phi, u), len: lerp(a.len, b.len, u), butt: lerp(a.butt, b.butt, u), c: u < 0.5 ? a.c : b.c, m: u < 0.5 ? a.m : b.m };
  }
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
  const FLAG = (w, hh) => `<svg width="${w}" height="${hh}" viewBox="0 0 14 16"><ellipse cx="3.2" cy="15" rx="3.1" ry="0.9" fill="#9A9A96"/><line x1="3.2" y1="1.2" x2="3.2" y2="14.8" stroke="#111111" stroke-width="1.5" stroke-linecap="round"/><path d="M3.9 1.5 L12.6 4.4 L3.9 7.3 Z" fill="#E5322D"/></svg>`;

  const PARTS = ["trail", "body", "shaft", "chead", "grip", "head"];
  const panels = ORDER.map((name, i) => {
    const el = h("div", "panel"); el.style.background = COL[name]; stage.appendChild(el);
    const content = h("div", "content"); el.appendChild(content);
    const svg = mk("svg", { width: 1080, height: 1920 }); content.appendChild(svg);
    let cap = null;
    if (name === EXP) { cap = h("img", "cap"); cap.src = CAP.file; content.insertBefore(cap, svg); }
    const groundRim = mk("path", { fill: "none", stroke: RIM, "stroke-linecap": "round", "stroke-linejoin": "round" });
    const ground = mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-linecap": "round", "stroke-linejoin": "round" });
    const rough = mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-linecap": "round" });
    const trailLine = mk("line", { stroke: "#FFFFFF", "stroke-linecap": "round" });
    const smear = mk("polyline", { fill: "none", stroke: "#FFFFFF", "stroke-linecap": "round", "stroke-linejoin": "round" });
    const tee = mk("path", { fill: "#FFFFFF" });
    const ball = mk("circle", { fill: "#FFFFFF", stroke: "#0A0A0A" });
    const anno = mk("g", { opacity: 0 });
    const man = mk("g", {}), rimG = mk("g", {}), mainG = mk("g", {});
    const mkPart = (k, col) => k === "head" ? mk("circle", { fill: col }) : mk("path", { fill: "none", stroke: col, "stroke-linecap": "round", "stroke-linejoin": "round" });
    const R = {}, M = {};
    for (const k of PARTS) { R[k] = mkPart(k, RIM); rimG.appendChild(R[k]); M[k] = mkPart(k, "#FFFFFF"); mainG.appendChild(M[k]); }
    man.appendChild(rimG); man.appendChild(mainG);
    for (const e of [groundRim, ground, rough, trailLine, tee, ball, anno, smear, man]) svg.appendChild(e);
    const rig = mk("g", { opacity: 0 }); svg.appendChild(rig);
    const word = h("div", "word", WORDS[i]); word.style.fontSize = WORD.size + "px"; word.style.letterSpacing = (-0.035 * WORD.size) + "px"; word.style.color = INK[name];
    content.appendChild(word);
    const shade = h("div", "shade"); el.appendChild(shade);
    return { name, i, el, content, svg, cap, groundRim, ground, rough, trailLine, smear, tee, ball, anno, man, rimG, R, M, rig, word, shade, S: RIGS[name].samples };
  });
  const PN = Object.fromEntries(panels.map((P) => [P.name, P]));

  // 그림 표식(숫자 라벨 없음): 뛴다 = 발밑 치수선, 고정 = 어깨–그립 직선 자, 돌린다 = 헤드가 그린 점선 원
  const A = {};
  A.jl = mk("path", { fill: "none", stroke: INK.jump, "stroke-width": 6, "stroke-linecap": "round" }); PN.jump.anno.appendChild(A.jl);
  A.ll = mk("path", { fill: "none", stroke: INK.lock, "stroke-width": 6, "stroke-linecap": "round" }); PN.lock.anno.appendChild(A.ll);
  A.ta = mk("polyline", { fill: "none", stroke: INK.twirl, "stroke-width": 6, "stroke-dasharray": "4 16", "stroke-linecap": "round" }); PN.twirl.anno.appendChild(A.ta);

  // 전체 화면 캡션 (보라 위 흰 글자)
  const ffcap = h("div", "ffcap", "프로 영상에서<br>뽑은 관절"); ffcap.style.cssText += ";left:96px;top:1236px;font-size:104px;letter-spacing:-3.4px;color:#FFFFFF;transform-origin:0 100%";
  root.appendChild(ffcap);

  // 마무리 글자층 (흰 바탕 · 검정 글자)
  const closing = h("div"); closing.id = "closing"; root.appendChild(closing);
  const maskEl = h("div", "mask"); maskEl.style.cssText = "left:0;top:690px;width:1080px;height:560px"; closing.appendChild(maskEl);   // 왼쪽 오버슈트가 잘리지 않게 마스크는 화면 폭
  const line = (cls, html, top, size, extra = "") => { const e = h("div", "ln " + cls, html); e.style.cssText += `;left:90px;top:${top}px;font-size:${size}px;transform-origin:0 100%;${extra}`; maskEl.appendChild(e); return e; };
  const LA = line("la", "스윙 스타일 3가지", 40, 104, "letter-spacing:-3.4px;color:#0A0A0A");
  const LB = line("lb", `${FLAG(56, 64)}<span style="margin-left:18px">메뉴에서 고른다</span>`, 196, 72, "letter-spacing:-1.8px;color:#0A0A0A");
  const EW = line("wm", "mini-golf", 40, 128, "letter-spacing:-4.4px;color:#0A0A0A");
  const EM = line("meta", "macOS 메뉴바 앱<br>무료 · 오픈소스", 200, 64, "letter-spacing:-1.4px;color:#2A2A2A");
  const EU = line("url", "github.com/w0uldy0udaestar/mini-golf", 380, 38, "letter-spacing:-0.4px;color:#2A2A2A");

  /* ── 공 자리: 임팩트 표본의 헤드 중심 ── */
  const BALL = {};
  for (const n of ORDER) { const r0 = sampleAt(RIGS[n].samples, 0); const j = joints(r0, 0, 0, 1); BALL[n] = [j.tip[0] + Math.cos(r0.phi) * 4.5, -5.6]; }
  const V_BALL = 230, LAUNCH = 13 * Math.PI / 180;

  /* ── 그리기 ── */
  const W = { trail: 5.5, body: 6, shaft: 3, chead: 13.6, grip: 4.6, head: 10 }, WR = { trail: 7.7, body: 8.4, shaft: 5.2, chead: 15.8, grip: 6.8, head: 11.2 };
  function drawMan(P, r, X, G, s) {
    const j = joints(r, X, G, s);
    const ctl = [(j.sh[0] + j.hip[0]) / 2 - 0.8 * s, (j.sh[1] + j.hip[1]) / 2];
    const arm = (a, e, b) => r.c ? `M${fp(a)} Q${fp(e)} ${fp(b)}` : `M${fp(a)} L${fp(e)} L${fp(b)}`;
    const pr = [Math.cos(r.phi), -Math.sin(r.phi)], c = [j.tip[0] + pr[0] * 4.5 * s, j.tip[1] + pr[1] * 4.5 * s], half = 1.7 * s;
    const D = {
      body: `M${fp(j.sh)} Q${fp(ctl)} ${fp(j.hip)} M${fp(j.hip)} L${fp(j.k1)} L${fp(j.f1)} M${fp(j.hip)} L${fp(j.k2)} L${fp(j.f2)} ${arm(j.sh, j.el, j.grip)}`,
      trail: arm(j.sh, j.et, j.ht), shaft: `M${fp(j.butt)} L${fp(j.tip)}`,
      grip: `M${fp(j.butt)} L${fp([j.grip[0] + j.sp * 8 * s, j.grip[1] + j.cp * 8 * s])}`,
      chead: `M${fp([c[0] - pr[0] * half, c[1] - pr[1] * half])} L${fp([c[0] + pr[0] * half, c[1] + pr[1] * half])}`,
    };
    for (const [set, wid] of [[P.R, WR], [P.M, W]]) for (const k of PARTS) {
      const e = set[k];
      if (k === "head") { e.setAttribute("cx", j.hd[0].toFixed(2)); e.setAttribute("cy", j.hd[1].toFixed(2)); e.setAttribute("r", (wid.head * s).toFixed(2)); }
      else { e.setAttribute("d", D[k]); e.setAttribute("stroke-width", (wid[k] * s).toFixed(2)); }
    }
    return j;
  }
  const rate = (n, f) => (rigT(n, f + 0.5) - rigT(n, f - 0.5)) * FPS;
  const smearGain = (n, f) => { let g = 0; for (let k = 0; k < 5; k++) g = Math.max(g, clamp((rate(n, f - k) - 0.12) / 0.5) * (1 - k / 5)); return g; };
  function drawSmear(P, t, X, G, s, f) {
    const pts = [];
    for (let k = 0; k <= 14; k++) { const tt = t - 0.09 + 0.09 * k / 14; pts.push(joints(sampleAt(P.S, tt), X, G, s).tip); }
    const sp = Math.hypot(pts[14][0] - pts[13][0], pts[14][1] - pts[13][1]) / (0.09 / 14) / s;
    P.smear.setAttribute("points", pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" "));
    P.smear.setAttribute("stroke-width", (2.8 * s).toFixed(2));
    P.smear.setAttribute("opacity", (0.6 * clamp((sp - 250) / 250) * smearGain(P.name, f)).toFixed(3));
  }
  function drawPanel(P, f, X, G, s, inv) {
    const t = rigT(P.name, f), r = sampleAt(P.S, t);
    const fg = inv ? COL[P.name] : "#FFFFFF";                          // ① 반전 프레임: 칸은 흰색, 선은 칸 색
    P.el.style.background = inv ? "#FFFFFF" : COL[P.name];
    for (const k of PARTS) { if (k === "head") P.M[k].setAttribute("fill", fg); else P.M[k].setAttribute("stroke", fg); }
    P.rimG.setAttribute("opacity", inv ? 0 : 1);
    for (const e of [P.ground, P.rough, P.trailLine, P.smear]) e.setAttribute("stroke", fg);
    P.tee.setAttribute("fill", fg); P.ball.setAttribute("fill", fg); P.groundRim.setAttribute("opacity", inv ? 0 : 1);
    // 실제 지형선 + 러프 틱
    const TR = RIGS[P.name].terrain, ty = TR.y, n = ty.length;
    let d = `M${fp([X - 3000, G - ty[0] * s])}`;
    for (let k = 0; k < n; k += 2) d += ` L${fp([X + (TR.x0 + k * TR.dx) * s, G - ty[k] * s])}`;
    d += ` L${fp([X + 3000, G - ty[n - 1] * s])}`;
    P.ground.setAttribute("d", d); P.ground.setAttribute("stroke-width", (1.8 * s).toFixed(2));
    P.groundRim.setAttribute("d", d); P.groundRim.setAttribute("stroke-width", (3.0 * s).toFixed(2));
    const yAt = (rx) => ty[clamp(Math.round((rx - TR.x0) / TR.dx), 0, n - 1)];
    P.rough.setAttribute("d", TR.ticks.map(([rx, hh]) => { const b = [X + rx * s, G - (yAt(rx) + 0.75) * s]; return `M${fp(b)} L${fp([b[0], b[1] - hh * s])}`; }).join(" "));
    P.rough.setAttribute("stroke-width", (1.1 * s).toFixed(2));
    // 티·공·궤적
    const b0 = [X + BALL[P.name][0] * s, G + BALL[P.name][1] * s];
    P.tee.setAttribute("d", `M${fp([b0[0] - 0.7 * s, G])} h${1.4 * s} v${-4 * s} h${-1.4 * s} Z M${fp([b0[0] - 2.6 * s, G - 4.6 * s])} h${5.2 * s} v${-1.1 * s} h${-5.2 * s} Z`);
    const tb = Math.max(0, t), dx = V_BALL * tb * Math.cos(LAUNCH), dy = V_BALL * tb * Math.sin(LAUNCH) - 0.5 * 9.8 * 3.2 * tb * tb * 0.35;
    const bp = [b0[0] + dx * s, b0[1] - dy * s];
    P.ball.setAttribute("cx", bp[0].toFixed(2)); P.ball.setAttribute("cy", bp[1].toFixed(2)); P.ball.setAttribute("r", (4.6 * s).toFixed(2)); P.ball.setAttribute("stroke-width", (0.9 * s).toFixed(2));
    P.trailLine.setAttribute("x1", b0[0].toFixed(2)); P.trailLine.setAttribute("y1", b0[1].toFixed(2));
    P.trailLine.setAttribute("x2", bp[0].toFixed(2)); P.trailLine.setAttribute("y2", bp[1].toFixed(2)); P.trailLine.setAttribute("stroke-width", (1.2 * s).toFixed(2));
    const j = drawMan(P, r, X, G, s);
    drawSmear(P, t, X, G, s, f);
    return { t, r, j, b0, X, G, s };
  }

  // ③ 키네틱 타이포: 칸 밖 오른쪽에서 날아들어 −4°→0, 스프링으로 멈춘다 (k = 착지 진행도)
  const kin = (f, f0, dist = 760) => { const k = Sk((f - f0) / FPS, "land"); return { k, tx: dist * (1 - k), rot: -4 * (1 - k), on: f >= f0 }; };   // 오버슈트 약 3%

  /* ── render(t) ── */
  let AUD = null;   // 감사용: 이번 프레임에 '멈춘' 요소
  function render(time) {
    const f = Math.round(time * FPS);
    AUD = { words: [false, false, false], men: true, ff: false, closing: false };
    // ① 흔들림: f14부터 10프레임, ±10px 감쇠 (세 칸 함께, 2D 이동만)
    const kS = f - F_IMP;
    let sx = 0, sy = 0;
    if (kS >= 0 && kS < 10) { const amp = 10 * Math.pow(1 - kS / 10, 1.4); sx = amp * Math.sin(kS * 2.3 + 1.2); sy = amp * Math.cos(kS * 3.1 + 0.4) * 0.8; AUD.men = false; }
    stage.style.transform = `translate(${sx.toFixed(2)}px,${sy.toFixed(2)}px)`;
    const inv = f === F_IMP;

    // ④ 줌 펀치(확장) · 복귀: 3칸 진행도 e (오버슈트 허용), 잘림 사각형은 0~1로
    const eIn = backOut(seg(f, F_EXP[0], F_EXP[1]), 1.6);
    const eBack = inOut(seg(f, F_REC[0], F_REC[0] + 20));
    const e = f < F_EXP[0] ? 0 : (f < F_REC[0] ? eIn : 1 - eBack);
    const out = {};
    panels.forEach((P, i) => {
      let top = PY[i], hh = PH, X = SX, G = PY[i] + GL, s = SC, ox = 0, oy = 0;
      if (P.name === EXP) { const ec = clamp(e); top = lerp(PY[i], 0, ec); hh = lerp(PH, 1920, ec); X = lerp(SX, FF.X, e); G = lerp(PY[i] + GL, FF.G, e); s = lerp(SC, FF.S, e); }
      else if (f >= F_EXP[1] + 2) {
        // ⑥ 복귀: 1칸 위에서 낙하, 2칸 오른쪽에서 (전체 화면 동안은 화면 밖에서 대기 — 3칸 뒤라 안 보인다)
        if (i === 0) oy = -(PY[0] + PH + 40) * (1 - Sk((f - (F_REC[0] + 4)) / FPS, "settle"));
        if (i === 1) ox = 1120 * (1 - Sk((f - (F_REC[0] + 8)) / FPS, "settle"));
      }
      // ⑥ 퇴장: 칸들이 엇갈려 빠지며 흰 바탕을 드러낸다
      const go = easeIn(seg(f, F_OUT[0] + 2 * i, F_OUT[0] + 2 * i + 10));
      ox += (i === 1 ? 1 : -1) * 1120 * go;
      if (f >= F_REC[0] && f < F_REC[0] + 34) AUD.men = false;
      if (f >= F_OUT[0]) AUD.men = false;
      P.el.style.top = top.toFixed(2) + "px"; P.el.style.height = hh.toFixed(2) + "px"; P.el.style.zIndex = P.name === EXP ? 3 : 1;
      P.el.style.transform = `translate(${ox.toFixed(2)}px,${oy.toFixed(2)}px)`;
      P.content.style.top = (-top).toFixed(2) + "px";
      out[P.name] = drawPanel(P, f, X, G, s, inv);
      // 주인공 아닌 칸은 흰 막을 얇게 씌워 물러나게(어둡게 하지 않는다)
      const [a0, a1] = SPOT[i];
      const hookMix = 1 - smooth(seg(f, 20, 26));
      let spot = smooth(seg(f, a0 - 3, a0 + 3)) * (P.name === EXP ? 1 : 1 - smooth(seg(f, a1 - 3, a1 + 3)));
      if (i === 0) spot = 1 - smooth(seg(f, a1 - 3, a1 + 3));
      const lit = Math.max(hookMix, spot, smooth(seg(f, F_REC[0], F_REC[0] + 8)));
      P.shade.style.opacity = (0.45 * (1 - lit)).toFixed(3);
      // ③ 단어
      const w0 = (P.name === EXP && f >= F_EXP[0]) ? F_REC[0] + 14 : F_WORD[i];
      const kw = kin(f, w0);
      const hideExp = P.name === EXP && f >= F_EXP[0] && f < F_REC[0] + 14;
      P.word.style.opacity = kw.on && !hideExp ? 1 : 0;
      P.word.style.right = (1080 - WORD.right) + "px"; P.word.style.top = (PY[i] + WORD.dy) + "px";
      P.word.style.transform = `translateX(${kw.tx.toFixed(2)}px) rotate(${kw.rot.toFixed(3)}deg)`;
      AUD.words[i] = kw.on && !hideExp && Math.abs(kw.k - 1) < 0.015 && ox === 0 && oy === 0;
    });

    // 그림 표식 (주인공 구간에만)
    const fade = (a, b) => smooth(seg(f, a, a + 5)) * (1 - smooth(seg(f, b - 5, b)));
    { const o = out.jump, s = o.s, x = o.X - 52 * s, g0 = o.G;
      const peak = Math.max(...RIGS.jump.samples.filter((q2) => q2.t > -0.1 && q2.t < 0.3).map((q2) => Math.min(q2.p[2][1], q2.p[3][1])));
      const lift = o.t > 0.081 ? peak : Math.max(0, Math.min(o.r.p[2][1], o.r.p[3][1])), g1 = g0 - lift * s;
      A.jl.setAttribute("d", `M${fp([x - 18, g0])} L${fp([x + 18, g0])} M${fp([x, g0])} L${fp([x, g1])} M${fp([x - 18, g1])} L${fp([x + 18, g1])}`);
      PN.jump.anno.setAttribute("opacity", (fade(30, SPOT[0][1]) * clamp(lift / 3)).toFixed(3)); }
    { const o = out.lock, j = o.j, dx = j.grip[0] - j.sh[0], dy = j.grip[1] - j.sh[1], L = Math.hypot(dx, dy), ux = dx / L, uy = dy / L;
      const a = [j.sh[0] - ux * 40, j.sh[1] - uy * 40], b = [j.grip[0] + ux * 40, j.grip[1] + uy * 40], nx = -uy * 16, ny = ux * 16;
      const tick = (p) => `M${fp([p[0] - nx, p[1] - ny])} L${fp([p[0] + nx, p[1] + ny])}`;
      A.ll.setAttribute("d", `M${fp(a)} L${fp(b)} ${tick(j.sh)} ${tick(j.el)} ${tick(j.grip)}`);
      PN.lock.anno.setAttribute("opacity", fade(92, SPOT[1][1]).toFixed(3)); }
    { const o = out.twirl, tw = RIGS.twirl.twirl, r0 = sampleAt(RIGS.twirl.samples, tw[0]), pts = [], g = o.j.grip, L = o.r.len * o.s;
      for (let ph = r0.phi; ph <= o.r.phi + 1e-6; ph += 0.05) pts.push([g[0] + Math.sin(ph) * L, g[1] + Math.cos(ph) * L]);
      A.ta.setAttribute("points", pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" "));
      PN.twirl.anno.setAttribute("opacity", (fade(160, F_EXP[0]) * clamp((o.r.phi - r0.phi) * 3)).toFixed(3)); }

    // 3칸 전체 화면: 벡터 → 같은 자세 실캡처(흰 선만) 교차, ⑤ 관절선 reveal
    const P3 = PN[EXP], o3 = out[EXP];
    // 겹친 반투명 유령을 피하는 2단 교차: 실캡처(아래층)를 먼저 100%로 올리고, 그다음 위의 벡터를 걷어 낸다
    const xcCap = smooth(seg(f, F_X[0] - 3, F_X[0] + 1)) * (1 - smooth(seg(f, F_REC[0] + 4, F_REC[0] + 10)));
    const xc = smooth(seg(f, F_X[0] + 1, F_X[1] + 1)) * (1 - smooth(seg(f, F_REC[0], F_REC[0] + 6)));
    P3.cap.style.left = (o3.X + CAP.rel[0] * o3.s).toFixed(2) + "px"; P3.cap.style.top = (o3.G + CAP.rel[1] * o3.s).toFixed(2) + "px";
    P3.cap.style.width = (CAP.size[0] * o3.s).toFixed(2) + "px"; P3.cap.style.height = (CAP.size[1] * o3.s).toFixed(2) + "px";
    P3.cap.style.opacity = xcCap.toFixed(3); P3.cap.style.display = xcCap > 0.001 ? "block" : "none";
    P3.man.setAttribute("opacity", (1 - xc).toFixed(3));
    for (const k of ["ground", "groundRim", "rough"]) P3[k].setAttribute("opacity", (1 - xc).toFixed(3));
    const away = 1 - smooth(seg(f, F_EXP[0] - 6, F_EXP[0])) * (1 - smooth(seg(f, F_REC[0], F_REC[1])));
    for (const k of ["ball", "trailLine", "tee"]) P3[k].setAttribute("opacity", Math.min(1 - xc, away).toFixed(3));
    P3.smear.setAttribute("opacity", (+P3.smear.getAttribute("opacity") * (1 - xc)).toFixed(3));
    drawRig(f, o3);
    const kc = kin(f, RIGF0 + 8), co = 1 - smooth(seg(f, F_REC[0] - 2, F_REC[0] + 4));
    ffcap.style.opacity = (kc.on ? co : 0).toFixed(3);
    ffcap.style.transform = `translateX(${kc.tx.toFixed(2)}px) rotate(${kc.rot.toFixed(3)}deg)`;
    AUD.ff = kc.on && Math.abs(kc.k - 1) < 0.015 && co > 0.99;
    if (f >= F_EXP[0] && f < F_EXP[1] + 4) AUD.men = false;

    // 마무리: A·B 날아듦 → (밀어 올리기) 엔드카드
    const sw = smooth(seg(f, F_SWAP, F_SWAP + 7));
    const inK = (el, f0) => { const k = kin(f, f0, 820); el.style.opacity = (k.on ? 1 - sw : 0).toFixed(3); el.style.transform = `translate(${k.tx.toFixed(2)}px,${(-80 * sw).toFixed(2)}px) rotate(${k.rot.toFixed(3)}deg)`; return Math.abs(k.k - 1) < 0.015 && sw === 0; };
    const okA = inK(LA, F_LA), okB = inK(LB, F_LB);
    const inE = (el, f0) => { const k = Sk((f - f0) / FPS, "calm"); el.style.opacity = k.toFixed(3); el.style.transform = `translateY(${(48 * (1 - k)).toFixed(2)}px)`; return k > 0.985; };
    const okW = inE(EW, F_SWAP + 3), okM = inE(EM, F_SWAP + 10), okU = inE(EU, F_SWAP + 16);
    AUD.closing = { LA: okA, LB: okB, EW: okW, EM: okM, EU: okU };
    return out;
  }

  // ⑤ 관절선: 뼈마다 부모 관절에서 뻗어 나가며(stroke reveal) 빠르게, 검정 굵은 선·점
  const BONES = [["hip", "sh", 0], ["hip", "k1", 2], ["k1", "f1", 4], ["hip", "k2", 2], ["k2", "f2", 4], ["sh", "el", 3], ["el", "grip", 5], ["sh", "et", 3], ["et", "ht", 5], ["grip", "tip", 7]];
  const JOINTS = { hip: 0, sh: 3, k1: 4, k2: 4, f1: 6, f2: 6, el: 5, et: 5, grip: 7, ht: 7 };
  const rigEls = { bones: [], joints: {}, head: null };
  { const g = PN[EXP].rig;
    for (const [, b] of BONES) { const l = mk("line", { stroke: "#0A0A0A", "stroke-width": b === "tip" ? 7 : 10, "stroke-linecap": "round" }); if (b === "tip") l.setAttribute("stroke-dasharray", "14 12"); g.appendChild(l); rigEls.bones.push(l); }
    rigEls.head = mk("circle", { fill: "none", stroke: "#0A0A0A", "stroke-width": 8, "stroke-dasharray": "6 12" }); g.appendChild(rigEls.head);
    for (const k in JOINTS) { const c = mk("circle", { fill: "#0A0A0A" }); g.appendChild(c); rigEls.joints[k] = c; } }
  function drawRig(f, o) {
    const g = PN[EXP].rig, j = o.j, s = o.s;
    const vis = f >= RIGF0 - 1 && f < F_REC[0] + 8;
    g.setAttribute("opacity", vis ? (1 - smooth(seg(f, F_REC[0] - 2, F_REC[0] + 4))).toFixed(3) : 0);
    if (!vis) return;
    BONES.forEach(([a, b, d0], k) => {
      const l = rigEls.bones[k], p = j[a], q2 = j[b], u = smooth(seg(f, RIGF0 + d0, RIGF0 + d0 + 4));
      l.setAttribute("x1", p[0].toFixed(2)); l.setAttribute("y1", p[1].toFixed(2));
      l.setAttribute("x2", lerp(p[0], q2[0], u).toFixed(2)); l.setAttribute("y2", lerp(p[1], q2[1], u).toFixed(2));
      l.setAttribute("opacity", u > 0.001 ? 1 : 0);
    });
    const hu = smooth(seg(f, RIGF0 + 6, RIGF0 + 11));
    rigEls.head.setAttribute("cx", j.hd[0].toFixed(2)); rigEls.head.setAttribute("cy", j.hd[1].toFixed(2)); rigEls.head.setAttribute("r", (10 * s).toFixed(2)); rigEls.head.setAttribute("opacity", hu.toFixed(3));
    for (const k in JOINTS) { const c = rigEls.joints[k], sc = Sk((f - (RIGF0 + JOINTS[k] + 2)) / FPS, "snap");
      c.setAttribute("cx", j[k][0].toFixed(2)); c.setAttribute("cy", j[k][1].toFixed(2)); c.setAttribute("r", (15 * clamp(sc, 0, 1.3)).toFixed(2)); }
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;

  // ?audit=1 : 3프레임 간격으로 '멈춘' 글자·스틱맨의 화면 사각형을 모아 <pre id="audit">에 JSON (날아드는 중·슬라이드 중은 판정 밖 — 움직임 기법)
  function audit() {
    const res = { frames: [] };
    const textRects = (e) => { const outR = []; const rg = document.createRange(); const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT);
      let n; while ((n = w.nextNode())) { if (!n.textContent.trim()) continue; rg.selectNodeContents(n); for (const r of rg.getClientRects()) outR.push([r.left, r.top, r.right, r.bottom].map(Math.round)); } return outR; };
    for (let f = 0; f < 450; f += 3) {
      const o = render(f / FPS); const fr = { f, items: [] };
      panels.forEach((P, i) => { if (AUD.words[i]) for (const r of textRects(P.word)) fr.items.push({ name: "word" + (i + 1), o: 1, r }); });
      if (AUD.ff) for (const r of textRects(ffcap)) fr.items.push({ name: "ffcap", o: 1, r });
      for (const [name, el] of [["lineA", LA], ["lineB", LB], ["wordmark", EW], ["meta", EM], ["url", EU]]) if (AUD.closing[name === "lineA" ? "LA" : name === "lineB" ? "LB" : name === "wordmark" ? "EW" : name === "meta" ? "EM" : "EU"]) for (const r of textRects(el)) fr.items.push({ name, o: 1, r });
      if (AUD.men && f < F_OUT[0]) for (const P of panels) { if (+P.man.getAttribute("opacity") < 0.05) continue;
        if (P.name !== EXP && f >= F_EXP[1] && f < F_REC[0] + 34) continue;
        const b = P.man.getBoundingClientRect(), pad = 4.2 * (P.name === EXP ? o[EXP].s : SC);
        if (b.width) fr.items.push({ name: "man-" + P.name, o: 1, r: [b.left - pad, b.top - pad, b.right + pad, b.bottom + pad].map(Math.round) }); }
      res.frames.push(fr);
    }
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(res); document.body.appendChild(pre);
  }
  // 감사 모드는 이미지가 필요 없다(헤드리스 덤프가 디코드를 기다리지 않아 감사가 빠질 수 있었다)
  Promise.all([document.fonts.ready, q.has("audit") ? null : PN[EXP].cap.decode().catch(() => null)]).then(() => { if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); window.__ready = true; });
})();
