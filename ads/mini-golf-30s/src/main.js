/* mini-golf 30s — 본편 컴포지션 (가로·세로 × 한·영 4변형을 이 파일 하나가 그린다)
 *
 * 구조: 셸(index.html = 1920×1080, vertical.html = 1080×1920)이 #root 크기를 정하고, 언어는 HyperFrames 변수 lang(ko|en).
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). GSAP 타임라인은 재생 헤드 역할만 한다. Math.random·Date 없음.
 * 타이밍 단일 출처: src/timeline.js (make-audio.py도 같은 파일을 읽는다). 기획·비트 시트·근거: plan.md
 *
 * 장면 = '데스크탑 한 벌'(1920×1080pt, .desk) + 2D 카메라(translate+scale 하나). 컷은 박 위의 하드컷이다(이 판에서 허용).
 *   S0 훅    f0–59    실제 리그(60Hz)로 그린 벡터 스틱맨, 1/4속 다운스윙 → f30 임팩트 → 속도 램프 + 풀백
 *   S1 헤드  f60–179  공이 창들 위로 날아와 "9홀이 조용히 돌아갑니다"의 마침표가 된다 → 마침표로 푸시인 (매치컷 준비)
 *   M1–M5   f180–599 몽타주 "창마다 다른 홀": 실캡처 클립(타일 코덱) · 댄스는 리그 벡터
 *   H 정직   f600–719 클릭이 스틱맨을 지나 아래 앱으로 → 끄면 흔적 없음
 *   E 엔드   f720–899 터미널 brew 설치 → 띠가 돌아온다 → 워드마크·메타·URL, 끝 정지
 */
