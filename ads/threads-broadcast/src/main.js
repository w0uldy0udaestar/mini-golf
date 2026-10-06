/* T5 「내 모니터에서 열린 메이저」 — TV 골프 중계 문법 × 내 바탕화면. 세로 1080×1920, 14초.
 *
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). GSAP 타임라인은 재생 헤드 역할만. Math.random·Date 없음.
 * 소재: 15초 광고의 실캡처 hero-drive(3번 홀 · 파 5 · 절벽 티, DR 풀스윙) — 판·스윙 크롭·리그 덤프.
 * 공·트레이서: data/shot.js = Ballistics.step(.fly) 이식 탄도(실캡처 궤적에 맞춘 미스힛 해), 화면 시간은 실캡처 공 표본에 맞춘 배율.
 * 자막 숫자: shot.js nums (출처·계산식은 plan.md).
 *
 * 비트 (프레임 @30fps, 12초 = 360프레임) — 2차: 벙커를 중계 문법의 웃음으로, 중반 압축
 *   f0–10    훅: 위 = 생중계 태그 · 홀 버그 "3번 홀 · 파 5 · 578 m" · 리더보드 "나 E", 가운데 = 어두운 데스크탑(코드 창), 띠의 스틱맨이 이미 톱(실캡처)
 *   f11      임팩트 (실캡처 크롭) + 트레이서 시작점 흰 섬광(정점 1프레임, 2프레임 꼬리) + 스탯 판 "볼 스피드 67 m/s" 동시 등장
 *   f13–40   카메라 풀백 ×2.4→×1.4 + 패닝 시작, f40–150 공을 따라 느린 패닝(2D)
 *   f53      정점 27 m(공이 정점에 닿는 순간) + 캐리(실시간 카운트) → f111 착지에 272로 멈춘다
 *   f45–144  해설 "이 샷, 코드 창 위를 넘어갑니다."
 *   f111–144 착지 → 한 번 튀고 → 굴러 정지 = 로그대로 벙커(REST lie bunker)
 *   f144     스탯 판 "라이 [벙커]"(흰 태그) · f150 해설 "…벙커입니다." · f159 리더보드 순위 칸 한 번 반전(여전히 1위) · f150–350 느린 푸시
 *   f189–219 스탯 판 퇴장 · 데스크탑 한 단 딤 → f195 태그라인 "메이저는 / 내 모니터에서 열린다."
 *   f255–    데스크탑 딤 · 중계 그래픽 퇴장 → 엔드카드(워드마크 · 메타 · URL), 띠의 스틱맨이 걸어온다
 */
