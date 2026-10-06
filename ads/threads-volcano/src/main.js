/* mini-golf 스레드 T2 「화산」 — 세로 1080×1920, 30fps, 13.5초 (시네마틱 원샷 + 대비 컷)
 *
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다. GSAP 타임라인은 재생 헤드 역할만 한다. Math.random·Date·네트워크 없음.
 * 그림은 전부 게임 화면 pt 좌표(1920×1080pt, 좌상단 원점)의 벡터다 — data/scene.js(실캡처·로그 → scripts/prep.py)를
 * 게임 렌더 규칙(GameScene.rebuildTerrain · StickmanNode) 그대로 다시 그리고, 카메라는 2D scale/translate만 쓴다.
 *
 * 비트(초) — 근거는 plan.md
 *   0.00  스틱맨 백스윙 톱(완결된 첫 그림) → 0.30 임팩트, 공이 높이 뜬다(실속도)
 *   0.62–1.30 속도 램프 1 → 0.2, 1.30–2.45 정점 슬로모, 2.45–3.05 → 0.45로 풀린다
 *   0.75  자막 "분화구에 떨어뜨리면"
 *   2.5–3.5 카메라가 분화구로 다가간다(×4.3 → ×8) · 공이 안쪽 벽에 떨어져 테두리 아래로 되굴러 컵으로
 *   ≈4.2  컵인 = 자막 "들어간다."
 *   5.3–6.1 카메라가 물러난다(×5) → 6.4 같은 구도에서 빗나간 샷으로 컷: 비탈에 맞고 발치로 굴러 내려온다 — "빗나가면 굴러 내려온다"
 *   8.3  "새 홀 · 화산" (카메라 ×3.7로 물러남) → 9.9 엔드카드 (장면 딤, 대시·워드마크·메타·URL), 끝 정지
 */
