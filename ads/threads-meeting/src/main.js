/* T3 「회의 중 9홀」 — 세로 1080×1920 · 30fps · 14.5초(435프레임) · 한국어. 소리 없이 완결.
 *
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). GSAP 타임라인은 재생 헤드 역할만. Math.random·Date·네트워크 없음.
 * 데스크탑(#desk)은 745×1103pt 세로 조각을 ×(1080/745)로 본다. 게임 판 좌표 y + 23 = 데스크탑 y (판 아래 = 화면 아래).
 *
 * 비트 (프레임 @30fps) — 자세한 근거는 plan.md
 *   f0       훅: 카메라 ×2.1로 띠를 당겨 잡는다(스틱맨 키 ≈ 290px). 채팅 입력란에 "네, 확인…" 타이핑 중 + 스틱맨이 이미 백스윙 톱(실캡처). 자막 "회의 중입니다."
 *   f11      임팩트(실캡처 크롭) → f13–46 공을 따라 ×1로 풀백, 회의 창 전체가 드러난다. 공은 참가자 격자를 가로질러 높게 날아(정점 부근 속도 램프) f84에 떨어진다
 *            f21부터 실제 리그(트월 → 클럽 걸치기)
 *   f38      채팅 전송 "네, 확인했습니다"
 *   f92      자막 교체 "클릭은 아래 앱으로 간다."
 *   f88–122  커서가 스틱맨을 지나 띠 아래 '음소거 해제'를 누른다(f118) → 버튼·내 타일이 바뀐다 = 클릭은 회의 앱으로 갔다
 *   f160     자막 → 큰 플립 시계 "14:00"(카드 168px) + 옆에 작게 "1번 홀"
 *   f170–282 타임랩스: 컷마다 시계가 넘어간다(14:00 → 14:45), 홀 1 → 2 → 3 → 4 → 5 → 7 → 9. 모든 컷이 움직인다:
 *            2·5·7번 = 30초판 실캡처 연번(티샷 · 급사면 샷 · 퍼트·컵인), 3·4·9번 = 실제 리그로 걷기. 채팅 "네" · "좋습니다" · "다음 주에 뵙겠습니다"
 *   f306     판독 → "회의 중에도 9홀."
 *   f340–    회의 창만 딤 → 엔드카드(띠는 밝게 남아 스틱맨이 계속 걷는다), 끝 정지
 */