(() => {
  const TL = window.TL, FPS = TL.fps, NF = TL.frames, DUR = NF / FPS;
  const root = document.getElementById("root");
  const RW = root.offsetWidth, RH = root.offsetHeight;
  const O = RW > RH ? "h" : "v";
  const vars = (window.__hyperframes && window.__hyperframes.getVariables && window.__hyperframes.getVariables()) || {};
  const q = new URLSearchParams(location.search);
  const LANG = q.get("lang") || vars.lang || "ko";
  const KO = LANG === "ko";

  // 글꼴 7면을 시작하자마자 모두 불러온다 — font-display:block이라, 처음 쓰이는 굵기(자막 800 등)가 늦게 오면 그 프레임 글자가 비어 찍힌다(결정성)
  const FONT_FACES = [["400", "Pretendard"], ["500", "Pretendard"], ["600", "Pretendard"], ["700", "Pretendard"], ["800", "Pretendard"], ["400", "JBM"], ["500", "JBM"]];
  const FONT_LOADS = FONT_FACES.map(([w, fam]) => document.fonts.load(`${w} 40px ${fam}`, fam === "JBM" ? "A1:" : "가A1").catch(() => []));

  /* ── 문구 ── */
  const TX = KO ? {
    tele: [["로프트", "10.5", "°"], ["백스핀", "2,700", " rpm"], ["탄도", "240", "Hz 실시간"]],
    kick: "화면 맨 아래 띠에서,", sent: ["9홀이 조용히", "돌아갑니다"],
    c1: "창마다, 다른 홀.", c2: "거위가 공 위에 앉고,", c3: "강아지가 공을 물고 가고,", c4: "스틱맨은 딴청을 피우고,",
    c5: "정각엔 뻐꾸기가 울어도,", c6: "그래도 버디.", h1: "클릭은 스틱맨을 지나, 아래 앱으로.", h2: "끄면, 흔적도 없이.",
    tag4: "잔동작 42종 · 밈 12종 — 헛스윙 개그",
    hud: { m1: ["1번 홀 · 파 5 · 계단", "드라이버 · 우드"], m2: ["3번 홀 · 파 4 · 협곡", "우드 · 바람 → 6m/s"], m3: ["2번 홀 · 파 4 · 폭포", "러프 · 바람 → 2m/s"],
           m5a: ["7번 홀 · 파 4 · 산정 그린", "우드 · 바람 → 6m/s"], m5b: ["7번 홀 · 파 4 · 산정 그린", "퍼터 · 그린 · 7m"] },
    badge: ["배지 획득", "등정가"],
    menu: ["편집기", "파일", "편집", "보기", "창"], clock: "수 9월 30일 오후 2:58", clock3: "수 9월 30일 오후 3:00",
    notes: "메모 — 오늘", ed: "Ballistics.swift — mini-golf", doc: "3분기 보고서 — 초안", chat: "제품팀", web: "온보딩 가이드", sheetT: "예산.xlsx", calT: "캘린더", termT: "터미널 — zsh",
    end2: "macOS 메뉴바 앱 · 무료 · 오픈소스",
  } : {
    tele: [["loft", "10.5", "°"], ["backspin", "2,700", " rpm"], ["ball flight", "240", " Hz live"]],
    kick: "Along the bottom of your screen,", sent: ["nine holes", "play quietly"],
    c1: "Every window, a different hole.", c2: "Geese sit on your ball,", c3: "a dog runs off with it,", c4: "the stickman goofs off,",
    c5: "the cuckoo calls the hour —", c6: "still a birdie.", h1: "Clicks pass right through.", h2: "Quit, and nothing stays behind.",
    tag4: "42 idle motions · 12 meme moves — the whiff gag",
    hud: { m1: ["Hole 1 · Par 5 · Terraces", "Driver · wood"], m2: ["Hole 3 · Par 4 · Canyon", "Wood · wind → 6 m/s"], m3: ["Hole 2 · Par 4 · Cascade", "Rough · wind → 2 m/s"],
           m5a: ["Hole 7 · Par 4 · Summit", "Wood · wind → 6 m/s"], m5b: ["Hole 7 · Par 4 · Summit", "Putter · green · 7 m"] },
    badge: ["Badge earned", "Summiteer"],
    menu: ["Editor", "File", "Edit", "View", "Window"], clock: "Wed Sep 30 2:58 PM", clock3: "Wed Sep 30 3:00 PM",
    notes: "Notes — Today", ed: "Ballistics.swift — mini-golf", doc: "Q3 report — draft", chat: "Product team", web: "Onboarding guide", sheetT: "budget.xlsx", calT: "Calendar", termT: "Terminal — zsh",
    end2: "macOS menu-bar app · free · open source",
  };
  if (O === "v") Object.assign(TX, KO ? { h1: "클릭은 스틱맨을 지나,\n아래 앱으로.", c3: "강아지가 공을\n물고 가고," }
    : { c1: "Every window,\na different hole.", c2: "Geese sit\non your ball,", c3: "a dog runs off\nwith it,", c4: "the stickman\ngoofs off,",
        c5: "the cuckoo calls\nthe hour —", h1: "Clicks pass\nright through.", h2: "Quit, and nothing\nstays behind." });
  const URL_TEXT = "github.com/w0uldy0udaestar/mini-golf";
  const BREW = "brew install --cask w0uldy0udaestar/tap/mini-golf";

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const smooth = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
  const seg = (f, a, b) => clamp((f - a) / (b - a));
  const bez = (x1, y1, x2, y2) => (p) => { if (p <= 0) return 0; if (p >= 1) return 1; let a = 0, b = 1, t = p;
    for (let i = 0; i < 30; i++) { t = (a + b) / 2; const x = 3 * x1 * (1 - t) ** 2 * t + 3 * x2 * (1 - t) * t * t + t ** 3; x < p ? a = t : b = t; }
    return 3 * y1 * (1 - t) ** 2 * t + 3 * y2 * (1 - t) * t * t + t ** 3; };
  const camEase = bez(0.25, 0.1, 0.25, 1);
  const SPR = { calm: [0.78, 2.7], settle: [0.62, 3.2], soft: [0.5, 3.3] };
  const step = (t, z, f) => { const w = 2 * Math.PI * f, d = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(d * t) + z * w / d * Math.sin(d * t)); };
  const Sk = (t, n) => { if (t <= 0) return 0; const [z, f] = SPR[n]; const D = 6 / (z * 2 * Math.PI * f); return t >= D ? 1 : step(t, z, f) / step(D, z, f); };
  const pw = (map, f) => { // 구간별 선형 맵 [[x,y],…]
    if (f <= map[0][0]) return map[0][1];
    for (let i = 1; i < map.length; i++) if (f <= map[i][0]) { const a = map[i - 1], b = map[i]; return b[0] === a[0] ? b[1] : lerp(a[1], b[1], (f - a[0]) / (b[0] - a[0])); }
    return map[map.length - 1][1];
  };
  const fx2 = (v) => v.toFixed(2);

  /* ── DOM ── */
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const px = (e, x, y, w, hh) => { e.style.left = x + "px"; e.style.top = y + "px"; if (w != null) e.style.width = w + "px"; if (hh != null) e.style.height = hh + "px"; return e; };
  const NS = "http://www.w3.org/2000/svg";
  const mk = (tag, a) => { const e = document.createElementNS(NS, tag); for (const k in a) e.setAttribute(k, a[k]); return e; };

  // 선로드: 판·아틀라스는 문서 안 <img>로 둔다 — 렌더러가 decode를 기다린다(첫 프레임 전에 전부 준비)
  const pre = h("div"); pre.id = "preload"; root.appendChild(pre);
  const IMG = {};
  const img = (src) => { if (IMG[src]) return IMG[src]; const e = h("img"); e.src = src; e.decoding = "sync"; pre.appendChild(e); IMG[src] = e; return e; };

  const FLAG = `<svg class="flag" viewBox="0 0 14 16"><line x1="3" y1="1" x2="3" y2="15" stroke="#E6E6E2" stroke-width="1.6" stroke-linecap="round"/><path d="M3.8 1.6 L12.5 4.4 L3.8 7.2 Z" fill="#D94D3D"/></svg>`;
  const CURSOR = `<svg viewBox="0 0 22 32" width="22" height="32"><path d="M2 2 L2 25 L7.6 19.8 L11.4 28.6 L15 27 L11.3 18.4 L18.8 18.4 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;

  function makeDesk(opts = {}) {
    const d = h("div", "desk"); root.insertBefore(d, screenLayer);
    const mb = h("div", "menubar", `<span class="app">${opts.app || TX.menu[0]}</span>${TX.menu.slice(1).map((s) => `<span>${s}</span>`).join("")}<span class="sp"></span><span class="flagbox">${FLAG}</span><span class="clk">${opts.clock || TX.clock}</span>`);
    d.appendChild(mb); d._menubar = mb;
    return d;
  }
  function win(desk, r, title, cls = "") {
    const w = px(h("div", "win " + cls), r[0], r[1], r[2], r[3]);
    w.innerHTML = `<div class="bar"><i></i><i></i><i></i><div class="t">${title}</div></div><div class="body"></div>`;
    desk.insertBefore(w, desk._menubar); return w.querySelector(".body");
  }

  /* ── 화면 고정층 (자막·HUD·텔레메트리·엔드) ── */
  const screenLayer = h("div"); screenLayer.id = "screen"; root.appendChild(screenLayer);

  /* ── 벡터 스틱맨: 게임 StickmanNode 렌더 규칙 그대로 (리그 좌표 = pt, y 위쪽, dir로 미러) ── */
  const RIGS = window.RIGS;
  function rigAt(track, t) {
    const S = track.samples; let lo = 0, hi = S.length - 1;
    if (t <= S[0][0]) return S[0]; if (t >= S[hi][0]) return S[hi];
    while (hi - lo > 1) { const m = (lo + hi) >> 1; S[m][0] <= t ? lo = m : hi = m; }
    const a = S[lo], b = S[hi], u = (t - a[0]) / (b[0] - a[0]), r = a.slice();
    if (a[28] !== b[28]) return u < 0.5 ? a : b;   // 방향 반전 순간은 보간하지 않는다
    for (let i = 2; i <= 26; i++) r[i] = lerp(a[i], b[i], u);
    r[1] = u < 0.5 ? a[1] : b[1]; r[27] = u < 0.5 ? a[27] : b[27];
    return r;
  }
  function stickAt(track, t) { // [t, x, groundY(top), mode] 0.5초 표본 선형 보간
    const S = track.stick; if (t <= S[0][0]) return S[0]; if (t >= S[S.length - 1][0]) return S[S.length - 1];
    for (let i = 1; i < S.length; i++) if (S[i][0] >= t) { const a = S[i - 1], b = S[i], u = (t - a[0]) / (b[0] - a[0]); return [t, lerp(a[1], b[1], u), lerp(a[2], b[2], u), a[3]]; }
  }
  const ell = (cx, cy, rx, ry, a0 = 0, a1 = 2 * Math.PI, n = 20) => { const o = []; for (let i = 0; i <= n; i++) { const a = lerp(a0, a1, i / n); o.push([cx + rx * Math.cos(a), cy + ry * Math.sin(a)]); } return o; };
  const poly = (f, pts) => "M" + pts.map(f).join(" L") + " Z";
  const HATS = { // 게임 StickmanNode.setHat 모양 그대로 (머리 중심 기준, y 위쪽)
    crown: { fill: "rgba(228,80,60,.95)", d: (f) => poly(f, [[-9, 7], [-9, 15], [-4.5, 10], [0, 16], [4.5, 10], [9, 15], [9, 7]]) },
    straw: { fill: "rgba(219,219,219,.95)", d: (f) => poly(f, ell(0, 8.75, 14, 2.25)) + " " + poly(f, [[-6.5, 8], [6.5, 8], [6.5, 13.5], [-6.5, 13.5]]) },
    propeller: { fill: "rgba(209,209,209,.95)", d: (f) => poly(f, ell(0, 6, 9.5, 9.5, 0, Math.PI, 16)) + " " + poly(f, ell(0, 16.8, 8, 1.3)) + " " + poly(f, [[-0.9, 13.5], [0.9, 13.5], [0.9, 16.5], [-0.9, 16.5]]) },
    top: { fill: "rgba(179,179,179,.95)", d: (f) => poly(f, [[-11, 6.5], [11, 6.5], [11, 9.1], [-11, 9.1]]) + " " + poly(f, [[-6.5, 9], [6.5, 9], [6.5, 21], [-6.5, 21]]) },
  };
  function makeMan(svg) {
    const g = mk("g", {}); svg.appendChild(g);
    const P = {
      trail: mk("path", { fill: "none", stroke: "rgba(224,224,224,.52)", "stroke-width": 5.5, "stroke-linecap": "round", "stroke-linejoin": "round" }),
      body: mk("path", { fill: "none", stroke: "rgba(224,224,224,.95)", "stroke-width": 6, "stroke-linecap": "round", "stroke-linejoin": "round" }),
      shaft: mk("path", { fill: "none", stroke: "rgba(194,194,194,.9)", "stroke-width": 3, "stroke-linecap": "round" }),
      chead: mk("path", { fill: "none", stroke: "rgba(237,237,237,.95)", "stroke-width": 13.6, "stroke-linecap": "round" }),
      grip: mk("path", { fill: "none", stroke: "rgba(153,153,153,.9)", "stroke-width": 4.6, "stroke-linecap": "round" }),
      head: mk("circle", { r: 10, fill: "rgba(224,224,224,.95)" }),
      hat: mk("path", { fill: "none" }),
    };
    for (const k of ["trail", "body", "shaft", "chead", "grip", "head", "hat"]) g.appendChild(P[k]);
    return { g, P };
  }
  function drawMan(M, r, gx, gy, hat) {
    const d = r[28], f = (p) => `${fx2(p[0])} ${fx2(p[1])}`;
    const pts = []; for (let i = 0; i < 10; i++) pts.push([gx + r[2 + 2 * i] * d, gy - r[3 + 2 * i]]);
    const [hip, sh, f1, f2, k1, k2, grip, ht, el, et] = pts;
    const ctl = [(sh[0] + hip[0]) / 2 - d * 0.8, (sh[1] + hip[1]) / 2];
    const arm = (a, e, b) => r[27] ? `M${f(a)} Q${f(e)} ${f(b)}` : `M${f(a)} L${f(e)} L${f(b)}`;
    M.P.body.setAttribute("d", `M${f(sh)} Q${f(ctl)} ${f(hip)} M${f(hip)} L${f(k1)} L${f(f1)} M${f(hip)} L${f(k2)} L${f(f2)} ${arm(sh, el, grip)}`);
    M.P.trail.setAttribute("d", arm(sh, et, ht));
    const phi = r[24], len = r[25], butt = r[26], sp = Math.sin(phi), cp = Math.cos(phi);
    const tip = [grip[0] + sp * len * d, grip[1] + cp * len], bt = [grip[0] - sp * butt * d, grip[1] - cp * butt];
    M.P.shaft.setAttribute("d", `M${f(bt)} L${f(tip)}`);
    M.P.grip.setAttribute("d", `M${f(bt)} L${f([grip[0] + sp * 8 * d, grip[1] + cp * 8])}`);
    const perp = [Math.cos(phi) * d, -Math.sin(phi)], c = [tip[0] + perp[0] * 4.5, tip[1] + perp[1] * 4.5], half = 1.7;
    M.P.chead.setAttribute("d", `M${f([c[0] - perp[0] * half, c[1] - perp[1] * half])} L${f([c[0] + perp[0] * half, c[1] + perp[1] * half])}`);
    const hd = [sh[0] + d * r[22], sh[1] - r[23]];
    M.P.head.setAttribute("cx", fx2(hd[0])); M.P.head.setAttribute("cy", fx2(hd[1]));
    const H = HATS[hat];
    if (H) { const hf = (p) => f([hd[0] + p[0] * d, hd[1] - p[1]]); M.P.hat.setAttribute("d", H.d(hf)); M.P.hat.setAttribute("fill", H.fill); }
    else M.P.hat.setAttribute("d", "");
    return { tip, grip, phi, len, d, hd };
  }

  /* ── 실캡처 클립 재생기 (타일 코덱: 판 + 바뀐 32px 타일) ── */
  const CLIPS = window.CLIPS;
  function makeClip(name, desk) {
    const C = CLIPS[name], T = C.tile;
    const cv = h("canvas", "clip"); cv.width = C.w; cv.height = C.h;
    px(cv, C.box[0], C.box[1], C.w / 2, C.h / 2);
    desk.appendChild(cv);
    const ctx = cv.getContext("2d");
    const plate = img(`assets/gen/${C.plate}`), atl = C.atlases.map((a) => img(`assets/gen/${a}`));
    const ts = C.frames.map((fr) => fr.t);
    let last = -1;
    return { el: cv, C,
      draw(t) {
        let lo = 0, hi = ts.length - 1;
        if (t <= ts[0]) hi = 0; else if (t >= ts[hi]) lo = hi; else { while (hi - lo > 1) { const m = (lo + hi) >> 1; ts[m] <= t ? lo = m : hi = m; } }
        const k = t >= ts[ts.length - 1] ? ts.length - 1 : lo;
        if (!(plate.complete && plate.naturalWidth) || atl.some((a) => !(a.complete && a.naturalWidth))) return;   // 이미지 전엔 그리지 않고 캐시도 안 한다
        if (k === last) return; last = k;
        ctx.clearRect(0, 0, C.w, C.h); ctx.drawImage(plate, 0, 0);
        for (const [tx, ty, u] of C.frames[k].tiles) {
          const ai = Math.floor(u / C.perAtlas), j = u % C.perAtlas, r = Math.floor(j / C.perRow), c = j % C.perRow;
          ctx.clearRect(tx * T, ty * T, T, T); ctx.drawImage(atl[ai], c * T, r * T, T, T, tx * T, ty * T, T, T);
        }
      } };
  }

  /* ── 카메라: 데스크탑 점 (cx,cy)를 화면 (sx,sy)에 배율 s로 ── */
  // 세로판: 데스크탑 아래 가장자리가 화면 y 1500(안전 영역 아래 경계)까지 올라올 수 있게 — 그 아래 420px(플랫폼 UI 자리)는 화면 밖 어둠
  const BELOW = O === "v" ? 420 : 0;
  function setCam(desk, s, cx, cy, sx = RW / 2, sy = RH / 2) {
    // 뷰가 데스크탑(1920×1080pt) 밖으로 나가지 않게 가둔다 — 화면 밖(검은 여백)을 보이지 않는다
    const vw = RW / s, vh = RH / s;
    let left = cx - sx / s, top = cy - sy / s;
    left = vw <= 1920 ? clamp(left, 0, 1920 - vw) : (1920 - vw) / 2;
    top = vh <= 1080 + BELOW / s ? clamp(top, 0, 1080 + BELOW / s - vh) : (1080 - vh) / 2;
    desk.style.transform = `translate(${(-s * left).toFixed(3)}px,${(-s * top).toFixed(3)}px) scale(${s.toFixed(5)})`;
    desk._cam = [s, left, top];
  }
  const camView = (s, cx, cy, sx = RW / 2, sy = RH / 2) => { const vw = RW / s, vh = RH / s; let left = cx - sx / s, top = cy - sy / s;
    left = vw <= 1920 ? clamp(left, 0, 1920 - vw) : (1920 - vw) / 2; top = vh <= 1080 + BELOW / s ? clamp(top, 0, 1080 + BELOW / s - vh) : (1080 - vh) / 2; return [s, left, top]; };
  const toScreen = (desk, p) => { const [s, left, top] = desk._cam; return [s * (p[0] - left), s * (p[1] - top)]; };
  const lerpCam = (A, B, u) => [lerp(A[0], B[0], u), lerp(A[1], B[1], u), lerp(A[2], B[2], u), lerp(A[3] ?? RW / 2, B[3] ?? RW / 2, u), lerp(A[4] ?? RH / 2, B[4] ?? RH / 2, u)];

  /* ════════════════ S0+S1: 훅 · 헤드라인 (절벽 티 데스크탑) ════════════════ */
  const HK = window.HOOK, HT = TL.hook;
  // 2단계: 메모 창을 가운데로 — 마침표가 f179에 다음 컷 공의 화면 자리(가둔 카메라로 닿는 자리)까지 올 수 있게 (오른쪽 끝이면 뷰 가둠 때문에 못 온다)
  const S1L = O === "h" ? { editor: [440, 330, 860, 760], notes: [640, 60, 860, 470], pad: [56, 54], kick: 38, sent: 94, gap: 18,
    ecu: [5.6, 178, 800], tee: [1.5, 560, 700], wide: [1.46, 1200, 330] }   // 마침표가 처음부터 화면 가운데 가까이 → 푸시인의 옆 미끄러짐을 줄인다
    : { editor: [300, 640, 560, 440], notes: [26, 330, 470, 290], pad: [34, 30], kick: 26, sent: 58, gap: 12,
    ecu: [6.4, 150, 800, 540, 900], tee: [2.2, 250, 640, 540, 900], wide: [2.2, 250, 640, 540, 900] };
  const dH = makeDesk({ clock: TX.clock });
  const edBody = win(dH, S1L.editor, TX.ed);
  const SWIFT = [
    ["c", KO ? "    /// 결정론적 물리 스텝. 경사면 바운스는 법선 반사, 굴림에는 중력의 경사 성분이 더해진다." : "    /// Deterministic physics step. Slope bounces reflect about the normal; rolling adds gravity's slope component."],
    ["", "    <k>public static func</k> step("], ["", "        _ b: <k>inout</k> BallState, hole: Hole, dt: Double = Phys.dt, wind: Double? = <k>nil</k>,"],
    ["", "        kind: BallKind = .standard"], ["", "    ) -> StepEvent {"], ["", "        <k>switch</k> b.phase {"], ["", "        <k>case</k> .fly:"],
    ["c", KO ? "            // 바람: 공기력은 대기 상대속도 기준 — 뒷바람은 항력을 줄이고 맞바람은 키운다" : "            // Wind: aero forces use air-relative velocity — tailwind cuts drag, headwind adds it"],
    ["", "            <k>let</k> rvx = b.vx - (wind ?? hole.wind)"], ["", "            <k>let</k> v = max(hypot(rvx, b.vy), <n>1e-9</n>)"],
    ["", "            <k>let</k> omega = b.spin * <n>2</n> * .pi / <n>60</n>"], ["", "            <k>let</k> spinRatio = min(Phys.ballRadius * omega / v, Phys.spinRatioMax)"],
    ["", "            <k>let</k> cl = min(Phys.clMax, Phys.clBase + Phys.clSlope * spinRatio)"],
    ["c", KO ? "            // 항력(상대속도 반대) + 마그누스 양력(상대속도 수직, 백스핀=위) + 중력" : "            // Drag (against relative velocity) + Magnus lift (perpendicular, backspin = up) + gravity"],
    ["", "            <k>let</k> ax = -q * Phys.cd * v * rvx + q * cl * v * -b.vy * b.spinSign"],
    ["", "            <k>let</k> ay = -Phys.g - q * Phys.cd * v * b.vy + q * cl * v * rvx * b.spinSign"],
    ["", "            b.vx += ax * dt"], ["", "            b.vy += ay * dt"], ["", "            b.x += b.vx * dt"], ["", "            b.y += b.vy * dt"],
    ["", "            b.spin *= 1 - min(0.06, max(0.01, Phys.spinDecayPerSpeed * v)) * dt"], ["", ""],
    ["", "            <k>let</k> ground = hole.ground(at: b.x)"], ["", "            <k>if</k> b.y <= ground {"],
    ["", "                <k>let</k> surfType = hole.surface(at: b.x)"], ["", "                <k>if</k> surfType == .water { <k>return</k> .water }"],
  ];
  const fmt = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/&lt;(\/?)(k|n)>/g, (m, sl, t) => sl ? "</span>" : `<span class="${t}">`);
  const code = h("div", "code"); code.innerHTML = SWIFT.map(([c, s], i) => `<span class="row"><span class="ln">${340 + i}</span>${c === "c" ? `<span class="c">${fmt(s)}</span>` : fmt(s)}</span>`).join("");
  edBody.appendChild(code); code.style.opacity = 0.4;   // 훅에선 ×1.5로 크게 보이는 배경 — 선화(주인공)보다 물러나게
  win(dH, S1L.notes, TX.notes, "notes");
  const plateH = px(h("img", "plate"), 0, 0); plateH.src = "assets/gen/plate-skytee.png"; img("assets/gen/plate-skytee.png"); dH.appendChild(plateH);
  const svgH = mk("svg", { class: "fx", width: 1920, height: 1080 }); dH.appendChild(svgH);
  const trailH = mk("polyline", { fill: "none", stroke: "rgba(255,255,255,.34)", "stroke-width": 1.4, "stroke-linecap": "round", "stroke-linejoin": "round" }); svgH.appendChild(trailH);
  const manH = makeMan(svgH);
  const smearH = mk("path", { fill: "none", stroke: "rgba(242,242,242,.38)", "stroke-width": 2.5, "stroke-linecap": "round" }); svgH.appendChild(smearH);
  const teeH = mk("g", {}); teeH.appendChild(mk("rect", { x: -0.7, y: -4, width: 1.4, height: 4, rx: 0.5, fill: "rgba(255,255,255,.9)" }));
  teeH.appendChild(mk("rect", { x: -2.6, y: -4.7, width: 5.2, height: 1.3, rx: 0.5, fill: "rgba(255,255,255,.9)" })); svgH.appendChild(teeH);
  const ringH = mk("circle", { r: 6, fill: "none", stroke: "rgba(255,255,255,.7)", "stroke-width": 1.2, opacity: 0 }); svgH.appendChild(ringH);
  const textH = px(h("div"), 0, 0, 1920, 1080); dH.appendChild(textH);
  const [NX, NY, NW] = S1L.notes;
  const kickEl = px(h("div", "kick"), NX + S1L.pad[0], NY + 34 + S1L.pad[1]); kickEl.style.fontSize = S1L.kick + "px"; textH.appendChild(kickEl);
  const sentTop = NY + 34 + S1L.pad[1] + S1L.kick * 1.3 + S1L.gap;
  const sentEl = px(h("div", "sent"), NX + S1L.pad[0], sentTop); sentEl.style.fontSize = S1L.sent + "px"; sentEl.style.lineHeight = "1.08";
  sentEl.style.letterSpacing = (KO ? -0.035 : -0.03) * S1L.sent + "px";
  sentEl.innerHTML = `<span class="ln2" id="s0"></span><span class="ln2" id="s1"></span>`; textH.appendChild(sentEl);
  const caretH = h("div", "caret"); textH.appendChild(caretH);
  const ballH = h("div", "ball"); dH.appendChild(ballH);

  // 텔레메트리 (화면 고정, 훅 풀백 동안): 클럽 데이터 README 표 그대로
  const tele = h("div"); tele.style.cssText = "position:absolute;left:0;top:0;opacity:0"; screenLayer.appendChild(tele);
  const teleRows = TX.tele.map((r) => { const e = h("div", "tele", `<span class="k">${r[0]}</span> <b class="v"></b><span class="u">${r[2]}</span>`); tele.appendChild(e); return e; });

  const S0_TEE = [153.5, 851.5];
  let SM = null;   // 글자 측정 캐시(폰트 로드 뒤에만)
  function measureHead() {
    const saved = dH.style.transform, disp = dH.style.display; dH.style.transform = "none"; dH.style.display = "block";
    const s0 = document.getElementById("s0"), s1 = document.getElementById("s1");
    const S0 = [...TX.sent[0]], S1 = [...TX.sent[1]];
    const W = (el, arr) => { const out = []; el.style.display = "inline-block"; for (let i = 0; i <= arr.length; i++) { el.textContent = arr.slice(0, i).join(""); out.push(el.getBoundingClientRect().width); } el.style.display = ""; el.textContent = ""; return out; };
    const w0 = W(s0, S0), w1 = W(s1, S1);
    s1.innerHTML = S1.join("") + `<span id="bl" style="display:inline-block;width:0;height:0;vertical-align:baseline"></span>`; s0.textContent = S0.join("");
    const d = dH.getBoundingClientRect(), bl = document.getElementById("bl").getBoundingClientRect(), s0r = s0.getBoundingClientRect(), s1r = s1.getBoundingClientRect(), sr = sentEl.getBoundingClientRect();
    kickEl.textContent = TX.kick; const kw = kickEl.getBoundingClientRect().width; kickEl.textContent = "";
    const kchars = [...TX.kick]; const kW = []; kickEl.style.display = "inline-block";
    for (let i = 0; i <= kchars.length; i++) { kickEl.textContent = kchars.slice(0, i).join(""); kW.push(kickEl.getBoundingClientRect().width); } kickEl.textContent = ""; kickEl.style.display = "";
    const period = { d: S1L.sent * 0.17 };
    period.x = sr.left - d.left + w1[S1.length] + S1L.sent * 0.03 + period.d / 2;
    period.y = bl.top - d.top - period.d / 2;
    s0.textContent = ""; s1.textContent = "";
    dH.style.transform = saved; dH.style.display = disp;
    SM = { w0, w1, kW, kw, period, s0top: s0r.top - d.top, s1top: s1r.top - d.top, lineH: s0r.height, S0, S1, kchars };
  }
  // 공 경로: 실제 드라이브 궤적의 아치(현에서 뜬 높이)를 새 현(티 → 마침표)에 옮긴다 (15초판과 같은 방법, 아치 ×1.7)
  let PATH = null;
  function buildPath() {
    const S = S0_TEE, E = [SM.period.x, SM.period.y], TR = HK.trail, B = HK.ball;
    const R0 = B.f73, R1 = B.f184;
    const arch = TR.map(([x, y]) => { const u = (x - R0[0]) / (R1[0] - R0[0]); return [u, y - (R0[1] + (R1[1] - R0[1]) * u)]; });
    arch.unshift([0, 0]); arch.push([1, 0]);
    const hAt = (u) => { for (let i = 1; i < arch.length; i++) if (arch[i][0] >= u) { const a = arch[i - 1], b = arch[i]; return lerp(a[1], b[1], (u - a[0]) / Math.max(1e-6, b[0] - a[0])); } return 0; };
    const k = (Math.hypot(E[0] - S[0], E[1] - S[1]) / Math.hypot(R1[0] - R0[0], R1[1] - R0[1])) * (O === "h" ? 1.7 : 1.5);
    PATH = []; for (let i = 0; i <= 400; i++) { const u = i / 400; PATH.push([lerp(S[0], E[0], u), lerp(S[1], E[1], u) + hAt(u) * k]); }
  }
  const pathAt = (u) => { const i = clamp(u) * 400, a = Math.min(399, Math.floor(i)), fr = i - a; return [lerp(PATH[a][0], PATH[a + 1][0], fr), lerp(PATH[a][1], PATH[a + 1][1], fr)]; };

  // 게임 시각 g(f): 1/4속 → 램프 → 1× (임팩트 f30에서 g=0이 되도록 적분)
  const speedAt = (f) => f < HT.rampFrom ? HT.slow : f < HT.rampTo ? lerp(HT.slow, 1, smooth(seg(f, HT.rampFrom, HT.rampTo))) : 1;
  const GT = (() => { const a = [0]; for (let f = 1; f <= 200; f++) a.push(a[f - 1] + (speedAt(f - 1) + speedAt(f)) / 2 / FPS); return a; })();
  const gOf = (f) => { const i = Math.floor(clamp(f, 0, 199)), u = f - i; return lerp(GT[i], GT[i + 1], u) - GT[HT.impact]; };
  const HERO = RIGS.hero;
  // 리그 속 임팩트 = 클럽 헤드 끝이 공(로컬 x=0)을 지나는 순간 (시각적 접촉, 15초판 캡처 대조와 같은 기준)
  const RIG_IMPACT = (() => { const S = HERO.samples; for (let i = 1; i < S.length; i++) { const a = S[i - 1], b = S[i];
    if (a[1] === "swinging" || b[1] === "motion") { const ta = a[14] + Math.sin(a[24]) * a[25], tb = b[14] + Math.sin(b[24]) * b[25];
      if (a[24] > 5 && ta < 0 && tb >= 0) return lerp(a[0], b[0], -ta / (tb - ta)); } } return 2.85; })();
  const FLIGHT_G = gOf(HT.land);   // 임팩트 → 착지(마침표)까지 게임 시각
  const flightU = (g) => 1 - Math.pow(1 - clamp(g / FLIGHT_G), 1.55);
  const groundH = (x) => HK.ground[Math.round(clamp(x, 0, 1919))] + 0.6;

  function renderS01(f) {
    // 카메라
    let cam;
    const E = S1L.ecu, Tee = S1L.tee, Nt = S1L.wide;
    if (f < HT.pullFrom) cam = E;
    else if (f < HT.pullTo) cam = lerpCam(E, Tee, camEase(seg(f, HT.pullFrom, HT.pullTo)));
    else if (f < HT.panFrom) cam = Tee;
    else cam = lerpCam(Tee, Nt, camEase(seg(f, HT.panFrom, HT.panTo)));
    setCam(dH, cam[0], cam[1], cam[2], cam[3], cam[4]);
    // 스틱맨 (리그)
    const g = gOf(f), rt = RIG_IMPACT + g;
    const r = rigAt(HERO, rt);
    const st = stickAt(HERO, rt);
    const gx = st[1], gy = groundH(gx);
    const man = drawMan(manH, r, gx, gy, "crown");
    // 티 페그: 임팩트에 앞으로 튕겨 1.5바퀴 (게임 teeNode 액션 그대로: 0.55초 회전 −4.5rad, 0.22초 +7/+11 → 0.33초 +5/−15, 0.35초부터 0.2초 페이드)
    const tg = g; let tx = S0_TEE[0], ty = groundH(S0_TEE[0]), rot = 0, top = 1;
    if (tg > 0) { rot = -4.5 * Math.min(1, tg / 0.55) * 57.2958;
      if (tg < 0.22) { const u = tg / 0.22; tx += 7 * u; ty -= 11 * (1 - (1 - u) * (1 - u)); } else { const u = Math.min(1, (tg - 0.22) / 0.33); tx += 7 + 5 * u; ty -= 11 - 15 * u * u; }
      top = tg < 0.35 ? 1 : Math.max(0, 1 - (tg - 0.35) / 0.2); }
    teeH.setAttribute("transform", `translate(${fx2(tx)} ${fx2(ty)}) rotate(${fx2(rot)})`); teeH.setAttribute("opacity", top.toFixed(3));
    // 임팩트 스미어 (게임 impactSmear: 헤드 궤적 원호 0.85rad, 0.13초 페이드)
    if (g >= 0 && g < 0.13) {
      const pts = []; for (let k = 0; k <= 10; k++) { const ph = man.phi - 0.85 * (1 - k / 10); pts.push([man.grip[0] + Math.sin(ph) * man.len * man.d, man.grip[1] + Math.cos(ph) * man.len]); }
      smearH.setAttribute("d", "M" + pts.map((p) => `${fx2(p[0])} ${fx2(p[1])}`).join(" L")); smearH.setAttribute("opacity", (1 - g / 0.13).toFixed(3));
    } else smearH.setAttribute("opacity", 0);
    // 접촉 링 (작게 — 번쩍임 아님): 임팩트 뒤 0.18초 게임 시각
    if (g >= 0 && g < 0.18) { const u = g / 0.18; ringH.setAttribute("cx", S0_TEE[0]); ringH.setAttribute("cy", S0_TEE[1]); ringH.setAttribute("r", fx2(5.5 + 14 * u)); ringH.setAttribute("opacity", (0.7 * (1 - u)).toFixed(3)); }
    else ringH.setAttribute("opacity", 0);
    // 공 + 궤적
    let bx, by, dia = 11;
    if (g < 0) { bx = S0_TEE[0]; by = S0_TEE[1]; trailH.setAttribute("points", ""); }
    else {
      const u = flightU(g), n = Math.max(1, Math.round(u * 400));
      [bx, by] = pathAt(u);
      trailH.setAttribute("points", PATH.slice(0, n + 1).map((p) => fx2(p[0]) + "," + fx2(p[1])).join(" ") + ` ${fx2(bx)},${fx2(by)}`);
      trailH.setAttribute("opacity", (1 - smooth(seg(f, 135, 160))).toFixed(3));
      dia = lerp(11, SM.period.d, smooth(u));
      if (f > HT.land) { const hop = seg(f, HT.land, HT.land + 9); by -= Math.sin(Math.PI * hop) * SM.period.d * 0.5; }
    }
    px(ballH, bx - dia / 2, by - dia / 2, dia, dia);
    // 헤드라인: 윗줄은 빠르게, 큰 문장은 박마다 한 단어 (타건 = 16분음 타이핑)
    const kN = Math.floor(clamp((f - HT.kick[0]) / (HT.kick[1] - HT.kick[0])) * SM.kchars.length + (f >= HT.kick[1] ? 0.5 : 0));
    kickEl.textContent = SM.kchars.slice(0, kN).join("");
    const words0 = TX.sent[0].split(" "), all = [...TX.sent[0].split(" ").map((w, i) => [0, w, i]), ...TX.sent[1].split(" ").map((w, i) => [1, w, i])];
    // 단어 등장 프레임 (3박): 줄마다 누적 문자 수
    const wordAt = HT.words; let n0 = 0, n1 = 0;
    const line0 = [...TX.sent[0]], line1 = [...TX.sent[1]];
    const w0s = TX.sent[0].split(" "), w1s = TX.sent[1].split(" ");
    const seq = [];
    let acc = 0; for (let i = 0; i < w0s.length; i++) { acc += [...w0s[i]].length + (i < w0s.length - 1 ? 1 : 0); seq.push([0, acc]); }
    acc = 0; for (let i = 0; i < w1s.length; i++) { acc += [...w1s[i]].length + (i < w1s.length - 1 ? 1 : 0); seq.push([1, acc]); }
    // 단어 k를 HT.words[j]에 친다: 단어 수에 맞춰 3박에 분배 (KO 3단어·EN 4단어)
    const wf = seq.map((_, i) => Math.round(lerp(wordAt[0], wordAt[wordAt.length - 1], seq.length > 1 ? i / (seq.length - 1) : 0)));
    const TYPE_F = 4; // 한 단어를 4프레임에 걸쳐 친다
    let lastKey = -99;
    seq.forEach(([ln, cum], i) => {
      const prevCum = i > 0 && seq[i - 1][0] === ln ? seq[i - 1][1] : 0;
      const u = clamp((f - wf[i]) / TYPE_F); const c = Math.round(lerp(prevCum, cum, u));
      if (f >= wf[i]) { if (ln === 0) n0 = Math.max(n0, c); else n1 = Math.max(n1, c); lastKey = Math.max(lastKey, Math.min(f, wf[i] + TYPE_F)); }
    });
    document.getElementById("s0").textContent = line0.slice(0, n0).join("");
    document.getElementById("s1").textContent = line1.slice(0, n1).join("");
    // 캐럿
    let cx, cy, ch;
    if (n0 === 0) { cx = NX + S1L.pad[0] + SM.kW[Math.min(kN, SM.kW.length - 1)]; cy = NY + 34 + S1L.pad[1] + S1L.kick * 0.1; ch = S1L.kick * 1.15; }
    else if (n1 === 0) { cx = NX + S1L.pad[0] + SM.w0[n0]; cy = SM.s0top + SM.lineH * 0.14; ch = SM.lineH * 0.78; }
    else { cx = NX + S1L.pad[0] + SM.w1[n1] + (f >= HT.land ? SM.period.d + S1L.sent * 0.1 : 0); cy = SM.s1top + SM.lineH * 0.14; ch = SM.lineH * 0.78; }
    const typingNow = f - lastKey < 6 || (f >= HT.kick[0] && f <= HT.kick[1] + 3);
    const carOn = f >= HT.kick[0] - 2 && (typingNow || Math.floor((f - Math.max(lastKey, HT.kick[1])) / 15) % 2 === 1);
    px(caretH, cx + 3, cy, null, ch); caretH.style.opacity = carOn ? 1 : 0;
    // 텔레메트리: f38부터 박마다 한 줄, 숫자는 12프레임 스프링 카운터 → f104부터 8프레임 페이드
    const tOn = f >= 44 && f < 74;
    tele.style.opacity = tOn ? (1 - smooth(seg(f, 66, 74))).toFixed(3) : 0;
    if (tOn) {
      const base = O === "h" ? [120, 330] : [96, 330], fs = O === "h" ? 34 : 38;
      teleRows.forEach((e, i) => {
        const f0 = [44, 50, 56][i], u = Sk((f - f0) / FPS, "settle");
        e.style.fontSize = fs + "px"; px(e, base[0], base[1] + i * fs * 1.55); e.style.opacity = f >= f0 ? Math.min(1, (f - f0) / 3).toFixed(3) : 0;
        e.style.transform = `translateY(${fx2((1 - u) * 10)}px)`;
        const tgt = parseFloat(TX.tele[i][1].replace(/,/g, "")), dec = TX.tele[i][1].includes(".") ? 1 : 0;
        const cnt = clamp((f - f0) / 9); const v = tgt * (1 - Math.pow(1 - cnt, 3));
        e.querySelector(".v").textContent = dec ? v.toFixed(1) : Math.round(v).toLocaleString("en-US");
      });
    }
  }

  /* ════════════════ 몽타주 데스크탑들 ════════════════ */
  const docHTML = (KO ? `<h1>3분기 보고서</h1><div class="meta">초안 · 편집 중 · 방금 저장됨</div><h2>1. 요약</h2><p>3분기 신규 가입은 전 분기 대비 18% 늘었고, 유지율은 두 달 연속 개선됐다. 온보딩 단계를 네 개에서 두 개로 줄인 효과가 가장 컸다.</p><h2>2. 지표</h2><p>주간 활성 사용자, 결제 전환, 이탈 사유를 순서대로 정리한다. 이탈 사유 1위는 여전히 '설정이 번거롭다'이다.</p><span class="ph" style="width:92%"></span><span class="ph" style="width:78%"></span><span class="ph" style="width:85%"></span><h2>3. 다음 분기</h2><p>알림 설정 간소화와 팀 초대 흐름 개선을 우선한다.</p><span class="ph" style="width:88%"></span><span class="ph" style="width:64%"></span>`
    : `<h1>Q3 report</h1><div class="meta">Draft · editing · saved just now</div><h2>1. Summary</h2><p>New sign-ups grew 18% over last quarter and retention improved for the second month in a row. Cutting onboarding from four steps to two had the biggest effect.</p><h2>2. Metrics</h2><p>Weekly actives, paid conversion and churn reasons, in that order. The top churn reason is still "setup takes too long".</p><span class="ph" style="width:92%"></span><span class="ph" style="width:78%"></span><span class="ph" style="width:85%"></span><h2>3. Next quarter</h2><p>Simplify notification settings and fix the team-invite flow first.</p><span class="ph" style="width:88%"></span><span class="ph" style="width:64%"></span>`);
  const chatHTML = (msgs, input) => `<div class="chat"><div class="side">${(KO ? ["제품팀", "디자인", "배포 알림", "랜덤", "민지"] : ["product", "design", "deploys", "random", "Minji"]).map((s, i) => `<div class="${i === 0 ? "on" : ""}"><b></b>${s}</div>`).join("")}</div><div class="main"><div class="msgs">${msgs}</div><div class="input"><span class="tx">${input}</span><span class="send">${KO ? "보내기" : "Send"}</span></div></div></div>`;
  const M_CHAT = KO ? `<div class="who">민지 · 오후 2:41</div><div class="m">배포는 4시로 미룰게요. QA가 한 건 더 남았어요.</div><div class="who">나</div><div class="m me">좋아요. 그동안 문서 정리할게요.</div><div class="who">서준 · 오후 2:55</div><div class="m">회의록 올렸습니다. 3번 항목만 확인 부탁드려요.</div>`
    : `<div class="who">Minji · 2:41 PM</div><div class="m">Pushing the deploy to 4. QA has one more item.</div><div class="who">Me</div><div class="m me">Sounds good. I'll tidy the docs meanwhile.</div><div class="who">Jun · 2:55 PM</div><div class="m">Notes are up. Can you check item 3?</div>`;
  const webHTML = `<div class="browser"><div class="tabs"><div class="tab on">${KO ? "온보딩 가이드" : "Onboarding guide"}</div><div class="tab">${KO ? "디자인 시스템" : "Design system"}</div><div class="tab">${KO ? "릴리스 노트" : "Release notes"}</div></div><div class="url"><div>docs.internal.example/onboarding</div></div><div class="page"><h1>${KO ? "첫 주에 할 일" : "Your first week"}</h1><p>${KO ? "계정 연결, 저장소 권한, 로컬 빌드까지 — 첫날 오전이면 끝납니다. 막히면 #도움 채널에 물어보세요." : "Accounts, repo access and a local build — done by lunch on day one. Stuck? Ask in #help."}</p><div class="cards">${(KO ? ["계정 연결", "저장소 권한", "로컬 빌드"] : ["Accounts", "Repo access", "Local build"]).map((s, i) => `<div class="card"><i></i><b>${i + 1}. ${s}</b>${KO ? "약 10분" : "about 10 min"}</div>`).join("")}</div></div></div>`;
  const sheetHTML = (() => { let s = `<div class="sheet"><div class="row h"><div></div>${"ABCDEFGHIJKLMN".split("").map((c) => `<div>${c}</div>`).join("")}</div>`;
    for (let r = 1; r <= 32; r++) { s += `<div class="row"><div>${r}</div>`; for (let c = 0; c < 14; c++) { const v = ((r * 7919 + c * 104729) % 9973) * (c % 3 === 0 ? 13 : 7); s += `<div>${c === 0 ? (KO ? ["인건비", "서버", "광고", "도구", "교육", "출장"][r % 6] : ["Payroll", "Servers", "Ads", "Tools", "Training", "Travel"][r % 6]) : v.toLocaleString("en-US")}</div>`; } s += `</div>`; }
    return s + `</div>`; })();
  const calHTML = (() => { const days = KO ? ["월 28", "화 29", "수 30", "목 1", "금 2"] : ["Mon 28", "Tue 29", "Wed 30", "Thu 1", "Fri 2"];
    let s = `<div class="cal"><div class="head">${days.map((d) => `<div>${d}</div>`).join("")}</div><div class="grid">`;
    for (let hr = 9; hr <= 18; hr++) s += `<div class="hr" style="top:${(hr - 9) * 88}px">${KO ? (hr < 12 ? "오전 " + hr : "오후 " + (hr === 12 ? 12 : hr - 12)) : (hr < 12 ? hr + " AM" : (hr === 12 ? 12 : hr - 12) + " PM")}</div>`;
    const ev = KO ? [[0, 10, 1, "주간 계획"], [1, 13, 1.5, "디자인 리뷰"], [2, 11, 1, "1:1"], [2, 15, 1, "제품 회의", true], [3, 10, 2, "워크숍"], [4, 14, 1, "회고"]]
      : [[0, 10, 1, "Weekly plan"], [1, 13, 1.5, "Design review"], [2, 11, 1, "1:1"], [2, 15, 1, "Product sync", true], [3, 10, 2, "Workshop"], [4, 14, 1, "Retro"]];
    for (const [d, hr, len, name, now] of ev) s += `<div class="ev${now ? " now" : ""}" style="left:calc(70px + ${d} * (100% - 70px) / 5 + 6px);width:calc((100% - 70px) / 5 - 12px);top:${(hr - 9) * 88 + 4}px;height:${len * 88 - 8}px">${name}<br><span style="opacity:.6">${KO ? (hr < 12 ? "오전 " : "오후 ") + (hr > 12 ? hr - 12 : hr) + ":00" : (hr > 12 ? hr - 12 : hr) + ":00"}</span></div>`;
    s += `<div class="nowline" style="left:calc(70px + 2 * (100% - 70px) / 5);width:calc((100% - 70px) / 5);top:${6 * 88}px"></div>`;
    return s + `</div></div>`; })();

  function montageDesk(kind, clock) {
    const d = makeDesk({ clock });
    // 창 자리: 각 샷의 카메라 뷰 안에 그 앱을 알아볼 부분(제목 막대·탭·열 머리·채팅 입력창)이 들어오게 놓는다
    const R = (O === "h" ? { doc: [300, 520, 1500, 560], chat: [260, 110, 1400, 970], web: [120, 784, 1620, 296], sheet: [150, 660, 1600, 420], cal: [200, 70, 1520, 1010] }
      : { doc: [240, 500, 900, 580], chat: [260, 110, 1400, 970], web: [200, 776, 1300, 304], sheet: [300, 610, 1100, 470], cal: [120, 70, 1560, 1010] })[kind];   // 세로 web: 2단계 QA — 펀치인 컷(×3.3)에서 탭 줄이 자막 밑에 30프레임 깔려 창을 86pt 내렸다
    const title = { doc: TX.doc, chat: TX.chat, web: TX.web, sheet: TX.sheetT, cal: TX.calT }[kind];
    const body = win(d, R, title);
    if (kind === "web") body.classList.add("webwin");
    body.innerHTML = { doc: `<div class="doc" style="padding-top:${O === "h" ? 210 : 150}px">${docHTML}</div>`, chat: chatHTML(M_CHAT, KO ? "회의록 확인했어요 — 3번은 오늘 안에" : "Checked the notes — item 3 by today"), web: webHTML, sheet: sheetHTML, cal: calHTML }[kind];
    const dim = h("div", "dim"); dim.style.opacity = kind === "sheet" ? (O === "v" ? 0.74 : 0.62) : kind === "chat" ? 0.5 : kind === "cal" ? 0.34 : 0.48; d.appendChild(dim); d._dim = dim;
    return d;
  }
  const SH = Object.fromEntries(TL.shots.map((s) => [s.id, s]));
  const dM1 = montageDesk("doc", TX.clock), cM1 = makeClip("terraces", dM1);
  const dM2 = montageDesk("chat", TX.clock), cM2 = makeClip("geese", dM2);
  const dM3 = montageDesk("web", TX.clock), cM3 = makeClip("dog", dM3);
  const dM4 = montageDesk("sheet", TX.clock);
  const svgM4 = mk("svg", { class: "fx", width: 1920, height: 1080 }); dM4.appendChild(svgM4);
  const groundM4 = mk("path", { fill: "none", stroke: "rgba(210,210,206,.85)", "stroke-width": 1.6, "stroke-linecap": "round" }); svgM4.appendChild(groundM4);
  const manM4 = makeMan(svgM4);
  const dM5 = montageDesk("cal", TX.clock), cM5a = makeClip("cuckoo", dM5), cM5b = makeClip("holeout", dM5);

  // 몽타주 카메라 (가로/세로): [f, s, cx, cy] 키 — 같은 프레임 두 키 = 컷(펀치인·펀치아웃 컷, 이 판에서 허용). 키 사이는 CSS ease
  const MC = O === "h" ? {
    m2: [[240, 2.45, 780, 858], [269, 2.45, 780, 858], [270, 3.7, 728, 930], [299, 3.7, 728, 930], [300, 2.15, 690, 800], [329, 2.15, 690, 800]],
    m3: [[330, 2.5, 760, 925], [359, 2.5, 760, 925], [360, 3.1, 610, 938], [389, 3.1, 610, 938]],
    m4: [[390, 3.3, 690, 850], [449, 3.3, 690, 850]],
    m5a: [[450, 4.5, 1790, 40], [469, 4.5, 1790, 40], [470, 2.35, 300, 240], [489, 2.35, 300, 240], [490, 4.4, 282, 112], [509, 4.4, 282, 112]],   // ECU 왼쪽 끝을 메뉴 사이 틈(x 64)에 — "편집기"/"Editor"가 반쯤 잘리지 않게
    m5b: [[510, 3.3, 1665, 668], [539, 3.3, 1665, 668], [540, 3.3, 1655, 668], [599, 3.3, 1655, 668]],
  } : {
    m2: [[240, 2.7, 800, 800], [269, 2.7, 800, 800], [270, 4.0, 728, 860], [299, 4.0, 728, 860], [300, 2.5, 640, 700], [329, 2.5, 640, 700]],
    m3: [[330, 2.3, 784, 860], [359, 2.3, 784, 860], [360, 3.3, 610, 880], [389, 3.3, 610, 880]],   // 2단계 QA: ×2.8에선 공(왼쪽 x≈65)·스틱맨 클럽(오른쪽 x≈1060)이 안전 영역 밖 → ×2.3으로 둘 다 안에
    m4: [[390, 4.2, 660, 790], [449, 4.2, 660, 790]],
    m5a: [[450, 5.0, 1812, 40], [469, 5.0, 1812, 40], [470, 3.0, 288, 218], [489, 3.0, 288, 218], [490, 5.2, 268, 140], [509, 5.2, 268, 140]],   // 2단계 QA: 470–489 시계가 안전 영역 위(y<300)에 있었다 → ×3.0, 가두지 않고 시계를 y≈560에 · 왼쪽 끝을 메뉴 사이 틈(x 108)에 둬 잘린 글자 없음
    m5b: [[510, 3.4, 1662, 640], [539, 3.4, 1662, 640], [540, 3.4, 1655, 640], [599, 3.4, 1655, 640]],
  };
  const camKeys = (keys, f) => {
    let i = 0; while (i < keys.length - 1 && keys[i + 1][0] <= f) i++;
    const a = keys[i], b = keys[Math.min(keys.length - 1, i + 1)];
    if (b[0] === a[0] || f <= a[0]) return a.slice(1);
    const u = camEase(seg(f, a[0], b[0]));
    return [lerp(a[1], b[1], u), lerp(a[2], b[2], u), lerp(a[3], b[3], u)];
  };
  const VY = O === "h" ? RH / 2 : 900; // 세로는 안전 영역 중심(y 900)에 맞춘다

  // M1: 티의 공 ECU(매치컷) → 임팩트 → 공을 따라가는 팬 → 착지 (실캡처 공 경로: prep-clips.py가 프레임마다 잰 129점)
  const M1BALL = [153.4, 835.7];
  const M1P = window.PATHS.terraces, M1_IMP = SH.m1.impactSrc;
  const M1_FLY = M1P.find((p) => p[0] > M1_IMP && Math.hypot(p[1] - 153.4, p[2] - 835.7) > 20)[0];   // 임팩트 직후 공이 클럽 헤드와 겹쳐 안 잡히는 프레임은 건너뛰고 첫 비행 표본부터
  const ballM1 = (t) => { const P = M1P; if (t <= P[0][0]) return [P[0][1], P[0][2]];
    for (let i = 1; i < P.length; i++) if (P[i][0] >= t) { const a = P[i - 1], b = P[i], u = (t - a[0]) / (b[0] - a[0]); return [lerp(a[1], b[1], u), lerp(a[2], b[2], u)]; }
    const L = P[P.length - 1]; return [L[1], L[2]]; };
  const M1S = O === "h" ? [3.2, 2.0] : [3.0, 2.5];   // 매치컷 배율(낮을수록 헤드라인 푸시인이 약하다) → 추적 배율
  function M1CAM(f) {
    const S = SH.m1;
    if (f < 196) return camView(M1S[0], M1BALL[0], M1BALL[1], RW / 2, VY);
    const u = camEase(seg(f, 196, 210)), s = lerp(M1S[0], M1S[1], u);
    const b = ballM1(pw(S.map, f - 3));                            // 3프레임 늦게 따라간다 — 공이 화면 앞쪽을 끌고 간다
    const lead = O === "h" ? [140, 10] : [40, 60];
    const cx = lerp(M1BALL[0], b[0] + lead[0], u), cy = lerp(M1BALL[1], Math.min(b[1], 880) + lead[1], u);
    return camView(s, cx, cy, RW / 2, VY);
  }
  // M1 궤적 보강(광고 강조): 실캡처의 가는 궤적(흰 28%·1pt) 위에 같은 경로를 1.7pt·50%로 한 번 더, 공은 벡터 원으로 또렷하게, 착지엔 먼지 점
  const svgM1 = mk("svg", { class: "fx", width: 1920, height: 1080 }); dM1.appendChild(svgM1);
  const trailM1 = mk("polyline", { fill: "none", stroke: "rgba(255,255,255,.5)", "stroke-width": 1.7, "stroke-linecap": "round", "stroke-linejoin": "round" }); svgM1.appendChild(trailM1);
  const ballM1El = mk("circle", { r: 5.5, fill: "#FAFAF8" }); svgM1.appendChild(ballM1El);
  const DUST = (() => { let sd = 0x5eed; const r = () => { sd = (sd * 1664525 + 1013904223) >>> 0; return sd / 4294967296; };
    return Array.from({ length: 7 }, () => ({ dx: (r() * 2 - 1) * 16, dy: (12 + r() * 22) * 1.1, rad: 1.4 + r() * 0.9 })); })();
  const dustM1 = DUST.map(() => { const c = mk("circle", { r: 1.5, fill: "rgba(236,236,232,.8)" }); svgM1.appendChild(c); return c; });
  function drawM1Overlay(t) {
    if (t < M1_FLY) { trailM1.setAttribute("points", ""); ballM1El.setAttribute("opacity", 0); dustM1.forEach((c) => c.setAttribute("opacity", 0)); return; }
    const pts = [[153.4, 830]].concat(M1P.filter((p) => p[0] >= M1_FLY && p[0] <= t).map((p) => [p[1], p[2]])); const b = ballM1(t); pts.push(b);
    trailM1.setAttribute("points", pts.map((p) => fx2(p[0]) + "," + fx2(p[1])).join(" "));
    trailM1.setAttribute("opacity", (1 - smooth(clamp((t - SH.m1.landSrc - 0.1) / 0.5))).toFixed(3));
    ballM1El.setAttribute("cx", fx2(b[0])); ballM1El.setAttribute("cy", fx2(b[1] - 0.5)); ballM1El.setAttribute("opacity", 1);
    const dt = t - SH.m1.landSrc, L = SH.m1.landAt;                  // 게임 FX.dust 문법: 0.16초 솟고 0.26초 가라앉으며 0.42초에 사라진다
    dustM1.forEach((c, i) => { const D = DUST[i]; if (dt < 0 || dt > 0.42) { c.setAttribute("opacity", 0); return; }
      const up = Math.min(1, dt / 0.16), dn = Math.max(0, (dt - 0.16) / 0.26);
      const x = L[0] + D.dx * (0.6 * (1 - (1 - up) ** 2) + 0.4 * dn * dn), y = L[1] - D.dy * (1 - (1 - up) ** 2) + D.dy * 0.6 * dn * dn;
      c.setAttribute("cx", fx2(x)); c.setAttribute("cy", fx2(y)); c.setAttribute("r", fx2(D.rad)); c.setAttribute("opacity", (0.8 * (1 - dt / 0.42)).toFixed(3)); });
  }

  // M4 지면선: 쇼피스 자리(x=646) 주변은 평지 — 캡처에서 확인. 선 하나만 긋는다
  const W_SHOW = RIGS.whiff.showpiece, W_GY = 1080 - W_SHOW.groundFromBottom;
  groundM4.setAttribute("d", `M ${W_SHOW.x - 520} ${W_GY + 1} L ${W_SHOW.x + 520} ${W_GY + 1}`);
  const M4MAP = [[390, 2.40], [449, 4.76]];

  function renderMontage(f) {
    for (const [id, d] of [["m1", dM1], ["m2", dM2], ["m3", dM3], ["m4", dM4], ["m5a", dM5], ["m5b", dM5]]) {
      const S = SH[id]; if (f < S.f0 || f > S.f1) continue;
      if (id === "m1") { const c = M1CAM(f); d.style.transform = `translate(${(-c[0] * c[1]).toFixed(3)}px,${(-c[0] * c[2]).toFixed(3)}px) scale(${c[0].toFixed(5)})`; d._cam = c; }
      else if (id === "m5a" && (f < 470 || (O === "v" && f < 490))) { // 메뉴바 ECU(+세로 시계 하강 샷): 가두지 않는다 — 위쪽 검정 = 모니터 윗변
        const [s, cx, cy] = camKeys(MC[id], f), L = cx - (RW / 2) / s, T = cy - VY / s;
        d.style.transform = `translate(${(-s * L).toFixed(3)}px,${(-s * T).toFixed(3)}px) scale(${s.toFixed(5)})`; d._cam = [s, L, T]; }
      else { const [s, cx, cy] = camKeys(MC[id], f); setCam(d, s, cx, cy, RW / 2, VY); }
      if (id === "m1") { cM1.draw(pw(S.map, f)); drawM1Overlay(pw(S.map, f)); }
      if (id === "m2") cM2.draw(pw(S.map, f));
      if (id === "m3") cM3.draw(pw(S.map, f));
      if (id === "m4") { const r = rigAt(RIGS.whiff, pw(M4MAP, f)); drawMan(manM4, r, W_SHOW.x, W_GY, "crown"); }
      if (id === "m5a") { const ecu = f >= 490; cM5a.el.style.visibility = ecu ? "hidden" : "visible"; cM5b.el.style.visibility = "hidden"; cM5a.draw(pw(S.map, f)); rollClock(f);
        drawClock(ecu ? pw(S.map, f) : null); }
      if (id === "m5b") { cM5a.el.style.visibility = "hidden"; cM5b.el.style.visibility = "visible"; cM5b.draw(pw(S.map, f)); rollClock(f); drawClock(null); }
    }
  }
  const svgClock = mk("svg", { class: "fx", width: 1920, height: 1080 }); dM5.appendChild(svgClock);
  const CK = {}, gray = (w, a) => `rgba(${Math.round(w * 255)},${Math.round(w * 255)},${Math.round(w * 255)},${a})`;
  for (const [k, tag, at] of [["string", "path", { fill: "none", stroke: gray(0.8, 0.7), "stroke-width": 1 }], ["weights", "path", { fill: "none", stroke: gray(0.6, 0.8), "stroke-width": 1 }],
    ["pend", "path", { fill: "none", stroke: gray(0.7, 0.9), "stroke-width": 1.2 }], ["bob", "circle", { r: 3, fill: gray(0.72, 0.95) }],
    ["house", "path", { fill: gray(0.72, 0.95), stroke: gray(0.5, 0.9), "stroke-width": 1.2, "stroke-linejoin": "round" }], ["face", "circle", { r: 8, fill: gray(0.95, 0.95), stroke: gray(0.5, 0.9), "stroke-width": 1 }],
    ["hands", "path", { fill: "none", stroke: gray(0.25, 0.95), "stroke-width": 1.2 }], ["bird", "ellipse", { rx: 5, ry: 3, fill: gray(0.92, 0.95) }],
    ["beak", "path", { fill: "none", stroke: gray(0.55, 0.95), "stroke-width": 1.6 }], ["door", "rect", { y: 0, height: 9, fill: gray(0.45, 0.95) }]]) { CK[k] = mk(tag, at); }
  const ckG = mk("g", {}); svgClock.appendChild(ckG); for (const k of ["string", "weights", "pend", "bob", "house", "face", "hands", "bird", "beak", "door"]) ckG.appendChild(CK[k]);
  function drawClock(t) {   // t = 원본 초 (null = 숨김). 게임 액션: 0.7초 하강(easeOut) → 0.5초 → 울음 i마다 문 0.08초 열림·새 0.1초 나옴 0.32초 머묾 0.12초 들어감·0.55초 뒤 문 닫힘, 0.8초 간격
    if (t == null) { ckG.setAttribute("opacity", 0); return; }
    ckG.setAttribute("opacity", 1);
    const t0 = SH.m5a.clockT0, [cx, restY] = SH.m5a.clockAt, S = 1.6;
    const du = clamp((t - t0) / 0.7), y0 = lerp(-90, restY, 1 - (1 - du) * (1 - du));
    ckG.setAttribute("transform", `translate(${cx} ${fx2(y0)}) scale(${S} ${-S})`);   // 게임 좌표(y 위쪽)를 그대로 쓴다
    let doorSx = 1, birdX = 0;
    for (let i = 0; i < 3; i++) { const c = t0 + 1.2 + 0.8 * i, d = t - c;
      if (d >= 0 && d < 0.8) { doorSx = d < 0.55 ? lerp(1, 0.15, clamp(d / 0.08)) : lerp(0.15, 1, clamp((d - 0.55) / 0.08));
        birdX = d < 0.1 ? 14 * d / 0.1 : d < 0.42 ? 14 : d < 0.54 ? 14 * (1 - (d - 0.42) / 0.12) : 0; } }
    CK.string.setAttribute("d", "M0 30 L0 200");
    CK.weights.setAttribute("d", "M-6 -22 L-6 -46 M6 -22 L6 -38");
    const ph = ((t - t0) % 1 + 1) % 1, ang = ph < 0.5 ? lerp(-0.3, 0.3, ph / 0.5) : lerp(0.3, -0.3, (ph - 0.5) / 0.5);
    // 진자: (0,-22)에서 길이 18, ±0.3rad 삼각파(1초 주기, 게임 repeatForever rotate)
    CK.pend.setAttribute("d", `M0 -22 L${fx2(Math.sin(ang) * 18)} ${fx2(-22 - Math.cos(ang) * 18)}`);
    CK.bob.setAttribute("cx", fx2(Math.sin(ang) * 18)); CK.bob.setAttribute("cy", fx2(-22 - Math.cos(ang) * 18));
    CK.house.setAttribute("d", "M-18 -22 L18 -22 L18 10 L0 28 L-18 10 Z");
    CK.face.setAttribute("cx", 0); CK.face.setAttribute("cy", -9);
    CK.hands.setAttribute("d", "M0 -9 L0 -3 M0 -9 L0 -5");
    CK.bird.setAttribute("cx", fx2(birdX)); CK.bird.setAttribute("cy", 12);
    CK.beak.setAttribute("d", `M${fx2(3 + birdX)} 12.5 L${fx2(5 + birdX)} 12`);
    CK.door.setAttribute("x", -5); CK.door.setAttribute("y", 8); CK.door.setAttribute("width", fx2(10 * doorSx));
  }
  // M5 메뉴바 시계: 2:59 → 3:00 자릿수 롤(마스크 안 밀어 올리기 6f, f457)
  const clk5 = dM5._menubar.querySelector(".clk");
  clk5.innerHTML = `${KO ? "수 9월 30일 오후 " : "Wed Sep 30 "}<span style="display:inline-block;position:relative;overflow:hidden;height:17px;vertical-align:-3px;width:28px"><span class="r0" style="position:absolute;left:0;top:0">2:59</span><span class="r1" style="position:absolute;left:0;top:0">3:00</span></span>${KO ? "" : " PM"}`;
  function rollClock(f) {
    const u = smooth(seg(f, SH.m5a.roll, SH.m5a.roll + 6));
    clk5.querySelector(".r0").style.transform = `translateY(${fx2(-17 * u)}px)`; clk5.querySelector(".r1").style.transform = `translateY(${fx2(17 * (1 - u))}px)`;
  }

  /* ════════════════ H: 정직 비트 ════════════════ */
  const HO = TL.honest;
  const dHo = makeDesk({ clock: TX.clock3 });
  const hoBody = win(dHo, O === "h" ? [300, 90, 1320, 990] : [760, 200, 1100, 880], TX.chat);
  hoBody.innerHTML = chatHTML(M_CHAT + `<div class="m me" id="sentmsg" style="display:none">${KO ? "3번 항목 확인했어요!" : "Item 3 looks good!"}</div>`, `<span id="hotx">${KO ? "3번 항목 확인했어요!" : "Item 3 looks good!"}</span>`);
  const svgHo = mk("svg", { class: "fx", width: 1920, height: 1080 }); dHo.appendChild(svgHo);
  const groundHo = mk("path", { fill: "none", stroke: "rgba(210,210,206,.8)", "stroke-width": 1.6 }); svgHo.appendChild(groundHo);
  const manHo = makeMan(svgHo);
  const curHo = h("div", null, CURSOR); curHo.style.cssText = "position:absolute;left:0;top:0;width:22px;height:32px;transform-origin:2px 2px"; dHo.appendChild(curHo);
  const GY_HO = 1060;   // 띠의 지면 = 화면 맨 아래 (스틱맨이 메신저 입력창·보내기 버튼 위를 지난다)
  groundHo.setAttribute("d", `M 0 ${GY_HO} L 1920 ${GY_HO}`);
  // 영웅 리그의 걷기 구간(실제 걸음): 걷기 시작 이후 리그 시각
  const WALK_T0 = (() => { const S = HERO.samples; for (const s of S) if (s[1] === "walking") return s[0] + 1.2; return 8; })();
  const HO_CAM = O === "h" ? [2.8, -40, -70] : [2.9, -120, -80];   // 2단계: ×2.8로 낮춰 빈 채팅 영역을 줄인다   // 보내기 버튼 기준 오프셋 (init에서 잰 SEND)
  let SEND = null;
  function renderHonest(f) {
    // 3샷: H1 보내기 버튼 ECU(클릭이 스틱맨을 지나 아래 앱으로) → H2 메뉴바 ⛳ ECU(우클릭 → 종료) → H3 같은 ECU로 돌아와 스틱맨이 사라진 빈자리
    const flagShot = f >= HO.flagCut && f < HO.backCut;
    // 세로: 2단계 QA — ×5.2에선 영어 시계 "PM"이 화면 오른쪽 끝에서 잘렸다 → ×4.85, 깃발~시계 끝이 안전 영역(x 70–1010) 안에
    if (flagShot) { const s = O === "h" ? 5.0 : 4.85, cx = dHo._flagPos[0] + (O === "h" ? 70 : 74), cy = 14, L = cx - (RW / 2) / s, T = cy - VY / s;
      dHo.style.transform = `translate(${(-s * L).toFixed(3)}px,${(-s * T).toFixed(3)}px) scale(${s})`; dHo._cam = [s, L, T]; }
    else setCam(dHo, HO_CAM[0], SEND[0] + HO_CAM[1], SEND[1] + HO_CAM[2], RW / 2, VY);
    // 스틱맨: 입력창 위를 걷는다 — 걷기 x는 리그 STICK을 옮겨 쓴다 (보내기 버튼 위를 f_press에 지나도록)
    const rt = WALK_T0 + (f - HO.f0) / FPS;
    const r = rigAt(HERO, rt), st = stickAt(HERO, rt);
    const st0 = stickAt(HERO, WALK_T0 + (HO.press - HO.f0) / FPS);
    const x = SEND[0] - 4 + (st[1] - st0[1]);
    drawMan(manHo, r, x, GY_HO, "crown");
    const gone = f >= HO.quit;   // 게임 창이 닫히는 순간 — H3에서는 이미 없다(빈자리)
    manHo.g.setAttribute("opacity", gone ? 0 : 1); groundHo.setAttribute("opacity", gone ? 0 : 0.9);
    const fb = dHo._menubar.querySelector(".flagbox");
    fb.style.opacity = (1 - smooth(seg(f, HO.quit, HO.quit + 4))).toFixed(3);
    fb.style.background = f >= HO.flagClick - 2 && f < HO.quit ? "rgba(255,255,255,.16)" : "transparent";
    // 커서
    const A = [SEND[0] - 260, SEND[1] - 190], B = [SEND[0] + 8, SEND[1] + 4], C = [dHo._flagPos[0] + 3, dHo._flagPos[1] + 4];
    let p, sc = 1;
    if (f < HO.flagCut) {
      if (f < HO.press + 6) { const u = Sk((f - (HO.f0 + 8)) / FPS, "calm"); p = [lerp(A[0], B[0], u), lerp(A[1], B[1], u) + Math.sin(Math.PI * u) * 30]; }
      else { const u = smooth(seg(f, HO.press + 6, HO.flagCut)); p = [lerp(B[0], B[0] + 120, u), lerp(B[1], B[1] - 260, u)]; }   // 위로 빠져나간다 (메뉴바 쪽)
      if (f >= HO.press - 2 && f < HO.press + 3) sc = 0.84;
    } else if (flagShot) {
      const u = Sk((f - HO.flagCut) / FPS, "calm"); p = [lerp(C[0] - 30, C[0], u), lerp(C[1] + 70, C[1], u)];
      if (f >= HO.flagClick - 2 && f < HO.flagClick + 3) sc = 0.84;
    } else p = [-200, -200];
    curHo.style.transform = `translate(${fx2(p[0])}px,${fx2(p[1])}px) scale(${sc})`;
    curHo.style.visibility = f >= HO.backCut ? "hidden" : "visible";
    document.getElementById("sentmsg").style.display = f >= HO.press + 2 ? "" : "none";
    document.getElementById("hotx").style.opacity = f >= HO.press + 2 ? 0 : 1;
  }

  /* ════════════════ E: 엔드 ════════════════ */
  const EN = TL.end;
  const dE = makeDesk({ clock: TX.clock3, app: KO ? "터미널" : "Terminal" });
  const termBody = win(dE, O === "h" ? [60, 440, 690, 230] : [24, 250, 560, 250], TX.termT);   // 2단계: 가로도 티 위쪽 가까이 — 마지막 구도에서 스틱맨을 키운다
  const term = h("div", "term"); termBody.appendChild(term);
  if (O === "v") { term.style.fontSize = "24px"; term.style.lineHeight = "38px"; }
  const plateE = px(h("img", "plate"), 0, 0); plateE.src = "assets/gen/plate-skytee.png"; dE.appendChild(plateE);
  const svgE = mk("svg", { class: "fx", width: 1920, height: 1080 }); dE.appendChild(svgE);
  const manE = makeMan(svgE);
  const ballE = h("div", "ball"); dE.appendChild(ballE);
  const endBlock = h("div"); endBlock.id = "end"; screenLayer.appendChild(endBlock);
  const EB = O === "h" ? { x: 1170, y: 250, wm: 116, dash: [76, 7], l2: 30, url: 27 } : { x: 90, y: 700, wm: 120, dash: [80, 8], l2: 34, url: 30 };
  endBlock.innerHTML = `<div class="dash" style="width:${EB.dash[0]}px;height:${EB.dash[1]}px;margin:0 0 ${EB.wm * 0.34}px 3px"></div>
    <div class="wm" style="font-size:${EB.wm}px;letter-spacing:${-0.035 * EB.wm}px;margin-bottom:${EB.wm * 0.3}px">mini-golf</div>
    <div class="l2" style="font-size:${EB.l2}px">${TX.end2}</div>
    <div class="url" style="font-size:${EB.url}px;margin-top:${EB.url * 1.0}px">${URL_TEXT}</div>`;
  px(endBlock, EB.x, EB.y);
  function renderEnd(f) {
    // 터미널 ECU(타이핑이 읽히게) → 엔터 → 한 번의 풀백(24f, CSS ease)으로 데스크탑 전체: 띠가 살아나고 메뉴바에 ⛳
    const EA = O === "h" ? [2.3, 400, 560] : [1.8, 300, 620], EB2 = O === "h" ? [1.5, 640, 720] : [1.8, 300, 620];   // 세로는 줌 없이(좁은 화면에서 명령 두 줄이 이미 크다)
    const a0 = camView(EA[0], EA[1], EA[2], RW / 2, VY), a1 = camView(EB2[0], EB2[1], EB2[2], RW / 2, VY);
    const pu = camEase(seg(f, EN.pullFrom, EN.pullTo));
    const cE = [lerp(a0[0], a1[0], pu), lerp(a0[1], a1[1], pu), lerp(a0[2], a1[2], pu)];
    dE.style.transform = `translate(${(-cE[0] * cE[1]).toFixed(3)}px,${(-cE[0] * cE[2]).toFixed(3)}px) scale(${cE[0].toFixed(5)})`; dE._cam = cE;
    const nC = Math.max(0, Math.min(BREW.length, Math.floor((f - EN.type0) * EN.typeRate * 1.0)));
    const typing = f >= EN.type0 && nC < BREW.length;
    const blink = typing || Math.floor(f / 15) % 2 === 0;
    const promptL = `<span class="pr">~ %</span> `;
    const brewShown = BREW.slice(0, nC), brk = 20;   // "brew install --cask \" 뒤에서 셸 줄 이음 (가로·세로 공통, 좁은 터미널)   // 세로: "brew install --cask \" 뒤에서 셸 줄 이음
    const cmdHTML = brewShown.length > brk ? brewShown.slice(0, brk) + "\\\n    " + brewShown.slice(brk) : brewShown;
    const line1 = promptL + `<span class="cmd">${cmdHTML}</span>` + (f < EN.enter && blink ? `<span class="caret"></span>` : "");
    const line2 = f >= EN.enter + 4 ? `\n` + promptL + (f >= 836 || Math.floor(f / 15) % 2 === 0 ? `<span class="caret"></span>` : "") : "";   // f836부터 캐럿 고정 — 끝 정지 2.1초는 완전히 멈춘다
    term.innerHTML = line1 + line2;
    // 띠가 돌아온다: 엔터 뒤 지형 판이 16프레임에 걸쳐 나타나고, 스틱맨은 티 꽂기 의식 → 조준 (실제 리그)
    const on = smooth(seg(f, EN.pullFrom + 4, EN.pullTo + 2));
    dE._menubar.querySelector(".flagbox").style.opacity = on.toFixed(3);
    plateE.style.opacity = on.toFixed(3); svgE.style.opacity = on.toFixed(3); ballE.style.opacity = on.toFixed(3);
    // 2단계 QA: 자세가 f857에 멈춰 끝 정지가 1.43초였다(기준 1.5초) → 리그를 12프레임 앞당겨 시작한다(띠가 보이기 전 구간, 실제 속도 그대로) → f845 정지, 끝 정지 1.8초
    const rt = Math.max(0, (f - EN.enter + 10) / FPS);
    const r = rigAt(HERO, Math.min(rt, RIG_IMPACT - 0.35)); const st = stickAt(HERO, 0.5);
    drawMan(manE, r, st[1], groundH(st[1]), "crown");
    const showBall = rt > 0.62; px(ballE, S0_TEE[0] - 5.5, S0_TEE[1] - 5.5, 11, 11); ballE.style.visibility = showBall ? "visible" : "hidden";
    const ei = Sk((f - EN.block) / FPS, "calm");
    endBlock.style.opacity = ei.toFixed(3); endBlock.style.transform = `translateY(${fx2(10 * (1 - ei))}px)`;
  }

  /* ════════════════ 자막 (화면 고정, 마스크 밀어 올리기 5f) ════════════════ */
  const CP = O === "h" ? { x: 118, y: 104, fs: 88, maxW: 1500 } : { x: 76, y: 330, fs: 76, maxW: 930 };
  const capScrim = h("div", "scrim"); screenLayer.appendChild(capScrim);
  const cap = h("div", "cap"); screenLayer.appendChild(cap);
  const capA = h("div", "ln"), capB = h("div", "ln"); cap.appendChild(capA); cap.appendChild(capB);
  capA.style.whiteSpace = capB.style.whiteSpace = "pre"; capA.style.lineHeight = capB.style.lineHeight = "1.22";
  const LH = CP.fs * 1.22;
  px(cap, CP.x, CP.y, CP.maxW, LH); capA.style.fontSize = capB.style.fontSize = CP.fs + "px";
  capA.style.letterSpacing = capB.style.letterSpacing = (KO ? -0.03 : -0.025) * CP.fs + "px";
  const CAPS = TL.captions.map(([f, k]) => [f, k === "-" ? "-" : TX[k]]);
  const hudEl = h("div", "hud", `<div class="a"></div><div class="b"></div>`); screenLayer.appendChild(hudEl);
  const HUDP = O === "h" ? { r: 118, b: 70, a: 30, bs: 22 } : { r: 76, b: 440, a: 34, bs: 25 };
  hudEl.style.right = HUDP.r + "px"; hudEl.style.bottom = HUDP.b + "px";
  hudEl.querySelector(".a").style.fontSize = HUDP.a + "px"; hudEl.querySelector(".b").style.fontSize = HUDP.bs + "px";
  const toastEl = h("div", "toast", `<div class="a">${TX.badge[0]}</div><div class="b">${TX.badge[1]}</div>`); screenLayer.appendChild(toastEl);
  const tagEl = h("div", "tele", TX.tag4); screenLayer.appendChild(tagEl);

  function renderCaptions(f) {
    // 자막 자리: 기본 왼쪽 위. 뻐꾸기 샷(M5a)은 시계가 화면 위를 차지해서 아래로 내린다
    const low = f >= SH.m5a.f0 && f <= SH.m5b.f1;   // 마지막 막(M5a·M5b)은 자막을 아래로 — 같은 문장이 컷에서 자리를 옮기지 않게 두 샷 모두
    const cy0 = low ? (O === "h" ? RH - 104 - LH : 1500 - 40 - LH) : CP.y;
    cap.style.top = cy0 + "px";
    let i = -1; for (let k = 0; k < CAPS.length; k++) if (f >= CAPS[k][0]) i = k;
    const inMont = f >= 180 && f < 720 && !(i >= 0 && CAPS[i][1] === "-");
    const endCap = i >= 0 && CAPS[i][0] >= 600 ? 719 : 599;
    const vis = i >= 0 && inMont && f <= (CAPS[i][0] >= 600 ? 719 : 599);
    cap.style.opacity = vis ? 1 : 0; capScrim.style.opacity = vis ? 1 : 0;
    if (!vis) return;
    const cur = CAPS[i], prev = i > 0 && CAPS[i - 1][1] !== "-" && CAPS[i - 1][0] >= (cur[0] >= 600 ? 600 : 180) ? CAPS[i - 1] : null;
    const u = smooth(seg(f, cur[0], cur[0] + 5));
    const nl = (t) => t.split("\n").length, lines = Math.max(nl(cur[1]), prev && u < 1 ? nl(prev[1]) : 1), MH = LH * lines;
    cap.style.height = MH + "px"; if (low) cap.style.top = (cy0 - (lines - 1) * LH) + "px";
    capB.textContent = cur[1]; capB.style.transform = `translateY(${fx2(MH * (1 - u))}px)`;
    if (prev && u < 1) { capA.textContent = prev[1]; capA.style.transform = `translateY(${fx2(-MH * u)}px)`; capA.style.visibility = "visible"; }
    else capA.style.visibility = "hidden";
    const w = capB.getBoundingClientRect().width;
    px(capScrim, CP.x - 140, (low ? cy0 - (lines - 1) * LH : cy0) - 90, Math.min(RW, w + 330), MH + 190);
  }
  function renderHud(f) {
    if (O === "v") { const low = f >= SH.m5a.f0 && f <= SH.m5b.f1; hudEl.style.bottom = low ? "auto" : HUDP.b + "px"; hudEl.style.top = low ? "330px" : "auto"; }
    let key = null; for (const id of ["m1", "m2", "m3", "m5a", "m5b"]) { const S = SH[id]; if (f >= S.f0 && f <= S.f1) key = id; }
    hudEl.style.opacity = key ? 1 : 0; if (!key) return;
    const [a, b] = TX.hud[key]; const S = SH[key];
    hudEl.querySelector(".a").textContent = a; hudEl.querySelector(".b").textContent = b;
    const u = Sk((f - S.f0 - 3) / FPS, "soft");
    hudEl.style.transform = `translateY(${fx2((1 - u) * 8)}px)`; hudEl.style.opacity = clamp((f - S.f0 - 3) / 4).toFixed(3);
  }
  function renderToast(f) {
    // 배지 토스트 (게임 토스트 문법 재현: 0.18초 페이드인 · 1.4초 · 0.45초 페이드아웃)
    const T0 = SH.m5b.toast; let tu = f < T0 ? 0 : f < T0 + 5 ? (f - T0) / 5 : f < T0 + 47 ? 1 : Math.max(0, 1 - (f - T0 - 47) / 14);
    if (f > SH.m5b.f1 || !dM5._cam) tu = 0;
    toastEl.style.opacity = tu.toFixed(3);
    if (tu > 0) { const tp = toScreen(dM5, [1655, 560]); toastEl.style.left = (tp[0] - 300) + "px"; toastEl.style.width = "600px"; toastEl.style.top = (tp[1] - 80) + "px";
      toastEl.querySelector(".a").style.fontSize = (O === "h" ? 44 : 50) + "px"; toastEl.querySelector(".b").style.fontSize = (O === "h" ? 28 : 32) + "px"; }
  }
  function renderTag(f) {
    const S = SH.m4, on = f >= S.tagAt && f <= S.f1;   // 헛스윙이 끝난 뒤 작게 — 개그가 먼저 읽힌다
    tagEl.style.opacity = on ? clamp((f - S.tagAt) / 6).toFixed(3) : 0;
    if (on) { tagEl.style.fontSize = (O === "h" ? 24 : 32) + "px"; tagEl.style.textShadow = "0 0 10px rgba(8,8,9,.95), 0 0 3px rgba(8,8,9,.95)"; if (O === "h") { tagEl.style.right = "118px"; tagEl.style.left = "auto"; tagEl.style.bottom = "74px"; tagEl.style.top = "auto"; } else { tagEl.style.left = "76px"; tagEl.style.top = "1450px"; } }
  }


  /* ════════════════ render(t) ════════════════ */
  const DESKS = [[dH, 0, 179], [dM1, 180, 239], [dM2, 240, 329], [dM3, 330, 389], [dM4, 390, 449], [dM5, 450, 599], [dHo, 600, 719], [dE, 720, 899]];
  const fontsOk = () => FONT_FACES.every(([w, fam]) => document.fonts.check(`${w} 40px ${fam}`)) && document.fonts.status === "loaded";
  let READY = false;
  function init() {
    measureHead(); buildPath();
    // 푸시인 목표 배율: 마침표 지름이 다음 컷 공 지름(화면 px)과 같아지게
    PUSH_S = (M1S[0] * 11) / SM.period.d;
    // 정직 비트: 보내기 버튼·메뉴바 깃발 위치 (카메라 적용 전 데스크탑 좌표)
    const disp = dHo.style.display, tr = dHo.style.transform; dHo.style.display = "block"; dHo.style.transform = "none";
    const d = dHo.getBoundingClientRect(), sb = dHo.querySelector(".send").getBoundingClientRect(), fb = dHo._menubar.querySelector(".flagbox").getBoundingClientRect();
    SEND = [sb.left - d.left + sb.width / 2, sb.top - d.top + sb.height / 2]; dHo._flagPos = [fb.left - d.left + fb.width / 2, fb.top - d.top + fb.height / 2];
    dHo.style.display = disp; dHo.style.transform = tr;
    READY = fontsOk();
  }
  let PUSH_S = 3;
  function render(t) {
    if (!READY) init();
    const f = Math.min(NF - 1, Math.round(t * FPS));
    for (const [d, a, b] of DESKS) d.style.display = f >= a && f <= b ? "block" : "none";
    if (f <= 179) renderS01Wrapped(f);
    else if (f <= 599) renderMontage(f);
    else if (f <= 719) renderHonest(f);
    else renderEnd(f);
    if (f > 179) tele.style.opacity = 0;
    if (f < 720) endBlock.style.opacity = 0;
    renderCaptions(f); renderHud(f); renderToast(f); renderTag(f);
  }
  function renderS01Wrapped(f) {
    // 푸시인의 목표 배율을 측정값으로 바꿔 끼운다
    const saved = S1L.wide;
    renderS01(f);
    if (f >= HT.pushFrom) { const u = camEase(seg(f, HT.pushFrom, HT.pushTo)); const W = saved;
      // 목표: 마침표가 f180 첫 컷의 공과 같은 화면 자리·같은 지름 (M1 첫 카메라를 같은 가둠 규칙으로 계산)
      const m1 = M1CAM(180), a = [m1[0] * (M1BALL[0] - m1[1]), m1[0] * (M1BALL[1] - m1[2])];
      const s = lerp(W[0], PUSH_S, u), cx = lerp(W[1], SM.period.x, u), cy = lerp(W[2], SM.period.y, u);
      const sx = lerp(W[3] ?? RW / 2, a[0], u), sy = lerp(W[4] ?? RH / 2, a[1], u);
      setCam(dH, s, cx, cy, sx, sy); }
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;
  // 폰트 + 판·아틀라스 decode 뒤 첫 렌더 (HyperFrames 런타임도 문서 안 <img> decode를 기다린다 — 미리보기와 같은 조건)
  Promise.all([...FONT_LOADS, ...Object.values(IMG).map((e) => e.decode().catch(() => {}))]).then(() => document.fonts.ready).then(() => {
    init(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); window.__ready = true; });
})();
