/* T1 「거위가 공 위에 앉았다」 v3 — 전부 벡터 (세로 1080×1920 · 12.5초 · 한국어 · 무음 완결)
 *
 * 화면은 SVG 하나. 게임 그림을 게임 소스의 도형 치수(Surprises*.swift: makeGoose·makeBird·makeMole·makeCat·makeDog·
 * makeSpectator, GameScene: 공 r5.5 · 깃대 62pt · 깃발 천 (0,62)-(21,55.5)-(0,49))로 다시 그린다. 위치·시각은
 * scripts/extract.py가 실제 게임 창 캡처에서 뽑은 data/scenes.js(원본 2x 픽셀)를 30fps로 보간한다. 캡처 그림 자체는 쓰지 않는다.
 * 모든 상태는 render(t)의 순수 함수. 난수·시계·네트워크 없음.
 *
 * 색: 선명한 노랑 단색 바탕 · 검정 선화(굵게) · 공만 흰색+검정 테두리 · 깃발만 빨강 · 마지막 데스크탑은 라이트 모드 흰 창
 * 모션 기법: ① 컷마다 휩 팬(4f, 가로 모션 블러) ② 사건 순간 2f 히트스톱 + 화면 흔들림(±8px, 6f 감쇠)
 *           ③ 키네틱 자막(단어마다 scale 1.3→1, 4f, 2f 간격) ④ 풀백 속도 램프(cubic in-out 1.5초, ×2.4→×0.224) ⑤ 띠 강조 테두리 쓸기
 */