(() => {
  const FPS = 30, DUR = 14.5, NF = Math.round(DUR * FPS);
  const root = document.getElementById("root");
  const q = new URLSearchParams(location.search);
  const DW = 745, DH = 1103, OFFY = 23, S = 1080 / DW;

  /* ── 수학 ── */
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, u) => a + (b - a) * u;
  const smooth = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
  const ease3 = (u) => { u = clamp(u); return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2; };
  const seg = (f, a, b) => clamp((f - a) / (b - a));
  const SPR = { calm: [0.78, 2.7] };
  const step = (t, z, fr) => { const w = 2 * Math.PI * fr, d = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(d * t) + z * w / d * Math.sin(d * t)); };
  const Sk = (t, n) => { if (t <= 0) return 0; const [z, fr] = SPR[n]; const D = 6 / (z * 2 * Math.PI * fr); return t >= D ? 1 : step(t, z, fr) / step(D, z, fr); };

  /* ── DOM ── */
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const px = (e, x, y, w, hh) => { e.style.left = x + "px"; e.style.top = y + "px"; if (w != null) e.style.width = w + "px"; if (hh != null) e.style.height = hh + "px"; return e; };
  const DH2 = Math.ceil(1920 / S);   // 화면 아래 베젤까지 포함한 높이 — 카메라와 함께 움직인다
  const desk = px(h("div"), 0, 0, DW, DH2); desk.id = "desk"; root.appendChild(desk);
  const bezel = px(h("div"), 0, DH, DW, DH2 - DH); bezel.id = "bezel"; desk.appendChild(bezel);

  const FLAG = `<svg viewBox="0 0 14 16"><line x1="3" y1="1" x2="3" y2="15" stroke="#E6E6E2" stroke-width="1.6" stroke-linecap="round"/><path d="M3.8 1.6 L12.5 4.4 L3.8 7.2 Z" fill="#D94D3D"/></svg>`;
  desk.appendChild(h("div", "menubar", `<span class="app">회의</span><span>파일</span><span>편집</span><span>보기</span><span>창</span><span class="sp"></span>${FLAG}<span>화</span><span class="clock" id="clock">14:00</span>`));

  // 아이콘 (일반형 — 특정 앱 모양 아님)
  const MIC = (on, c = "#77787A") => `<svg viewBox="0 0 16 16"><rect x="5.5" y="1.5" width="5" height="8.5" rx="2.5" fill="none" stroke="${c}" stroke-width="1.5"/><path d="M3 7.5 a5 5 0 0 0 10 0 M8 12.5 V15" fill="none" stroke="${c}" stroke-width="1.5" stroke-linecap="round"/>${on ? "" : `<line x1="2" y1="14.5" x2="14" y2="1.5" stroke="${c}" stroke-width="1.6" stroke-linecap="round"/>`}</svg>`;
  const CAM = (c) => `<svg viewBox="0 0 16 16"><rect x="1.5" y="4" width="9" height="8" rx="2" fill="none" stroke="${c}" stroke-width="1.5"/><path d="M10.5 7 L14.5 4.8 V11.2 L10.5 9 Z" fill="none" stroke="${c}" stroke-width="1.5" stroke-linejoin="round"/><line x1="1.5" y1="14.5" x2="14.5" y2="1.5" stroke="${c}" stroke-width="1.6" stroke-linecap="round"/></svg>`;
  const SHARE = (c) => `<svg viewBox="0 0 16 16"><rect x="1.5" y="2.5" width="13" height="9" rx="1.5" fill="none" stroke="${c}" stroke-width="1.5"/><path d="M8 9.5 V5 M5.8 7 L8 4.8 L10.2 7" fill="none" stroke="${c}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><line x1="5" y1="14.2" x2="11" y2="14.2" stroke="${c}" stroke-width="1.5" stroke-linecap="round"/></svg>`;
  const SIL = (w) => `<svg class="sil" width="${w}" height="${w}" viewBox="0 0 100 100"><circle cx="50" cy="36" r="19" fill="#2A2B30"/><path d="M14 98 C14 70 30 60 50 60 C70 60 86 70 86 98 Z" fill="#2A2B30"/></svg>`;

  /* ── 회의 창 ── */
  const WIN = [22, 236, 606, 756];   // x, y, w, h (데스크탑 pt)
  const win = px(h("div", "win"), ...WIN); desk.appendChild(win);
  win.appendChild(h("div", "bar", `<i></i><i></i><i></i><div class="t">주간 회의</div>`));
  const TW = 291, TH = 160, TG = 8;
  const tiles = [];
  for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) {
    const t = px(h("div", "tile"), 8 + i * (TW + TG), 42 + j * (TH + TG), TW, TH);
    const self = i === 1 && j === 1, talk = i === 0 && j === 0;
    t.innerHTML = SIL(116) + `<div class="tag">${self ? `<span id="selfmic">${MIC(false)}</span><span>나</span>` : talk ? MIC(true, "#8C8D89") : MIC(false)}</div><div class="ring" ${self ? 'id="selfring"' : talk ? 'style="opacity:.55"' : ""}></div>`;
    win.appendChild(t); tiles.push(t);
  }
  // 채팅 패널: 목록(마지막 3줄) + 입력란. 입력란은 티의 스틱맨 오른쪽에서 시작한다(겹치지 않게)
  const CH = [8, 378, 590, 192];   // 창 안 좌표
  const chat = px(h("div", "chat"), ...CH); win.appendChild(chat);
  chat.appendChild(h("div", "hd", "채팅"));
  const LIST_TOP = 26, PITCH = 36, LIST_H = PITCH * 3 + 2;
  const list = px(h("div", "list"), 0, LIST_TOP, null, LIST_H); chat.appendChild(list);
  const MSGS = [
    { t: "자료 공유드렸습니다", in: 1, f: -999 }, { t: "확인 부탁드려요", in: 1, f: -999 },
    { t: "네, 확인했습니다", in: 0, f: 38 }, { t: "네", in: 0, f: 205 }, { t: "좋습니다", in: 0, f: 241 }, { t: "다음 주에 뵙겠습니다", in: 0, f: 281 },
  ];
  const msgEls = MSGS.map((m) => { const e = h("div", "msg " + (m.in ? "in" : "out"), m.t); list.appendChild(e); return e; });
  const plus = px(h("div", "plus", "+"), 14, 150, 34, 34); chat.appendChild(plus);
  const input = px(h("div", "input"), 226, 150, 350, 34); chat.appendChild(input);
  // 입력 스크립트: [문구, 타이핑 시작, 글자당 프레임, 전송 프레임]
  const TYPE = [["네, 확인했습니다", -16, 4, 38], ["네", 199, 3, 205], ["좋습니다", 226, 3, 241], ["다음 주에 뵙겠습니다", 258, 2, 281]];

  // 툴바 (창 아래쪽 = 띠 아래). '음소거 해제'는 티의 스틱맨 바로 아래
  const TB_Y = 706;
  const tMute = px(h("div", "tool"), 64, TB_Y, 128, 38); win.appendChild(tMute);
  const tCam = px(h("div", "tool", CAM("#8C8D89") + "비디오 시작"), 200, TB_Y, 128, 38); win.appendChild(tCam);
  const tShare = px(h("div", "tool", SHARE("#8C8D89") + "화면 공유"), 336, TB_Y, 116, 38); win.appendChild(tShare);
  const tLeave = px(h("div", "tool", "나가기"), 506, TB_Y, 84, 38); win.appendChild(tLeave);
  const MUTE_C = [WIN[0] + 64 + 64, WIN[1] + TB_Y + 19];   // 버튼 중심 (데스크탑)

  const dim = px(h("div"), 0, 0, DW, DH); dim.id = "dim"; desk.appendChild(dim);

  /* ── 게임층: 홀 판(실캡처) → 스윙 크롭(실캡처) → 벡터 스틱맨(실제 리그) → 궤적 → 공 → 커서 ── */
  const H = window.HOLES, RIG = window.RIG, TR = window.TRAIL;
  const SCHED = [[1, 0], [2, 170], [3, 190], [4, 214], [5, 234], [7, 254], [9, 276]];
  const XF = 4;
  const plates = {}, seqs = {};
  for (const [n] of SCHED) {
    if (H[n].seq) { seqs[n] = []; for (let k = 0; k < H[n].seq.n; k++) { const e = px(h("img", "plate"), 0, 600 + OFFY, DW, 480); e.src = `assets/gen/seq-${n}-${k}.png`; e.style.visibility = "hidden"; desk.appendChild(e); seqs[n].push(e); } }
    else { const e = px(h("img", "plate"), 0, 600 + OFFY, DW, 480); e.src = `assets/gen/hole-${n}.png`; e.style.opacity = 0; desk.appendChild(e); plates[n] = e; }
  }
  // 홀 하나의 띠 그림(판 또는 연번 클립의 해당 프레임)을 불투명도 o로 보인다
  function showHole(n, f, o) {
    if (seqs[n]) { const sq = H[n].seq, k = clamp(f - sq.f0, 0, sq.n - 1); seqs[n].forEach((e, i) => { e.style.visibility = i === k && o > 0.001 ? "visible" : "hidden"; }); seqs[n][k].style.opacity = o.toFixed(3); }
    else plates[n].style.opacity = o.toFixed(3);
  }
  const TEE_SHIFT = H[1].ground[153] - 859.6;   // 15초판 크롭(절벽 티 지면 859.6) → 1번 홀 티 지면
  const SWING = ["swing-top", "swing-down", "swing-impact", "swing-follow", "swing-finish"];
  const crops = SWING.map((n) => { const e = px(h("img", "crop"), 40, 716 + TEE_SHIFT + OFFY); e.src = `assets/gen/${n}.png`; e.style.visibility = "hidden"; desk.appendChild(e); return e; });
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg"); svg.id = "fx"; svg.setAttribute("width", DW); svg.setAttribute("height", DH); desk.appendChild(svg);
  const mk = (tag, a) => { const e = document.createElementNS(NS, tag); for (const k in a) e.setAttribute(k, a[k]); return e; };
  const trailEl = mk("polyline", { fill: "none", stroke: "#FFFFFF", "stroke-width": 2.3, "stroke-linecap": "round", "stroke-linejoin": "round" });
  svg.appendChild(trailEl);
  const ghosts = [1, 2, 3, 4, 5, 6].map(() => { const c = mk("circle", { fill: "#FFFFFF", r: 0, opacity: 0 }); svg.appendChild(c); return c; });
  const ripple = mk("circle", { fill: "none", stroke: "#EDEDE8", "stroke-width": 2, r: 0, opacity: 0 }); svg.appendChild(ripple);
  const mkMan = () => { const g = mk("g", {}); svg.appendChild(g); const Q = {
    trail: mk("path", { fill: "none", stroke: "rgba(255,255,255,.55)", "stroke-width": 5.5, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    body: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 6, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    shaft: mk("path", { fill: "none", stroke: "#E9E9E9", "stroke-width": 3, "stroke-linecap": "round" }),
    chead: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 13.6, "stroke-linecap": "round" }),
    grip: mk("path", { fill: "none", stroke: "#BDBDBD", "stroke-width": 4.6, "stroke-linecap": "round" }),
    head: mk("circle", { r: 10, fill: "#FFFFFF" }),
    hat: mk("path", { fill: "rgba(228,80,60,.95)" }),
  }; for (const k of ["trail", "body", "shaft", "chead", "grip", "head", "hat"]) g.appendChild(Q[k]); return { g, P: Q }; };
  const MEN = [mkMan(), mkMan()];
  const ballEl = h("div"); ballEl.id = "ball"; desk.appendChild(ballEl);
  const cursor = h("div"); cursor.innerHTML = `<svg viewBox="0 0 22 32" width="22" height="32"><path d="M2 2 L2 25 L7.6 19.8 L11.4 28.6 L15 27 L11.3 18.4 L18.8 18.4 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
  cursor.style.cssText = "position:absolute;left:0;top:0;width:22px;height:32px;transform-origin:2px 2px"; desk.appendChild(cursor);

  /* ── 화면 고정층: 자막 띠 · 엔드카드 ── */
  const CAP_Y = 150, CAP_H = 120;
  const cap = px(h("div", "cap"), 72, CAP_Y, 940, CAP_H); root.appendChild(cap);
  const CAPS = [
    { html: "회의 중입니다.", size: 88 },
    { html: "클릭은 아래 앱으로 간다.", size: 72 },
    { html: "회의 중에도 9홀.", size: 88 },
  ];
  const capEls = CAPS.map((c) => { const e = h("div", "line", c.html); e.style.fontSize = c.size + "px"; e.style.letterSpacing = (-0.035 * c.size) + "px"; e.style.lineHeight = CAP_H + "px"; cap.appendChild(e); return e; });
  const CAP_IN = [-99, 92, 306], CAP_OUT = [92, 160, 99999], SW_LEN = 7;
  // 플립 시계: 카드 4장(14 : mm) + 옆에 작게 홀 번호. 넘김은 2D만(위 반쪽 scaleY 1→0, 아래 반쪽 0→1)
  const CK = { y: 126, h: 176, cw: 104, ch: 168, gap: 10, font: 150 };
  const clockBox = px(h("div", "flipbox"), 72, CK.y, 760, CK.h); root.appendChild(clockBox);
  const clockIn = h("div", "flipin"); clockBox.appendChild(clockIn);
  const cardX = [0, CK.cw + CK.gap, 2 * (CK.cw + CK.gap) + 36, 3 * (CK.cw + CK.gap) + 36];
  const half = (top, cls) => { const e = px(h("div", "half " + cls), 0, top ? 0 : CK.ch / 2, CK.cw, CK.ch / 2); e.innerHTML = `<div class="dg" style="top:${top ? 0 : -CK.ch / 2}px;height:${CK.ch}px;line-height:${CK.ch}px;font-size:${CK.font}px"></div>`; return e; };
  const cards = cardX.map((x) => { const c = px(h("div", "card"), x, 0, CK.cw, CK.ch); const L = { topNew: half(true, ""), botOld: half(false, ""), flapTop: half(true, "flap ft"), flapBot: half(false, "flap fb") };
    for (const k of ["topNew", "botOld", "flapTop", "flapBot"]) c.appendChild(L[k]); c.appendChild(h("div", "split")); clockIn.appendChild(c); return L; });
  const colon = px(h("div", "colon", ":"), 2 * (CK.cw + CK.gap) - 4, 0, 40, CK.ch); colon.style.fontSize = CK.font * 0.8 + "px"; colon.style.lineHeight = CK.ch - 14 + "px"; clockIn.appendChild(colon);
  const holeTag = px(h("div", "holetag"), cardX[3] + CK.cw + 26, CK.ch - 62, 220, 56); clockIn.appendChild(holeTag);
  const TIMES = { 1: "1400", 2: "1407", 3: "1414", 4: "1421", 5: "1428", 7: "1437", 9: "1445" };
  const setDigit = (el, d) => { const g = el.firstChild; if (g.textContent !== d) g.textContent = d; };

  const E = { wm: 124, l1: 52, l2: 34, url: 31 };
  const end = px(h("div"), 72, 600); end.id = "end";
  end.innerHTML = `<div class="dash" style="width:76px;height:8px;margin:0 0 ${E.wm * 0.34}px 4px"></div>
    <div class="wm" style="font-size:${E.wm}px;letter-spacing:${-0.035 * E.wm}px;margin-bottom:${E.wm * 0.32}px">mini-golf</div>
    <div class="l1" style="font-size:${E.l1}px;letter-spacing:${-0.02 * E.l1}px">화면 맨 아래 띠에서.</div>
    <div class="l2" style="font-size:${E.l2}px;margin-top:${E.l2 * 0.9}px">macOS 메뉴바 앱 · 무료 · 오픈소스</div>
    <div class="url" style="font-size:${E.url}px;margin-top:${E.url * 0.8}px">github.com/w0uldy0udaestar/mini-golf</div>`;
  root.appendChild(end);

  /* ── 공 경로: 실제 드라이브 궤적의 아치(현에서 뜬 높이)를 새 현(티 → 페어웨이)에 옮긴다 ── */
  const F_IMP = 11, F_LAND = 84, APEX_Y = 318;   // 정점 y(데스크탑) = 참가자 격자 윗줄(278~438) 위
  const BS = [153.5, 851.5 + TEE_SHIFT + OFFY];
  const LX = 600, BE = [LX, H[1].ground[LX] + OFFY - 4.0];
  let PATH = null;
  function buildPath() {
    const R0 = TR.ball.f73, R1 = TR.ball.f184;
    const arch = TR.pts.map(([x, y]) => { const u = (x - R0[0]) / (R1[0] - R0[0]); return [u, y - (R0[1] + (R1[1] - R0[1]) * u)]; });
    arch.unshift([0, 0]); arch.push([1, 0]);
    const hAt = (u) => { for (let i = 1; i < arch.length; i++) if (arch[i][0] >= u) { const a = arch[i - 1], b = arch[i]; return lerp(a[1], b[1], (u - a[0]) / Math.max(1e-6, b[0] - a[0])); } return 0; };
    const lenR = Math.hypot(R1[0] - R0[0], R1[1] - R0[1]), lenN = Math.hypot(BE[0] - BS[0], BE[1] - BS[1]);
    let uA = 0, hA = 0; for (let i = 0; i <= 400; i++) { const v = hAt(i / 400); if (v < hA) { hA = v; uA = i / 400; } }
    const k = (lerp(BS[1], BE[1], uA) - APEX_Y) / -hA;    // 실제 궤적 아치 모양 그대로, 높이만 맞춘다
    PATH = []; for (let i = 0; i <= 400; i++) { const u = i / 400; PATH.push([lerp(BS[0], BE[0], u), lerp(BS[1], BE[1], u) + hAt(u) * k]); }
    // 시간 → 진행도: 속도 v(u) = 출발이 빠르고 착지로 갈수록 느린 기본형 × 정점 부근 램프(0.38배까지 느리게, 약 0.3초)
    const v = (u) => (1.3 - 0.6 * u) * (1 - 0.62 * Math.exp(-Math.pow((u - uA) / 0.055, 2)));
    const T = [0]; for (let i = 1; i <= 2000; i++) T.push(T[i - 1] + (1 / 2000) / v((i - 0.5) / 2000));
    const tot = T[2000]; UT = T.map((x) => x / tot);
  }
  let UT = null;
  buildPath();
  const pathAt = (u) => { const i = u * 400, a = Math.floor(clamp(i, 0, 399)), fr = i - a; return [lerp(PATH[a][0], PATH[a + 1][0], fr), lerp(PATH[a][1], PATH[a + 1][1], fr)]; };
  const flightU = (f) => { const tau = clamp((f - F_IMP) / (F_LAND - F_IMP)); let lo = 0, hi = 2000;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; UT[mid] < tau ? lo = mid : hi = mid; }
    const a = UT[lo], b = UT[hi]; return (lo + (b > a ? (tau - a) / (b - a) : 0)) / 2000; };

  /* ── 스틱맨 (실제 리그 → StickmanNode 렌더 규칙 그대로, 15초판과 같은 그리기) ── */
  // 홀별 리그 매핑: 1번 = 훅 그대로(RIG[f]), 3번 = RIG[f+40](절벽 티 실제 지면 위 걷기), 9번 = 미러 + 평행 이동(RIG[f-2])
  const MAN = { 1: { off: 0, C: 0 }, 3: { off: 40, C: 0 }, 4: { off: -39, C: -30 }, 9: { off: -2, C: 293 } };
  function drawMan(n, f, set) {
    const P = set.P;
    const M = MAN[n], Hn = H[n];
    const r = RIG[clamp(f + M.off, 0, RIG.length - 1)];
    const plX = Hn.mirror ? 1920 - r.x + M.C : r.x;
    const d = Hn.mirror ? -r.dir : r.dir;
    const gx = plX - Hn.sx, gy = Hn.ground[Math.round(clamp(plX, 0, 1919))] + 0.6 + OFFY;
    const T = (p) => [gx + p[0] * d, gy - p[1]];
    const [hip, sh, f1, f2, k1, k2, grip, ht, el, et] = r.pts.map(T);
    const ff = (p) => `${p[0].toFixed(2)} ${p[1].toFixed(2)}`;
    const ctl = [(sh[0] + hip[0]) / 2 - d * 0.8, (sh[1] + hip[1]) / 2];
    const arm = (a, e, b) => r.curved ? `M${ff(a)} Q${ff(e)} ${ff(b)}` : `M${ff(a)} L${ff(e)} L${ff(b)}`;
    P.body.setAttribute("d", `M${ff(sh)} Q${ff(ctl)} ${ff(hip)} M${ff(hip)} L${ff(k1)} L${ff(f1)} M${ff(hip)} L${ff(k2)} L${ff(f2)} ${arm(sh, el, grip)}`);
    P.trail.setAttribute("d", arm(sh, et, ht));
    const sp = Math.sin(r.phi), cp = Math.cos(r.phi);
    const tip = [grip[0] + sp * r.len * d, grip[1] + cp * r.len];
    const butt = [grip[0] - sp * r.butt * d, grip[1] - cp * r.butt];
    P.shaft.setAttribute("d", `M${ff(butt)} L${ff(tip)}`);
    P.grip.setAttribute("d", `M${ff(butt)} L${ff([grip[0] + sp * 8 * d, grip[1] + cp * 8])}`);
    const perp = [Math.cos(r.phi) * d, -Math.sin(r.phi)];
    const c = [tip[0] + perp[0] * 4.5, tip[1] + perp[1] * 4.5], half = (17 - 13.6) / 2;
    P.chead.setAttribute("d", `M${ff([c[0] - perp[0] * half, c[1] - perp[1] * half])} L${ff([c[0] + perp[0] * half, c[1] + perp[1] * half])}`);
    const hd = [sh[0] + d * r.head[0], sh[1] - r.head[1]];
    P.head.setAttribute("cx", hd[0].toFixed(2)); P.head.setAttribute("cy", hd[1].toFixed(2));
    const crown = [[-9, 7], [-9, 15], [-4.5, 10], [0, 16], [4.5, 10], [9, 15], [9, 7]];
    P.hat.setAttribute("d", "M" + crown.map(([x, y]) => ff([hd[0] + x * d, hd[1] - y])).join(" L") + " Z");
  }

  /* ── 카메라 (2D scale/translate만): 훅 ×2.1(스틱맨 발 (153,868)pt → 화면 (310,1395)px) → f13–46 공을 따라 ×1 풀백 ── */
  const M0 = 2.1, V0 = [153 - 310 / (S * M0), 868 - 1395 / (S * M0)];
  const camEase = (u) => { u = clamp(u); return u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2; };
  function camera(f) { const u = camEase(seg(f, 13, 46)); const m = Math.exp(Math.log(M0) * (1 - u)); return [m, lerp(V0[0], 0, u), lerp(V0[1], 0, u)]; }

  /* ── 커서 (데스크탑 좌표) ── */
  const CUR0 = [252, 598], F_MOVE = 88, F_ARRIVE = 114, F_PRESS = 118, F_REL = 122, CS = 1.5;
  function cursorAt(f) {
    const u = ease3(seg(f, F_MOVE, F_ARRIVE)), a = CUR0, b = [MUTE_C[0] + 2, MUTE_C[1] - 4];
    const bow = Math.sin(Math.PI * u) * 22;
    const nx = -(b[1] - a[1]), ny = b[0] - a[0], nl = Math.hypot(nx, ny);
    const press = f >= F_PRESS - 2 && f < F_REL ? 1 - 0.14 * smooth(seg(f, F_PRESS - 2, F_PRESS)) : (f >= F_REL && f < F_REL + 3 ? 1 - 0.14 * (1 - smooth(seg(f, F_REL, F_REL + 3))) : 1);
    return [lerp(a[0], b[0], u) + nx / nl * bow, lerp(a[1], b[1], u) + ny / nl * bow, press];
  }

  /* ── 상태 함수 ── */
  const holeAt = (f) => { let k = 0; for (let i = 0; i < SCHED.length; i++) if (f >= SCHED[i][1]) k = i; return k; };
  const minuteAt = (f) => f < 170 ? 0 : Math.min(45, Math.floor(45 * (f - 170) / 115));
  const typedAt = (f) => { // 입력란 글자(문구, 개수, 타이핑 중?)
    for (const [txt, f0, rate, fs] of TYPE) { const ch = [...txt]; if (f >= f0 && f < fs) { const n = Math.min(ch.length, Math.floor((f - f0) / rate) + 1); return [ch.slice(0, n).join(""), n < ch.length || f - (f0 + (ch.length - 1) * rate) < 6]; } }
    return ["", false];
  };

  const fontsOk = () => ["700 88px Pretendard", "800 124px Pretendard", "500 19px Pretendard", "500 31px JBM"].every((s) => document.fonts.check(s)) && document.fonts.status === "loaded";
  let lastHole = -1;
  function render(t) {
    const f = Math.round(t * FPS);
    // 카메라
    const [cm, vx, vy] = camera(f), sc = S * cm;
    desk.style.transform = `translate(${(-vx * sc).toFixed(3)}px,${(-vy * sc).toFixed(3)}px) scale(${sc.toFixed(5)})`;

    // 홀 (교차 4f) — 판 또는 연번 클립
    const k = holeAt(f), [n, fs] = SCHED[k];
    const u = k === 0 ? 1 : smooth((f - fs) / XF);
    const prevN = k > 0 && u < 1 ? SCHED[k - 1][0] : null;
    for (const [m] of SCHED) if (m !== n && m !== prevN) showHole(m, f, 0);
    showHole(n, f, u); if (prevN) showHole(prevN, f, 1 - u);
    // 메뉴바 시계 = 플립 시계와 같은 값(컷마다 넘어간다)
    const tm = TIMES[n];
    document.getElementById("clock").textContent = `${tm.slice(0, 2)}:${tm.slice(2)}`;
    // 스틱맨: 1번 홀 f0–20 실캡처 크롭 → 리그 / 3·4·9번 리그 / 2·5·7번은 연번 클립 속 실제 스틱맨
    const CROP_AT = [[0, 10, 0], [10, 11, 1], [11, 14, 2], [14, 18, 3], [18, 21, 4]];
    crops.forEach((e, i) => { const c = CROP_AT.find((r) => r[2] === i); e.style.visibility = f >= c[0] && f < c[1] ? "visible" : "hidden"; });
    const want = [];
    if (MAN[n] && !(n === 1 && f < 21)) want.push([n, u]);
    if (prevN && MAN[prevN]) want.push([prevN, 1 - u]);
    MEN.forEach((set, i) => { const w = want[i]; set.g.style.visibility = w ? "visible" : "hidden"; if (w) { drawMan(w[0], f, set); set.g.setAttribute("opacity", w[1].toFixed(3)); } });

    // 공 + 궤적 + 잔상 (1번 홀)
    const p1 = parseFloat(plates[1].style.opacity);
    ghosts.forEach((g) => g.setAttribute("opacity", 0));
    if (f >= F_IMP && p1 > 0.001) {
      const fu = flightU(f), nn = Math.max(2, Math.round(fu * 400));
      trailEl.setAttribute("points", PATH.slice(0, nn + 1).map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" "));
      trailEl.setAttribute("opacity", ((1 - smooth(seg(f, 128, 156))) * p1).toFixed(3));
      let [bx, by] = pathAt(fu);
      if (f > F_LAND) { const hop = seg(f, F_LAND, F_LAND + 9); by -= Math.sin(Math.PI * hop) * 7; bx += 9 * (1 - Math.pow(1 - seg(f, F_LAND, F_LAND + 22), 2)); by = Math.min(by, H[1].ground[Math.round(bx)] + OFFY - 5.5); }
      if (f > F_IMP && f <= F_LAND) ghosts.forEach((g, i) => { const [gx, gy] = pathAt(flightU(f - 0.7 * (i + 1)));   // 공 뒤 짧은 잔상(시간 함수)
        g.setAttribute("cx", gx.toFixed(2)); g.setAttribute("cy", gy.toFixed(2)); g.setAttribute("r", (5.5 * (1 - 0.1 * (i + 1))).toFixed(2)); g.setAttribute("opacity", (0.5 * (1 - (i + 1) / 7) * p1).toFixed(3)); });
      const dia = 11;
      ballEl.style.visibility = "visible"; ballEl.style.opacity = p1.toFixed(3);
      px(ballEl, bx - dia / 2, by - dia / 2, dia, dia);
    } else { ballEl.style.visibility = "hidden"; trailEl.setAttribute("points", ""); }

    // 커서 + 클릭
    const [cx, cy, cs] = cursorAt(f);
    cursor.style.transform = `translate(${cx.toFixed(2)}px,${cy.toFixed(2)}px) scale(${(cs * CS).toFixed(3)})`;
    cursor.style.opacity = (1 - smooth(seg(f, 150, 157))).toFixed(3);
    const rp = seg(f, F_PRESS, F_PRESS + 13);
    ripple.setAttribute("cx", MUTE_C[0].toFixed(1)); ripple.setAttribute("cy", MUTE_C[1].toFixed(1));
    ripple.setAttribute("r", (6 + 30 * (1 - Math.pow(1 - rp, 2))).toFixed(2)); ripple.setAttribute("opacity", f >= F_PRESS && f < F_PRESS + 13 ? (0.75 * (1 - rp)).toFixed(3) : 0);
    const on = f >= F_PRESS + 2;
    tMute.innerHTML = on ? MIC(true, "#C9CAC6") + "음소거" : MIC(false, "#C9CAC6") + "음소거 해제";
    tMute.style.background = f >= F_PRESS - 2 && f < F_REL + 3 ? "#34353B" : (f >= F_ARRIVE - 3 && f < 150 ? "#2A2B30" : "#22232A");
    tMute.style.color = "#C9CAC6";
    document.getElementById("selfmic").innerHTML = MIC(on, on ? "#B9BAB5" : "#77787A");
    document.getElementById("selfring").style.opacity = smooth(seg(f, F_PRESS + 2, F_PRESS + 8)).toFixed(3);

    // 채팅 목록 (아래 기준, 새 메시지는 6f 동안 한 줄 밀어 올린다)
    let c = 0; MSGS.forEach((m) => { c += smooth((f - m.f) / 6); });
    // 위로 밀려 나가는 줄은 목록 위 가장자리(y<4)에 닿기 전에 사라진다 — 잘린 말풍선 테두리가 남지 않게
    MSGS.forEach((m, i) => { const e = msgEls[i]; const y = LIST_H - 2 - (c - i) * PITCH; e.style.top = y.toFixed(2) + "px"; e.style.opacity = (smooth((f - m.f) / 6) * smooth((y - 0) / 8)).toFixed(3); });
    const [tx, typing] = typedAt(f);
    const lastSent = Math.max(...TYPE.map((r) => (f >= r[3] ? r[3] : -99)));
    const caretOn = tx ? (typing || Math.floor(f / 16) % 2 === 0) : (f - lastSent > 4 && Math.floor((f - lastSent) / 16) % 2 === 1 && f < 330);
    input.innerHTML = (tx ? tx : `<span class="ph">메시지 입력…</span>`.replace("<span class=\"ph\">", tx ? "" : "<span class=\"ph\">")) + (caretOn ? `<span class="caret"></span>` : "");
    if (!tx) input.innerHTML = (caretOn ? `<span class="caret" style="margin-left:0;margin-right:4px"></span>` : "") + `<span class="ph">메시지 입력…</span>`;

    // 자막 띠: 마스크 밀어 올리기 7f (들어올 때 아래→0, 나갈 때 0→위)
    const slotY = (f, fin, fout, H0) => f < fin ? H0 : f < fout ? H0 * (1 - smooth(seg(f, fin, fin + SW_LEN))) : -H0 * smooth(seg(f, fout, fout + SW_LEN));
    capEls.forEach((e, i) => { const y = slotY(f, CAP_IN[i], CAP_OUT[i], CAP_H); e.style.transform = `translateY(${y.toFixed(2)}px)`; e.style.visibility = Math.abs(y) >= CAP_H - 0.01 ? "hidden" : "visible"; });
    // 플립 시계: f160 들어오고 f306 나간다. 컷마다 바뀌는 자리만 6f 넘김(위 반쪽 3f 접힘 → 아래 반쪽 3f 펼침)
    const cy0 = slotY(f, 160, 306, CK.h);
    clockIn.style.transform = `translateY(${cy0.toFixed(2)}px)`; clockBox.style.visibility = Math.abs(cy0) >= CK.h - 0.01 ? "hidden" : "visible";
    const prevT = k > 0 ? TIMES[SCHED[k - 1][0]] : tm;
    cards.forEach((L, i) => {
      const nd = tm[i], od = prevT[i], flipping = nd !== od && f < fs + 6;
      const u1 = seg(f, fs, fs + 3), u2 = seg(f, fs + 3, fs + 6);
      setDigit(L.topNew, nd); setDigit(L.botOld, flipping ? od : nd); setDigit(L.flapTop, od); setDigit(L.flapBot, nd);
      L.flapTop.style.visibility = flipping && u1 < 1 ? "visible" : "hidden"; L.flapTop.style.transform = `scaleY(${(1 - smooth(u1)).toFixed(3)})`;
      L.flapBot.style.visibility = flipping && u1 >= 1 ? "visible" : "hidden"; L.flapBot.style.transform = `scaleY(${smooth(u2).toFixed(3)})`;
    });
    const tag = `${n}번 홀`; if (holeTag.textContent !== tag) holeTag.textContent = tag;
    holeTag.style.opacity = k > 0 ? smooth(seg(f, fs, fs + 4)).toFixed(3) : 1;

    // 엔드: 회의 창·메뉴바만 딤(띠는 밝게 남는다) → 엔드카드
    const dm = smooth(seg(f, 336, 354));
    dim.style.opacity = (0.86 * dm).toFixed(3);
    const ei = Sk((f - 344) / FPS, "calm");
    end.style.opacity = ei.toFixed(3); end.style.transform = `translateY(${(14 * (1 - ei)).toFixed(2)}px)`;
  }

  const tl = gsap.timeline({ paused: true, onUpdate: () => render(tl.time()) });
  tl.to({}, { duration: DUR }, 0);
  window.__timelines = window.__timelines || {};
  window.__timelines.main = tl;
  window.__render = render;

  // ?audit=1 : 3프레임 간격으로 '읽혀야 하는 것'의 화면 사각형을 모은다 (scripts/qa.py가 읽는다)
  function audit() {
    const out = { frames: [], fontsOk: fontsOk() };
    const vis = (e) => { let o = 1, nd = e; while (nd && nd !== document.body) { const cs = getComputedStyle(nd); if (cs.visibility === "hidden" || cs.display === "none") return 0; o *= parseFloat(cs.opacity); nd = nd.parentElement; } return o; };
    const R = (r) => [r.left, r.top, r.right, r.bottom].map((v) => Math.round(v));
    const textRects = (e) => { const o = []; const rg = document.createRange(); const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT); let nd;
      while ((nd = w.nextNode())) { if (!nd.textContent.trim()) continue; rg.selectNodeContents(nd); for (const r of rg.getClientRects()) o.push(R(r)); } return o; };
    const capBox = cap.getBoundingClientRect();
    for (let f = 0; f < NF; f += 3) {
      render(f / FPS); const fr = { f, items: [] };
      capEls.forEach((e) => { if (vis(e) > 0.05 && e.style.visibility !== "hidden") for (let r of textRects(e)) { r = [r[0], Math.max(r[1], capBox.top), r[2], Math.min(r[3], capBox.bottom)].map(Math.round); if (r[3] - r[1] > 8) fr.items.push({ name: "caption", r }); } });
      if (vis(end) > 0.05) for (const r of textRects(end)) fr.items.push({ name: "end", r });
      msgEls.forEach((e) => { if (vis(e) > 0.3) { const r = R(e.getBoundingClientRect()); const lb = list.getBoundingClientRect(); if (r[1] >= lb.top - 1 && r[3] <= lb.bottom + 1) fr.items.push({ name: "chat", r }); } });
      if (vis(input) > 0.05 && typedAt(f)[0]) fr.items.push({ name: "typing", r: R(input.getBoundingClientRect()) });
      MEN.forEach((m) => { if (m.g.style.visibility === "visible" && parseFloat(m.g.getAttribute("opacity")) > 0.3) fr.items.push({ name: "man", r: R(m.g.getBoundingClientRect()) }); });
      if (clockBox.style.visibility === "visible") { const cb = clockBox.getBoundingClientRect(); for (const c of clockIn.querySelectorAll(".card,.holetag")) { const r = c.getBoundingClientRect(); const rr = [r.left, Math.max(r.top, cb.top), r.right, Math.min(r.bottom, cb.bottom)].map(Math.round); if (rr[3] - rr[1] > 8) fr.items.push({ name: "clock", r: rr }); } }
      crops.forEach((e) => { if (e.style.visibility === "visible") fr.items.push({ name: "man", r: R(e.getBoundingClientRect()) }); });
      if (ballEl.style.visibility === "visible") fr.items.push({ name: "ball", r: R(ballEl.getBoundingClientRect()) });
      if (parseFloat(cursor.style.opacity) > 0.3) fr.items.push({ name: "cursor", r: R(cursor.getBoundingClientRect()) });
      fr.items.push({ name: "mute", r: R(tMute.getBoundingClientRect()) });
      out.frames.push(fr);
    }
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  document.fonts.ready.then(() => { if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); window.__ready = true; });
})();
