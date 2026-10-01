/* mini-golf 15s — 본편 컴포지션 (가로·세로 × 한·영 4변형을 이 파일 하나가 그린다)
 *
 * 구조: 셸(index.html = 1920×1080, vertical.html = 1080×1920)이 #root 크기를 정하고, 언어는 HyperFrames 변수 lang(ko|en).
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). GSAP 타임라인은 재생 헤드 역할만 한다. Math.random·Date 없음.
 *
 * 비트 (프레임 @30fps, 가로·세로 공통) — 자세한 근거는 plan.md
 *   f0–10   훅: 에디터 아래 띠, 스틱맨이 톱(실캡처). 에디터 현재 줄이 타이핑되는 중(첫 프레임부터 진행)
 *   f10–20  다운스윙 → 임팩트 f11 → 팔로 → 피니시 (실캡처 크롭 5장). 공 출발
 *   f16–34  카메라 풀백 1회 (×1.5/×1.9 → ×1, CSS ease 18f) — 데스크탑 전체와 메모 창이 드러난다
 *   f21–    스틱맨은 실제 리그 덤프(60Hz)로 그린 벡터 — 트레이드마크 트월 → f145부터 띠를 따라 걷는다(실제 걸음)
 *   f36–106 메모 창에 문장 타이핑: 한 줄 "코드를 쓰는 동안," + 큰 문장 "9홀이 조용히 / 돌아갑니다"
 *   f112    공이 날아와 문장 끝에 앉는다 = 마침표 (광고적 과장, 궤적 모양은 실제 드라이브 궤적의 아치를 그대로 늘린 것)
 *   f150–290 느린 푸시 1회 (가로 ×1.12 좌하단 기준 = 띠 쪽으로, 세로 ×1.06 — 안전 영역 안에서)
 *   f200–252 커서가 띠를 가로질러 에디터 '실행'을 누른다 — 스틱맨은 그대로 걷는다(클릭은 아래 앱으로 통과)
 *   f254    윗줄 교체(마스크 밀어 올리기 5f): "빌드를 기다리는 동안,"
 *   f335–   엔드카드: 데스크탑 18f 딤 → 워드마크·한 줄·메타·URL (위층만 페이드), 끝 정지 2.7초
 */