(() => {
  const FPS = 30, DUR = 12.5, NF = 375;
  const W = 1080, H = 1920;
  const root = document.getElementById("root");
  const q = new URLSearchParams(location.search);
  const S = window.SCENES;
  // 지형선 고르기: 추출 표본(6~8px 간격)의 계단을 이동 평균(±3)으로 펴서 확대해도 꺾임이 안 보이게
  for (const k of Object.keys(S)) { const T = S[k].terrain; if (!T) continue;
    S[k].terrain = T.map((p, i) => { let a = 0, n = 0; for (let j = Math.max(0, i - 3); j <= Math.min(T.length - 1, i + 3); j++) { a += T[j][1]; n++; } return [p[0], a / n]; }); }
  const YEL = "#FFD21F", INK = "#111111", RED = "#E5372B";

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const prog = (t, a, d) => clamp((t - a) / d);
  const outCubic = (u) => 1 - Math.pow(1 - u, 3);
  const inOutSine = (u) => 0.5 - 0.5 * Math.cos(Math.PI * clamp(u));
  const inOutCubicR = (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
  const inOutQuart = (u) => (u < 0.5 ? 8 * u * u * u * u : 1 - Math.pow(-2 * u + 2, 4) / 2);
  const inOutExpo = (u) => (u <= 0 ? 0 : u >= 1 ? 1 : u < 0.5 ? Math.pow(2, 20 * u - 10) / 2 : (2 - Math.pow(2, -20 * u + 10)) / 2);
  const F = (n) => n / FPS;
  function interp(track, ct, i1 = 1, i2 = 2) {   // [t, a, b, ...] 표본을 시각 ct로 선형 보간
    if (!track.length) return null;
    if (ct <= track[0][0]) return [track[0][i1], track[0][i2]];
    for (let k = 1; k < track.length; k++) if (ct <= track[k][0]) {
      const a = track[k - 1], b = track[k], u = (ct - a[0]) / (b[0] - a[0]);
      return [lerp(a[i1], b[i1], u), lerp(a[i2], b[i2], u)];
    }
    const z = track[track.length - 1]; return [z[i1], z[i2]];
  }
  function groundY(terr, x) {
    if (x <= terr[0][0]) return terr[0][1];
    for (let k = 1; k < terr.length; k++) if (x <= terr[k][0]) { const a = terr[k - 1], b = terr[k]; return lerp(a[1], b[1], (x - a[0]) / (b[0] - a[0])); }
    return terr[terr.length - 1][1];
  }

  /* ── SVG 조각 (원본 2x 픽셀 좌표, y 아래로). 게임 도형(pt, y 위로, 원점=발)을 pt→2px로 옮긴다 ── */
  const f1 = (v) => v.toFixed(1);
  // 게임 좌표 → 원본 좌표: (ox, oy) 발 위치, dir 1=오른쪽 보기, -1=왼쪽
  const P = (ox, oy, dir) => (x, y) => [ox + dir * x * 2, oy - y * 2];
  const ell = (c, rx, ry, fill, sw = 0, rot = 0) => `<ellipse cx="${f1(c[0])}" cy="${f1(c[1])}" rx="${f1(rx)}" ry="${f1(ry)}" fill="${fill}"${sw ? ` stroke="${INK}" stroke-width="${f1(sw)}"` : ""}${rot ? ` transform="rotate(${f1(rot)} ${f1(c[0])} ${f1(c[1])})"` : ""}/>`;
  const line = (pts, sw, col = INK) => `<polyline points="${pts.map((p) => f1(p[0]) + "," + f1(p[1])).join(" ")}" fill="none" stroke="${col}" stroke-width="${f1(sw)}" stroke-linecap="round" stroke-linejoin="round"/>`;
  const quad = (a, c, b, sw) => `<path d="M${f1(a[0])},${f1(a[1])} Q${f1(c[0])},${f1(c[1])} ${f1(b[0])},${f1(b[1])}" fill="none" stroke="${INK}" stroke-width="${f1(sw)}" stroke-linecap="round"/>`;
  const rotP = (o, p, ang) => { const s = Math.sin(ang), c = Math.cos(ang); return [o[0] + (p[0] - o[0]) * c - (p[1] - o[1]) * s, o[1] + (p[0] - o[0]) * s + (p[1] - o[1]) * c]; };
  const OUT = 1.6;   // 검정 실루엣 둘레 덧선(원본 px) — 도형이 굵게 읽히게

  const ball = (x, y, sw) => `<circle cx="${f1(x)}" cy="${f1(y)}" r="11" fill="#fff" stroke="${INK}" stroke-width="${f1(sw)}"/>`;
  function goose(ox, oy, dir, opt = {}) {   // makeGoose: 몸 20×10 @(0,6) · 목 (7,8)→Q(12,12)→(11,21) 2.6 · 머리 r3.2 @(11.5,22) · 부리 (14,22)→(19,21) · 다리
    const p = P(ox, oy, dir); let s = "";
    if (!opt.sit && !opt.fly) for (const lx of [-3, 3]) s += line([p(lx, 3), p(lx - 1 + (opt.step ? Math.sin(opt.step + lx) : 0), 0)], 3.4);
    if (opt.fly) {   // 날개 (날 때만): 등에서 뒤·위로 꺾여 뻗고 위아래로 친다
      const a = Math.sin(opt.fly);
      s += line([p(2, 10), p(-6, 13 + a * 7), p(-15, 11 + a * 12)], 5.2);
    }
    s += ell(p(0, 6), 20, 10, INK, OUT);
    const hb = opt.bob || 0;
    s += quad(p(7, 8), p(12, 12), p(11 + hb * 0.4, 21 + hb), 5.6);
    s += `<circle cx="${f1(p(11.5 + hb * 0.4, 22 + hb)[0])}" cy="${f1(p(11.5 + hb * 0.4, 22 + hb)[1])}" r="6.8" fill="${INK}"/>`;
    s += line([p(14 + hb * 0.4, 22 + hb), p(19 + hb * 0.4, 21 + hb)], 4.2);
    return s;
  }
  function bird(ox, oy, dir, flap) {   // makeBird: 몸 16×9 · 날개 (-10,6)→(-1,1)→(8,6) 2.4 · 부리 (8,1)→(13,-1)
    const p = P(ox, oy, dir), a = Math.sin(flap) * 6;
    return ell(p(0, 0), 16, 9, INK, OUT) + line([p(-10, 6 + a), p(-1, 1), p(8, 6 + a)], 5) + line([p(8, 1), p(13, -1)], 4.2);
  }
  function mole(ox, oy, rise) {   // makeMole: 반원 r9 + 코 r2.2 @(0,8) — rise 0..1 만큼 땅 위로
    const r = 18, y0 = oy + (1 - rise) * 22;
    return `<g clip-path="url(#above)"><path d="M${f1(ox - r)},${f1(y0)} A${r},${r} 0 0 1 ${f1(ox + r)},${f1(y0)} Z" fill="${INK}"/>` +
      `<circle cx="${f1(ox)}" cy="${f1(y0 - 16)}" r="4.8" fill="${INK}"/><circle cx="${f1(ox + 7)}" cy="${f1(y0 - 9)}" r="2.2" fill="${YEL}"/></g>`;
  }
  function cat(ox, oy, dir, ct) {   // makeCat: 몸 34×14 @(0,9) · 머리 r7.5 @(17,16) · 귀 · 꼬리 Q · 다리 3 · 눈
    const p = P(ox, oy, dir); let s = "";
    const sw = Math.sin(ct * 2 * Math.PI / 1.2) * 0.25;   // 꼬리 ±0.25rad, 1.2초 주기
    const base = p(-16, 10), tip = rotP(base, p(-28, 26), dir * sw), ctl = rotP(base, p(-30, 8), dir * sw);
    s += quad(base, ctl, tip, 6.4);
    [-11, -6, 6].forEach((lx, i) => { const ph = ct * 14 + i * 2.1; s += line([p(lx, 6), p(lx + Math.sin(ph) * 3.2, 0)], 6); });
    s += ell(p(0, 9), 34, 14, INK, OUT);
    s += line([p(12, 7), p(12 + Math.sin(ct * 14 + 1) * 3, 0)], 6);
    s += `<circle cx="${f1(p(17, 16)[0])}" cy="${f1(p(17, 16)[1])}" r="15" fill="${INK}"/>`;
    for (const ex of [13, 20]) s += `<polygon points="${[p(ex, 21), p(ex + 2.5, 28), p(ex + 5, 21)].map((v) => f1(v[0]) + "," + f1(v[1])).join(" ")}" fill="${INK}"/>`;
    s += `<circle cx="${f1(p(20, 17)[0])}" cy="${f1(p(20, 17)[1])}" r="3" fill="${YEL}"/>`;
    return s;
  }
  function dog(ox, oy, dir, ct, moving, carry) {   // makeDog: 몸 26×11 @(0,10) · 머리 r6 @(13,17) · 주둥이 · 귀 · 눈 · 꼬리 · 다리 두 쌍
    const p = P(ox, oy, dir); let s = "";
    const tw = Math.sin(ct * 2 * Math.PI / 0.16) * 0.38;
    const tb = p(-12, 12); s += quad(tb, rotP(tb, p(-20, 13), dir * tw), rotP(tb, p(-19, 21), dir * tw), 5.4);
    [[-8, 7], [-5, 10]].forEach((xs, i) => xs.forEach((x) => {
      const a = moving ? Math.sin(ct * 2 * Math.PI / 0.24 + i * Math.PI) * 0.35 : 0;
      const top = p(x, 7); s += line([top, rotP(top, p(x, 0), dir * a)], 5);
    }));
    s += ell(p(0, 10), 26, 11, INK, OUT);
    s += `<circle cx="${f1(p(13, 17)[0])}" cy="${f1(p(13, 17)[1])}" r="12" fill="${INK}"/>`;
    s += ell(p(18, 15), 7, 4.5, INK);
    s += ell(p(10.5, 17), 4.5, 8.5, INK, 0, dir * -20);
    s += `<circle cx="${f1(p(15.5, 18.5)[0])}" cy="${f1(p(15.5, 18.5)[1])}" r="2.6" fill="${YEL}"/>`;
    if (carry) s += ball(p(21, 13)[0], p(21, 13)[1] + 3, 4);
    return s;
  }
  function flag(x, yBase, lift, legPh, walking) {   // 깃대 62pt + 천(빨강) + 다리 2개 (s·3, -9) ±0.5rad 0.1초
    const yb = yBase - lift; let s = "";
    if (walking) [-1, 1].forEach((sg, i) => { const a = Math.sin(legPh + i * Math.PI) * 0.5; const o = [x, yb - 2]; s += line([o, rotP(o, [x + sg * 6, yb + 18], a)], 5); });
    s += line([[x, yb], [x, yb - 124]], 5.5);
    s += `<polygon points="${f1(x)},${f1(yb - 124)} ${f1(x + 42)},${f1(yb - 111)} ${f1(x)},${f1(yb - 98)}" fill="${RED}" stroke="${INK}" stroke-width="3" stroke-linejoin="round"/>`;
    return s;
  }
  function spectator(x, y, v, cheer, hop, walkPh) {   // makeSpectator: 키 22/25/20/24 · 몸·다리 2.2 · 머리 r3.4 · 홀수는 모자 챙 · 팔 2개
    const h = [22, 25, 20, 24][v % 4] * [0.95, 1.05, 0.9, 1.0][v % 4], p = P(x, y - hop, 1); let s = "";
    const lw = walkPh == null ? 0 : Math.sin(walkPh) * 2.5;
    s += line([p(-4 + lw, 0), p(0, h * 0.45), p(4 - lw, 0)], 4.6) + line([p(0, h * 0.45), p(0, h)], 4.6);
    for (const sx of [-1, 1]) { const sh = p(0, h * 0.9); const hand = cheer ? p(sx * 6, h * 0.9 + 8) : p(sx * 2, h * 0.9 - 8); s += line([sh, hand], 4.6); }
    const hc = p(0, h + 4.5); s += `<circle cx="${f1(hc[0])}" cy="${f1(hc[1])}" r="7.2" fill="${INK}"/>`;
    if (v % 2 === 1) s += `<rect x="${f1(hc[0] - 10)}" y="${f1(hc[1] - 9.5)}" width="20" height="3.6" rx="1.5" fill="${INK}"/>`;
    return s;
  }
  function stickman(x, y, walkPh) {   // 피니시 자세(캡처 외곽 1498–1624 × 1775–1972 에 맞춘 자세) — 걸을 때는 다리만 흔든다
    const k = walkPh == null ? 0 : Math.sin(walkPh); let s = "";
    const hip = [x + 30, y - 78], neck = [x + 18, y - 150], head = [x + 12, y - 178];
    s += line([[x + 10 + k * 14, y], [hip[0] - 4, hip[1] + 30], hip], 13) + line([[x + 62 - k * 14, y - 2], [hip[0] + 18, hip[1] + 34], hip], 13);
    s += line([hip, neck], 13);
    const hand = [x + 50, y - 168];
    s += line([neck, [x + 40, y - 138], hand], 11) + line([neck, [x + 6, y - 140], hand], 11);
    s += line([hand, [x + 118, y - 182]], 8) + ell([x + 121, y - 182], 14, 11, INK);
    s += `<circle cx="${f1(head[0])}" cy="${f1(head[1])}" r="26" fill="${INK}"/>`;
    return s;
  }
  function tree(x, yG) {
    let s = line([[x, yG], [x, yG - 120]], 11);
    for (const [dx, dy, r] of [[0, -150, 30], [-26, -132, 22], [26, -132, 22], [-18, -170, 22], [18, -170, 22]]) s += `<circle cx="${x + dx}" cy="${yG + dy}" r="${r}" fill="${INK}"/>`;
    return s;
  }
  const terrainPath = (terr, sw) => line(terr, sw);

  /* ── 컷 (광고 시각 t0~t1, 캡처 시각 c = c0 + sp·(t−t0), 사건 ev(캡처 시각)에서 2f 히트스톱) ── */
  const CUTS = [
    { id: "geese", t0: 0, t1: 2.75, c0: 5.11, sp: 1.0, ev: 6.64, f: [2312, 1763], a: [500, 1180], z: (t) => lerp(4.2, 4.3, prog(t, 0, 1.5)) - 1.1 * inOutSine(prog(t, 1.6, 0.5)) },
    { id: "bird", t0: 2.75, t1: 3.8, c0: 2.05, sp: 1.15, ev: 2.45, f: [775, 1900], a: [500, 1320], z: (t) => lerp(3.0, 3.1, prog(t, 2.75, 1.05)) },
    { id: "pin", t0: 3.8, t1: 4.75, c0: 1.25, sp: 1.4, ev: null, f: [3440, 1760], a: [500, 1290], z: (t) => lerp(4.0, 4.12, prog(t, 3.8, 0.95)) },
    { id: "mole", t0: 4.75, t1: 5.55, c0: 0.85, sp: 1.5, ev: 1.62, f: [1400, 1950], a: [500, 1180], z: (t) => lerp(5.0, 5.15, prog(t, 4.75, 0.8)) },
    { id: "cat", t0: 5.55, t1: 6.25, c0: 2.3, sp: 1.3, ev: null, f: null, a: [500, 1180], z: (t) => 3.0 },
    { id: "dog", t0: 6.25, t1: 6.9, c0: 1.45, sp: 1.6, ev: 1.99, f: [1170, 1935], a: [500, 1180], z: (t) => lerp(3.6, 3.7, prog(t, 6.25, 0.65)) },
    { id: "gallery", t0: 6.9, t1: DUR, c0: 0.0, sp: 1.0, ev: null, f: [1660, 1905], a: [500, 1150], z: (t) => lerp(2.4, 2.46, prog(t, 6.9, 0.65)) },
  ];
  const PULL = [7.5, 9.0];
  const SCR = { x: 60, y: 800, w: 860 }; SCR.h = SCR.w * 2160 / 3840; const Z1 = SCR.w / 3840;
  const HS = 2;   // 히트스톱 프레임
  const capTime = (c, t) => {
    if (c.ev == null) return c.c0 + c.sp * (t - c.t0);
    const te = c.t0 + (c.ev - c.c0) / c.sp;
    if (t < te) return c.c0 + c.sp * (t - c.t0);
    if (t < te + F(HS)) return c.ev;
    return c.c0 + c.sp * (t - c.t0 - F(HS));
  };
  const SHAKE = [[8, -5], [-7, 6], [5, 3], [-4, -4], [2, 2], [-1, 0]];
  const shakeAt = (c, t) => {
    if (c.ev == null) return [0, 0];
    const te = c.t0 + (c.ev - c.c0) / c.sp, k = Math.round((t - te) * FPS);
    return k >= 0 && k < SHAKE.length ? SHAKE[k] : [0, 0];
  };

  /* ── 장면 그리기 (캡처 시각 ct, 화면 배율 z — 선 굵기를 화면 px로 맞추려 z를 받는다) ── */
  function scene(id, ct, z) {
    const T = S[id === "gallery" ? "gallery" : id].terrain; const lw = 15 / z; let s = terrainPath(T, lw);
    const bsw = 6 / z;
    if (id === "geese") {
      const G = S.geese.geese, b = S.geese.ball[0];
      const takeoff = ct >= 6.64;
      const flock = takeoff ? interp(S.geese.actor, ct) : null, f0 = S.geese.actor[0];
      const dx = flock ? flock[0] - f0[1] : 0, dy = flock ? flock[1] - f0[2] : 0;
      // 알 (날아오른 뒤) — 게임: 공 옆 11pt, 5×7pt 타원
      if (ct >= 6.7) s += ell([b[1] + 24, groundY(T, b[1] + 24) - 8], 6.5, 8.5, "#fff", bsw * 0.8);
      s += ball(b[1], groundY(T, b[1]) - 11, bsw);
      G.forEach((g, i) => {
        const ox = g[2] - 20, sit = i === 1 && !takeoff;
        const k = takeoff ? 1 + 0.12 * (i - 2) : 1;
        const lag = takeoff ? clamp((ct - 6.64 - i * 0.025) / 0.1) : 0;
        const x = ox + dx * k * lag, y = (sit ? groundY(T, ox) - 14 : groundY(T, ox)) + dy * k * lag;
        const bob = takeoff ? 0 : Math.sin(ct * (sit ? 9 : 5.5) + i * 1.7) * (sit ? 1.6 : 2.2);
        s += goose(x, y + (sit ? Math.abs(Math.sin(ct * 4.5)) * 4 : 0), -1, { sit, fly: takeoff ? ct * 26 + i : 0, step: takeoff ? 0 : null, bob });
      });
      return s;
    }
    if (id === "bird") {
      const tx = 828; s += tree(tx, groundY(T, tx));
      const bp = interp(S.bird.ball, ct); const by = bp[1];
      let bx = bp[0], bdy = by;
      if (ct < 2.36) { bx = S.bird.ball[0][1]; bdy = groundY(T, bx) - 11; }
      s += ball(bx, bdy, bsw);
      // 새: 1.55초에 오른쪽 위에서 내려와 1.85초에 공 위에 앉고, 2.36초부터 공을 물고 솟는다(공 궤적 = 실캡처)
      let x, y, flap;
      if (ct < 1.85) { const u = inOutSine(prog(ct, 1.5, 0.35)); x = lerp(1040, bx + 4, u); y = lerp(1700, bdy - 22, u); flap = ct * 30; }
      else if (ct < 2.36) { x = bx + 4; y = bdy - 22 + Math.abs(Math.sin(ct * 18)) * -3; flap = ct * 8; }
      else { x = bx + 4; y = bdy - 20; flap = ct * 34; }
      s += bird(x, y, -1, flap);
      return s;
    }
    if (id === "pin") {
      const fp = interp(S.pin.flag, ct); const x = fp[0];
      const walking = ct >= 1.3 && ct <= 2.6;
      const lift = walking ? 18 * clamp(Math.min((ct - 1.3) / 0.08, (2.6 - ct) / 0.08)) : 0;
      const cupX = ct < 2.6 ? 3471 : 3410;
      s += `<rect x="${cupX - 13}" y="${f1(groundY(T, cupX) - 2)}" width="26" height="24" fill="${INK}"/>`;
      if (ct >= 2.45 && ct < 2.9) for (let i = 0; i < 4; i++) { const u = (ct - 2.45) / 0.45, a = -1.2 + i * 0.8; s += `<circle cx="${f1(3410 + Math.cos(a) * 40 * u)}" cy="${f1(groundY(T, 3410) - 6 - Math.sin(Math.PI * u) * (30 + i * 8))}" r="5" fill="${INK}"/>`; }
      s += flag(x, groundY(T, x), lift, ct * 2 * Math.PI / 0.2, walking);
      return s;
    }
    if (id === "mole") {
      const bp = interp(S.mole.ball, ct);
      const rise = ct < 0.84 ? 0 : ct < 1.95 ? outCubic(prog(ct, 0.84, 0.18)) : 1 - prog(ct, 1.95, 0.15);
      if (ct >= 0.35 && ct < 0.85) for (let i = 0; i < 3; i++) { const u = prog(ct, 0.35 + i * 0.08, 0.35); if (u > 0 && u < 1) s += `<circle cx="${f1(1412 + (i - 1) * 12 * u)}" cy="${f1(1958 - Math.sin(Math.PI * u) * (22 + i * 6))}" r="3.6" fill="${INK}"/>`; }
      s += ball(bp[0], groundY(T, bp[0]) - 11, bsw);
      s += mole(1418, groundY(T, 1418), rise);
      return s;
    }
    if (id === "cat") {
      const fx = S.cat.fit.x, x = fx[0] * ct + fx[1], y = groundY(T, x);
      s += cat(x + 34, y, -1, ct);
      // 커서(일반형 화살표): 창 캡처에는 안 찍히는 진짜 커서 자리 — 고양이 앞 115px(원본)
      const cx = x - 115 + 14 * Math.sin(ct * 7.1), cy = y - 110 + 10 * Math.sin(ct * 5.3 + 1.2), k = 1.9;
      const pts = [[0, 0], [0, 23], [5.6, 17.8], [9.4, 26.6], [13, 25], [9.3, 16.4], [16.8, 16.4]].map(([a, b]) => f1(cx + a * k) + "," + f1(cy + b * k)).join(" ");
      s += `<polygon points="${pts}" fill="#fff" stroke="${INK}" stroke-width="${f1(4.6 / z * 1.9)}" stroke-linejoin="round"/>`;
      return s;
    }
    if (id === "dog") {
      const a = interp(S.dog.actor, ct), dir = ct < 2.2 ? -1 : 1;
      const prev = interp(S.dog.actor, ct - 0.05), moving = Math.abs(a[0] - prev[0]) > 1.2 || ct < 2.0;
      const carry = ct >= 1.99;
      if (!carry) s += ball(S.dog.ball[0][1], groundY(T, S.dog.ball[0][1]) - 11, bsw);
      const ox = a[0] - dir * 6;
      s += dog(ox, groundY(T, ox), dir, ct, moving, carry);
      return s;
    }
    if (id === "gallery") {
      const fl = S.gallery.flag, bxy = S.gallery.ballxy;
      if (fl) s += flag(fl[0], groundY(T, fl[0]), 0, 0, false);
      if (bxy) s += ball(bxy[0], groundY(T, bxy[0]) - 11, bsw);
      const xs = [1646, 1706, 1766, 1826];
      xs.forEach((x0, i) => {
        const cheer = ct < 1.3, hop = cheer ? Math.abs(Math.sin((ct + i * 0.07) * Math.PI / 0.3)) * 14 : 0;
        const x = ct < 1.5 ? x0 : x0 - (ct - 1.5) * 120;
        s += spectator(x, groundY(T, x), i, cheer, hop, ct < 1.5 ? null : ct * 12 + i);
      });
      const mx = ct < 2.0 ? 1500 : 1500 - (ct - 2.0) * 70;
      s += stickman(mx, groundY(T, mx + 30), ct < 2.0 ? null : ct * 9);
      return s;
    }
    return s;
  }
  function desktop(k) {   // 라이트 모드 창(흰 창 · 연회색 테두리) + 메뉴바 — 원본 3840×2160 좌표. k = 진하기(색을 노랑과 섞는다 — 그룹 투명도 없음)
    if (k <= 0) return "";
    const Y = [255, 210, 31], mix = (rgb) => "rgb(" + rgb.map((v, i) => Math.round(Y[i] + (v - Y[i]) * clamp(k))).join(",") + ")";
    const WHITE = mix([255, 255, 255]), BORDER = mix([210, 210, 210]), BAR = mix([226, 226, 226]), DOT = mix([217, 217, 217]), TXT = mix([233, 233, 233]), MB = mix([250, 250, 250]), MBI = mix([201, 201, 201]);
    let s = `<rect x="0" y="0" width="3840" height="46" fill="${MB}"/>`;
    for (const x of [40, 150, 250, 350, 450]) s += `<rect x="${x}" y="15" width="64" height="16" rx="6" fill="${MBI}"/>`;
    const win = (x0, y0, x1, y1, rows, indent) => {
      let w = `<rect x="${x0}" y="${y0}" width="${x1 - x0}" height="${y1 - y0}" rx="22" fill="${WHITE}" stroke="${BORDER}" stroke-width="8"/>`;
      w += `<path d="M${x0 + 4},${y0 + 66} H${x1 - 4}" stroke="${BAR}" stroke-width="6"/>`;
      for (let i = 0; i < 3; i++) w += `<circle cx="${x0 + 38 + i * 38}" cy="${y0 + 34}" r="12" fill="${DOT}"/>`;
      let y = y0 + 110, seed = x0 * 7 + 3;
      for (let r = 0; r < rows && y < y1 - 60; r++) { seed = (seed * 1103515245 + 12345) & 0x7fffffff; const u = seed / 0x7fffffff;
        const ind = indent ? Math.floor(u * 4) * 56 : 0, len = 260 + Math.floor(((seed >> 7) % 1000) / 1000 * (x1 - x0 - 520));
        if (u > 0.1) w += `<rect x="${x0 + 70 + ind}" y="${y}" width="${len}" height="20" rx="8" fill="${TXT}"/>`; y += 54; }
      return w;
    };
    s += win(150, 130, 1390, 1440, 30, true) + win(2000, 250, 3680, 1440, 30, false) + win(1230, 470, 2150, 1290, 14, false);
    return s;
  }

  /* ── 요소 ── */
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg"); svg.setAttribute("viewBox", `0 0 ${W} ${H}`); svg.setAttribute("width", W); svg.setAttribute("height", H);
  svg.style.cssText = "position:absolute;left:0;top:0";
  svg.innerHTML = `<defs><filter id="hblur" x="-20%" y="0" width="140%" height="100%"><feGaussianBlur id="hb" stdDeviation="0 0"/></filter>
    <clipPath id="above"><rect x="0" y="0" width="4000" height="1958"/></clipPath></defs>
    <rect width="${W}" height="${H}" fill="${YEL}"/><g id="cam"><g id="world"></g></g><g id="frame"></g>`;
  root.appendChild(svg);
  const cam = svg.querySelector("#cam"), world = svg.querySelector("#world"), hb = svg.querySelector("#hb"), frameG = svg.querySelector("#frame");
  const clip = svg.querySelector("#above rect");

  /* ── 자막: 검정 큰 글자, 단어가 scale 1.3→1로 날아와 앉는다(4f, 단어마다 2f 간격) ── */
  const CAPS = [
    { t0: 0, t1: 1.9, lines: ["거위가", "공 위에 앉음."], size: 140, top: 330, still: true, out: 3 },
    { t0: 2.05, t1: 2.75, lines: ["알 낳고 감"], size: 150, top: 380 },
    { t0: 2.75, t1: 3.8, lines: ["새가 물어감"], size: 150, top: 380 },
    { t0: 3.8, t1: 4.75, lines: ["핀이 도망감"], size: 150, top: 380 },
    { t0: 4.75, t1: 5.55, lines: ["두더지 등장"], size: 150, top: 380 },
    { t0: 5.55, t1: 6.25, lines: ["커서 사냥 중"], size: 150, top: 380 },
    { t0: 6.25, t1: 6.9, lines: ["물고 튐"], size: 150, top: 380 },
    { t0: 6.9, t1: PULL[0] + 0.2, lines: ["관중 환호"], size: 150, top: 380, out: 4 },
  ];
  const capEls = CAPS.map((c) => {
    const e = document.createElement("div"); e.className = "cap"; e.style.fontSize = c.size + "px"; e.style.top = c.top + "px";
    e.innerHTML = c.lines.map((l) => `<span class="l">${l.split(" ").map((w) => `<span class="w">${w}</span>`).join(" ")}</span>`).join("");
    root.appendChild(e); return e;
  });
  const reveal = document.createElement("div"); reveal.className = "reveal";
  reveal.innerHTML = `<span class="l"><span class="w">다</span> <span class="w">내</span> <span class="w">바탕화면</span></span><span class="l"><span class="w band">맨 아래 띠</span><span class="w">에서</span></span><span class="l"><span class="w">벌어진</span> <span class="w">일.</span></span>`;
  root.appendChild(reveal);
  const REV = { t0: 8.75, t1: 10.55 };
  const end = document.createElement("div"); end.id = "end";
  end.innerHTML = `<div class="wm">mini-golf</div><div class="l2">macOS 메뉴바 앱 · 무료 · 오픈소스</div><div class="url">github.com/w0uldy0udaestar/mini-golf</div>`;
  root.appendChild(end); const endParts = [...end.children];
  const END = { t0: 10.75 };
  const strip = document.createElement("div"); strip.id = "strip"; root.appendChild(strip);
  const SB = { x: SCR.x - 10, y: Math.round(SCR.y + 1500 * Z1) - 8, w: SCR.w + 20, h: Math.round(SCR.h - 1500 * Z1) + 18 };
  Object.assign(strip.style, { left: SB.x + "px", top: SB.y + "px", width: SB.w + "px", height: SB.h + "px" });

  function kinetic(el, t, t0, still) {
    const ws = el.querySelectorAll(".w");
    ws.forEach((w, i) => {
      if (still) { w.style.transform = "none"; w.style.opacity = 1; return; }
      const u = prog(t, t0 + i * F(2), F(4)), e = outCubic(u);
      w.style.opacity = clamp(u * 2.5).toFixed(3); w.style.transform = `scale(${(1.3 - 0.3 * e).toFixed(4)})`;
    });
  }

  /* ── 렌더 ── */
  function render(t) {
    // 어느 컷인가 + 휩 팬: 경계 앞 2f는 나가는 컷이 왼쪽으로, 뒤 2f는 들어오는 컷이 오른쪽에서 (가로 블러)
    let ci = CUTS.findIndex((c) => t >= c.t0 - 1e-6 && t < c.t1 - 1e-6); if (ci < 0) ci = CUTS.length - 1;
    const c = CUTS[ci];
    let whip = 0, blur = 0;
    const nb = ci < CUTS.length - 1 ? CUTS[ci + 1].t0 : null, kOut = nb != null ? Math.round((nb - t) * FPS) : 99, kIn = Math.round((t - c.t0) * FPS);
    if (ci < CUTS.length - 1 && kOut <= 2 && kOut >= 1) { whip = -[0, 440, 170][kOut]; blur = [0, 64, 30][kOut]; }
    if (ci > 0 && kIn < 2) { whip = [380, 130][kIn]; blur = [60, 22][kIn]; }
    const ct = capTime(c, t);
    let z, f, a, k = 0;
    if (c.id === "gallery" && t >= PULL[0]) {
      const zA = c.z(PULL[0]), fA = c.f, aA = c.a, zB = Z1, fB = [0, 0], aB = [SCR.x, SCR.y];
      const p = [0, 1].map((i) => (fA[i] * zA - fB[i] * zB + aB[i] - aA[i]) / (zA - zB));
      const D = [0, 1].map((i) => (p[i] - fA[i]) * zA + aA[i]);
      const u = inOutCubicR(prog(t, PULL[0], PULL[1] - PULL[0]));
      z = Math.exp(Math.log(zA) + (Math.log(zB) - Math.log(zA)) * u); f = p; a = D;
      k = clamp((Math.log(zA) - Math.log(z)) / (Math.log(zA) - Math.log(zB)) * 1.6);
    } else if (c.id === "cat") {
      const fx = S.cat.fit.x, x = fx[0] * ct + fx[1]; z = c.z(t); f = [x - 30, groundY(S.cat.terrain, x) - 20]; a = c.a;
    } else { z = c.z(t); f = c.f; a = c.a; }
    const sh = shakeAt(c, t);
    const tx = a[0] - f[0] * z + whip + sh[0], ty = a[1] - f[1] * z + sh[1];
    world.setAttribute("transform", `translate(${tx.toFixed(2)} ${ty.toFixed(2)}) scale(${z.toFixed(5)})`);
    hb.setAttribute("stdDeviation", `${blur} 0`);
    if (blur > 0) cam.setAttribute("filter", "url(#hblur)"); else cam.removeAttribute("filter");
    let body = "";
    if (c.id === "gallery") body += desktop(k);
    body += scene(c.id, ct, z);
    world.innerHTML = body;
    // 풀백 뒤 화면 테두리(검정, 굵게) — 데스크탑 크기가 드러날수록
    if (c.id === "gallery" && k > 0) {
      const x0 = tx, y0 = ty, w = 3840 * z, h = 2160 * z;
      frameG.innerHTML = k >= 0.999 ? `<rect x="${(x0 - 4).toFixed(1)}" y="${(y0 - 4).toFixed(1)}" width="${(w + 8).toFixed(1)}" height="${(h + 8).toFixed(1)}" rx="10" fill="none" stroke="${INK}" stroke-width="8"/>` : "";
    } else frameG.innerHTML = "";
    // 자막
    CAPS.forEach((cp, i) => {
      const e = capEls[i], on = t >= cp.t0 - 1e-6 && t < cp.t1 - 1e-6;
      if (!on) { e.style.opacity = 0; return; }
      let o = 1, y = 0;
      if (cp.out) { const u = prog(t, cp.t1 - F(cp.out), F(cp.out)); o = 1 - u; y = -20 * u; }
      e.style.opacity = o; e.style.transform = `translateY(${y.toFixed(1)}px)`;
      kinetic(e, t, cp.t0, cp.still);
    });
    const rOn = t >= REV.t0 && t < REV.t1 + F(6);
    reveal.style.opacity = rOn ? (1 - prog(t, REV.t1, F(6))).toFixed(3) : 0;
    reveal.style.transform = `translateY(${(-24 * prog(t, REV.t1, F(6))).toFixed(1)}px)`;
    kinetic(reveal, t, REV.t0, false);
    const sw = inOutSine(prog(t, REV.t0 + 0.25, F(10)));
    strip.style.clipPath = `inset(-8px ${((1 - sw) * 100).toFixed(2)}% -8px -8px)`;
    strip.style.opacity = (sw > 0 ? 1 : 0);
    endParts.forEach((p, i) => { const u = prog(t, END.t0 + i * F(3), F(5)), e = outCubic(u);
      p.style.opacity = clamp(u * 2).toFixed(3); p.style.transform = i === 0 ? `scale(${(1.3 - 0.3 * e).toFixed(4)})` : `translateY(${(22 * (1 - e)).toFixed(1)}px)`; });
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;
  window.__ready = false;

  function audit() {
    const out = { frames: [], fonts: ["600 46px Pretendard", "700 64px Pretendard", "800 150px Pretendard"].map((f) => document.fonts.check(f)) };
    const vis = (e) => { let o = 1, n = e; while (n && n !== document.body) { const cs = getComputedStyle(n); if (cs.display === "none" || cs.visibility === "hidden") return 0; o *= parseFloat(cs.opacity); n = n.parentElement; } return o; };
    const textRects = (e) => { const r = []; const rg = document.createRange(); const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT); let n;
      while ((n = w.nextNode())) { if (!n.textContent.trim()) continue; rg.selectNodeContents(n); for (const b of rg.getClientRects()) r.push([b.left, b.top, b.right, b.bottom].map(Math.round)); } return r; };
    const items = [...CAPS.map((c, i) => ["cap" + i, capEls[i]]), ["reveal", reveal], ...endParts.map((p, i) => ["end" + i, p])];
    for (let fr = 0; fr < NF; fr += 3) {
      render(fr / FPS); const o2 = { f: fr, items: [] };
      for (const [name, el] of items) { const o = vis(el); if (o > 0.05) for (const r of textRects(el)) o2.items.push({ name, o: +o.toFixed(2), r, px: parseFloat(getComputedStyle(el).fontSize) }); }
      out.frames.push(o2);
    }
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  document.fonts.ready.then(() => { if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); window.__ready = true; });
  render(0);
})();