(() => {
  const FPS = 30, DUR = 14.0, W = 1080, H = 1920;
  const root = document.getElementById("root");
  const q = new URLSearchParams(location.search);
  const SC = window.SCENE;

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const smooth = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
  const smoother = (u) => { u = clamp(u); return u * u * u * (u * (u * 6 - 15) + 10); };
  const seg = (t, a, b) => clamp((t - a) / (b - a));
  const outCubic = (u) => 1 - Math.pow(1 - clamp(u), 3);
  const inOut = (u) => { u = clamp(u); return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2; };

  /* ── 지형 (1m 간격, 게임 linePath와 같은 간격) ── */
  const PPM = SC.PPM, G = SC.GROUND, GX0 = SC.GX0;
  const groundM = (xm) => { const i = clamp(xm - GX0, 0, G.length - 1.001), a = Math.floor(i); return lerp(G[a], G[a + 1], i - a); };
  const ground = (xpt) => groundM(xpt / PPM);
  const R_BALL = 5.5;
  const CUP_X = SC.CUP_X, CUP_TOP = SC.CUP_TOP;

  /* ── 시간 왜곡: 광고 시간 t → 게임 시간 τ (임팩트 = 0) ── */
  const TAU0 = -0.008;  // 임팩트 프레임에서 시작(클럽 머리가 공 바로 뒤) → 다음 프레임에 공이 뜬다. 더 이르면 ×6 구도에서 클럽 머리가 왼쪽 밖
  const TAU_HOLED = 1.74;          // 컵에 떨어지는 순간(로그 HOLED 1.75s와 표본 1.66s 공이 컵 테두리)
  function speed(t) {
    let v = 1;
    if (t >= 0.45) v = lerp(1, 0.2, smooth(seg(t, 0.45, 1.10)));
    if (t >= 2.30) v = lerp(0.2, 0.45, smooth(seg(t, 2.30, 2.90)));
    return v;
  }
  let T_HOLED = 99;
  const TAB = [], STEP = 1 / 600;
  function buildTau() {
    // 두 번 적분: 첫 번째로 컵인 시각을 찾고, 두 번째로 컵인 뒤 속도 복귀를 포함해 다시 적분
    for (let pass = 0; pass < 2; pass++) {
      TAB.length = 0; let tau = TAU0; let th = 99;
      for (let i = 0; i <= DUR / STEP + 2; i++) {
        TAB.push(tau);
        if (th === 99 && tau >= TAU_HOLED) th = i * STEP;
        tau += speed(i * STEP) * STEP;
      }
      T_HOLED = th;
    }
  }
  const tauAt = (t) => { const i = clamp(t / STEP, 0, TAB.length - 1.001), a = Math.floor(i); return lerp(TAB[a], TAB[a + 1], i - a); };

  /* ── 공 궤적 ── */
  const [X0, Y0] = SC.TEE_BALL;
  const poly = (F, tau) => {
    const [a1, a2, a3] = F.cx, [b1, b2, b3] = F.cy;
    return [X0 + a1 * tau + a2 * tau * tau + a3 * tau ** 3, Y0 + b1 * tau + b2 * tau * tau + b3 * tau ** 3];
  };
  const landTau = (F, from) => { for (let tau = from; tau < 3; tau += 0.0005) { const [x, y] = poly(F, tau); if (y >= ground(x) - R_BALL) return tau; } return 3; };
  const TL_H = landTau(SC.FLIGHT_H, 0.9), TL_M = landTau(SC.FLIGHT_M, 0.5);
  const XL_H = poly(SC.FLIGHT_H, TL_H)[0], XL_M = poly(SC.FLIGHT_M, TL_M)[0];
  const T_LIP = 1.68, X_LIP = CUP_X + 3.0;          // 컵 테두리(우측 립) 도착 — 표본 1.663s에 1739.5pt
  // 홀인 샷: 안쪽 벽(테두리 바로 아래)에 떨어져 백스핀으로 되감기 → V 바닥으로 가속해 컵으로 (실측 표본에 맞춘 a=0.7)
  function ballH(tau) {
    if (tau <= 0) return { x: X0, y: Y0, vis: 1, clip: 0 };
    if (tau <= TL_H) { const [x, y] = poly(SC.FLIGHT_H, tau); return { x, y, vis: 1, clip: 0 }; }
    if (tau <= T_LIP) {
      const u = (tau - TL_H) / (T_LIP - TL_H), f = 0.7 * u + 0.3 * u * u;
      const x = lerp(XL_H, X_LIP, f), hop = Math.sin(Math.PI * clamp((tau - TL_H) / 0.09)) * 1.6;
      return { x, y: ground(x) - R_BALL - hop, vis: 1, clip: 0 };
    }
    // 립 → 컵 속으로 (0.07s): 가운데로 미끄러지며 가라앉는다. 컵 윗변 아래는 잘린다
    const u = clamp((tau - T_LIP) / (TAU_HOLED - T_LIP));
    const x = lerp(X_LIP, CUP_X, smooth(u));
    return { x, y: lerp(ground(X_LIP) - R_BALL, CUP_TOP + 7.5, u * u), vis: 1, clip: 1 };
  }
  // 빗나간 샷: 비탈에 맞고 되감겨 발치로 — 착지 뒤는 실측 표본(≈15Hz, 두 번 찍어 엇갈림)의 x를 이어 쓰고 y는 지면
  const MS = SC.BALL_M.filter((p) => p[0] > TL_M + 0.01).sort((a, b) => a[0] - b[0]);
  const MK = [[TL_M, XL_M]];
  for (const p of MS) { const last = MK[MK.length - 1]; if (p[0] - last[0] > 0.03) MK.push([p[0], Math.min(last[1], p[1])]); }
  function ballM(tau) {
    if (tau <= 0) return { x: X0, y: Y0, vis: 1, clip: 0 };
    if (tau <= TL_M) { const [x, y] = poly(SC.FLIGHT_M, tau); return { x, y, vis: 1, clip: 0 }; }
    let x = MK[MK.length - 1][1];
    for (let i = 0; i < MK.length - 1; i++) if (tau < MK[i + 1][0]) { const [ta, xa] = MK[i], [tb, xb] = MK[i + 1]; x = lerp(xa, xb, smooth((tau - ta) / (tb - ta)) * 0.35 + 0.65 * (tau - ta) / (tb - ta)); break; }
    const hop = Math.sin(Math.PI * clamp((tau - TL_M) / 0.1)) * 1.4;
    return { x, y: ground(x) - R_BALL - hop, vis: 1, clip: 0 };
  }
  const TRAIL_N = 90;
  function trailPts(F, tauNow, tl) {
    const end = Math.min(tauNow, tl); if (end <= 0) return null;
    const out = [];
    for (let i = 0; i <= TRAIL_N; i++) { const [x, y] = poly(F, (end * i) / TRAIL_N); out.push(x.toFixed(2) + "," + y.toFixed(2)); }
    return out;
  }

  /* ── 리그 (60Hz 덤프) 보간 ── */
  function rigAt(R, tau) {
    let lo = 0, hi = R.length - 1;
    if (tau <= R[0][0]) return R[0]; if (tau >= R[hi][0]) return R[hi];
    while (hi - lo > 1) { const m = (lo + hi) >> 1; R[m][0] <= tau ? lo = m : hi = m; }
    const a = R[lo], b = R[hi], u = (tau - a[0]) / (b[0] - a[0]);
    return [tau, a[1], a[2].map((p, i) => [lerp(p[0], b[2][i][0], u), lerp(p[1], b[2][i][1], u)]),
      [lerp(a[3][0], b[3][0], u), lerp(a[3][1], b[3][1], u)], lerp(a[4], b[4], u), lerp(a[5], b[5], u), lerp(a[6], b[6], u), a[7], a[8]];
  }

  /* ── DOM ── */
  const NS = "http://www.w3.org/2000/svg";
  const mk = (tag, a, parent) => { const e = document.createElementNS(NS, tag); for (const k in a) e.setAttribute(k, a[k]); if (parent) parent.appendChild(e); return e; };
  const svg = mk("svg", { id: "world", width: W, height: H, viewBox: `0 0 ${W} ${H}` }); root.appendChild(svg);
  // 결정론: 화면에는 SVG가 아니라 소프트웨어 2D 캔버스(willReadFrequently → CPU 래스터)에 같은 장면을 칠한다.
  // ×6~×9.75 근접에서 SVG(합성기 래스터)는 렌더마다 선 가장자리 안티앨리어싱이 달랐다(3회 중 1회, 최대 58). SVG는 숨긴 채 장면 그래프·감사(사각형)용으로만 쓴다
  svg.style.visibility = "hidden";
  const cv = document.createElement("canvas"); cv.width = W; cv.height = H; cv.id = "cv";
  cv.style.cssText = "position:absolute;left:0;top:0;width:1080px;height:1920px"; root.appendChild(cv);
  const ctx = cv.getContext("2d", { willReadFrequently: true });
  const num = (e, k, d = 0) => { const v = e.getAttribute(k); return v == null ? d : parseFloat(v); };
  function paint(node, st, alpha) {
    for (const el of node.children) {
      const tag = el.tagName; if (tag === "defs" || tag === "clipPath") continue;
      const a = alpha * num(el, "opacity", 1); if (a <= 0.001) continue;
      const s2 = { fill: el.getAttribute("fill") ?? st.fill, stroke: el.getAttribute("stroke") ?? st.stroke, sw: num(el, "stroke-width", st.sw),
        cap: el.getAttribute("stroke-linecap") ?? st.cap, join: el.getAttribute("stroke-linejoin") ?? st.join };
      if (tag === "g") {
        ctx.save();
        if (el.getAttribute("clip-path")) { ctx.beginPath(); ctx.rect(1400, 600, 600, CUP_TOP + 2.5 - 600); ctx.clip(); }
        paint(el, s2, a); ctx.restore(); continue;
      }
      let path = null;
      if (tag === "polyline") { const pts = (el.getAttribute("points") || "").trim(); if (!pts) continue; path = new Path2D("M" + pts.split(/\s+/).join(" L").replace(/,/g, " ")); }
      else if (tag === "line") { path = new Path2D(`M${num(el, "x1")} ${num(el, "y1")} L${num(el, "x2")} ${num(el, "y2")}`); }
      else if (tag === "path") { const d = el.getAttribute("d"); if (!d) continue; path = new Path2D(d); }
      else if (tag === "rect") { path = new Path2D(); path.rect(num(el, "x"), num(el, "y"), num(el, "width"), num(el, "height")); }
      else if (tag === "circle") { path = new Path2D(); path.arc(num(el, "cx"), num(el, "cy"), num(el, "r"), 0, Math.PI * 2); }
      if (!path) continue;
      ctx.globalAlpha = a;
      if (s2.fill && s2.fill !== "none") { ctx.fillStyle = s2.fill; ctx.fill(path); }
      if (s2.stroke && s2.stroke !== "none" && s2.sw > 0) { ctx.strokeStyle = s2.stroke; ctx.lineWidth = s2.sw; ctx.lineCap = s2.cap || "butt"; ctx.lineJoin = s2.join || "miter"; ctx.stroke(path); }
    }
  }
  const defs = mk("defs", {}, svg);
  const cupClip = mk("clipPath", { id: "cupclip", clipPathUnits: "userSpaceOnUse" }, defs);
  mk("rect", { x: 1400, y: 600, width: 600, height: CUP_TOP + 2.5 - 600 }, cupClip);   // 컵 윗변 아래로 내려간 공은 보이지 않는다
  const cam = mk("g", {}, svg);

  // 지형: 러프(회색 0.85 α.5, 1.8pt) + 잔디 틱(1.5m 간격, 좌우 교차) · 분화구 그린(흰색 α.95, 2.6pt) · 컵 홈 · 깃발
  // 결정론: 큰 경로 하나(×9.75에서 화면 4000px)는 렌더마다 가장자리 안티앨리어싱이 달랐다 → 4m 조각으로 나누고,
  // 조각 이음매에 반투명이 겹쳐 구슬이 생기지 않게 게임 색을 바탕(#121315) 위 합성값의 불투명 색으로 쓴다(러프 α.5 → #767676, 그린 α.95 → #F3F3F3)
  const RC = "#767676", TC = "rgba(217,217,217,0.45)", GC = "#F3F3F3";
  const P = (xm) => `${(xm * PPM).toFixed(2)},${groundM(xm).toFixed(2)}`;
  const line = (from, to) => { const pts = [P(from)]; for (let x = Math.floor(from) + 1; x < to; x++) pts.push(P(x)); pts.push(P(to)); return pts.join(" "); };
  const terr = mk("g", { fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round" }, cam);
  const GXEND = GX0 + G.length - 1;
  const [GR0, GR1] = SC.GREEN, CUPL = SC.HOLE_X - SC.CUP_HALF, CUPR = SC.HOLE_X + SC.CUP_HALF;
  for (const [a, b] of [[GX0, GR0], [GR1, GXEND]]) {
    for (let c0 = a; c0 < b - 0.01; c0 += 4) mk("polyline", { points: line(c0, Math.min(b, c0 + 4)), stroke: RC, "stroke-width": 1.8 }, terr);
    let lean = false;
    for (let gx = a + 0.9; gx < b - 0.5; gx += 1.5) {
      const x = gx * PPM, y = groundM(gx);
      mk("line", { x1: x.toFixed(2), y1: y.toFixed(2), x2: (x + (lean ? -0.8 : 0.9)).toFixed(2), y2: (y - (lean ? 4.2 : 5.4)).toFixed(2), stroke: TC, "stroke-width": 1 }, terr); lean = !lean;
    }
  }
  for (const [a, b] of [[GR0, CUPL], [CUPR, GR1]]) for (let c0 = a; c0 < b - 0.01; c0 += 4) mk("polyline", { points: line(c0, Math.min(b, c0 + 4)), stroke: GC, "stroke-width": 2.6 }, terr);
  mk("rect", { x: CUP_X - 5, y: CUP_TOP, width: 10, height: 9, fill: "rgba(13,13,13,0.85)" }, terr);

  // 궤적선: 흰 α.28 1pt → 불투명 합성색 #545454, 10구간씩 조각(이음매 겹침 없음). 걷힐 때는 묶음 opacity
  const trailEl = mk("g", { fill: "none", stroke: "#545454", "stroke-width": 1, "stroke-linecap": "round", "stroke-linejoin": "round" }, cam);
  const trailSegs = Array.from({ length: TRAIL_N / 10 }, () => mk("polyline", {}, trailEl));
  const flag = mk("g", {}, cam);
  mk("rect", { x: CUP_X - 0.6, y: CUP_TOP - 62, width: 1.2, height: 62, fill: "rgba(242,242,242,0.85)" }, flag);
  mk("path", { d: `M${CUP_X} ${CUP_TOP - 62} L${CUP_X + 21} ${CUP_TOP - 55.5} L${CUP_X} ${CUP_TOP - 49} Z`, fill: "#D94D3D" }, flag);

  // 스틱맨 (StickmanNode 렌더 규칙 — 15초 본편 drawMan과 같은 획) + 프로펠러캡
  const man = mk("g", {}, cam);
  const SP = {
    trail: mk("path", { fill: "none", stroke: "rgba(224,224,224,.52)", "stroke-width": 5.5, "stroke-linecap": "round", "stroke-linejoin": "round" }, man),
    body: mk("path", { fill: "none", stroke: "rgba(224,224,224,.95)", "stroke-width": 6, "stroke-linecap": "round", "stroke-linejoin": "round" }, man),
    shaft: mk("path", { fill: "none", stroke: "rgba(194,194,194,.9)", "stroke-width": 3, "stroke-linecap": "round" }, man),
    chead: mk("path", { fill: "none", stroke: "rgba(237,237,237,.95)", "stroke-width": 13.6, "stroke-linecap": "round" }, man),
    grip: mk("path", { fill: "none", stroke: "rgba(153,153,153,.9)", "stroke-width": 4.6, "stroke-linecap": "round" }, man),
    head: mk("circle", { r: 10, fill: "rgba(224,224,224,.95)" }, man),
    hat: mk("path", { fill: "rgba(209,209,209,.95)" }, man),
  };
  const dust = mk("g", { fill: "rgba(240,240,240,0.85)" }, cam);
  const DUST = [[-6, 7], [-3, 10], [1, 11], [4, 8], [7, 6], [-9, 4]].map(([dx, dy]) => [dx, dy, mk("circle", { r: 1.1 }, dust)]);
  const ballG = mk("g", {}, cam);
  const ballEl = mk("circle", { r: R_BALL, fill: "#FAFAF8" }, ballG);

  function drawMan(r, gx, gy) {
    const d = r[8], T = (p) => [gx + p[0] * d, gy - p[1]];
    const [hip, sh, f1, f2, k1, k2, grip, ht, el, et] = r[2].map(T);
    const f = (p) => `${p[0].toFixed(2)} ${p[1].toFixed(2)}`;
    const ctl = [(sh[0] + hip[0]) / 2 - d * 0.8, (sh[1] + hip[1]) / 2];
    const arm = (a, e, b) => r[7] ? `M${f(a)} Q${f(e)} ${f(b)}` : `M${f(a)} L${f(e)} L${f(b)}`;
    SP.body.setAttribute("d", `M${f(sh)} Q${f(ctl)} ${f(hip)} M${f(hip)} L${f(k1)} L${f(f1)} M${f(hip)} L${f(k2)} L${f(f2)} ${arm(sh, el, grip)}`);
    SP.trail.setAttribute("d", arm(sh, et, ht));
    const phi = r[4], len = r[5], butt = r[6], sp = Math.sin(phi), cp = Math.cos(phi);
    const tip = [grip[0] + sp * len * d, grip[1] + cp * len], bt = [grip[0] - sp * butt * d, grip[1] - cp * butt];
    SP.shaft.setAttribute("d", `M${f(bt)} L${f(tip)}`);
    SP.grip.setAttribute("d", `M${f(bt)} L${f([grip[0] + sp * 8 * d, grip[1] + cp * 8])}`);
    const perp = [Math.cos(phi) * d, -Math.sin(phi)], c = [tip[0] + perp[0] * 4.5, tip[1] + perp[1] * 4.5], half = (17 - 13.6) / 2;
    SP.chead.setAttribute("d", `M${f([c[0] - perp[0] * half, c[1] - perp[1] * half])} L${f([c[0] + perp[0] * half, c[1] + perp[1] * half])}`);
    const hd = [sh[0] + d * r[3][0], sh[1] - r[3][1]];
    SP.head.setAttribute("cx", hd[0].toFixed(2)); SP.head.setAttribute("cy", hd[1].toFixed(2));
    // 프로펠러캡: 반구(중심 0,6 반지름 9.5) + 날개 타원 + 꼭지 (게임 setHat .propeller, y 위 → 아래로 뒤집음)
    const hx = hd[0], hy = hd[1];
    SP.hat.setAttribute("d", `M${(hx + 9.5).toFixed(2)} ${(hy - 6).toFixed(2)} A9.5 9.5 0 0 0 ${(hx - 9.5).toFixed(2)} ${(hy - 6).toFixed(2)} Z ` +
      `M${(hx - 8).toFixed(2)} ${(hy - 16.8).toFixed(2)} a8 1.3 0 1 0 16 0 a8 1.3 0 1 0 -16 0 Z M${(hx - 0.9).toFixed(2)} ${(hy - 16.5).toFixed(2)} h1.8 v3 h-1.8 Z`);
  }

  /* ── 카메라: 2D scale/translate만. 키 사이에는 정지(홀드) ── */
  const K = {
    // 2차(10-06): 전 구간 ×1.25~1.3 당김. 장면 중심 y≈950, 자막은 위쪽 띠(330~570).
    // ×6에서는 피니시 클럽 머리(1570pt)~깃발 끝(1757pt) 187pt가 화면 폭을 넘는다 → 클럽 머리는 왼쪽 프레임 밖, 몸·공·깃발은 안전 영역 안
    hero: { s: 6.0, cx: 1692.5, cy: 847 },   // ×1.25 · 뒷발 x≈45 · 깃발 끝 x≈927 · 깃대 끝 y≈645 · 지면 y≈1278
    crater: { s: 9.75, cx: 1738, cy: 829.4 }, // ×1.3 · 깃대 끝 y≈620 · 컵 y≈1224 · 착지점 x≈715
    mid: { s: 6.0, cx: 1692.5, cy: 847 },    // ×1.2(=히어로 구도) — 폭 147pt(뒷발~깃발 끝)가 860px 안에 들어가는 최대 배율. 매치 컷이 첫 구도를 되풀이한다
    endw: { s: 4.8, cx: 1700, cy: 907 },     // ×1.3 · 깃대 끝 y≈420 · 지면 y≈926 — 아래 엔드카드(1010~)와 겹치지 않는다
  };
  const MOVES = [["hero", "crater", 1.7, 2.85], ["crater", "mid", 5.3, 6.15], ["mid", "endw", 8.55, 9.4]];
  function camera(t) {
    let c = K.hero;
    for (const [a, b, t0, t1] of MOVES) {
      if (t < t0) break;
      const u = inOut(seg(t, t0, t1)), A = K[a], B = K[b];
      // 배율은 로그 공간에서 보간(체감 속도 일정)
      c = { s: Math.exp(lerp(Math.log(A.s), Math.log(B.s), u)), cx: lerp(A.cx, B.cx, u), cy: lerp(A.cy, B.cy, u) };
    }
    return c;
  }
  const toScreen = (c, x, y) => [(x - c.cx) * c.s + W / 2, (y - c.cy) * c.s + H / 2];

  /* ── 글자층: 자막 슬롯 하나(한 번에 한 줄) · 타이틀 · 엔드카드 ── */
  // 빗나간 샷은 같은 구도에서 임팩트부터(2차 수정 — 컷 순간 '공 순간이동'으로 읽히던 것)
  const T_CUT = 6.4, TAU_M0 = -0.008, TAU_M_END = 2.06;
  const CAP_Y = 330, CAP_FS = 104, LH = 1.14;
  const caps = [];
  // 자막 슬롯: 위쪽 띠. 줄 수만큼 높이를 잡고 블록째 마스크 와이프. delay = 들어오기 전 숨(프레임)
  const addCap = (html, tIn, tOut, { fs = CAP_FS, y = CAP_Y, lines = 1, delay = 0, wipe = 10, lead = 0 } = {}) => {
    const h = Math.round(fs * LH * lines);
    const box = document.createElement("div"); box.className = "cap"; box.style.top = y + "px"; box.style.height = h + "px";
    box.innerHTML = `<span class="ln" style="font-size:${fs}px;line-height:${LH}">${html}</span>`; root.appendChild(box);
    caps.push({ box, ln: box.firstChild, tIn, tOut, h, delay: delay / FPS, wipe: wipe / FPS, lead }); return box;
  };
  addCap("분화구에<br>떨어뜨리면", 0.6, 99, { lines: 2 });   // tOut은 컵인 시각으로 init에서 채운다
  addCap("들어간다.", 99, T_CUT, { delay: 5 });
  addCap("빗나가면<br>굴러 내려온다", T_CUT, 8.65, { lines: 2, wipe: 6, lead: 0.34 });   // 컷 프레임에 이미 70% 올라와 있다(컷 전에는 안 보임)
  addCap(`<span class="dim2">새 홀 ·</span> 화산`, 9.2, 10.8, { fs: 128, y: 1030 });   // 엔드카드 자리에서 → 엔드카드로 넘긴다
  const end = document.createElement("div"); end.id = "end"; end.style.top = "1010px";
  end.innerHTML = `<div class="row" style="height:6px;margin:0 0 40px 4px"><div class="dash"></div></div>
    <div class="row" style="height:138px"><div class="wm">mini-golf</div></div>
    <div class="row" style="height:62px;margin-top:22px"><div class="meta">macOS 메뉴바 앱 · 무료 · 오픈소스</div></div>
    <div class="row" style="height:50px;margin-top:18px"><div class="url">github.com/w0uldy0udaestar/mini-golf</div></div>`;
  root.appendChild(end);
  const dim = document.createElement("div"); dim.id = "dim"; root.insertBefore(dim, cv.nextSibling);   // 캔버스 위·글자 아래
  const endRows = [...end.querySelectorAll(".row > div")];
  const ROW_H = [6, 138, 62, 50];
  const T_END = 10.85;

  const WIPE = 10 / FPS;   // 자막 마스크 와이프 10프레임
  function capState(c, t) {
    // 나가는 줄이 먼저 빠지고(7f) 들어오는 줄은 5f 뒤에 올라온다(10f) — 두 줄이 한꺼번에 반씩 보이는 순간을 줄인다
    const tin = c.tIn + c.delay;
    if (t < tin || t >= c.tOut + 7 / FPS) return null;
    const pin = outCubic(clamp((t - tin) / c.wipe + c.lead)), pout = inOut(seg(t, c.tOut, c.tOut + 7 / FPS));
    return (1 - pin) * c.h - pout * c.h;
  }

  /* ── render(t) ── */
  function render(t) {
    const c = camera(t);
    cam.setAttribute("transform", `translate(${(W / 2 - c.cx * c.s).toFixed(3)} ${(H / 2 - c.cy * c.s).toFixed(3)}) scale(${c.s.toFixed(5)})`);
    const miss = t >= T_CUT;
    const tau = miss ? Math.min(TAU_M_END, TAU_M0 + (t - T_CUT)) : tauAt(t);
    const R = miss ? SC.RIG_M : SC.RIG_H, F = miss ? SC.FLIGHT_M : SC.FLIGHT_H, TL = miss ? TL_M : TL_H;
    // 홀인 뒤 리그는 'holed'(피니시 유지) 구간 안에서만 — 3.5s부터는 다음 홀 티 의식이라 쓰지 않는다
    drawMan(rigAt(R, miss ? tau : Math.min(tau, 3.45)), SC.STICK_X, SC.STICK_GY);
    // 공
    const b = miss ? ballM(tau) : ballH(tau);
    ballEl.setAttribute("cx", b.x.toFixed(2)); ballEl.setAttribute("cy", b.y.toFixed(2));
    if (b.clip) ballG.setAttribute("clip-path", "url(#cupclip)"); else ballG.removeAttribute("clip-path");
    // 궤적선: 비행 구간만 그리고(게임과 같다), 컵인 뒤·장면 끝에는 걷힌다
    const tp = trailPts(F, tau, TL);
    trailSegs.forEach((e, i) => e.setAttribute("points", tp ? tp.slice(i * 10, i * 10 + 11).join(" ") : ""));
    const trA = miss ? 1 - smooth(seg(t, 8.4, 9.2)) : 1 - smooth(seg(t, T_HOLED + 0.5, T_HOLED + 1.3));
    trailEl.setAttribute("opacity", trA.toFixed(3));
    // 착지 먼지 (게임 Effects.dust 결: 0.16s 위로 → 0.26s 아래로, 사라짐) — 게임 시간으로 진행
    const dt = tau - TL, xl = miss ? XL_M : XL_H;
    if (dt > 0 && dt < 0.42) {
      dust.setAttribute("opacity", (0.9 * (1 - smooth(seg(dt, 0.18, 0.42)))).toFixed(3));
      for (const [dx, dy, e] of DUST) {
        const up = clamp(dt / 0.16), dn = clamp((dt - 0.16) / 0.26);
        const x = xl + dx * 0.6 * outCubic(up) + dx * 0.4 * dn, y0 = ground(xl) - 1;
        e.setAttribute("cx", x.toFixed(2)); e.setAttribute("cy", (y0 - dy * outCubic(up) + dy * 0.6 * dn * dn).toFixed(2));
      }
    } else dust.setAttribute("opacity", 0);
    // 화면: 소프트웨어 캔버스에 장면 그래프를 칠한다 (카메라 = setTransform)
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.clearRect(0, 0, W, H);
    ctx.setTransform(c.s, 0, 0, c.s, W / 2 - c.cx * c.s, H / 2 - c.cy * c.s);
    paint(cam, { fill: "#000", stroke: null, sw: 1, cap: "butt", join: "miter" }, 1);

    // 자막 슬롯
    for (const cp of caps) {
      const y = capState(cp, t);
      cp.box.style.visibility = y == null ? "hidden" : "visible";
      // transform 대신 top(레이아웃): 합성 레이어 승격 없이 CPU 래스터 → 두 번 렌더가 같은 픽셀(결정론)
      if (y != null) cp.ln.style.top = `${Math.round(y)}px`;
    }
    // 엔드카드: 장면 딤 + 줄마다 4프레임 간격으로 밀려 올라온다
    const dm = smooth(seg(t, T_END - 0.1, T_END + 0.5));
    dim.style.opacity = (0.72 * dm).toFixed(3);
    end.style.visibility = t >= T_END ? "visible" : "hidden";
    endRows.forEach((e, i) => { const u = outCubic(seg(t, T_END + i * 4 / FPS, T_END + i * 4 / FPS + 12 / FPS));
      if (i === 0) e.style.width = `${Math.round(64 * u)}px`; else e.style.top = `${Math.round((1 - u) * ROW_H[i] * 1.05)}px`; });
  }

  function init() {
    buildTau();
    caps[0].tOut = T_HOLED; caps[1].tIn = T_HOLED;
    caps[1].tOut = T_CUT - 7 / FPS;   // 컷 전에 자막 슬롯을 비운다 → 컷 5프레임 뒤 새 줄
  }
  init();

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;

  // ?audit=1 : 3프레임마다 글자 사각형·공·컵·깃발·스틱맨의 화면 사각형을 <pre id="audit">에 JSON으로 (scripts/qa.py가 읽는다)
  function audit() {
    const out = { frames: [], T_HOLED, TL_H, TL_M, XL_H, XL_M };
    const rect = (e) => { const r = e.getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom].map(Math.round); };
    const textRects = (e) => { const o = []; const rg = document.createRange(); const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT); let n;
      while ((n = w.nextNode())) { if (!n.textContent.trim()) continue; rg.selectNodeContents(n); for (const r of rg.getClientRects()) o.push([r.left, r.top, r.right, r.bottom].map(Math.round)); } return o; };
    for (let f = 0; f < DUR * FPS; f += 3) {
      const t = f / FPS; render(t);
      const fr = { f, items: [] };
      for (const cp of caps) if (cp.box.style.visibility === "visible") { const mb = cp.box.getBoundingClientRect();
        for (const r of textRects(cp.box)) { const cl = [Math.max(r[0], mb.left), Math.max(r[1], mb.top), Math.min(r[2], mb.right), Math.min(r[3], mb.bottom)].map(Math.round); if (cl[3] - cl[1] > 4) fr.items.push({ name: "cap", r: cl }); } }
      if (end.style.visibility === "visible") for (const r of textRects(end)) fr.items.push({ name: "end", r });
      if (t < 9.9) { fr.items.push({ name: "ball", r: rect(ballEl) }); }
      const c = camera(t), [fx0, fy0] = toScreen(c, CUP_X - 6, CUP_TOP - 62), [fx1, fy1] = toScreen(c, CUP_X + 21, CUP_TOP + 9);
      if (t >= 2.4 && t < 9.9) fr.items.push({ name: "cup+flag", r: [fx0, fy0, fx1, fy1].map(Math.round) });
      // 스틱맨: 몸·머리(클럽 제외)를 안전 영역 판정에, 클럽까지 포함한 사각형은 참고로
      if (t < 1.7 || t >= 6.15) { const rb = SP.body.getBoundingClientRect(), rh = SP.hat.getBoundingClientRect();
        fr.items.push({ name: "man-body", r: [Math.min(rb.left, rh.left), Math.min(rb.top, rh.top), Math.max(rb.right, rh.right), rb.bottom].map(Math.round) });
        fr.items.push({ name: "man+club(ref)", r: rect(man) }); }
      fr.scale = +c.s.toFixed(3);
      out.frames.push(fr);
    }
    out.textPx = { caption: CAP_FS, title: 128, wordmark: 132, meta: 46, url: 36 };
    out.fonts = ["700 104px Pretendard", "800 132px Pretendard", "500 46px Pretendard", "500 36px JBM"].map((s) => document.fonts.check(s));
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  document.fonts.ready.then(() => { if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); });
})();