(() => {
  const FPS = 30, DUR = 15;
  const root = document.getElementById("root");
  const O = root.offsetWidth > root.offsetHeight ? "h" : "v";
  const vars = (window.__hyperframes && window.__hyperframes.getVariables && window.__hyperframes.getVariables()) || {};
  const q = new URLSearchParams(location.search);
  const LANG = q.get("lang") || vars.lang || "ko";
  const KO = LANG === "ko";

  /* ── 문구 ── */
  const TX = KO ? {
    kick: ["코드를 쓰는 동안,", "빌드를 기다리는 동안,"], sent: ["9홀이 조용히", "돌아갑니다"],
    end1: "화면 맨 아래 띠에서.<br>클릭은 전부 아래 앱으로.", end2: "macOS 메뉴바 앱 · 무료 · 오픈소스",
    menu: ["편집기", "파일", "편집", "보기", "창"], clock: "화 9월 29일 오후 2:14", notes: "메모 — 오늘",
    run: "실행", building: "빌드 중", built: "빌드 성공 · 2.4초", pos: "360행, 72열   Swift",
  } : {
    kick: ["While you code,", "While the build runs,"], sent: ["nine holes", "play quietly"],
    end1: "Along the bottom of your screen.<br>Clicks pass right through.", end2: "macOS menu-bar app · free · open source",
    menu: ["Editor", "File", "Edit", "View", "Window"], clock: "Tue Sep 29 2:14 PM", notes: "Notes — Today",
    run: "Run", building: "Building", built: "Build succeeded · 2.4s", pos: "Ln 360, Col 72   Swift",
  };
  const URL_TEXT = "github.com/w0uldy0udaestar/mini-golf";

  /* ── 방향별 배치 (데스크탑 pt 좌표) ── */
  const L = O === "h" ? {
    desk: [1920, 1080], s1: 1, plateY: 0, editor: [40, 380, 1000, 670], notes: [880, 90, 990, 560],
    kick: 40, sent: 104, pad: [60, 58], gap: 22,
    cam0: [1.5, 0, -540], push: { s: 1.12, ax: 0, ay: 1080 }, cur0: [700, 640],
    end: { w: 900, wm: 92, dash: [64, 6], l1: 34, l2: 26, url: 24 },
  } : {
    // 세로: 데스크탑 771×1371pt를 ×1.4로 본다(= 1080×1920). 띠의 스틱맨이 가로판보다 1.4배 크게 읽히게
    desk: [771, 1372], s1: 1.4, plateY: 60, editor: [14, 660, 742, 530], notes: [30, 176, 711, 474],
    kick: 33, sent: 88, pad: [36, 42], gap: 17,
    cam0: [2.1, 0, -782], push: { s: 1.06, ax: 300, ay: 1100 }, cur0: [560, 800],
    end: { w: 900, wm: 104, dash: [72, 7], l1: 40, l2: 30, url: 27 },
  };

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const smooth = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
  const bez = (x1, y1, x2, y2) => (p) => { if (p <= 0) return 0; if (p >= 1) return 1; let a = 0, b = 1, t = p;
    for (let i = 0; i < 30; i++) { t = (a + b) / 2; const x = 3 * x1 * (1 - t) ** 2 * t + 3 * x2 * (1 - t) * t * t + t ** 3; x < p ? a = t : b = t; }
    return 3 * y1 * (1 - t) ** 2 * t + 3 * y2 * (1 - t) * t * t + t ** 3; };
  const camEase = bez(0.25, 0.1, 0.25, 1);
  const SPR = { calm: [0.78, 2.7], settle: [0.62, 3.2], soft: [0.5, 3.3] };
  const step = (t, z, f) => { const w = 2 * Math.PI * f, d = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(d * t) + z * w / d * Math.sin(d * t)); };
  const Sk = (t, n) => { if (t <= 0) return 0; const [z, f] = SPR[n]; const D = 6 / (z * 2 * Math.PI * f); return t >= D ? 1 : step(t, z, f) / step(D, z, f); };
  const seg = (f, a, b) => clamp((f - a) / (b - a));

  /* ── DOM ── */
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const px = (e, x, y, w, hh) => { e.style.left = x + "px"; e.style.top = y + "px"; if (w != null) e.style.width = w + "px"; if (hh != null) e.style.height = hh + "px"; return e; };
  const [DW, DH] = L.desk;
  const desk = px(h("div"), 0, 0, DW, DH); desk.id = "desk"; root.appendChild(desk);

  const FLAG = `<svg viewBox="0 0 14 16"><line x1="3" y1="1" x2="3" y2="15" stroke="#E6E6E2" stroke-width="1.6" stroke-linecap="round"/><path d="M3.8 1.6 L12.5 4.4 L3.8 7.2 Z" fill="#D94D3D"/></svg>`;
  desk.appendChild(h("div", "menubar", `<span class="app">${TX.menu[0]}</span>${TX.menu.slice(1).map((s) => `<span>${s}</span>`).join("")}<span class="sp"></span>${FLAG}<span>${TX.clock}</span>`));

  const win = (r, title, cls = "") => { const w = px(h("div", "win " + cls), r[0], r[1], r[2], r[3]);
    w.innerHTML = `<div class="bar"><i></i><i></i><i></i><div class="t">${title}</div></div><div class="body"></div>`; desk.appendChild(w); return w; };

  // 에디터 — Ballistics.swift 실제 발췌 (공개 저장소)
  const SWIFT = [
    ["c", "    /// 결정론적 물리 스텝. 경사면 바운스는 법선 반사, 굴림에는 중력의 경사 성분이 더해진다."],
    ["", "    <k>public static func</k> step("], ["", "        _ b: <k>inout</k> BallState, hole: Hole, dt: Double = Phys.dt, wind: Double? = <k>nil</k>,"],
    ["", "        kind: BallKind = .standard"], ["", "    ) -> StepEvent {"], ["", "        <k>switch</k> b.phase {"], ["", "        <k>case</k> .fly:"],
    ["c", "            // 바람: 공기력은 대기 상대속도 기준 — 뒷바람은 항력을 줄이고 맞바람은 키운다"],
    ["", "            <k>let</k> rvx = b.vx - (wind ?? hole.wind)"], ["", "            <k>let</k> v = max(hypot(rvx, b.vy), <n>1e-9</n>)"],
    ["", "            <k>let</k> omega = b.spin * <n>2</n> * .pi / <n>60</n>"], ["", "            <k>let</k> spinRatio = min(Phys.ballRadius * omega / v, Phys.spinRatioMax)"],
    ["", "            <k>let</k> cl = min(Phys.clMax, Phys.clBase + Phys.clSlope * spinRatio)"],
    ["c", "            // 항력(상대속도 반대) + 마그누스 양력(상대속도 수직, 백스핀=위) + 중력"],
    ["", "            <k>let</k> ax = -q * Phys.cd * v * rvx + q * cl * v * -b.vy * b.spinSign"],
    ["", "            <k>let</k> ay = -Phys.g - q * Phys.cd * v * b.vy + q * cl * v * rvx * b.spinSign"],
    ["", "            b.vx += ax * dt"], ["", "            b.vy += ay * dt"], ["", "            b.x += b.vx * dt"], ["", "            b.y += b.vy * dt"],
    ["cur", "            b.spin *= 1 - min(0.06, max(0.01, Phys.spinDecayPerSpeed * v)) * dt"], ["", ""],
    ["", "            <k>let</k> ground = hole.ground(at: b.x)"], ["", "            <k>if</k> b.y <= ground {"],
    ["", "                <k>let</k> surfType = hole.surface(at: b.x)"], ["", "                <k>if</k> surfType == .water { <k>return</k> .water }"],
    ["", "                b.y = ground"], ["", "                <k>let</k> s = hole.slope(at: b.x)"], ["", "                <k>let</k> baseAng = atan(s)"],
  ];
  const fmt = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/&lt;(\/?)(k|n)>/g, (m, sl, t) => sl ? "</span>" : `<span class="${t}">`);
  const editor = win(L.editor, "Ballistics.swift — mini-golf");
  const code = h("div", "code"); const CUR_I = SWIFT.findIndex((r) => r[0] === "cur"); const CUR_TEXT = SWIFT[CUR_I][1];
  code.innerHTML = SWIFT.map(([c, s], i) => `<span class="row ${c === "cur" ? "cur" : ""}"><span class="ln">${340 + i}</span>${c === "c" ? `<span class="c">${fmt(s)}</span>` : c === "cur" ? `<span id="curtext"></span><span id="edcaret" style="display:inline-block;width:2px;height:18px;background:#E6E6E2;vertical-align:-3px"></span>` : fmt(s)}</span>`).join("");
  code.style.marginTop = (O === "h" ? -126 : -330) + "px";   // 타이핑 중인 줄이 티(스틱맨 발밑) 바로 위에 오게
  editor.querySelector(".body").appendChild(code);
  const status = h("div", "status", `<span>${TX.pos}</span><span class="runbtn" id="runbtn"><svg viewBox="0 0 9 10"><path d="M0 0 L9 5 L0 10 Z" fill="#C9CAC6"/></svg>${TX.run}</span><span class="buildmsg" id="buildmsg"></span>`);
  editor.querySelector(".body").appendChild(status);

  // 메모 창
  const notes = win(L.notes, TX.notes, "notes");

  // 게임층: 판(지형·HUD) → 스윙 크롭 → 벡터 스틱맨 → 궤적 → 메모 글자층 → 공 → 커서
  const plate = px(h("img", "plate"), 0, L.plateY); plate.src = `assets/gen/plate-${LANG}.png`; desk.appendChild(plate);
  const SWING = ["swing-top", "swing-down", "swing-impact", "swing-follow", "swing-finish"];
  const crops = SWING.map((n) => { const e = px(h("img", "crop"), 80 / 2, 1432 / 2 + L.plateY); e.src = `assets/gen/${n}.png`; e.style.visibility = "hidden"; desk.appendChild(e); return e; });
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg"); svg.id = "fx"; svg.setAttribute("width", DW); svg.setAttribute("height", DH); desk.appendChild(svg);
  const mk = (tag, a) => { const e = document.createElementNS(NS, tag); for (const k in a) e.setAttribute(k, a[k]); return e; };
  const trailEl = mk("polyline", { fill: "none", stroke: "#9C9D99", "stroke-width": 1.6, "stroke-linecap": "round", "stroke-linejoin": "round" });
  svg.appendChild(trailEl);
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

  // 메모 글자층 (궤적보다 위 — 글자가 궤적 선을 가린다. 메모 창 배경은 궤적보다 아래)
  const [NX, NY, NW] = L.notes;
  const dim = h("div"); dim.id = "dim"; desk.appendChild(dim);
  const textLayer = px(h("div"), 0, 0, DW, DH); desk.appendChild(textLayer);
  const kick = px(h("div", "kick"), NX + L.pad[0], NY + 34 + L.pad[1]); kick.style.fontSize = L.kick + "px"; kick.style.height = L.kick * 1.3 + "px"; kick.style.width = (NW - 2 * L.pad[0]) + "px";
  kick.innerHTML = `<div class="mask" style="height:${L.kick * 1.3}px;right:0"><div class="line" id="k0"></div><div class="line" id="k1"></div></div>`;
  textLayer.appendChild(kick);
  const sentTop = NY + 34 + L.pad[1] + L.kick * 1.3 + L.gap;
  const sent = px(h("div", "sent"), NX + L.pad[0], sentTop); sent.style.fontSize = L.sent + "px"; sent.style.lineHeight = "1.08";
  sent.style.letterSpacing = (KO ? -0.035 : -0.03) * L.sent + "px";
  sent.innerHTML = `<span class="ln2" id="s0"></span><span class="ln2" id="s1"></span>`;
  textLayer.appendChild(sent);
  const caret = h("div", "caret"); textLayer.appendChild(caret);

  const ballEl = h("div"); ballEl.id = "ball"; desk.appendChild(ballEl);
  const cursor = h("div"); cursor.innerHTML = `<svg id="cursor" viewBox="0 0 22 32"><path d="M2 2 L2 25 L7.6 19.8 L11.4 28.6 L15 27 L11.3 18.4 L18.8 18.4 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
  cursor.style.cssText = "position:absolute;left:0;top:0;width:22px;height:32px;transform-origin:2px 2px"; desk.appendChild(cursor);

  // 엔드카드 (화면 고정)
  const E = L.end;
  const end = px(h("div"), 0, 0, E.w); end.id = "end";
  end.innerHTML = `<div class="dash" style="width:${E.dash[0]}px;height:${E.dash[1]}px;margin:0 0 ${E.wm * 0.34}px 3px"></div>
    <div class="wm" style="font-size:${E.wm}px;letter-spacing:${-0.035 * E.wm}px;margin-bottom:${E.wm * 0.3}px">mini-golf</div>
    <div class="l1" style="font-size:${E.l1}px;line-height:1.28;letter-spacing:${-0.02 * E.l1}px">${TX.end1}</div>
    <div class="l2" style="font-size:${E.l2}px;margin-top:${E.l2 * 0.9}px">${TX.end2}</div>
    <div class="url" style="font-size:${E.url}px;margin-top:${E.url * 1.1}px">${URL_TEXT}</div>`;
  // 엔드카드 뒤 부드러운 어둠(상자 없음): 딤된 띠·스틱맨이 글자와 겹쳐 읽히지 않게
  const endScrim = h("div"); endScrim.style.cssText = "position:absolute;pointer-events:none;opacity:0;background:radial-gradient(closest-side,rgba(5,5,6,.92) 55%,rgba(5,5,6,0) 100%)";
  root.appendChild(endScrim); root.appendChild(end);

  /* ── 측정 (한 번, 결정적): 글자별 캐럿 위치, 마침표 자리 ── */
  const RIG = window.RIG, GROUND = window.GROUND, TR = window.TRAIL;
  const typeTimes = (text, f0, rate) => [...text].map((_, i) => f0 + i * rate);
  const K0 = [...TX.kick[0]], S0 = [...TX.sent[0]], S1 = [...TX.sent[1]];
  const F_K = 36, KR = KO ? 3.2 : 2.0;
  const F_S = Math.round(F_K + K0.length * KR + 6);
  const F_SEND = 106, SR = (F_SEND - F_S) / (S0.length + S1.length);
  const tK0 = typeTimes(K0, F_K, KR), tS = typeTimes([...S0, ...S1], F_S, SR);
  const F_LAND = 112, F_IMP = 11;
  const ED_RATE = 0.45, ED0 = 67 - Math.round(30 * 0.45);   // 에디터 현재 줄(67자): f0에 54자, f30에 다 친다
  let M = null;
  function measure() {
    const saved = desk.style.transform; desk.style.transform = "none";
    const pre = (el, chars) => { const out = []; for (let i = 0; i <= chars.length; i++) { el.textContent = chars.slice(0, i).join(""); out.push(el.getBoundingClientRect().width); } el.textContent = ""; return out; };
    const k0 = document.getElementById("k0"), s0 = document.getElementById("s0"), s1 = document.getElementById("s1");
    k0.style.display = "inline-block"; s0.style.display = "inline-block"; s1.style.display = "inline-block";
    const W = { k0: pre(k0, K0), s0: pre(s0, S0), s1: pre(s1, S1) };
    k0.style.display = ""; s0.style.display = ""; s1.style.display = "";
    s1.innerHTML = S1.join("") + `<span id="bl" style="display:inline-block;width:0;height:0;vertical-align:baseline"></span>`;
    s0.textContent = S0.join("");
    const bl = document.getElementById("bl").getBoundingClientRect(), sr = sent.getBoundingClientRect(), s0r = s0.getBoundingClientRect(), s1r = s1.getBoundingClientRect();
    const d = desk.getBoundingClientRect(); // 카메라 적용 전(항등)에 잰다
    const period = { d: L.sent * 0.17 };
    period.x = sr.left - d.left + W.s1[S1.length] + L.sent * 0.03 + period.d / 2;
    period.y = bl.top - d.top - period.d / 2;
    s0.textContent = ""; s1.textContent = "";
    M = { W, period, s0top: s0r.top - d.top, s1top: s1r.top - d.top, lineH: s0r.height, ktop: kick.getBoundingClientRect().top - d.top };
    desk.style.transform = saved;
  }

  /* ── 공 경로: 실제 드라이브 궤적의 아치(현에서 뜬 높이)를 새 현(티 → 마침표)에 옮긴다 ── */
  let PATH = null; const ARCH = O === "h" ? 1.8 : 1.6;   // 현 대비 아치 높이 배율 (실제 궤적 아치 × 배율)
  function buildPath() {
    const S = [153.5, 851.5 + L.plateY], Ee = [M.period.x, M.period.y];
    const R0 = TR.ball.f73, R1 = TR.ball.f184;
    const arch = TR.pts.map(([x, y]) => { const u = (x - R0[0]) / (R1[0] - R0[0]); return [u, y - (R0[1] + (R1[1] - R0[1]) * u)]; });
    arch.unshift([0, 0]); arch.push([1, 0]);
    const hAt = (u) => { for (let i = 1; i < arch.length; i++) if (arch[i][0] >= u) { const a = arch[i - 1], b = arch[i]; return lerp(a[1], b[1], (u - a[0]) / Math.max(1e-6, b[0] - a[0])); } return 0; };
    const lenR = Math.hypot(R1[0] - R0[0], R1[1] - R0[1]), lenN = Math.hypot(Ee[0] - S[0], Ee[1] - S[1]);
    const k = (lenN / lenR) * ARCH;
    PATH = []; for (let i = 0; i <= 400; i++) { const u = i / 400; PATH.push([lerp(S[0], Ee[0], u), lerp(S[1], Ee[1], u) + hAt(u) * k]); }
  }
  const pathAt = (u) => { const i = u * 400, a = Math.floor(clamp(i, 0, 399)), fr = i - a; return [lerp(PATH[a][0], PATH[a + 1][0], fr), lerp(PATH[a][1], PATH[a + 1][1], fr)]; };
  // 실제 공 시간 표본(임팩트 후 1.63초에 수평 60%, 3.0초에 90%) → u = 1-(1-τ)^1.6
  const flightU = (f) => 1 - Math.pow(1 - clamp((f - F_IMP) / (F_LAND - F_IMP)), 1.6);

  /* ── 스틱맨 (실제 리그 → StickmanNode 렌더 규칙 그대로) ── */
  function drawMan(fr) {
    const r = RIG[Math.min(RIG.length - 1, fr)], d = r.dir;
    const gx = r.x, gy = GROUND[Math.round(clamp(gx, 0, 1919))] + 0.6 + L.plateY;
    const T = (p) => [gx + p[0] * d, gy - p[1]];
    const [hip, sh, f1, f2, k1, k2, grip, ht, el, et] = r.pts.map(T);
    const f = (p) => `${p[0].toFixed(2)} ${p[1].toFixed(2)}`;
    const ctl = [(sh[0] + hip[0]) / 2 - d * 0.8, (sh[1] + hip[1]) / 2];
    const arm = (a, e, b) => r.curved ? `M${f(a)} Q${f(e)} ${f(b)}` : `M${f(a)} L${f(e)} L${f(b)}`;
    P.body.setAttribute("d", `M${f(sh)} Q${f(ctl)} ${f(hip)} M${f(hip)} L${f(k1)} L${f(f1)} M${f(hip)} L${f(k2)} L${f(f2)} ${arm(sh, el, grip)}`);
    P.trail.setAttribute("d", arm(sh, et, ht));
    const sp = Math.sin(r.phi), cp = Math.cos(r.phi);
    const tip = [grip[0] + sp * r.len * d, grip[1] + cp * r.len];
    const butt = [grip[0] - sp * r.butt * d, grip[1] - cp * r.butt];
    P.shaft.setAttribute("d", `M${f(butt)} L${f(tip)}`);
    P.grip.setAttribute("d", `M${f(butt)} L${f([grip[0] + sp * 8 * d, grip[1] + cp * 8])}`);
    const perp = [Math.cos(r.phi) * d, -Math.sin(r.phi)];            // y 아래 좌표계
    const c = [tip[0] + perp[0] * 4.5, tip[1] + perp[1] * 4.5], half = (17 - 13.6) / 2;
    P.chead.setAttribute("d", `M${f([c[0] - perp[0] * half, c[1] - perp[1] * half])} L${f([c[0] + perp[0] * half, c[1] + perp[1] * half])}`);
    const hd = [sh[0] + d * r.head[0], sh[1] - r.head[1]];
    P.head.setAttribute("cx", hd[0].toFixed(2)); P.head.setAttribute("cy", hd[1].toFixed(2));
    const crown = [[-9, 7], [-9, 15], [-4.5, 10], [0, 16], [4.5, 10], [9, 15], [9, 7]];
    P.hat.setAttribute("d", "M" + crown.map(([x, y]) => f([hd[0] + x * d, hd[1] - y])).join(" L") + " Z");
  }

  /* ── 카메라 ── */
  function camera(f) {
    const [s0, x0, y0] = L.cam0;
    let s = s0, tx = x0, ty = y0;
    const u = camEase(seg(f, 16, 34));
    s = lerp(s0, L.s1, u); tx = lerp(x0, 0, u); ty = lerp(y0, 0, u);
    const pu = camEase(seg(f, 150, 290));   // 느린 푸시 1회 4.7초 (초당 배율 변화 ≤ 2.6%)
    if (pu > 0) { const ps = L.s1 * lerp(1, L.push.s, pu); s = ps; tx = L.push.ax * (1 - ps / L.s1); ty = L.push.ay * (1 - ps / L.s1); }
    return [s, tx, ty];
  }

  /* ── 커서 (데스크탑 좌표) ── */
  const F_MOVE = 200, F_MOVE_END = 226, F_PRESS = 247, F_REL = 251;
  let RUN = null, END_POS = null;
  function cursorAt(f) {
    const a = L.cur0, b = RUN;
    const s = Sk((f - F_MOVE) / FPS, "calm");
    const x = lerp(a[0], b[0], s), y = lerp(a[1], b[1], s);
    const bow = Math.sin(Math.PI * s) * 36;                         // 살짝 휜 경로
    const nx = -(b[1] - a[1]), ny = b[0] - a[0], nl = Math.hypot(nx, ny);
    const press = f >= F_PRESS - 2 && f < F_REL ? 1 - 0.16 * smooth(seg(f, F_PRESS - 2, F_PRESS)) : 1 - 0.16 * (1 - smooth(seg(f, F_REL, F_REL + 3))) * (f >= F_REL && f < F_REL + 3 ? 1 : 0);
    return [x + nx / nl * bow, y + ny / nl * bow, press];
  }

  /* ── render(t) ── */
  // 글자 측정(캐럿·마침표 자리)은 폰트가 실제로 올라온 뒤에만 캐시한다 — 폰트 전에 잰 값이 굳으면 렌더마다 자리가 달라진다(실측: v-ko 2회 렌더 f55–255 불일치)
  const fontsOk = () => ["600 40px Pretendard", "700 100px Pretendard", "800 90px Pretendard", "400 16px JBM"].every((f) => document.fonts.check(f)) && document.fonts.status === "loaded";
  function render(t) {
    if (!M || !M.fontsOk) { M = null; END_POS = null; RUN = null; init(); M.fontsOk = fontsOk(); }
    const f = Math.round(t * FPS);
    // 카메라
    const [s, tx, ty] = camera(f);
    desk.style.transform = `translate(${tx.toFixed(3)}px,${ty.toFixed(3)}px) scale(${s.toFixed(5)})`;

    // 에디터 현재 줄 타이핑 (f0부터 진행 중) — 들여쓰기 뒤 글자만
    const ind = CUR_TEXT.match(/^\s*/)[0].length, body = CUR_TEXT.slice(ind);
    const nEd = Math.min(body.length, ED0 + Math.floor(Math.min(f, 30) * ED_RATE));   // 13.5자/초 — 사람 속도
    document.getElementById("curtext").textContent = CUR_TEXT.slice(0, ind) + body.slice(0, nEd);
    const edCaretOn = f < 34 ? 1 : 0;
    document.getElementById("edcaret").style.opacity = edCaretOn;

    // 스윙: 실캡처 크롭 (f0–20) → 리그 벡터 (f21–)
    const CROP_AT = [[0, 10, 0], [10, 11, 1], [11, 14, 2], [14, 18, 3], [18, 21, 4]];
    crops.forEach((e, i) => { const c = CROP_AT.find((r) => r[2] === i); e.style.visibility = f >= c[0] && f < c[1] ? "visible" : "hidden"; });
    man.style.visibility = f >= 21 ? "visible" : "hidden";
    if (f >= 21) drawMan(f);

    // 공 + 궤적
    if (f >= F_IMP) {
      const u = flightU(f);
      const n = Math.max(2, Math.round(u * 400));
      trailEl.setAttribute("points", PATH.slice(0, n + 1).map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" "));
      trailEl.setAttribute("opacity", (1 - smooth(seg(f, 150, 172))).toFixed(3));
      let [bx, by] = pathAt(u);
      if (f > F_LAND) { const hop = seg(f, F_LAND, F_LAND + 10); by -= Math.sin(Math.PI * hop) * M.period.d * 0.55; }
      const dia = lerp(9, M.period.d, smooth(u));
      ballEl.style.visibility = "visible";
      px(ballEl, bx - dia / 2, by - dia / 2, dia, dia);
    } else { ballEl.style.visibility = "hidden"; trailEl.setAttribute("points", ""); }

    // 메모: 윗줄 타이핑 → 교체(마스크 밀어 올리기 5f), 큰 문장 타이핑
    const nK = tK0.filter((x) => f >= x).length;
    const k0 = document.getElementById("k0"), k1 = document.getElementById("k1");
    k0.textContent = TX.kick[0].slice(0, [...TX.kick[0]].slice(0, nK).join("").length);
    const F_SWAP = 254, sw = smooth(seg(f, F_SWAP, F_SWAP + 5)), kh = L.kick * 1.3;
    k0.style.transform = `translateY(${(-kh * sw).toFixed(2)}px)`; k1.textContent = TX.kick[1];
    k1.style.transform = `translateY(${(kh * (1 - sw)).toFixed(2)}px)`; k1.style.visibility = f >= F_SWAP ? "visible" : "hidden";
    const nS = tS.filter((x) => f >= x).length, n0 = Math.min(S0.length, nS), n1 = Math.max(0, nS - S0.length);
    document.getElementById("s0").textContent = S0.slice(0, n0).join("");
    document.getElementById("s1").textContent = S1.slice(0, n1).join("");
    // 캐럿: 메모에 포커스가 온 뒤(f36)부터. 타이핑 중엔 켜짐, 쉬면 16f 주기로 깜빡
    let cx, cy, ch;
    if (nS === 0) { cx = M.W.k0[nK]; cy = M.ktop; ch = L.kick * 1.18; cx += NX + L.pad[0]; cy += L.kick * 0.08; }
    else if (n1 === 0) { cx = NX + L.pad[0] + M.W.s0[n0]; cy = M.s0top + M.lineH * 0.14; ch = M.lineH * 0.78; }
    else { cx = NX + L.pad[0] + M.W.s1[n1] + (f >= F_LAND ? M.period.d + L.sent * 0.1 : 0); cy = M.s1top + M.lineH * 0.14; ch = M.lineH * 0.78; }
    const lastKey = Math.max(...tK0.concat(tS).filter((x) => f >= x), -99);
    const typing = f - lastKey < 8;
    const carOn = f >= F_K - 2 && f < 335 && (typing || Math.floor((f - lastKey) / 16) % 2 === 1);
    px(caret, cx + 3, cy, null, ch); caret.style.opacity = carOn ? 1 : 0;

    // 커서
    const [cxp, cyp, cs] = cursorAt(f);
    cursor.style.transform = `translate(${cxp.toFixed(2)}px,${cyp.toFixed(2)}px) scale(${cs.toFixed(3)})`;
    const rb = document.getElementById("runbtn");
    rb.style.background = f >= F_PRESS - 2 && f < F_REL + 3 ? "#3A3B41" : (f >= F_MOVE_END - 4 && f < 330 ? "#313238" : "#2A2B30");
    const bm = document.getElementById("buildmsg");
    bm.textContent = f >= 318 ? TX.built : f >= F_REL ? TX.building + " " + "·".repeat(1 + Math.floor((f - F_REL) / 10) % 3) : "";

    // 엔드카드: 데스크탑 딤(18f) → 카드(위층만 페이드)
    const dm = smooth(seg(f, 335, 353));
    dim.style.opacity = (0.62 * dm).toFixed(3);
    if (!END_POS) { const [es, etx, ety] = camera(449); END_POS = [etx + es * (NX + L.pad[0]), ety + es * (L.notes[1] + L.notes[3]) + (O === "h" ? 44 : 56)]; }
    end.style.left = END_POS[0] + "px"; end.style.top = END_POS[1] + "px";
    const eb = [end.offsetWidth, end.offsetHeight];
    px(endScrim, END_POS[0] - 280, END_POS[1] - 100, eb[0] * 0.9 + 440, eb[1] + 200); endScrim.style.opacity = dm.toFixed(3);
    const ei = Sk((f - 346) / FPS, "calm");
    end.style.opacity = ei.toFixed(3); end.style.transform = `translateY(${(10 * (1 - ei)).toFixed(2)}px)`;
  }

  function init() {
    if (M && M.fontsOk) return;
    measure(); buildPath();
    const saved = desk.style.transform; desk.style.transform = "none";
    // '실행' 버튼 자리 = 클릭 순간 스틱맨 바로 아래 (클릭이 띠를 통과해 아래 앱으로 간다는 걸 보이게)
    const manX = RIG[F_PRESS].x;
    status.style.paddingLeft = "330px";   // 재측정 때 이전 이동이 누적되지 않게
    const rb = document.getElementById("runbtn").getBoundingClientRect(), d = desk.getBoundingClientRect();
    const shift = manX - 6 - (rb.left - d.left);
    status.style.paddingLeft = (330 + shift) + "px";
    const rb2 = document.getElementById("runbtn").getBoundingClientRect();
    RUN = [rb2.left - d.left + 18, rb2.top - d.top + 8];
    desk.style.transform = saved;
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;
  window.__ready = false;
  // ?audit=1 : 전 프레임(3프레임 간격)을 돌며 '글자 있는 요소'와 스틱맨의 화면 사각형을 모아 <pre id="audit">에 JSON으로 쓴다 (scripts/qa.py가 읽는다)
  function audit() {
    const out = { orient: O, lang: LANG, frames: [] };
    const vis = (e) => { let o = 1, n = e; while (n && n !== document.body) { const cs = getComputedStyle(n); if (cs.visibility === "hidden" || cs.display === "none") return 0; o *= parseFloat(cs.opacity); n = n.parentElement; } return o; };
    const rectOf = (e) => { const r = e.getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom].map((v) => Math.round(v)); };
    const textRects = (e) => { const out = []; const rg = document.createRange(); const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT);
      let n; while ((n = w.nextNode())) { if (!n.textContent.trim()) continue; rg.selectNodeContents(n); for (const r of rg.getClientRects()) out.push([r.left, r.top, r.right, r.bottom].map((v) => Math.round(v))); } return out; };
    const crit = [["kick", kick], ["sent", sent], ["end", end]];
    for (let f = 0; f < 450; f += 3) {
      render(f / FPS);
      const fr = { f, items: [] };
      const mk = kick.querySelector(".mask").getBoundingClientRect();
      for (const [name, el] of crit) { const o = vis(el); if (o > 0.05) for (let r of textRects(el)) {
        if (name === "kick") { r = [Math.max(r[0], mk.left), Math.max(r[1], mk.top), Math.min(r[2], mk.right), Math.min(r[3], mk.bottom)].map(Math.round); if (r[3] - r[1] < 4) continue; }   // 마스크 밖(밀려 나간 줄)은 안 보인다
        fr.items.push({ name, o: +o.toFixed(2), r }); } }
      if (vis(ballEl) > 0.05 && f >= F_LAND) fr.items.push({ name: "ball", o: 1, r: rectOf(ballEl) });
      if (f >= 21) fr.items.push({ name: "man", o: 1, r: rectOf(man) });
      fr.scale = +camera(f)[0].toFixed(3);
      out.frames.push(fr);
    }
    // 화면상 글자 크기(px) = CSS 크기 × 카메라 배율
    const sz = (el) => parseFloat(getComputedStyle(el).fontSize);
    out.fontsOk = M.fontsOk; out.fontStatus = document.fonts.status;
    out.fontChecks = ["600 40px Pretendard", "700 100px Pretendard", "800 90px Pretendard", "400 16px JBM"].map((f) => document.fonts.check(f));
    out.textPx = { kick: sz(kick) * L.s1, sent: sz(sent) * L.s1, endWordmark: E.wm, endLine: E.l1, endMeta: E.l2, endUrl: E.url, codeInEditor: 16.5 * L.s1, menubar: 13.5 * L.s1 };
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  document.fonts.ready.then(() => { init(); if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); window.__ready = true; }); // ?t= 는 스틸 미리보기용
  // 폰트 준비 전 첫 호출 대비
  window.__init = init;
})();
