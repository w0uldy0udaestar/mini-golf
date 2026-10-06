/* mini-golf 스레드 T2 「홀마다 다른 산」 — 세로 1080×1920, 30fps, 14.8초 (코스 쇼릴)
 *
 * 컷마다 홀 하나: 선명한 단색 바탕 + 흰 선화 지형(게임 코스 생성기 실제 홀) + 공의 결정적 순간(게임 탄도 엔진 시뮬레이션) + 한 단어.
 * 모션: 휩 팬(모션 블러) · 1프레임 컬러 스왑 플래시 · 착지 2프레임 히트스톱 + 흔들림 · 줌 펀치(×1.15, 3프레임) · 지형 선 왼→오 리빌 · 키네틱 단어.
 * 결정론: 화면은 소프트웨어 2D 캔버스(willReadFrequently)에만 그린다. 글자는 DOM이지만 transform 없이 left/top/font-size(레이아웃)만 바꾼다.
 * 모든 상태는 render(t)가 t만 보고 계산한다. Math.random·Date·네트워크 없음.
 */
(() => {
  const FPS = 30, NF = 448, DUR = NF / FPS, W = 1080, H = 1920;   // 박 격자: 128.57bpm = 한 박 14프레임, 컷은 8분음표(7프레임) 경계
  const root = document.getElementById("root");
  const q = new URLSearchParams(location.search);
  const CUTS = window.CUTS, V = window.SCENE;

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const smooth = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
  const outCubic = (u) => 1 - Math.pow(1 - clamp(u), 3);
  const inCubic = (u) => Math.pow(clamp(u), 3);
  const outBack = (u) => { u = clamp(u); const c1 = 1.25, c3 = c1 + 1; return 1 + c3 * Math.pow(u - 1, 3) + c1 * Math.pow(u - 1, 2); };
  const shade = (hex, k) => { const n = parseInt(hex.slice(1), 16); const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
    return `rgb(${Math.round(r * k)},${Math.round(g * k)},${Math.round(b * k)})`; };

  /* ── 타임라인 (프레임) ── */
  const STARTS = [0, 42, 77, 112, 147, 182, 217, 252];   // 8 아키타입 (절벽 3박, 나머지 2.5박)
  const V0 = 287, V1 = 336, TAG0 = 336, END0 = 371;      // 화산 3.5박 · 한 줄 2.5박 · 엔드카드
  const LF_LAND = [28, 14, 20, 28, 14, 14, 10, 12];      // 컷 안에서 핵심 사건 프레임(폭포 = 입수, 산정 = 꼭대기 착지)
  const SPEED = { cliff: [1.8, 1.0], canyon: [1.6, 1.0], cascade: [0, 1.0], summit: [0, 1.0], island: [1.6, 1.4], ridge: [1.6, 2.2], terraces: [1.6, 0], forest: [1.4, 1.5] };
  const FLASH = new Set([77, 182, 287]);                  // 1프레임 컬러 스왑 플래시로 들어가는 컷 (나머지는 휩 팬)
  const SP_IN = 1.6, SP_OUT = 1.0;                         // 착지 전 빨리감기 · 착지 뒤 실속도
  const VOLC_BG = "#2D5BFF", TAG_BG = "#FFD93B";

  /* ── 컷 시간 → 게임 시간(τ, 샷 기준 초): 착지 전 빨리감기 → 2프레임 히트스톱 → 실속도 ── */
  function tauAt(lf, tl, land, spIn = SP_IN, spOut = SP_OUT) {
    if (lf < land) return tl - (land - lf) / FPS * spIn;
    if (lf < land + 2) return tl;
    return tl + (lf - land - 2) / FPS * spOut;
  }
  const ballAt = (B, tau) => {
    if (tau <= B[0][0]) return [B[0][1], B[0][2]];
    const i = Math.min(B.length - 2, Math.max(0, Math.floor(tau * 120)));
    let k = i; while (k < B.length - 2 && B[k + 1][0] < tau) k++; while (k > 0 && B[k][0] > tau) k--;
    const a = B[k], b = B[k + 1], u = clamp((tau - a[0]) / Math.max(1e-6, b[0] - a[0]));
    return [lerp(a[1], b[1], u), lerp(a[2], b[2], u)];
  };
  // 펀치(×1.15, 3프레임 올라갔다 8프레임에 걸쳐 돌아온다) · 흔들림(8프레임 감쇠, 결정적 사인)
  const punchK = (d) => d < 0 ? 0 : d < 3 ? outCubic(d / 3) : 1 - smooth((d - 3) / 8);
  const shakeXY = (d, A = 16) => d < 0 || d >= 8 ? [0, 0] : [A * (1 - d / 8) * Math.sin(d * 2.3 + 0.4), A * 0.8 * (1 - d / 8) * Math.cos(d * 2.9 + 1.1)];

  /* ── 리그 (실제 60Hz 덤프, 화산 홀인 샷) ── */
  function rigAt(R, tau) {
    let lo = 0, hi = R.length - 1;
    if (tau <= R[0][0]) return R[0]; if (tau >= R[hi][0]) return R[hi];
    while (hi - lo > 1) { const m = (lo + hi) >> 1; R[m][0] <= tau ? lo = m : hi = m; }
    const a = R[lo], b = R[hi], u = (tau - a[0]) / (b[0] - a[0]);
    return [tau, a[1], a[2].map((p, i) => [lerp(p[0], b[2][i][0], u), lerp(p[1], b[2][i][1], u)]),
      [lerp(a[3][0], b[3][0], u), lerp(a[3][1], b[3][1], u)], lerp(a[4], b[4], u), lerp(a[5], b[5], u), lerp(a[6], b[6], u), a[7], a[8]];
  }
  function drawMan(c, r, gx0, gy0) {
    c.save(); c.translate(gx0, gy0); c.scale(MAN_K, MAN_K); const gx = 0, gy = 0, LW = 2 / MAN_K;
    const d = r[8], T = (p) => [gx + p[0] * d, gy - p[1]];
    const [hip, sh, f1, f2, k1, k2, grip, ht, el, et] = r[2].map(T);
    const ln = (pts, w, col) => { c.beginPath(); c.moveTo(pts[0][0], pts[0][1]); for (let i = 1; i < pts.length; i++) c.lineTo(pts[i][0], pts[i][1]); c.lineWidth = w * LW; c.strokeStyle = col; c.stroke(); };
    const qd = (a, m, b, w, col) => { c.beginPath(); c.moveTo(a[0], a[1]); c.quadraticCurveTo(m[0], m[1], b[0], b[1]); c.lineWidth = w * LW; c.strokeStyle = col; c.stroke(); };
    c.lineCap = "round"; c.lineJoin = "round";
    const arm = (a, e, b, w, col) => r[7] ? qd(a, e, b, w, col) : ln([a, e, b], w, col);
    arm(sh, et, ht, 5.5, "rgba(255,255,255,0.6)");
    qd(sh, [(sh[0] + hip[0]) / 2 - d * 0.8, (sh[1] + hip[1]) / 2], hip, 6, "#FFFFFF");
    ln([hip, k1, f1], 6, "#FFFFFF"); ln([hip, k2, f2], 6, "#FFFFFF"); arm(sh, el, grip, 6, "#FFFFFF");
    const phi = r[4], len = r[5], butt = r[6], sp = Math.sin(phi), cp = Math.cos(phi);
    const tip = [grip[0] + sp * len * d, grip[1] + cp * len], bt = [grip[0] - sp * butt * d, grip[1] - cp * butt];
    ln([bt, tip], 3, "rgba(255,255,255,0.85)");
    const perp = [Math.cos(phi) * d, -Math.sin(phi)], cc = [tip[0] + perp[0] * 4.5, tip[1] + perp[1] * 4.5], half = 1.7;
    ln([[cc[0] - perp[0] * half, cc[1] - perp[1] * half], [cc[0] + perp[0] * half, cc[1] + perp[1] * half]], 13.6, "#FFFFFF");
    const hd = [sh[0] + d * r[3][0], sh[1] - r[3][1]];
    c.fillStyle = "#FFFFFF"; c.beginPath(); c.arc(hd[0], hd[1], 10, 0, Math.PI * 2); c.fill();
    // 프로펠러캡 (게임 setHat .propeller)
    c.fillStyle = "rgba(255,255,255,0.92)"; c.beginPath(); c.arc(hd[0], hd[1] - 6, 9.5, Math.PI, 0); c.closePath(); c.fill();
    c.beginPath(); c.ellipse(hd[0], hd[1] - 16.8, 8, 1.3, 0, 0, Math.PI * 2); c.fill(); c.fillRect(hd[0] - 0.9, hd[1] - 16.5, 1.8, 3);
    c.restore();
  }

  /* ── 굵은 포스터 선화 (보강 10-06): 굵기를 화면 px 기준 하한으로 — 카메라 배율이 작은 컷에서도 선이 ≥ 6px ── */
  let SCL = 1;                                   // 지금 그리는 컷의 카메라 배율(px/pt)
  const wpx = (pt, px) => Math.max(pt, px / SCL); // 게임 굵기(pt)와 화면 하한(px) 중 굵은 쪽
  const MAN_K = 1.5;                             // 스틱맨 키 ×1.5 (선은 ×2)

  /* ── 지형 그리기 (게임 화면 pt 좌표) ── */
  function drawTerrain(c, cut, bg) {
    const T = cut.terr;
    // 땅: 바탕보다 어두운 같은 색(그라데이션 없음) — 산의 실루엣이 폰에서도 읽히게
    c.fillStyle = shade(bg, 0.78); c.beginPath(); c.moveTo(T[0][0], 3000); for (const p of T) c.lineTo(p[0], p[1]); c.lineTo(T[T.length - 1][0], 3000); c.closePath(); c.fill();
    c.lineCap = "round"; c.lineJoin = "round";
    // 물: 수면 아래 12pt 옅은 면 + 점선 수면 (게임 규칙, 색만 흰색)
    for (let i = 0; i < T.length - 1; i++) if (T[i][2] === "water") { c.fillStyle = "rgba(255,255,255,0.22)"; c.fillRect(T[i][0], T[i][1], T[i + 1][0] - T[i][0] + 0.5, 12); }
    c.setLineDash([wpx(5, 16), wpx(4, 12)]); c.strokeStyle = "rgba(255,255,255,0.95)"; c.lineWidth = wpx(1.8, 7);
    for (let i = 0; i < T.length - 1; i++) if (T[i][2] === "water") { c.beginPath(); c.moveTo(T[i][0], T[i][1]); c.lineTo(T[i + 1][0], T[i + 1][1]); c.stroke(); }
    c.setLineDash([]);
    // 지형선: 러프·페어웨이·티 = 1.8pt, 그린 = 2.6pt 흰색
    const run = (pred, w, col) => { c.lineWidth = w; c.strokeStyle = col; c.beginPath(); let on = false;
      for (let i = 0; i < T.length - 1; i++) { if (pred(T[i][2])) { if (!on) { c.moveTo(T[i][0], T[i][1]); on = true; } c.lineTo(T[i + 1][0], T[i + 1][1]); } else on = false; } c.stroke(); };
    run((s) => s !== "water" && s !== "green", wpx(1.8, 7), "rgba(255,255,255,0.95)");
    run((s) => s === "green", wpx(2.8, 10), "#FFFFFF");
    c.lineWidth = wpx(1, 3); c.strokeStyle = "rgba(255,255,255,0.7)"; c.beginPath();
    for (const [x, y, l] of cut.ticks) { c.moveTo(x, y); c.lineTo(x + (l ? -0.8 : 0.9), y - (l ? 4.2 : 5.4)); } c.stroke();
    // 나무: 트렁크 + 6스캘럽 캐노피 (게임 규칙)
    for (const [gx, gy, cy, r] of cut.trees || []) {
      c.strokeStyle = "rgba(255,255,255,0.9)"; c.lineWidth = wpx(4.5, 12); c.beginPath(); c.moveTo(gx, gy - 1); c.lineTo(gx, cy + r * 0.3); c.stroke();
      c.beginPath();
      for (let k = 0; k < 6; k++) { const ph = Math.PI / 2 - k * Math.PI / 3; const cx = gx + 0.6 * r * Math.cos(ph), cyy = cy - 0.6 * r * Math.sin(ph);
        c.arc(cx, cyy, 0.48 * r, -(ph + 1.199), -(ph - 1.199), false); }
      c.closePath(); c.fillStyle = "rgba(255,255,255,0.18)"; c.fill(); c.strokeStyle = "rgba(255,255,255,0.95)"; c.lineWidth = wpx(2, 7); c.stroke();
    }
    if (cut.flag) drawFlag(c, cut.flag[0], cut.flag[1], bg);
  }
  function drawFlag(c, x, y, bg) {
    c.fillStyle = shade(bg, 0.45); c.fillRect(x - 5, y, 10, 9);
    const pw = wpx(1.2, 5); c.fillStyle = "rgba(255,255,255,0.95)"; c.fillRect(x - pw / 2, y - 62, pw, 62);
    c.fillStyle = "#E8402F"; c.beginPath(); c.moveTo(x, y - 62); c.lineTo(x + 21, y - 55.5); c.lineTo(x, y - 49); c.closePath(); c.fill();
  }
  function drawBall(c, x, y, a = 1) { const r = wpx(5.5, 12); c.globalAlpha = a; c.fillStyle = "#FFFFFF"; c.beginPath(); c.arc(x, y - (r - 5.5), r, 0, Math.PI * 2); c.fill();
    c.lineWidth = 3 / SCL; c.strokeStyle = "#0E0E10"; c.stroke(); c.globalAlpha = 1; }
  function drawTrail(c, pts) { if (pts.length < 2) return; c.strokeStyle = "rgba(255,255,255,0.8)"; c.lineWidth = wpx(1.3, 4.5); c.beginPath(); c.moveTo(pts[0][0], pts[0][1]); for (const p of pts) c.lineTo(p[0], p[1]); c.stroke(); }
  function drawDust(c, x, y, d) {   // 착지 먼지 6점 (게임 Effects.dust 결: 위로 0.16s → 아래로 0.26s)
    if (d < 0 || d > 0.42) return; const up = clamp(d / 0.16), dn = clamp((d - 0.16) / 0.26);
    c.globalAlpha = 0.95 * (1 - smooth((d - 0.18) / 0.24)); c.fillStyle = "#FFFFFF";
    for (const [dx, dy] of [[-6, 7], [-3, 10], [1, 11], [4, 8], [7, 6], [-9, 4]]) { c.beginPath(); c.arc(x + dx * 0.6 * outCubic(up) + dx * 0.4 * dn, y - 1 - dy * outCubic(up) + dy * 0.6 * dn * dn, wpx(1.3, 4), 0, 7); c.fill(); }
    c.globalAlpha = 1;
  }

  /* ── 3차: 지형 실루엣이 주인공 — prep.py가 이미 화면 px로 맞춰 둔 데이터(폭 89%, 세로 과장)를 그대로 그린다 ── */
  // 컷별 게임 시간 속도 [착지 전, 착지 뒤]. 0 = 자동(산정·폭포: 컷 첫 프레임이 첫 샷 τ=0 / 계단: 마지막 바운스가 컷 끝 6프레임 전)
  CUTS.forEach((cut, i) => {
    const len = (STARTS[i + 1] ?? V0) - STARTS[i], LF = LF_LAND[i], sp = SPEED[cut.key];
    let tl = cut.land[0];
    if (cut.key === "cascade") { const w = cut.ev.find((e) => e[1] === "water"); tl = w ? w[0] : tl; }
    cut.tl = tl;
    cut.spIn = sp[0] || (cut.key === "cascade" ? (tl - (cut.land[0] - 0.5)) / (LF / FPS) : tl / (LF / FPS));
    const lastB = Math.max(...cut.ev.filter((e) => e[1] === "bounce" || e[1] === "water").map((e) => e[0]), tl);
    cut.spOut = sp[1] || Math.max(1, (lastB - tl) / ((len - LF - 8) / FPS));
  });
  const tauOf = (cut, i, lf) => tauAt(lf, cut.tl, LF_LAND[i], cut.spIn, cut.spOut);
  const lfOfTau = (cut, i, tau) => { const LF = LF_LAND[i]; return tau <= cut.tl ? LF - (cut.tl - tau) / cut.spIn * FPS : LF + 2 + (tau - cut.tl) / cut.spOut * FPS; };
  const WATER = "#1E6BFF";
  function drawSil(c, cut, bg, lf, i) {
    const T = cut.terr;
    c.lineCap = "round"; c.lineJoin = "round";
    // 땅 실루엣(바탕보다 어두운 같은 색)
    c.fillStyle = shade(bg, 0.74); c.beginPath(); c.moveTo(T[0][0], 2400); for (const p of T) c.lineTo(p[0], p[1]); c.lineTo(T[T.length - 1][0], 2400); c.closePath(); c.fill();
    // 절벽·협곡 벽 빗금: 가파른 면(화면 기울기 > 1.1) 아래 땅 속에 45° 빗금
    if (cut.hatch) { c.save(); c.beginPath(); c.moveTo(T[0][0], 2400); for (const p of T) c.lineTo(p[0], p[1]); c.lineTo(T[T.length - 1][0], 2400); c.closePath(); c.clip();
      c.strokeStyle = "rgba(255,255,255,0.42)"; c.lineWidth = 4; c.beginPath();
      for (let k = 0; k < T.length - 1; k++) { const dx = T[k + 1][0] - T[k][0], dy = T[k + 1][1] - T[k][1]; if (Math.abs(dy / dx) < 1.1) continue;
        for (let x = T[k][0] - 4; x < T[k + 1][0] + 4; x += 6) { if (Math.round(x) % 18 > 5) continue; const y = Math.min(T[k][1], T[k + 1][1]); c.moveTo(x - 30, y + 30); c.lineTo(x + 150, y + 210); } }
      c.stroke(); c.restore(); }
    // 물: 수면부터 화면 아래까지 파랑 채움 + 흰 수면선
    for (let k = 0; k < T.length - 1; k++) if (T[k][2] === "water") { c.fillStyle = WATER; c.fillRect(T[k][0] - 0.5, T[k][1], T[k + 1][0] - T[k][0] + 1, 2400); }
    c.strokeStyle = "#FFFFFF"; c.lineWidth = 6; c.setLineDash([22, 12]);
    for (let k = 0; k < T.length - 1; k++) if (T[k][2] === "water") { c.beginPath(); c.moveTo(T[k][0], T[k][1]); c.lineTo(T[k + 1][0], T[k + 1][1]); c.stroke(); }
    c.setLineDash([]);
    // 지형선: 굵은 흰 선 7px, 그린 11px
    const run = (pred, w) => { c.lineWidth = w; c.strokeStyle = "#FFFFFF"; c.beginPath(); let on = false;
      for (let k = 0; k < T.length - 1; k++) { if (pred(T[k][2])) { if (!on) { c.moveTo(T[k][0], T[k][1]); on = true; } c.lineTo(T[k + 1][0], T[k + 1][1]); } else on = false; } c.stroke(); };
    run((s) => s !== "water" && s !== "green", 7); run((s) => s === "green", 11);
    // 러프 잔디 틱 (16px 간격)
    c.lineWidth = 3; c.strokeStyle = "rgba(255,255,255,0.75)"; c.beginPath(); let lean = false;
    for (let k = 0; k < T.length - 1; k++) if (T[k][2] === "rough") for (let x = T[k][0]; x < T[k + 1][0]; x += 16) {
      const u = (x - T[k][0]) / Math.max(1e-6, T[k + 1][0] - T[k][0]), y = lerp(T[k][1], T[k + 1][1], u); c.moveTo(x, y); c.lineTo(x + (lean ? -2.5 : 3), y - (lean ? 9 : 12)); lean = !lean; }
    c.stroke();
    // 큰 나무: 줄기 + 6스캘럽 캐노피 (캐노피 바닥은 실제 높이 그대로, 반지름만 크게)
    for (const [gx, gy, cy, r] of cut.trees) {
      c.strokeStyle = "#FFFFFF"; c.lineWidth = 16; c.beginPath(); c.moveTo(gx, gy); c.lineTo(gx, cy + r * 0.2); c.stroke();
      c.beginPath(); for (let k = 0; k < 6; k++) { const ph = Math.PI / 2 - k * Math.PI / 3; c.arc(gx + 0.6 * r * Math.cos(ph), cy - 0.6 * r * Math.sin(ph), 0.48 * r, -(ph + 1.199), -(ph - 1.199), false); }
      c.closePath(); c.fillStyle = shade(bg, 0.6); c.fill(); c.strokeStyle = "#FFFFFF"; c.lineWidth = 8; c.stroke();
    }
    if (cut.flag) { const [x, y] = cut.flag; c.fillStyle = shade(bg, 0.4); c.fillRect(x - 13, y, 26, 20); c.fillStyle = "#FFFFFF"; c.fillRect(x - 3, y - 150, 6, 150);
      c.fillStyle = "#E8402F"; c.beginPath(); c.moveTo(x + 3, y - 150); c.lineTo(x + 66, y - 128); c.lineTo(x + 3, y - 106); c.closePath(); c.fill(); }
  }
  function drawArch(c, i, lf, opt) {
    const cut = CUTS[i], bg = cut.bg, LF = LF_LAND[i];
    c.setTransform(1, 0, 0, 1, 0, 0); c.globalAlpha = 1; c.fillStyle = opt.inv || bg; c.fillRect(0, 0, W, H);
    const tau = tauOf(cut, i, lf), b = ballAt(cut.ball, tau);
    const lx = cut.land[2], ly = (cut.terr.find((p) => p[0] >= lx) || [0, b[1] + 14])[1];
    const d = lf - LF, pk = 1 + 0.15 * punchK(d), [shx, shy] = shakeXY(d, 18);
    // 줌 펀치는 착지점 기준, 흔들림은 화면 평행이동
    c.setTransform(pk, 0, 0, pk, lx - lx * pk + shx + (opt.dx || 0), ly - ly * pk + shy);
    const rv = opt.noReveal || i === 0 ? 1 : outCubic(lf / 7);
    c.save();
    if (rv < 1) { c.beginPath(); c.rect(-200, -200, (W * rv - (opt.dx || 0)) / pk + 200 + lx * (1 - 1 / pk), 3000); c.clip(); }
    drawSil(c, cut, bg, lf, i);
    // 궤적선(이 컷에서 보이기 시작한 곳부터) · 스틱맨(작게) · 공(지름 28px, 검정 테두리)
    const t0 = Math.max(0, tauOf(cut, i, 0) - 0.5), tr = [];
    for (let k = 0; k <= 60; k++) tr.push(ballAt(cut.ball, lerp(t0, tau, k / 60)));
    c.strokeStyle = "rgba(255,255,255,0.85)"; c.lineWidth = 5; c.beginPath(); c.moveTo(tr[0][0], tr[0][1]); for (const p of tr) c.lineTo(p[0], p[1]); c.stroke();
    if (cut.stick) { c.save(); SCL = 1; drawManPx(c, rigAt(V.RIG_H, Math.min(1.6, 0.9 + lf / FPS)), cut.stick[0], cut.stick[1], 2.0); c.restore(); }
    // 바운스마다 먼지, 입수마다 물결·물방울
    for (const e of cut.ev) { const el = lfOfTau(cut, i, e[0]); const dd = (lf - el) / FPS; const ey = (cut.terr.find((p) => p[0] >= e[2]) || [0, ly])[1];
      if (e[1] === "bounce") drawPuff(c, e[2], ey, dd); else if (e[1] === "water") drawSplash(c, e[2], ey, dd); }
    if (cut.key === "island") drawSplash(c, lx - 8, ly, (lf - LF) / FPS, 0.6);   // 물가 착지에 튄 물방울
    const inWater = cut.ev.some((e) => e[1] === "water" && tau > e[0] + 0.02);
    if (!inWater) { c.fillStyle = "#FFFFFF"; c.beginPath(); c.arc(b[0], b[1], 14, 0, Math.PI * 2); c.fill(); c.lineWidth = 3.5; c.strokeStyle = "#0E0E10"; c.stroke(); }
    c.restore(); c.setTransform(1, 0, 0, 1, 0, 0);
  }
  function drawPuff(c, x, y, d) { if (d < 0 || d > 0.4) return; const u = clamp(d / 0.4); c.globalAlpha = 0.95 * (1 - u); c.fillStyle = "#FFFFFF";
    for (const [dx, dy] of [[-16, 18], [-7, 26], [4, 28], [13, 20], [21, 12], [-24, 9]]) { c.beginPath(); c.arc(x + dx * outCubic(u) * 1.6, y - 4 - dy * outCubic(u) * 1.4 + 60 * u * u, 4.5, 0, 7); c.fill(); }
    c.globalAlpha = 1; }
  function drawSplash(c, x, y, d, k = 1) { if (d < 0 || d > 0.6) return; const u = clamp(d / 0.6);
    c.globalAlpha = 1 - u; c.strokeStyle = "#FFFFFF"; c.lineWidth = 5; c.beginPath(); c.ellipse(x, y, (14 + u * 90) * k, (4 + u * 18) * k, 0, 0, Math.PI * 2); c.stroke();
    c.fillStyle = "#FFFFFF"; for (const [dx, vy] of [[-22, 70], [-9, 95], [5, 105], [17, 85], [28, 60], [-30, 50]]) { const t = d; c.beginPath(); c.arc(x + dx * k * (1 + 2 * u), y - (vy * t - 260 * t * t) * 1.6 * k, 5, 0, 7); c.fill(); }
    c.globalAlpha = 1; }
  // 스틱맨(화면 px): 리그 단위 × k, 선은 게임 굵기 × k × 1.25
  function drawManPx(c, r, gx, gy, k) { c.save(); c.translate(gx, gy); c.scale(k / MAN_K, k / MAN_K); drawMan(c, r, 0, 0); c.restore(); }

  /* ── 화산 컷: T2 1차의 실캡처·리그 데이터 (게임 화면 pt) ── */
  const VPPM = V.PPM, VG = V.GROUND, VGX0 = V.GX0;
  const vgroundM = (xm) => { const i = clamp(xm - VGX0, 0, VG.length - 1.001), a = Math.floor(i); return lerp(VG[a], VG[a + 1], i - a); };
  const vground = (x) => vgroundM(x / VPPM);
  const [VX0, VY0] = V.TEE_BALL;
  const vpoly = (F, t) => [VX0 + F.cx[0] * t + F.cx[1] * t * t + F.cx[2] * t ** 3, VY0 + F.cy[0] * t + F.cy[1] * t * t + F.cy[2] * t ** 3];
  let VTL = 1.0; for (let t = 0.9; t < 3; t += 0.0005) { const [x, y] = vpoly(V.FLIGHT_H, t); if (y >= vground(x) - 5.5) { VTL = t; break; } }
  const VXL = vpoly(V.FLIGHT_H, VTL)[0], VT_LIP = 1.68, VT_HOLED = 1.74, VX_LIP = V.CUP_X + 3;
  function vball(t) {
    if (t <= VTL) return [...vpoly(V.FLIGHT_H, t), 0];
    if (t <= VT_LIP) { const u = (t - VTL) / (VT_LIP - VTL), x = lerp(VXL, VX_LIP, 0.7 * u + 0.3 * u * u); return [x, vground(x) - 5.5 - Math.sin(Math.PI * clamp((t - VTL) / 0.09)) * 1.6, 0]; }
    const u = clamp((t - VT_LIP) / (VT_HOLED - VT_LIP)); return [lerp(VX_LIP, V.CUP_X, smooth(u)), lerp(vground(VX_LIP) - 5.5, V.CUP_TOP + 7.5, u * u), 1];
  }
  const VOLC = { terr: VG.map((y, i) => [(VGX0 + i) * VPPM, y, (VGX0 + i) >= V.GREEN[0] && (VGX0 + i) <= V.GREEN[1] ? "green" : "rough"]), ticks: [], trees: [], flag: null };
  { let lean = false; for (let g = VGX0 + 0.9; g < VGX0 + VG.length - 1; g += 1.5) { if (!(g >= V.GREEN[0] && g <= V.GREEN[1])) VOLC.ticks.push([g * VPPM, vgroundM(g), lean ? 1 : 0]); lean = !lean; } }
  const VCAM = { s: 7.2, cx: 1738, cy: 828, sx: 505, sy: 1080 };
  const V_LAND = 16;

  /* ── 오프스크린(소프트웨어) 캔버스 두 장: 컷 한 장씩 그리고 합성 ── */
  const cv = document.createElement("canvas"); cv.width = W; cv.height = H; cv.style.cssText = "position:absolute;left:0;top:0;width:1080px;height:1920px"; root.appendChild(cv);
  const ctx = cv.getContext("2d", { willReadFrequently: true });
  const off = [0, 1].map(() => { const o = document.createElement("canvas"); o.width = W; o.height = H; return o.getContext("2d", { willReadFrequently: true }); });

  // 컷 i(0–7: 아키타입, 8: 화산)의 로컬 프레임 lf를 c에 그린다. inv: 플래시 프레임(바탕·선 색 맞바꿈)
  function drawCut(c, i, lf, opt = {}) {
    if (i < 8) { drawArch(c, i, lf, opt); return { holedLf: 1e9 }; }
    const isV = i === 8, cut = isV ? VOLC : CUTS[i], bg = isV ? VOLC_BG : CUTS[i].bg;
    const land = isV ? V_LAND : LF_LAND[i];
    c.setTransform(1, 0, 0, 1, 0, 0); c.globalAlpha = 1; c.fillStyle = opt.inv ? opt.inv : bg; c.fillRect(0, 0, W, H);
    const cam = VCAM;
    const d = lf - land, pk = 1 + 0.15 * punchK(d), [shx, shy] = shakeXY(d);
    let pk2 = 1, sh2 = [0, 0];
    let tau, b, holedLf = 1e9;
    if (isV) {
      tau = lf < land ? VTL - (land - lf) / FPS * 0.9 : lf < land + 2 ? VTL : VTL + (lf - land - 2) / FPS * 0.75;
      holedLf = land + 2 + (VT_HOLED - VTL) / 0.75 * FPS;
      pk2 = 1 + 0.12 * punchK(lf - holedLf); sh2 = shakeXY(lf - holedLf, 12);
      b = vball(tau);
    } else { tau = tauAt(lf, cut.land[0], land); b = ballAt(cut.ball, tau); }
    const s = cam.s * pk * pk2; SCL = s;
    c.setTransform(s, 0, 0, s, cam.sx - cam.cx * s + shx + sh2[0] + (opt.dx || 0), cam.sy - cam.cy * s + shy + sh2[1]);
    // 리빌: 지형·선화가 왼쪽에서 오른쪽으로 그려진다 (7프레임)
    const rv = opt.noReveal || i === 0 ? 1 : outCubic(lf / 7);   // 첫 컷은 첫 프레임부터 완결된 그림
    c.save();
    if (rv < 1) { const inv = 1 / s; c.beginPath(); c.rect(-1e4, -1e4, ((W * rv) - (cam.sx - cam.cx * s + (opt.dx || 0))) * inv + 1e4, 3e4); c.clip(); }
    drawTerrain(c, cut, bg);
    if (isV) drawFlag(c, V.CUP_X, V.CUP_TOP, bg);
    // 궤적선: 이 컷에서 보이기 시작한 지점부터 지금까지
    const t0 = isV ? VTL - land / FPS * 0.9 : tauAt(0, cut.land[0], land), tr = [];
    for (let k = 0; k <= 40; k++) { const tt = lerp(Math.max(0, t0 - 0.6), Math.min(tau, isV ? VTL : cut.land[0]), k / 40); tr.push(isV ? vball(tt) : ballAt(cut.ball, tt)); }
    if (tau > t0 - 0.6) drawTrail(c, tr);
    if (!isV && cut.stickIn) drawMan(c, rigAt(V.RIG_H, Math.min(1.6, 0.9 + lf / FPS)), cut.stick[0], cut.stick[1]);
    const lx = isV ? VXL : cut.land[2], ly = isV ? vground(VXL) : (cut.terr.find((p) => p[0] >= lx) || [0, b[1] + 5.5])[1];
    drawDust(c, lx, ly, (lf - land) / FPS * 0.6);
    if (isV && b[2]) { c.save(); c.beginPath(); c.rect(1600, 600, 400, V.CUP_TOP + 2.5 - 600); c.clip(); drawBall(c, b[0], b[1]); c.restore(); }
    else if (!(cut.key === "cascade" && tau > cut.land[0] + 0.02)) drawBall(c, b[0], b[1]);
    if (cut.key === "cascade") { const dd = (lf - land) / FPS; if (dd >= 0 && dd < 0.5) { c.strokeStyle = `rgba(255,255,255,${(0.9 * (1 - dd / 0.5)).toFixed(3)})`; c.lineWidth = 1.6; c.beginPath(); c.ellipse(lx, ly, 4 + dd * 40, 1.5 + dd * 8, 0, 0, Math.PI * 2); c.stroke(); } }
    c.restore();
    c.setTransform(1, 0, 0, 1, 0, 0);
    return { holedLf };
  }

  /* ── 글자 (DOM, left/top/font-size만) ── */
  const mkText = (html, cls, fs, color) => { const e = document.createElement("div"); e.className = "w " + cls; e.innerHTML = html; e.style.fontSize = fs + "px"; e.style.color = color; root.appendChild(e); return e; };
  const words = CUTS.map((c) => mkText(c.word, "word", 230, c.ink));
  const hook = mkText("홀마다<br>다른 산", "hook", 150, "#0E0E10");
  const vword = mkText("화산", "word", 230, "#FFFFFF");
  const vnew = mkText("NEW", "new", 92, "#0E0E10");
  const tag = mkText("9홀,<br>매번 다른 산.", "hook", 132, "#0E0E10");
  const end = document.createElement("div"); end.id = "end";
  end.innerHTML = `<div class="r"><div class="dash"></div></div><div class="r"><div class="wm">mini-golf</div></div>
    <div class="r"><div class="meta">macOS 메뉴바 앱 · 무료 · 오픈소스</div></div><div class="r"><div class="url">github.com/w0uldy0udaestar/mini-golf</div></div>`;
  root.appendChild(end);
  const endRows = [...end.querySelectorAll(".r > div")];
  const place = (e, x, y, vis = true) => { e.style.visibility = vis ? "visible" : "hidden"; e.style.left = Math.round(x) + "px"; e.style.top = Math.round(y) + "px"; };
  // 키네틱 단어: 오른쪽에서 날아들어 오버슈트로 멈추고, 휩 팬 때 장면과 같이 왼쪽으로 빠진다
  const flyIn = (lf, at) => 104 + (1 - outBack((lf - at) / 9)) * 700;   // 오버슈트 최저 x≈78 (안전 영역 70)

  /* ── 전환 합성: 휩 팬(6프레임, 모션 블러 4겹) ── */
  function composite(drawA, drawB, u) {
    const e = smooth(u), dx = -W * e;
    for (const [k, cvs, base] of [[0, off[0], dx], [1, off[1], dx + W]]) {
      (k ? drawB : drawA)(cvs);
      for (let m = 0; m < 4; m++) { ctx.globalAlpha = m === 0 ? 1 : 0.28; ctx.drawImage(cvs.canvas, Math.round(base + m * 26 * Math.sin(Math.PI * u)), 0); }
    }
    ctx.globalAlpha = 1;
    return dx;
  }

  function render(t) {
    const f = Math.min(NF - 1, Math.round(t * FPS));
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1;
    for (const e of [...words, hook, vword, vnew, tag]) e.style.visibility = "hidden";
    end.style.visibility = "hidden";
    // 어느 컷인가
    const all = [...STARTS, V0, TAG0, END0];
    let i = all.length - 1; while (i > 0 && f < all[i]) i--;
    const lf = f - all[i];
    const nextStart = all[i + 1] ?? 1e9;
    const sceneDraw = (k, l, opt) => (c) => drawCut(c, k, l, opt);
    let dxOut = 0;
    if (i <= 8) {
      // 다음 컷으로 휩 팬 중인가 (경계 3프레임 전부터 3프레임 뒤까지; 플래시 경계 제외)
      const toNext = i < 8 && !FLASH.has(nextStart) && f >= nextStart - 3;
      const fromPrev = i > 0 && !FLASH.has(all[i]) && lf < 3;
      if (toNext || fromPrev) {
        const a = toNext ? i : i - 1, b = a + 1, bStart = all[b], u = (f - (bStart - 3)) / 6;
        dxOut = composite(sceneDraw(a, f - all[a], { noReveal: true }), sceneDraw(b, f - bStart, {}), u);
        if (toNext) i = a;
      } else if (i < 8 && FLASH.has(nextStart) && f === nextStart - 1) {
        // 1프레임 컬러 스왑: 다음 컷 바탕색 위에 지금 컷의 선을 지금 바탕색으로
        const nb = nextStart === V0 ? VOLC_BG : CUTS[i + 1].bg;
        drawCut(off[0], i, lf, { inv: nb, noReveal: true }); ctx.drawImage(off[0].canvas, 0, 0);
      } else { drawCut(off[0], i, lf); ctx.drawImage(off[0].canvas, 0, 0); }
      // 단어
      const k = i, lk = f - all[k], tw = toNext => 0;
      const wordX = (at) => flyIn(lk, at) + (f >= nextStart - 3 && !FLASH.has(nextStart) ? -W * smooth((f - (nextStart - 3)) / 6) : 0);
      if (k === 0) {
        // 훅: 첫 프레임부터 "홀마다 / 다른 산" (6프레임에 걸쳐 살짝 내려앉는다) → 착지 때 위로 빠지고 "절벽"이 날아든다
        if (lk < 31) place(hook, 104, 336 - 16 * (1 - outCubic(lk / 6)) - (lk >= 27 ? 900 * inCubic((lk - 27) / 4) : 0));
        if (lk >= 29) place(words[0], wordX(29), 330);
      } else if (k <= 7) { if (lk >= 2) place(words[k], wordX(2), 330); }
      else {
        if (lk >= 2) place(vword, flyIn(lk, 2) + (f >= V1 - 3 ? -W * smooth((f - (V1 - 3)) / 6) : 0), 330);
        const hl = LF_LAND.length && (V_LAND + 2 + (VT_HOLED - VTL) / 0.75 * FPS);
        if (lk >= hl) { const u = outBack((lk - hl) / 7); vnew.style.fontSize = Math.round(92 * (0.4 + 0.6 * u)) + "px"; place(vnew, 560 + (f >= V1 - 3 ? -W * smooth((f - (V1 - 3)) / 6) : 0), 392 - 30 * (1 - u)); }
      }
    } else {
      // 한 줄 → 엔드카드 (노란 바탕). 화산 컷에서 휩 팬으로 들어온다
      if (f < TAG0 + 3) { composite(sceneDraw(8, f - V0, { noReveal: true }), (c) => { c.setTransform(1, 0, 0, 1, 0, 0); c.fillStyle = TAG_BG; c.fillRect(0, 0, W, H); }, (f - (TAG0 - 3)) / 6); }
      else { ctx.fillStyle = TAG_BG; ctx.fillRect(0, 0, W, H); }
      if (f < END0 + 4) { const lk = f - TAG0, out = f >= END0 ? inCubic((f - END0) / 4) : 0;
        place(tag, flyIn(lk, 1), 700 - 900 * out); }
      if (f >= END0) { end.style.visibility = "visible"; const lk = f - END0;
        endRows.forEach((e, j) => { const u = outBack((lk - 3 - j * 3) / 9); if (j === 0) e.style.width = Math.round(72 * clamp((lk - 3) / 6)) + "px"; else e.style.left = Math.round((1 - u) * 900) + "px"; }); }
    }
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;

  // ?audit=1 : 3프레임마다 글자 사각형과 공(화면 좌표)을 모은다
  function audit() {
    const out = { frames: [] };
    const rects = (e) => { const r = e.getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom].map(Math.round); };
    for (let f = 0; f < NF; f += 3) {
      render(f / FPS);
      const fr = { f, items: [] };
      for (const e of [...words, hook, vword, vnew, tag, ...endRows]) if (getComputedStyle(e).visibility === "visible" && (e !== endRows[0])) {
        const rg = document.createRange(); rg.selectNodeContents(e); for (const r of rg.getClientRects()) fr.items.push({ name: e.className || "end", r: [r.left, r.top, r.right, r.bottom].map(Math.round) }); }
      // 공·착지점 화면 좌표 (휩 팬 중간 프레임은 제외)
      const all = [...STARTS, V0]; let i = all.length - 1; while (i > 0 && f < all[i]) i--;
      if (f < TAG0 && (f - all[i]) >= 3 && (all[i + 1] ?? TAG0) - f > 3) {
        const lf = f - all[i];
        if (i < 8) { const cut = CUTS[i], b = ballAt(cut.ball, tauOf(cut, i, lf));
          const X = b[0], Y = b[1];
          fr.items.push({ name: "ball", r: [X - 20, Y - 20, X + 20, Y + 20].map(Math.round) }); }
      }
      out.frames.push(fr);
    }
    out.cams = CUTS.map((c) => ({ key: c.key, vx: +c.vx.toFixed(1), spIn: +c.spIn.toFixed(2), spOut: +c.spOut.toFixed(2) }));
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  // ?sfx=1 : 효과음 큐(전역 프레임)를 <pre id="sfx">에 — scripts/make-audio.py가 읽는다(그림과 소리의 단일 출처)
  function sfx() {
    const out = [], all = [...STARTS, V0, TAG0, END0];
    const clubKind = (cl) => /DR|3W|5W/.test(cl) ? "driver" : /SW|PW|8I|9I/.test(cl) ? "wedge" : "iron";
    CUTS.forEach((cut, i) => {
      const f0 = STARTS[i], len = all[i + 1] - f0;
      if (i > 0) out.push([f0, FLASH.has(f0) ? "flash" : "whoosh"]);
      out.push([f0 + 1, "impact-" + clubKind(cut.club || "7I")]);
      let first = true;
      for (const e of cut.ev) { const lf = Math.round(lfOfTau(cut, i, e[0])); if (lf < 0 || lf >= len) continue;
        if (e[1] === "water") out.push([f0 + lf, "splash"]); else if (e[1] === "bounce") { out.push([f0 + lf, first ? "thud" : "tok"]); first = false; } }
      if (cut.key === "summit") { let t = 0; for (const e of cut.ev) if (e[1] === "bounce" && e[0] > t + 1.5) { t = e[0]; } }
      if (cut.key === "forest" && cut.trees.length) { const tx = cut.trees[0][0]; for (let lf = 0; lf < len; lf++) { const b = ballAt(cut.ball, tauOf(cut, i, lf)); if (b[0] >= tx - 40) { out.push([f0 + lf, "swish"]); break; } } }
      if (cut.key === "island") out.push([f0 + LF_LAND[i] + 1, "splash-small"]);
    });
    out.push([V0, "flash"], [V0 + 1, "impact-wedge"], [V0 + V_LAND, "thud"]);
    const hl = Math.round(V_LAND + 2 + (VT_HOLED - VTL) / 0.75 * FPS); out.push([V0 + hl, "cup"], [V0 + hl + 1, "chime"]);
    out.push([TAG0 - 3, "whoosh"], [END0, "whoosh-up"], [END0 + 8, "end-chime"]);
    out.sort((a, b) => a[0] - b[0]);
    const pre = document.createElement("pre"); pre.id = "sfx"; pre.textContent = JSON.stringify({ fps: FPS, nf: NF, cues: out }); document.body.appendChild(pre);
  }
  document.fonts.ready.then(() => { if (q.has("audit")) audit(); if (q.has("sfx")) sfx(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); });
})();
