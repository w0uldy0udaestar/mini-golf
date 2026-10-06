/* T5 「내 모니터에서 열린 메이저」 — TV 골프 중계 문법 × 내 바탕화면. 세로 1080×1920, 12초 (3차: 밝은 중계 톤 + 모션 기법).
 *
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). Math.random·Date 없음.
 * 소재: 15초 광고의 실캡처 hero-drive(3번 홀 · 파 5 · 절벽 티, DR 풀스윙) — 판·스윙 크롭(흰색 굵은 선으로 변환)·리그 덤프.
 * 공·트레이서: data/shot.js = Ballistics.step(.fly) 이식 탄도. 자막 숫자: shot.js nums (출처·계산식은 plan.md).
 * 시간: shot.js warp = 실프레임 → 장면 프레임 표 (임팩트 2프레임 히트스톱 + 정점 중심 0.3배속 0.3초 속도 램프). 장면(공·스틱맨·카메라 경로)은
 *       장면 프레임으로, 중계 그래픽·펀치·흔들림·푸시는 실프레임으로 움직인다.
 *
 * 비트 (실프레임 @30fps)
 *   f0–10    훅: 초록 바탕, 흰 판 중계 그래픽(생중계 · 3번 홀 · 파 5 · 578 m · 리더보드 1 나 E), 흰 코드 창 옆 띠의 스틱맨이 이미 톱
 *   f11–13   임팩트: 2프레임 히트스톱 + 화면 흔들림(±8px, 감쇠) + 줌 펀치(×1.12) + 흰 섬광·노랑 충격 링. 스탯 판이 옆에서 밀려 들어오고 볼 스피드가 굴러 올라간다
 *   f15–42   풀백 + 패닝(장면 프레임). 트레이서(노랑 6px + 흰 심 2px)가 공 뒤를 그린다
 *   f51–66   정점 속도 램프(0.3배속 9f + 램프 3f씩): 정점 27 m가 굴러 올라가고, 캐리가 공을 따라 굴러간다
 *   f49–     해설 판이 펼쳐지고 "이 샷, 코드 창 위를 넘어갑니다." 타자기처럼 찍힌다
 *   f121     착지 → 캐리 272 m 고정 · f154 정지(로그대로 벙커): "벙커" 태그가 도장처럼 찍힌다(×1.6→1, 3f) + 흔들림
 *   f154–    해설이 백스페이스로 지워지고 "…벙커입니다." 타자 · f169 리더보드 칸 전체가 노랑으로 두 번 깜빡(여전히 1 나 E)
 *   f196–226 스탯 판이 왼쪽으로 빠지고 → 같은 자리에 태그라인 판이 와이프로 들어온다 "메이저는 / 내 모니터에서 열린다."
 *   f255–273 엔드카드 가로 와이프(노랑 선두 막대): 초록 슬레이트 + mini-golf · 메타 · URL. 아래 띠에서 스틱맨이 걸어온다
 */