(() => {
  const FPS = 30, DUR = 12, NF = DUR * FPS;
  const root = document.getElementById("root");
  const q = new URLSearchParams(location.search);
  const SH = window.SHOT, RIG = window.RIG, GROUND = window.GROUND, NUM = SH.nums;
  const URL_TEXT = "github.com/w0uldy0udaestar/mini-golf";

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const smooth = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
  const seg = (f, a, b) => clamp((f - a) / (b - a));
  const bez = (x1, y1, x2, y2) => (p) => { if (p <= 0) return 0; if (p >= 1) return 1; let a = 0, b = 1, t = p;
    for (let i = 0; i < 30; i++) { t = (a + b) / 2; const x = 3 * x1 * (1 - t) ** 2 * t + 3 * x2 * (1 - t) * t * t + t ** 3; x < p ? a = t : b = t; }
    return 3 * y1 * (1 - t) ** 2 * t + 3 * y2 * (1 - t) * t * t + t ** 3; };
  const easeIO = bez(0.42, 0, 0.25, 1), easeOut = bez(0.2, 0.7, 0.3, 1);
  const SPR = { calm: [0.78, 2.7], settle: [0.62, 3.2] };
  const stepR = (t, z, f) => { const w = 2 * Math.PI * f, d = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(d * t) + z * w / d * Math.sin(d * t)); };
  const Sk = (t, n) => { if (t <= 0) return 0; const [z, f] = SPR[n]; const D = 6 / (z * 2 * Math.PI * f); return t >= D ? 1 : stepR(t, z, f) / stepR(D, z, f); };
  // 단조 3차 에르미트 (Fritsch–Carlson) — 카메라 패닝 키를 속도 연속으로 잇는다
  function hermite(keys) {
    const n = keys.length, d = [], m = new Array(n).fill(0);
    for (let i = 0; i < n - 1; i++) d.push((keys[i + 1][1] - keys[i][1]) / (keys[i + 1][0] - keys[i][0]));
    for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    return (x) => {
      if (x <= keys[0][0]) return keys[0][1];
      if (x >= keys[n - 1][0]) return keys[n - 1][1];
      let i = 0; while (x > keys[i + 1][0]) i++;
      const h = keys[i + 1][0] - keys[i][0], t = (x - keys[i][0]) / h, t2 = t * t, t3 = t2 * t;
      return (2 * t3 - 3 * t2 + 1) * keys[i][1] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * keys[i + 1][1] + (t3 - t2) * h * m[i + 1];
    };
  }

  /* ── DOM ── */
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const px = (e, x, y, w, hh) => { e.style.left = x + "px"; e.style.top = y + "px"; if (w != null) e.style.width = w + "px"; if (hh != null) e.style.height = hh + "px"; return e; };
  const desk = h("div"); desk.id = "desk"; root.appendChild(desk);
  const FLAG = `<svg viewBox="0 0 14 16"><line x1="3" y1="1" x2="3" y2="15" stroke="#E6E6E2" stroke-width="1.6" stroke-linecap="round"/><path d="M3.8 1.6 L12.5 4.4 L3.8 7.2 Z" fill="#D94D3D"/></svg>`;
  desk.appendChild(h("div", "menubar", `<span class="app">편집기</span><span>파일</span><span>편집</span><span>보기</span><span>창</span><span class="sp"></span>${FLAG}<span>화 10월 6일 오후 2:14</span>`));
  const win = (r, title, cls = "") => { const w = px(h("div", "win " + cls), r[0], r[1], r[2], r[3]);
    w.innerHTML = `<div class="bar"><i></i><i></i><i></i><div class="t">${title}</div></div><div class="body"></div>`; desk.appendChild(w); return w; };

  // 터미널(뒤) — 일반 빌드 출력
  const term = win([1040, 96, 820, 470], "터미널 — zsh");
  term.querySelector(".body").innerHTML = `<div class="term"><span class="p">$</span> swift build
Building for debugging...
<span class="ok">Build complete!</span> (2.41s)
<span class="p">$</span> git status
On branch main
nothing to commit, working tree clean
<span class="p">$</span> </div>`;
  // 코드 창(앞) — 이 저장소 Ballistics.swift 실제 발췌 (launch: 볼 스피드 식 → step: 비행)
  const SWIFT = [
    ["c", "    /// 샷 발사: 클럽·백스윙 높이·라이를 반영해 공 상태를 설정"],
    ["", "    <k>public static func</k> launch("], ["", "        _ b: <k>inout</k> BallState, club: Club, heightPct: Double, lie: Surface, dir: Double,"],
    ["", "        mishit: Double = <n>0</n>, punch: Double = <n>0</n>, slope: Double = <n>0</n>,"], ["", "    ) {"],
    ["", "        <k>let</k> minR = club.isPutter ? Phys.putterMinRatio : Phys.minPowerRatio"],
    ["", "        <k>var</k> v0 = club.power * lie.powerFactor * (minR + (<n>1</n> - minR) * heightPct) * (<n>1</n> - abs(mishit) * <n>0.12</n>)"],
    ["", "        <k>let</k> loft = max(<n>0.02</n>, loftDeg * .pi / <n>180</n> + atan(slope * dir) + mishit * <n>4</n> * .pi / <n>180</n>)"],
    ["", "        b.vx = dir * v0 * cos(loft)"], ["", "        b.vy = club.isPutter ? <n>0</n> : v0 * sin(loft)"], ["", "    }"], ["", ""],
    ["c", "    /// 결정론적 물리 스텝. 경사면 바운스는 법선 반사, 굴림에는 중력의 경사 성분이 더해진다."],
    ["", "    <k>public static func</k> step(_ b: <k>inout</k> BallState, hole: Hole, dt: Double = Phys.dt) -> StepEvent {"],
    ["", "        <k>switch</k> b.phase {"], ["", "        <k>case</k> .fly:"],
    ["c", "            // 바람: 공기력은 대기 상대속도 기준 — 뒷바람은 항력을 줄이고 맞바람은 키운다"],
    ["", "            <k>let</k> rvx = b.vx - (wind ?? hole.wind)"], ["", "            <k>let</k> v = max(hypot(rvx, b.vy), <n>1e-9</n>)"],
    ["", "            <k>let</k> omega = b.spin * <n>2</n> * .pi / <n>60</n>"], ["", "            <k>let</k> spinRatio = min(Phys.ballRadius * omega / v, Phys.spinRatioMax)"],
    ["", "            <k>let</k> cl = min(Phys.clMax, Phys.clBase + Phys.clSlope * spinRatio)"],
    ["c", "            // 항력(상대속도 반대) + 마그누스 양력(상대속도 수직, 백스핀=위) + 중력"],
    ["", "            <k>let</k> ax = -q * Phys.cd * v * rvx + q * cl * v * -b.vy * b.spinSign"],
    ["", "            <k>let</k> ay = -Phys.g - q * Phys.cd * v * b.vy + q * cl * v * rvx * b.spinSign"],
    ["", "            b.vx += ax * dt"], ["", "            b.vy += ay * dt"], ["", "            b.x += b.vx * dt"], ["", "            b.y += b.vy * dt"],
    ["", "            <k>let</k> ground = hole.ground(at: b.x)"], ["", "            <k>if</k> b.y <= ground {"],
  ];
  const fmt = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/&lt;(\/?)(k|n)>/g, (m, sl, t) => sl ? "</span>" : `<span class="${t}">`);
  const editor = win([70, 300, 1080, 735], "Ballistics.swift — mini-golf");
  editor.querySelector(".body").innerHTML = `<div class="code">${SWIFT.map(([c, s], i) => `<span class="row"><span class="ln">${216 + i}</span>${c === "c" ? `<span class="c">${fmt(s)}</span>` : fmt(s)}</span>`).join("")}</div>`;

  // 게임층: 판(지형·깃발·HUD, 실캡처) → 스윙 크롭 → 트레이서·스틱맨·공(SVG) → 딤
  const plate = px(h("img", "plate"), 0, 0); plate.decoding = "sync"; plate.src = "assets/gen/plate-ko.png"; desk.appendChild(plate);   // 동기 디코드: 첫 프레임 래스터가 실행마다 달라지지 않게
  const SWING = ["swing-top", "swing-down", "swing-impact", "swing-follow", "swing-finish"];
  const crops = SWING.map((n) => { const e = px(h("img", "crop"), 40, 716); e.decoding = "sync"; e.src = `assets/gen/${n}.png`; e.style.visibility = "hidden"; desk.appendChild(e); return e; });
  const NS = "http://www.w3.org/2000/svg";
  const mk = (tag, a) => { const e = document.createElementNS(NS, tag); for (const k in a) e.setAttribute(k, a[k]); return e; };
  const svg = mk("svg", { width: 1920, height: 1080 }); svg.id = "fx"; desk.appendChild(svg);
  const NSS = { "vector-effect": "non-scaling-stroke", fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round" };
  const TRC = {   // 트레이서: 흰색~회색 3겹 (빛 번짐 → 몸통 → 심). 화면 px 굵기 고정
    glow: mk("polyline", { ...NSS, stroke: "rgba(236,236,232,.10)", "stroke-width": 22 }),
    mid: mk("polyline", { ...NSS, stroke: "rgba(236,236,232,.22)", "stroke-width": 10 }),
    core: mk("polyline", { ...NSS, stroke: "rgba(250,250,247,.96)", "stroke-width": 4 }),
  };
  for (const k of ["glow", "mid", "core"]) svg.appendChild(TRC[k]);
  const man = mk("g", {}); svg.appendChild(man);
  const P = {
    trail: mk("path", { fill: "none", stroke: "rgba(224,224,224,.52)", "stroke-width": 5.5, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    body: mk("path", { fill: "none", stroke: "rgba(224,224,224,.95)", "stroke-width": 6, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    shaft: mk("path", { fill: "none", stroke: "rgba(194,194,194,.9)", "stroke-width": 3, "stroke-linecap": "round" }),
    chead: mk("path", { fill: "none", stroke: "rgba(237,237,237,.95)", "stroke-width": 13.6, "stroke-linecap": "round" }),
    grip: mk("path", { fill: "none", stroke: "rgba(153,153,153,.9)", "stroke-width": 4.6, "stroke-linecap": "round" }),
    head: mk("circle", { r: 10, fill: "rgba(224,224,224,.95)" }),
    hat: mk("path", { fill: "rgba(228,80,60,.95)" }),
  };
  for (const k of ["trail", "body", "shaft", "chead", "grip", "head", "hat"]) man.appendChild(P[k]);
  const halo = mk("circle", { r: 15, fill: "rgba(250,250,247,.16)" }), ball = mk("circle", { r: 5.5, fill: "#FAFAF8" });
  svg.appendChild(halo); svg.appendChild(ball);
  // 임팩트 섬광: 트레이서 시작점(티 위 공)의 흰 방사형 빛 — 정점 1프레임(f11) + 2프레임 꼬리. 면적이 작아 플래시 기준과 무관
  const defs = mk("defs", {}); defs.innerHTML = `<radialGradient id="burstg"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".32" stop-color="#fff" stop-opacity=".7"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>`;
  svg.insertBefore(defs, svg.firstChild);
  const burst = mk("circle", { cx: SH.tee[0], cy: SH.tee[1], r: 20, fill: "url(#burstg)", opacity: 0 }); svg.appendChild(burst);
  const dim = h("div"); dim.id = "dim"; desk.appendChild(dim);

  /* ── 중계 그래픽 (화면 고정) ── */
  const gfx = h("div"); gfx.id = "gfx"; root.appendChild(gfx);
  const band = h("div"); band.id = "band"; gfx.appendChild(band);
  const topfade = h("div"); topfade.id = "topfade"; gfx.appendChild(topfade);   // 맨 위 메뉴바 띠를 중계 그래픽 뒤로 눕힌다
  const tag = px(h("div", "tag", `<i class="dot"></i>생중계 · 1라운드`), 72, 168); gfx.appendChild(tag);
  const bug = px(h("div", "panel bug", `<div class="main">${NUM.hole}번 홀 · 파 ${NUM.par} · ${NUM.len} m</div><div class="sub">절벽 티 · 바람 → 1 m/s</div>`), 70, 228);
  bug.style.padding = "28px 34px 26px"; gfx.appendChild(bug);
  const lb = h("div", "panel lb", `<div class="hd">리더보드</div><div class="row"><span class="rk">1</span><span class="nm">나</span><span class="sc">E</span></div>`);
  lb.style.padding = "24px 30px 26px"; gfx.appendChild(lb);
  const ST_X = 70, ST_Y = 470, ST_W = 600, ROW = 104;
  const stats = px(h("div", "panel stats"), ST_X, ST_Y, ST_W); gfx.appendChild(stats);
  const statRow = (lab, i) => { const r = px(h("div", "r", `<span class="lab">${lab}</span><span class="val"></span>`), 0, 22 + i * ROW); r.style.padding = "0 34px"; r.style.height = ROW + "px"; r.style.alignItems = "center"; stats.appendChild(r); return r; };
  const R = [statRow("볼 스피드", 0), statRow("정점", 1), statRow("캐리", 2), statRow("라이", 3)];
  for (let i = 1; i < 4; i++) { const ru = px(h("div", "rule"), 34, 22 + i * ROW); ru.style.right = "34px"; ru.style.left = "34px"; stats.appendChild(ru); R[i].rule = ru; }
  const val = (n, u) => `${n}<small>${u}</small>`;
  const cmt = px(h("div", "cmt", `<div class="who">해설</div><div class="say">이 샷, 코드 창 위를 넘어갑니다.</div>`), 72, 1502); gfx.appendChild(cmt);
  const cmt2 = px(h("div", "cmt", `<div class="who">해설</div><div class="say">…벙커입니다.</div>`), 72, 1502); gfx.appendChild(cmt2);
  const rk = lb.querySelector(".rk");
  const TG = 92;
  const tagline = px(h("div", "tagline", `<span class="ln"><span>메이저는</span></span><span class="ln"><span>내 모니터에서 열린다.</span></span>`), 70, 452);
  tagline.style.fontSize = TG + "px"; tagline.style.letterSpacing = (-0.035 * TG) + "px"; gfx.appendChild(tagline);
  const end = px(h("div"), 74, 760, 840); end.id = "end";
  end.innerHTML = `<div class="wm" style="font-size:112px;letter-spacing:-3.9px">mini-golf</div>
    <div class="l2" style="font-size:46px;margin-top:34px">macOS 메뉴바 앱 · 무료 · 오픈소스</div>
    <div class="url" style="font-size:38px;margin-top:26px">${URL_TEXT}</div>`;
  gfx.appendChild(end);

  /* ── 공 경로 (shot.js) ── */
  const gyAt = (x) => GROUND[Math.round(clamp(x, 0, 1919))];
  const BR = 6;                                   // 공 중심 = 지면선 − 6pt (판 실측: 티 위 851.5 vs 지면 859.6 − 티 페그)
  const PTS = SH.pts.map((p) => p.slice());
  const last = PTS[PTS.length - 1], corr = (gyAt(SH.xLand) - BR) - last[2];
  for (const p of PTS) p[2] += corr * smooth(seg(p[0], SH.fLand - 12, SH.fLand));   // 마지막 12f에 착지 지면과 3pt 이음
  const F_IMP = 11;
  const flightAt = (f) => { let i = 1; while (i < PTS.length - 1 && PTS[i][0] < f) i++;
    const a = PTS[i - 1], b = PTS[i], u = clamp((f - a[0]) / Math.max(1e-6, b[0] - a[0])); return [lerp(a[1], b[1], u), lerp(a[2], b[2], u)]; };
  // 착지 뒤: 한 번 튐(실캡처 f184 표본을 지나는 포물선) → 굴러 REST 지점(342.0 m)에 선다
  const HOP_U = 0.625, fH1 = SH.fLand + (SH.hop[0] - SH.fLand) / HOP_U, xH1 = SH.xLand + (SH.hop[1] - SH.xLand) / HOP_U;
  const hopH = ((gyAt(SH.hop[1]) - BR) - SH.hop[2]) / (4 * HOP_U * (1 - HOP_U));
  function ballAt(f) {
    if (f <= SH.fLand) return flightAt(f);
    if (f <= fH1) { const u = (f - SH.fLand) / (fH1 - SH.fLand), x = lerp(SH.xLand, xH1, u); return [x, gyAt(x) - BR - hopH * 4 * u * (1 - u)]; }
    const u = seg(f, fH1, SH.fRest), x = lerp(xH1, SH.xRest, 1 - (1 - u) * (1 - u)); return [x, gyAt(x) - BR];
  }

  /* ── 카메라: 2D scale/translate만. 데스크탑 아래 가장자리를 화면 y 1500에 고정(그 아래는 중계 띠) ── */
  const S0 = 2.4, S1 = 1.4, BOT = 1490;
  let TXF = null;
  function buildCam() {
    const b40 = flightAt(40)[0];
    TXF = hermite([[13, 0], [40, 640 - S1 * b40], [150, 760 - S1 * SH.xRest]]);
  }
  const PUSH = { f0: 150, f1: 350, k: 1.045 };
  function camera(f) {
    const s = lerp(S0, S1, easeIO(seg(f, 13, 40)));
    let tx = TXF(f), ty = BOT - s * 1080;
    const pu = easeIO(seg(f, PUSH.f0, PUSH.f1));
    if (pu > 0) {   // 느린 푸시: 정지한 공 자리를 기준으로 ×1.045 (5초, 초당 배율 변화 ≤ 1.3%)
      const k = lerp(1, PUSH.k, pu), [bx, by] = ballAt(SH.fRest), ax = tx + s * bx, ay = ty + s * by;
      return [s * k, ax - (ax - tx) * k, ay - (ay - ty) * k];
    }
    return [s, tx, ty];
  }

  /* ── 스틱맨 (실제 리그 → StickmanNode 렌더 규칙, 15초 광고와 동일) ── */
  function drawMan(fr) {
    const r = RIG[Math.min(RIG.length - 1, fr)], d = r.dir;
    const gx = r.x, gy = GROUND[Math.round(clamp(gx, 0, 1919))] + 0.6;
    const T = (p) => [gx + p[0] * d, gy - p[1]];
    const [hip, sh, f1, f2, k1, k2, grip, ht, el, et] = r.pts.map(T);
    const f = (p) => `${p[0].toFixed(2)} ${p[1].toFixed(2)}`;
    const ctl = [(sh[0] + hip[0]) / 2 - d * 0.8, (sh[1] + hip[1]) / 2];
    const arm = (a, e, b) => r.curved ? `M${f(a)} Q${f(e)} ${f(b)}` : `M${f(a)} L${f(e)} L${f(b)}`;
    P.body.setAttribute("d", `M${f(sh)} Q${f(ctl)} ${f(hip)} M${f(hip)} L${f(k1)} L${f(f1)} M${f(hip)} L${f(k2)} L${f(f2)} ${arm(sh, el, grip)}`);
    P.trail.setAttribute("d", arm(sh, et, ht));
    const sp = Math.sin(r.phi), cp = Math.cos(r.phi);
    const tip = [grip[0] + sp * r.len * d, grip[1] + cp * r.len], butt = [grip[0] - sp * r.butt * d, grip[1] - cp * r.butt];
    P.shaft.setAttribute("d", `M${f(butt)} L${f(tip)}`);
    P.grip.setAttribute("d", `M${f(butt)} L${f([grip[0] + sp * 8 * d, grip[1] + cp * 8])}`);
    const perp = [Math.cos(r.phi) * d, -Math.sin(r.phi)], c = [tip[0] + perp[0] * 4.5, tip[1] + perp[1] * 4.5], half = (17 - 13.6) / 2;
    P.chead.setAttribute("d", `M${f([c[0] - perp[0] * half, c[1] - perp[1] * half])} L${f([c[0] + perp[0] * half, c[1] + perp[1] * half])}`);
    const hd = [sh[0] + d * r.head[0], sh[1] - r.head[1]];
    P.head.setAttribute("cx", hd[0].toFixed(2)); P.head.setAttribute("cy", hd[1].toFixed(2));
    const crown = [[-9, 7], [-9, 15], [-4.5, 10], [0, 16], [4.5, 10], [9, 15], [9, 7]];
    P.hat.setAttribute("d", "M" + crown.map(([x, y]) => f([hd[0] + x * d, hd[1] - y])).join(" L") + " Z");
  }

  /* ── 비트 프레임 ── */
  const F = { stats: F_IMP - 1, apex: Math.round(SH.fApex), land: SH.fLand, bunker: Math.round(SH.fRest), statsOut: 189, cmtIn: 45, cmtOut: Math.round(SH.fRest), cmt2In: 150, cmt2Out: 195,
    lbBlink: Math.round(SH.fRest) + 15, tag: 195, endDim: 255, endIn: 262 };
  // 왼→오 닦아 내기: 가장자리가 부드러운 마스크(폭 14%) — 딱딱한 클립이 글자를 반쯤 자른 채 보이는 프레임이 없게
  const wipe = (el, f, f0, n = 9) => { const u = easeOut(seg(f, f0, f0 + n)), e = -14 + 114 * u;
    const m = u >= 1 ? "none" : `linear-gradient(90deg, #000 ${e.toFixed(2)}%, transparent ${(e + 14).toFixed(2)}%)`;
    el.style.maskImage = m; el.style.webkitMaskImage = m; el.style.opacity = f >= f0 ? 1 : 0; return u; };

  let ready = false;
  const fontsOk = () => ["700 64px Pretendard", "800 92px Pretendard", "600 44px Pretendard", "500 34px JBM"].every((x) => document.fonts.check(x)) && document.fonts.status === "loaded";
  function init() {
    buildCam();
    // 리더보드: 홀 버그 오른쪽, 같은 높이 (폭은 글자 실측)
    const bw = bug.offsetWidth; px(lb, 70 + bw + 16, 228, 930 - (70 + bw + 16), bug.offsetHeight);
    stats.style.height = (22 * 2 + 4 * ROW) + "px";
    ready = fontsOk();
  }

  function render(t) {
    if (!ready) init();
    const f = Math.round(t * FPS);
    const [s, tx, ty] = camera(f);
    desk.style.transform = `translate(${tx.toFixed(3)}px,${ty.toFixed(3)}px) scale(${s.toFixed(5)})`;

    // 스윙: 실캡처 크롭 (f0–20) → 리그 벡터 (f21–)
    const CROP_AT = [[0, 10], [10, 11], [11, 14], [14, 18], [18, 21]];
    crops.forEach((e, i) => { e.style.visibility = f >= CROP_AT[i][0] && f < CROP_AT[i][1] ? "visible" : "hidden"; });
    man.style.visibility = f >= 21 ? "visible" : "hidden";
    if (f >= 21) drawMan(f);

    // 임팩트 섬광 (f11 정점 → f12·f13 꼬리)
    const bu = { [F_IMP]: 1, [F_IMP + 1]: 0.35, [F_IMP + 2]: 0.1 }[f] || 0;
    burst.setAttribute("opacity", bu); burst.setAttribute("r", (20 + 8 * (1 - bu)).toFixed(2));
    // 공 + 트레이서 (임팩트부터, 착지점에서 멈춘다)
    if (f >= F_IMP) {
      const [bx, by] = ballAt(f);
      const fe = Math.min(f, SH.fLand), pts = PTS.filter((p) => p[0] <= fe).map((p) => [p[1], p[2]]);
      pts.push(flightAt(fe));
      const str = pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ");
      for (const k in TRC) TRC[k].setAttribute("points", str);
      ball.setAttribute("cx", bx.toFixed(2)); ball.setAttribute("cy", by.toFixed(2)); ball.style.visibility = "visible";
      halo.setAttribute("cx", bx.toFixed(2)); halo.setAttribute("cy", by.toFixed(2));
      halo.setAttribute("opacity", (f <= SH.fLand ? 1 : 1 - smooth(seg(f, SH.fLand, SH.fLand + 20))).toFixed(3));
    } else { for (const k in TRC) TRC[k].setAttribute("points", ""); ball.style.visibility = "hidden"; halo.setAttribute("opacity", 0); }

    // 스탯 판: 볼 스피드(임팩트와 동시) → 정점·캐리(정점 순간) → 라이 [벙커](정지 순간) → 퇴장
    const sIn = easeOut(seg(f, F.stats, F.stats + 6)), sOut = smooth(seg(f, F.statsOut, F.statsOut + 12));
    stats.style.opacity = (sIn * (1 - sOut)).toFixed(3);
    stats.style.transform = `translateY(${(-14 * sOut).toFixed(2)}px)`;
    const shown = [F.stats, F.apex, F.apex + 4, F.bunker];
    R.forEach((r, i) => { wipe(r, f, shown[i]); if (r.rule) r.rule.style.opacity = f >= shown[i] ? 1 : 0; });
    const nRows = shown.reduce((a, f0) => a + easeOut(seg(f, f0 - 2, f0 + 9)), 0);   // 판 높이는 줄이 늘 때 11f에 걸쳐 자란다(한 프레임 점프 없음)
    stats.style.clipPath = `inset(0 0 ${((1 - clamp(nRows / 4)) * 100 * (4 * ROW) / (4 * ROW + 44)).toFixed(2)}% 0)`;
    R[0].querySelector(".val").innerHTML = val(NUM.speed, "m/s");
    R[1].querySelector(".val").innerHTML = val(NUM.apex, "m");
    const carryNow = f >= F.land ? NUM.carry : Math.round((ballAt(f)[0] - SH.tee[0]) / SH.pxm);
    R[2].querySelector(".val").innerHTML = val(carryNow, "m");
    R[3].querySelector(".val").innerHTML = `<span class="chip">벙커</span>`;   // PLAY REST … lie bunker

    // 해설 자막
    wipe(cmt, f, F.cmtIn, 14); const cOut = smooth(seg(f, F.cmtOut, F.cmtOut + 8));   // 정지 순간 위로 비켜 나가고
    cmt.style.opacity = (f >= F.cmtIn ? 1 - cOut : 0).toFixed(3); cmt.style.transform = `translateY(${(-18 * cOut).toFixed(2)}px)`;
    wipe(cmt2, f, F.cmt2In, 12); const c2Out = smooth(seg(f, F.cmt2Out, F.cmt2Out + 10));   // 같은 자리에서 다음 줄이 이어받는다
    cmt2.style.opacity = (f >= F.cmt2In ? 1 - c2Out : 0).toFixed(3);
    // 리더보드: 0.5초 뒤 순위 칸이 한 번 반전(4f 켜짐 · 4f 유지 · 6f 꺼짐) — 여전히 1위
    const bl = smooth(seg(f, F.lbBlink, F.lbBlink + 4)) * (1 - smooth(seg(f, F.lbBlink + 8, F.lbBlink + 14)));
    const mixc = (a, b) => Math.round(lerp(a, b, bl));
    rk.style.background = `rgba(244,244,241,${bl.toFixed(3)})`; rk.style.color = `rgb(${mixc(110, 11)},${mixc(111, 12)},${mixc(107, 14)})`;

    // 태그라인: 두 줄이 아래에서 밀려 올라온다 (줄 상자 안에서, 12f · 6f 시차)
    tagline.querySelectorAll(".ln span").forEach((e, i) => { const u = easeOut(seg(f, F.tag + i * 6, F.tag + i * 6 + 12)); e.style.transform = `translateY(${((1 - u) * 105).toFixed(2)}%)`; });
    tagline.style.visibility = f >= F.tag ? "visible" : "hidden";

    // 엔드: 데스크탑 딤 18f → 중계 그래픽 퇴장 → 브랜드 블록(위층만 페이드)
    const dm = smooth(seg(f, F.endDim, F.endDim + 18));
    // 태그라인 때 데스크탑을 한 단 낮추고(0.36, 18f) 엔드에서 한 단 더(0.66) — 글자 뒤 코드가 소음이 되지 않게
    dim.style.opacity = (0.36 * smooth(seg(f, F.statsOut, F.statsOut + 18)) + 0.30 * dm).toFixed(3);
    const gOut = 1 - smooth(seg(f, F.endDim, F.endDim + 12));
    for (const e of [tag, bug, lb]) e.style.opacity = gOut.toFixed(3);
    const ei = Sk((f - F.endIn) / FPS, "calm");
    end.style.opacity = ei.toFixed(3); end.style.transform = `translateY(${(12 * (1 - ei)).toFixed(2)}px)`;
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;

  // ?audit=1 : 3프레임 간격으로 글자 요소·공·스틱맨의 화면 사각형을 모아 <pre id="audit">에 JSON (scripts/qa.py가 읽는다)
  function audit() {
    const out = { frames: [] };
    const vis = (e) => { let o = 1, n = e; while (n && n !== document.body) { const cs = getComputedStyle(n); if (cs.visibility === "hidden" || cs.display === "none") return 0; o *= parseFloat(cs.opacity); n = n.parentElement; } return o; };
    const rect = (e) => { const r = e.getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom].map(Math.round); };
    const crit = [["tag", tag], ["bug", bug], ["lb", lb], ["stats", stats], ["cmt", cmt], ["cmt2", cmt2], ["tagline", tagline], ["end", end]];
    for (let f = 0; f < NF; f += 3) {
      render(f / FPS);
      const fr = { f, items: [] };
      for (const [name, el] of crit) { const o = vis(el); if (o > 0.05) fr.items.push({ name, o: +o.toFixed(2), r: rect(el) }); }
      if (f >= F_IMP) fr.items.push({ name: "ball", o: 1, r: rect(ball) });
      if (f < 21) fr.items.push({ name: "man", o: 1, r: rect(crops[0]) }); else fr.items.push({ name: "man", o: 1, r: rect(man) });
      fr.scale = +camera(f)[0].toFixed(3);
      out.frames.push(fr);
    }
    out.fontsOk = fontsOk();
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  Promise.all([document.fonts.ready, ...[plate, ...crops].map((e) => e.decode().catch(() => 0))]).then(() => { init(); if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); });
})();