(() => {
  const FPS = 30, DUR = 12, NF = DUR * FPS;
  const root = document.getElementById("root");
  const q = new URLSearchParams(location.search);
  const SH = window.SHOT, RIG = window.RIG, GROUND = window.GROUND, NUM = SH.nums, B = SH.beats, WARP = SH.warp;
  const URL_TEXT = "github.com/w0uldy0udaestar/mini-golf";

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const smooth = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
  const seg = (f, a, b) => clamp((f - a) / (b - a));
  const bez = (x1, y1, x2, y2) => (p) => { if (p <= 0) return 0; if (p >= 1) return 1; let a = 0, b = 1, t = p;
    for (let i = 0; i < 30; i++) { t = (a + b) / 2; const x = 3 * x1 * (1 - t) ** 2 * t + 3 * x2 * (1 - t) * t * t + t ** 3; x < p ? a = t : b = t; }
    return 3 * y1 * (1 - t) ** 2 * t + 3 * y2 * (1 - t) * t * t + t ** 3; };
  const easeIO = bez(0.42, 0, 0.25, 1), easeOut = bez(0.2, 0.7, 0.3, 1), easeIn = bez(0.55, 0, 0.9, 0.4), wipeE = bez(0.35, 0.1, 0.55, 1);
  function hermite(keys) {   // 단조 3차 에르미트 (Fritsch–Carlson) — 패닝 키를 속도 연속으로 잇는다
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
  const sceneF = (f) => WARP[Math.max(0, Math.min(WARP.length - 1, f))];

  /* ── DOM: 데스크탑 ── */
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const px = (e, x, y, w, hh) => { e.style.left = x + "px"; e.style.top = y + "px"; if (w != null) e.style.width = w + "px"; if (hh != null) e.style.height = hh + "px"; return e; };
  // 화면 전체 초록 판: PNG 시퀀스 캡처는 알파를 살려 #root 배경을 투명으로 찍는다 → 데스크탑 아래(y > 1465)가 검게 인코드됐다(3차 실측)
  const bgPlate = h("div"); bgPlate.id = "bg"; root.appendChild(bgPlate);
  const desk = h("div"); desk.id = "desk"; root.appendChild(desk);
  const win = (r, title) => { const w = px(h("div", "win"), r[0], r[1], r[2], r[3]);
    w.innerHTML = `<div class="bar"><i></i><i></i><i></i><div class="t">${title}</div></div><div class="body"></div>`; desk.appendChild(w); return w; };
  const term = win([980, 80, 760, 400], "터미널 — zsh");
  term.querySelector(".body").innerHTML = `<div class="term"><span class="p">$</span> swift build
Building for debugging...
<span class="ok">Build complete!</span> (2.41s)
<span class="p">$</span> git status
On branch main
nothing to commit, working tree clean
<span class="p">$</span> </div>`;
  // 코드 창(라이트 모드) — 이 저장소 Ballistics.swift 실제 발췌. 아래 가장자리 830pt: 공은 창 아랫부분 위를 넘어가고, 스틱맨·지형은 초록 위에 선다
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
    ["", "            <k>let</k> rvx = b.vx - (wind ?? hole.wind)"], ["", "            <k>let</k> v = max(hypot(rvx, b.vy), <n>1e-9</n>)"],
    ["", "            <k>let</k> ax = -q * Phys.cd * v * rvx + q * cl * v * -b.vy * b.spinSign"],
    ["", "            <k>let</k> ay = -Phys.g - q * Phys.cd * v * b.vy + q * cl * v * rvx * b.spinSign"],
  ];
  const fmt = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/&lt;(\/?)(k|n)>/g, (m, sl, t) => sl ? "</span>" : `<span class="${t}">`);
  const editor = win([300, 250, 860, 580], "Ballistics.swift — mini-golf");
  editor.querySelector(".body").innerHTML = `<div class="code">${SWIFT.map(([c, s], i) => `<span class="row"><span class="ln">${216 + i}</span>${c === "c" ? `<span class="c">${fmt(s)}</span>` : fmt(s)}</span>`).join("")}</div>`;

  // 게임층: 판(흰 지형·HUD, 실캡처) → 스윙 크롭 → 트레이서·스틱맨·공·임팩트 효과(SVG)
  const plate = px(h("img", "plate"), 0, 0); plate.decoding = "sync"; plate.src = "assets/gen/plate-ko.png"; desk.appendChild(plate);
  const SWING = ["swing-top", "swing-down", "swing-impact", "swing-follow", "swing-finish"];
  const crops = SWING.map((n) => { const e = px(h("img", "crop"), 40, 716); e.decoding = "sync"; e.src = `assets/gen/${n}.png`; e.style.visibility = "hidden"; desk.appendChild(e); return e; });
  // 감사용 표식: 스윙 크롭 5장의 불투명(α>200) 영역 합집합(크롭 px 70–314 × 36–301 → 데스크탑 pt). 화면에는 안 보인다
  const manBox = px(h("div"), 40 + 35, 716 + 18, 122, 133); manBox.style.cssText += ";position:absolute;visibility:hidden"; desk.appendChild(manBox);
  const NS = "http://www.w3.org/2000/svg";
  const mk = (tag, a) => { const e = document.createElementNS(NS, tag); for (const k in a) e.setAttribute(k, a[k]); return e; };
  const svg = mk("svg", { width: 1920, height: 1080 }); svg.id = "fx"; desk.appendChild(svg);
  const NSS = { "vector-effect": "non-scaling-stroke", fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round" };
  // 트레이서: 노랑 6px + 흰 심 2px(빛남은 두 겹 선으로). 흰 코드 창 위에서도 읽히게 아래에 진초록 10px 테두리 한 겹
  const TRC = { edge: mk("polyline", { ...NSS, stroke: "#1E4A1C", "stroke-width": 10 }), gold: mk("polyline", { ...NSS, stroke: "#FFD21F", "stroke-width": 6 }),
    core: mk("polyline", { ...NSS, stroke: "#FFFFFF", "stroke-width": 2 }) };
  svg.appendChild(TRC.edge); svg.appendChild(TRC.gold); svg.appendChild(TRC.core);
  const man = mk("g", {}); svg.appendChild(man);
  const P = {
    trail: mk("path", { fill: "none", stroke: "rgba(255,255,255,.85)", "stroke-width": 6.5, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    body: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 8, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    shaft: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 4, "stroke-linecap": "round" }),
    chead: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 13.6, "stroke-linecap": "round" }),
    grip: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 5, "stroke-linecap": "round" }),
    head: mk("circle", { r: 11, fill: "#FFFFFF" }),
    hat: mk("path", { fill: "#FFFFFF" }),
  };
  for (const k of ["trail", "body", "shaft", "chead", "grip", "head", "hat"]) man.appendChild(P[k]);
  const ball = mk("circle", { r: 6, fill: "#FFFFFF", stroke: "#1F4F1B", "stroke-width": 1.6 }); svg.appendChild(ball);
  // 임팩트: 흰 섬광(정점 1프레임 + 꼬리 2프레임) + 노랑 충격 링(히트스톱 동안 퍼진다)
  const flash = mk("circle", { cx: SH.tee[0], cy: SH.tee[1], r: 16, fill: "#FFFFFF", opacity: 0 }); svg.appendChild(flash);
  const ring = mk("circle", { cx: SH.tee[0], cy: SH.tee[1], r: 16, fill: "none", stroke: "#FFD21F", "stroke-width": 5, opacity: 0 }); svg.appendChild(ring);

  /* ── 중계 그래픽 (화면 고정) ── */
  const gfx = h("div"); gfx.id = "gfx"; root.appendChild(gfx);
  const tag = px(h("div", "tag", `<i class="dot"></i>생중계 · 1라운드`), 70, 160); gfx.appendChild(tag);
  const bug = px(h("div", "panel bug", `<div class="main">${NUM.hole}번 홀 · 파 ${NUM.par} · ${NUM.len} m</div><div class="sub">절벽 티 · 바람 → 1 m/s</div>`), 70, 232);
  bug.style.padding = "26px 32px 24px"; gfx.appendChild(bug);
  const lb = h("div", "panel lb", `<div class="hd">리더보드</div><div class="row"><span class="rk">1</span><span class="nm">나</span><span class="sc">E</span></div>`);
  lb.style.padding = "22px 28px 24px"; gfx.appendChild(lb);
  // 스탯 판: 값은 굴러 올라가는 카운터(오도미터) 84px
  const ST_X = 70, ST_Y = 470, ST_W = 640, ROW = 116, PADY = 18;
  const stats = px(h("div", "panel stats"), ST_X, ST_Y, ST_W); gfx.appendChild(stats);
  const statRow = (lab, i, inner) => { const r = px(h("div", "r", `<span class="lab">${lab}</span><span class="val">${inner}</span>`), 0, PADY + i * ROW); r.style.padding = "0 30px"; r.style.height = ROW + "px"; stats.appendChild(r); return r; };
  const odo = (n) => `<span class="odo">${Array.from({ length: n }, () => `<span class="col"><span class="strip">${[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0].join("<br>")}</span></span>`).join("")}</span>`;
  const R = [statRow("볼 스피드", 0, `${odo(2)}<small>m/s</small>`), statRow("정점", 1, `${odo(2)}<small>m</small>`), statRow("캐리", 2, `${odo(3)}<small>m</small>`),
    statRow("라이", 3, `<span class="chip">벙커</span>`)];
  for (let i = 1; i < 4; i++) { const ru = px(h("div", "rule"), 30, PADY + i * ROW - 1); ru.style.right = "30px"; stats.appendChild(ru); R[i].rule = ru; }
  const chip = R[3].querySelector(".chip");
  // 해설 판 (타자기)
  const CM1 = [..."이 샷, 코드 창 위를 넘어갑니다."], CM2 = [..."…벙커입니다."];
  const cmt = px(h("div", "panel cmt", `<div class="who">해설</div><div class="say"></div>`), 70, 1466); cmt.style.padding = "14px 24px 16px"; gfx.appendChild(cmt);
  const say = cmt.querySelector(".say");
  const L1 = CM1.map((c) => { const e = h("span", null); e.textContent = c; return e; }), L2 = CM2.map((c) => { const e = h("span", null); e.textContent = c; return e; });
  for (const e of L1.concat(L2)) say.appendChild(e);
  // 태그라인 판
  const TG = 92;
  const tagline = px(h("div", "panel tagline", `<span class="ln"><span>메이저는</span></span><span class="ln"><span>내 모니터에서 열린다.</span></span>`), 70, 470);
  tagline.style.fontSize = TG + "px"; tagline.style.letterSpacing = (-0.035 * TG) + "px"; tagline.style.padding = "26px 34px 30px"; gfx.appendChild(tagline);
  // 엔드: 초록 슬레이트가 가로로 닦고 들어온다(노랑 선두 막대). 슬레이트 안에 브랜드 블록. 태그라인 판은 슬레이트 위에 남는다
  const slate = h("div"); slate.id = "slate"; gfx.insertBefore(slate, tagline);
  const end = px(h("div"), 74, 800, 840); end.id = "end";
  end.innerHTML = `<div class="wm" style="font-size:112px;letter-spacing:-3.9px">mini-golf</div>
    <div class="l2" style="font-size:46px;margin-top:30px">macOS 메뉴바 앱 · 무료 · 오픈소스</div>
    <div class="url" style="font-size:38px;margin-top:22px">${URL_TEXT}</div>`;
  slate.appendChild(end);
  const wbar = h("div"); wbar.id = "wbar"; gfx.insertBefore(wbar, tagline);

  /* ── 공 경로 (shot.js, 장면 프레임) ── */
  const gyAt = (x) => GROUND[Math.round(clamp(x, 0, 1919))];
  const BR = 6;
  const PTS = SH.pts.map((p) => p.slice());
  const last = PTS[PTS.length - 1], corr = (gyAt(SH.xLand) - BR) - last[2];
  for (const p of PTS) p[2] += corr * smooth(seg(p[0], SH.fLand - 12, SH.fLand));
  const F_IMP = B.imp;
  const flightAt = (f) => { let i = 1; while (i < PTS.length - 1 && PTS[i][0] < f) i++;
    const a = PTS[i - 1], b = PTS[i], u = clamp((f - a[0]) / Math.max(1e-6, b[0] - a[0])); return [lerp(a[1], b[1], u), lerp(a[2], b[2], u)]; };
  const HOP_U = 0.625, fH1 = SH.fLand + (SH.hop[0] - SH.fLand) / HOP_U, xH1 = SH.xLand + (SH.hop[1] - SH.xLand) / HOP_U;
  const hopH = ((gyAt(SH.hop[1]) - BR) - SH.hop[2]) / (4 * HOP_U * (1 - HOP_U));
  function ballAt(sf) {
    if (sf <= SH.fLand) return flightAt(sf);
    if (sf <= fH1) { const u = (sf - SH.fLand) / (fH1 - SH.fLand), x = lerp(SH.xLand, xH1, u); return [x, gyAt(x) - BR - hopH * 4 * u * (1 - u)]; }
    const u = seg(sf, fH1, SH.fRest), x = lerp(xH1, SH.xRest, 1 - (1 - u) * (1 - u)); return [x, gyAt(x) - BR];
  }

  /* ── 카메라: 2D scale/translate만 ── */
  const S0 = 2.4, S1 = 1.4, BOT = 1465;
  let TXF = null;
  function buildCam() { TXF = hermite([[13, 0], [40, 640 - S1 * flightAt(40)[0]], [150, 760 - S1 * SH.xRest]]); }
  const SHAKE = [[7, -5], [-8, 6], [6, -4], [-5, 4], [4, -3], [-3, 2], [2, -1], [-1, 1], [1, 0]];   // 임팩트 흔들림(px, ±8 감쇠)
  const punchAt = (f) => f < F_IMP ? 0 : f === F_IMP ? 0.6 : f === F_IMP + 1 ? 1 : Math.exp(-(f - F_IMP - 1) / 4);
  function camera(f) {
    const sf = sceneF(f);
    let s = lerp(S0, S1, easeIO(seg(sf, 13, 40))), tx = TXF(sf), ty = BOT - s * 1080;
    const pu = easeIO(seg(f, B.restR + 6, 350));
    if (pu > 0) { const k = lerp(1, 1.045, pu), [bx, by] = ballAt(SH.fRest), ax = tx + s * bx, ay = ty + s * by; tx = ax - (ax - tx) * k; ty = ay - (ay - ty) * k; s *= k; }
    const pn = punchAt(f);
    if (pn > 0.002) { const k = 1 + 0.12 * pn, ax = tx + s * SH.tee[0], ay = ty + s * SH.tee[1]; tx = ax - (ax - tx) * k; ty = ay - (ay - ty) * k; s *= k; }
    const sh = SHAKE[f - F_IMP]; if (sh) { tx += sh[0]; ty += sh[1]; }
    return [s, tx, ty];
  }

  /* ── 스틱맨 (실제 리그 → StickmanNode 렌더 규칙, 색만 흰색 100%) ── */
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

  /* ── 오도미터: v(실수)를 자리마다 세로 띠로 굴린다. 일의 자리는 연속, 윗자리는 아래 자리가 9.x일 때만 넘어간다 ── */
  function setOdo(el, v) {
    const cols = el.querySelectorAll(".col"), n = cols.length;
    cols.forEach((c, i) => {
      const k = n - 1 - i, p10 = 10 ** k;
      let pos = k === 0 ? v % 10 : Math.floor(v / p10) % 10 + clamp((v % p10) - (p10 - 1), 0, 1);
      c.firstChild.style.transform = `translateY(${(-pos).toFixed(4)}em)`;
      c.style.visibility = k > 0 && v < p10 - 1 ? "hidden" : "visible";   // 앞자리 0은 숨김(굴러 들어오는 순간부터 보임)
    });
  }

  /* ── 비트 ── */
  const RR = Math.round(B.restR), AR = Math.round(B.apexR), LR = B.landR;
  const F = { statsIn: F_IMP - 1, apexRow: AR - 4, carryRow: AR, lieRow: RR - 8, stamp: RR, cmtIn: 45, cmt1: B.cmt1, erase: RR, cmt2: B.cmt2, cmtOut: 212,
    blink: B.lbBlink, statsOut: B.statsOut, tag: B.tag, wipe: B.wipe, wipeLen: B.wipeLen };
  const BLINK = [0.6, 1, 1, 0.4, 0, 0, 0.6, 1, 1, 0.4, 0];                  // 칸 전체 노랑, 두 번
  const STAMP_SHAKE = [[0, 0], [0, 0], [0, 0], [6, -4], [-5, 3], [4, -2], [-2, 2], [1, -1]];
  const wipeIn = (el, f, f0, n) => { const u = easeOut(seg(f, f0, f0 + n)); el.style.clipPath = `inset(-6px ${(100 - 100 * u).toFixed(2)}% -6px -6px)`; return u; };

  let ready = false, colW = 0;
  const fontsOk = () => ["800 64px Pretendard", "800 92px Pretendard", "700 44px Pretendard", "500 38px JBM"].every((x) => document.fonts.check(x)) && document.fonts.status === "loaded";
  function init() {
    buildCam();
    const bw = bug.offsetWidth; px(lb, 70 + bw + 16, 232, 930 - (70 + bw + 16), bug.offsetHeight);
    stats.style.height = (PADY * 2 + 4 * ROW) + "px";
    // 오도미터 자리 폭 = 고정폭 숫자 "0" 실측
    const t = h("span", null, "0"); t.style.cssText = "position:absolute;visibility:hidden;font:800 84px Pretendard;font-variant-numeric:tabular-nums"; root.appendChild(t);
    colW = t.getBoundingClientRect().width; root.removeChild(t);
    stats.querySelectorAll(".col").forEach((c) => { c.style.width = colW.toFixed(2) + "px"; });
    // 해설 판 폭 = 긴 줄 실측
    for (const e of L2) e.style.display = "none";
    const wmax = say.scrollWidth; for (const e of L2) e.style.display = "";
    cmt.style.width = (wmax + 48 + 6) + "px";
    ready = fontsOk();
  }

  function render(t) {
    if (!ready) init();
    const f = Math.round(t * FPS), sf = sceneF(f);
    const [s, tx, ty] = camera(f);
    desk.style.transform = `translate(${tx.toFixed(3)}px,${ty.toFixed(3)}px) scale(${s.toFixed(5)})`;

    // 스윙: 실캡처 크롭 → 리그 벡터 (장면 프레임; 히트스톱 동안 임팩트 크롭이 멈춰 있다)
    const CROP_AT = [[0, 10], [10, 11], [11, 14], [14, 18], [18, 21]];
    crops.forEach((e, i) => { e.style.visibility = sf >= CROP_AT[i][0] && sf < CROP_AT[i][1] ? "visible" : "hidden"; });
    man.style.visibility = sf >= 21 ? "visible" : "hidden";
    if (sf >= 21) drawMan(Math.round(sf));

    // 임팩트 섬광·충격 링 (실프레임)
    const fl = { [F_IMP]: 1, [F_IMP + 1]: 0.45, [F_IMP + 2]: 0.15 }[f] || 0;
    flash.setAttribute("opacity", fl); flash.setAttribute("r", (16 + 10 * (1 - fl)).toFixed(2));
    const ru = seg(f, F_IMP, F_IMP + 5);
    ring.setAttribute("opacity", (f >= F_IMP && f <= F_IMP + 5 ? 1 - ru : 0).toFixed(3)); ring.setAttribute("r", (16 + 34 * easeOut(ru)).toFixed(2));
    ring.setAttribute("stroke-width", (5 - 3 * ru).toFixed(2));

    // 공 + 트레이서 (장면 프레임, 착지점에서 멈춘다)
    if (sf >= F_IMP) {
      const [bx, by] = ballAt(sf);
      const fe = Math.min(sf, SH.fLand), pts = PTS.filter((p) => p[0] <= fe).map((p) => [p[1], p[2]]);
      pts.push(flightAt(fe));
      const str = pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ");
      for (const k in TRC) TRC[k].setAttribute("points", str);
      ball.setAttribute("cx", bx.toFixed(2)); ball.setAttribute("cy", by.toFixed(2)); ball.style.visibility = "visible";
    } else { for (const k in TRC) TRC[k].setAttribute("points", ""); ball.style.visibility = "hidden"; }

    // 스탯 판: 옆에서 밀려 들어옴(임팩트와 함께) → 줄마다 와이프 → 정지에 벙커 도장 → 왼쪽으로 빠짐
    const sIn = easeOut(seg(f, F.statsIn, F.statsIn + 6)), sOut = easeIn(seg(f, F.statsOut, F.statsOut + 10));
    stats.style.opacity = f < F.statsIn ? 0 : 1;
    stats.style.transform = `translate(${(-760 * sOut).toFixed(2)}px,${(-24 * (1 - sIn)).toFixed(2)}px)`;   // 위에서 내려앉아 들어오고 왼쪽으로 빠진다
    const shown = [F.statsIn, F.apexRow, F.carryRow, F.lieRow];
    R.forEach((r, i) => { const u = easeOut(seg(f, shown[i], shown[i] + 6)); r.style.opacity = f >= shown[i] ? 1 : 0; r.style.clipPath = u >= 1 ? "none" : `inset(-30px ${(100 - 100 * u).toFixed(2)}% -30px -30px)`;
      if (r.rule) r.rule.style.opacity = f >= shown[i] ? 1 : 0; });
    const nRows = shown.reduce((a, f0) => a + easeOut(seg(f, f0 - 2, f0 + 6)), 0);
    stats.style.clipPath = nRows >= 3.999 ? "none" : `inset(-40px -120px ${((1 - clamp(nRows / 4)) * 100 * (4 * ROW) / (4 * ROW + 2 * PADY + 6)).toFixed(2)}% -40px)`;
    setOdo(R[0].querySelector(".odo"), NUM.speed * easeOut(seg(f, F_IMP, F_IMP + 14)));
    setOdo(R[1].querySelector(".odo"), NUM.apex * easeOut(seg(f, F.apexRow, F.apexRow + 12)));
    const carry = f >= LR ? NUM.carry : Math.max(0, (ballAt(sf)[0] - SH.tee[0]) / SH.pxm);
    setOdo(R[2].querySelector(".odo"), carry);
    // 벙커 도장: ×1.6 → ×1 (3프레임, 가속해 내려찍기) + 흔들림
    const su = seg(f, F.stamp, F.stamp + 3), sc = f < F.stamp ? 1.6 : 1.6 - 0.6 * su * su;
    const ss = STAMP_SHAKE[f - F.stamp] || [0, 0];
    chip.style.transform = `translate(${ss[0]}px,${ss[1]}px) scale(${sc.toFixed(3)})`; chip.style.opacity = f >= F.stamp ? 1 : 0;

    // 해설 판: 펼침(6f) → 타자(2f/자, 글자마다 찍히는 팝) → 정지에 백스페이스(2자/f) → "…벙커입니다." 타자 → 접힘
    const cw = easeOut(seg(f, F.cmtIn, F.cmtIn + 6)), cc = easeIn(seg(f, F.cmtOut, F.cmtOut + 6));
    cmt.style.opacity = f >= F.cmtIn && cc < 1 ? 1 : 0;
    cmt.style.clipPath = `inset(-4px ${(100 - 100 * cw + 100 * cc).toFixed(2)}% -4px -4px)`;
    L1.forEach((e, i) => { const at = F.cmt1 + i * B.cmtRate, gone = F.erase + Math.floor((CM1.length - 1 - i) / 2);
      const on = f >= at && f < gone, pop = 1 + 0.35 * (1 - seg(f, at, at + 2));
      e.style.display = f >= gone ? "none" : ""; e.style.opacity = on ? 1 : 0; e.style.transform = `scale(${on ? pop.toFixed(3) : 1})`; });
    L2.forEach((e, i) => { const at = F.cmt2 + i * B.cmtRate, on = f >= at, pop = 1 + 0.35 * (1 - seg(f, at, at + 2));
      e.style.display = f >= F.erase + Math.ceil(CM1.length / 2) ? "" : "none"; e.style.opacity = on ? 1 : 0; e.style.transform = `scale(${on ? pop.toFixed(3) : 1})`; });

    // 리더보드: 칸 전체가 노랑으로 두 번 깜빡 (값은 그대로 1 나 E)
    const bl = BLINK[f - F.blink] || 0;
    lb.style.background = `rgb(255,${Math.round(lerp(255, 210, bl))},${Math.round(lerp(255, 31, bl))})`;

    // 태그라인 판: 스탯 판이 빠진 자리로 와이프 인(8f) → 두 줄이 줄 상자 안에서 밀려 올라온다(12f · 6f 시차)
    const tw = wipeIn(tagline, f, F.tag, 8);
    tagline.style.visibility = f >= F.tag ? "visible" : "hidden";
    tagline.querySelectorAll(".ln span").forEach((e, i) => { const u = easeOut(seg(f, F.tag + 4 + i * 6, F.tag + 16 + i * 6)); e.style.transform = `translateY(${((1 - u) * 105).toFixed(2)}%)`; });

    // 엔드카드: 초록 슬레이트 가로 와이프(노랑 선두 막대) — 위쪽 중계 그래픽과 창을 덮고 브랜드 블록을 드러낸다
    const wu = wipeE(seg(f, F.wipe, F.wipe + F.wipeLen)), wx = 1080 * wu;
    slate.style.visibility = f >= F.wipe ? "visible" : "hidden";
    slate.style.clipPath = `inset(0 ${(100 - 100 * wu).toFixed(3)}% 0 0)`;
    wbar.style.visibility = f >= F.wipe && wu < 1 ? "visible" : "hidden"; px(wbar, wx - 18, 0);
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;

  // ?audit=1 : 3프레임 간격으로 글자 판·공·스틱맨의 화면 사각형 → <pre id="audit"> (scripts/qa.py)
  function audit() {
    const out = { frames: [] };
    const vis = (e) => { let o = 1, n = e; while (n && n !== document.body) { const cs = getComputedStyle(n); if (cs.visibility === "hidden" || cs.display === "none") return 0; o *= parseFloat(cs.opacity); n = n.parentElement; } return o; };
    const rect = (e) => { const r = e.getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom].map(Math.round); };
    const crit = [["tag", tag], ["bug", bug], ["lb", lb], ["stats", stats], ["cmt", cmt], ["tagline", tagline], ["end", end]];
    for (let f = 0; f < NF; f += 3) {
      render(f / FPS);
      const fr = { f, items: [] };
      for (const [name, el] of crit) {
        const o = vis(el); if (o <= 0.05) continue;
        if (name === "stats" && f >= F.statsOut) continue;                        // 왼쪽으로 빠지는 중(글자 없음 → 화면 밖)
        if (name === "end" && f < F.wipe + F.wipeLen) continue;                   // 와이프로 드러나는 중
        if ((name === "tag" || name === "bug" || name === "lb") && f >= F.wipe + F.wipeLen) continue;   // 슬레이트 아래
        fr.items.push({ name, o: +o.toFixed(2), r: rect(el) });
      }
      if (sceneF(f) >= F_IMP) fr.items.push({ name: "ball", o: 1, r: rect(ball) });
      fr.items.push({ name: "man", o: 1, r: sceneF(f) < 21 ? rect(manBox) : rect(man) });
      fr.scale = +camera(f)[0].toFixed(3);
      out.frames.push(fr);
    }
    out.fontsOk = fontsOk();
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  Promise.all([document.fonts.ready, ...[plate, ...crops].map((e) => e.decode().catch(() => 0))]).then(() => { init(); if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); });
})();
