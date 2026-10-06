/* T3 「회의 중 9홀」 — 세로 1080×1920 · 30fps · 14.5초(435프레임) · 한국어. 소리 없이 완결. (3차: 색·모션 전면 교체)
 *
 * 모든 상태는 render(t)가 t(초)만 보고 계산한다(순수 함수). GSAP 타임라인은 재생 헤드 역할만. Math.random·Date·네트워크 없음.
 * 데스크탑(#desk)은 745×1103pt 세로 조각(+아래 베젤)을 ×(1080/745)로 본다. 게임 판 좌표 y + 23 = 데스크탑 y.
 * 색: 코발트 단색 바탕 · 라이트 모드 회의 창(흰 창, 파스텔 타일) · 띠의 선화는 흰색 100% 굵은 선 + 남색 케이싱 · 빨강은 깃발만.
 *
 * 비트 (프레임 @30fps) — 자세한 근거는 plan.md
 *   f0       훅: 카메라 ×2.1(스틱맨 키 ≈ 290px). 채팅 입력 "네, 확인…" 타이핑 중 + 스틱맨 백스윙 톱(실캡처). 자막 "회의 중입니다."(검정 띠)
 *   f11–13   임팩트 히트스톱 2f + 화면 흔들림(±8px, 6f 감쇠) + 줌 펀치(1.0→1.12, 3f → 9f 복귀)
 *   f16–48   공을 따라 ×1 풀백. 공은 참가자 격자를 넘어 높게(정점 0.3배속 램프, 잔상 6개) f86에 떨어진다
 *   f38      채팅 전송 "네, 확인했습니다"
 *   f92      자막(키네틱) "클릭은 / 아래 앱으로 간다."
 *   f88–122  커서가 스틱맨을 지나 띠 아래 회의 툴바 '음소거 해제'를 누른다(f118, 원형 파동 2겹)
 *   f160     플립 시계(흰 카드·검정 숫자) + 홀 번호
 *   f168–278 타임랩스: 컷마다 휩 팬(4f, 가로 블러)으로 띠가 넘어가고 시계가 넘어간다. 홀 1 → 2 → 3 → 4 → 5 → 7 → 9, 모든 컷이 움직인다
 *   f306     "회의 중에도 9홀." (키네틱)
 *   f336–    흰 엔드카드가 스틱맨 쪽에서 원형 마스크로 열린다. 띠는 아래에 남아 스틱맨이 계속 걷는다
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
  const eout = (u) => 1 - Math.pow(1 - clamp(u), 3);
  const seg = (f, a, b) => clamp((f - a) / (b - a));
  const SPR = { calm: [0.78, 2.7], pop: [0.52, 2.5] };
  const step = (t, z, fr) => { const w = 2 * Math.PI * fr, d = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(d * t) + z * w / d * Math.sin(d * t)); };
  const Sk = (t, n) => { if (t <= 0) return 0; const [z, fr] = SPR[n]; const D = 6 / (z * 2 * Math.PI * fr); return t >= D ? 1 : step(t, z, fr) / step(D, z, fr); };

  /* ── DOM ── */
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const px = (e, x, y, w, hh) => { e.style.left = x + "px"; e.style.top = y + "px"; if (w != null) e.style.width = w + "px"; if (hh != null) e.style.height = hh + "px"; return e; };
  const warm = h("div", null, ["400", "500", "600", "700", "800"].map((w) => `<span style="font-weight:${w}">가나다 1234 abc</span>`).join("") + `<span style="font-family:JBM;font-weight:500">github.com</span>`);
  warm.style.cssText = "position:absolute;left:0;top:0;visibility:hidden;white-space:nowrap;font-size:20px"; root.appendChild(warm);
  const DH2 = Math.ceil(1920 / S);
  const desk = px(h("div"), 0, 0, DW, DH2); desk.id = "desk"; root.appendChild(desk);
  const bezel = px(h("div"), 0, DH, DW, DH2 - DH); bezel.id = "bezel"; desk.appendChild(bezel);
  // 휩 팬용 가로 블러 필터
  const defs = h("div"); defs.innerHTML = `<svg width="0" height="0" style="position:absolute"><filter id="whip" x="-30%" y="-5%" width="160%" height="110%"><feGaussianBlur stdDeviation="18 0"/></filter></svg>`; root.appendChild(defs);

  const FLAG = `<svg viewBox="0 0 14 16"><line x1="3" y1="1" x2="3" y2="15" stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round"/><path d="M3.8 1.6 L12.5 4.4 L3.8 7.2 Z" fill="#E5483A"/></svg>`;
  desk.appendChild(h("div", "menubar", `<span class="app">회의</span><span>파일</span><span>편집</span><span>보기</span><span>창</span><span class="sp"></span>${FLAG}<span>화</span><span class="clock" id="clock">14:00</span>`));

  // 아이콘 (일반형 — 특정 앱 모양 아님)
  const MIC = (on, c) => `<svg viewBox="0 0 16 16"><rect x="5.5" y="1.5" width="5" height="8.5" rx="2.5" fill="none" stroke="${c}" stroke-width="1.6"/><path d="M3 7.5 a5 5 0 0 0 10 0 M8 12.5 V15" fill="none" stroke="${c}" stroke-width="1.6" stroke-linecap="round"/>${on ? "" : `<line x1="2" y1="14.5" x2="14" y2="1.5" stroke="${c}" stroke-width="1.7" stroke-linecap="round"/>`}</svg>`;
  const CAM = (c) => `<svg viewBox="0 0 16 16"><rect x="1.5" y="4" width="9" height="8" rx="2" fill="none" stroke="${c}" stroke-width="1.6"/><path d="M10.5 7 L14.5 4.8 V11.2 L10.5 9 Z" fill="none" stroke="${c}" stroke-width="1.6" stroke-linejoin="round"/><line x1="1.5" y1="14.5" x2="14.5" y2="1.5" stroke="${c}" stroke-width="1.7" stroke-linecap="round"/></svg>`;
  const SHARE = (c) => `<svg viewBox="0 0 16 16"><rect x="1.5" y="2.5" width="13" height="9" rx="1.5" fill="none" stroke="${c}" stroke-width="1.6"/><path d="M8 9.5 V5 M5.8 7 L8 4.8 L10.2 7" fill="none" stroke="${c}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><line x1="5" y1="14.2" x2="11" y2="14.2" stroke="${c}" stroke-width="1.6" stroke-linecap="round"/></svg>`;
  const SIL = (w) => `<svg class="sil" width="${w}" height="${w}" viewBox="0 0 100 100"><circle cx="50" cy="36" r="19" fill="rgba(20,30,70,.16)"/><path d="M14 98 C14 70 30 60 50 60 C70 60 86 70 86 98 Z" fill="rgba(20,30,70,.16)"/></svg>`;
  const INK = "#1A1C22";

  /* ── 회의 창 (라이트 모드). 창은 띠 위에서 끝나고(스틱맨은 코발트 바탕 위에 선다), 회의 툴바는 띠 아래에 떠 있다 ── */
  const WIN = [22, 270, 606, 490];
  const win = px(h("div", "win"), ...WIN); desk.appendChild(win);
  win.appendChild(h("div", "bar", `<i></i><i></i><i></i><div class="t">주간 회의</div>`));
  const TW = 291, TH = 137, TG = 8, PASTEL = ["#FFE7A3", "#C6F1D6", "#DCD3FF", "#CBE4FF"];
  for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) {
    const t = px(h("div", "tile"), 8 + i * (TW + TG), 38 + j * (TH + TG), TW, TH); t.style.background = PASTEL[j * 2 + i];
    const self = i === 1 && j === 1, talk = i === 0 && j === 0;
    t.innerHTML = SIL(104) + `<div class="tag">${self ? `<span id="selfmic">${MIC(false, INK)}</span><span>나</span>` : MIC(talk, INK)}</div><div class="ring" ${self ? 'id="selfring"' : talk ? 'style="opacity:.5"' : ""}></div>`;
    win.appendChild(t);
  }
  const CH = [8, 328, 590, 156];
  const chat = px(h("div", "chat"), ...CH); win.appendChild(chat);
  chat.appendChild(h("div", "hd", "채팅"));
  const LIST_TOP = 20, PITCH = 30, LIST_H = 96;
  const list = px(h("div", "list"), 0, LIST_TOP, null, LIST_H); chat.appendChild(list);
  const MSGS = [
    { t: "자료 공유드렸습니다", in: 1, f: -999 }, { t: "확인 부탁드려요", in: 1, f: -999 },
    { t: "네, 확인했습니다", in: 0, f: 38 }, { t: "네", in: 0, f: 205 }, { t: "좋습니다", in: 0, f: 241 }, { t: "다음 주에 뵙겠습니다", in: 0, f: 281 },
  ];
  const msgEls = MSGS.map((m) => { const e = h("div", "msg " + (m.in ? "in" : "out"), m.t); list.appendChild(e); return e; });
  chat.appendChild(px(h("div", "plus", "+"), 14, 118, 34, 34));
  const input = px(h("div", "input"), 226, 118, 350, 34); chat.appendChild(input);
  const TYPE = [["네, 확인했습니다", -16, 4, 38], ["네", 199, 3, 205], ["좋습니다", 226, 3, 241], ["다음 주에 뵙겠습니다", 258, 2, 281]];

  // 떠 있는 회의 툴바(띠 아래). '음소거 해제'는 티의 스틱맨 바로 아래
  const TB = [60, 940, 530, 50];
  const bar = px(h("div", "tbar"), ...TB); desk.appendChild(bar);
  const tMute = px(h("div", "tool"), 26, 6, 128, 38); bar.appendChild(tMute);
  bar.appendChild(px(h("div", "tool", CAM("#FFFFFF") + "비디오 시작"), 162, 6, 128, 38));
  bar.appendChild(px(h("div", "tool", SHARE("#FFFFFF") + "화면 공유"), 298, 6, 116, 38));
  bar.appendChild(px(h("div", "tool leave", "나가기"), 432, 6, 84, 38));
  const MUTE_C = [TB[0] + 90, TB[1] + 25];

  /* ── 게임층 ── */
  const H = window.HOLES, RIG = window.RIG, TR = window.TRAIL;
  const SCHED = [[1, 0], [2, 170], [3, 190], [4, 214], [5, 234], [7, 254], [9, 276]];
  const CUTS = SCHED.slice(1).map((s) => s[1]);
  const NAVY = "#0B1E6B";
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg"); svg.id = "fx"; svg.setAttribute("width", DW); svg.setAttribute("height", DH); desk.appendChild(svg);
  const mk = (tag, a) => { const e = document.createElementNS(NS, tag); for (const k in a) e.setAttribute(k, a[k]); return e; };
  // 홀 지형 = 게임 코스 생성기 표고의 벡터 (캡처 비트맵 없음): 물 → 러프 틱 → 지형선 → 그린 → 나무 → 깃발 → HUD 글자. 흰 선 + 남색 케이싱
  const holeG = {};
  const pl = (pts) => pts.map((q, i) => (i ? "L" : "M") + q[0].toFixed(2) + " " + (q[1] + OFFY).toFixed(2)).join(" ");
  for (const [n] of SCHED) {
    const Hn = H[n], g = mk("g", {}); g.style.visibility = "hidden"; svg.appendChild(g); holeG[n] = g;
    for (const w of Hn.water) { const d = pl(w.pts) + ` L${w.pts[w.pts.length - 1][0]} ${w.lvl + OFFY} L${w.pts[0][0]} ${w.lvl + OFFY} Z`;
      g.appendChild(mk("path", { d, fill: "rgba(255,255,255,.28)", stroke: "none" }));
      g.appendChild(mk("path", { d: `M${w.pts[0][0]} ${w.lvl + OFFY} L${w.pts[w.pts.length - 1][0]} ${w.lvl + OFFY}`, stroke: "#FFFFFF", "stroke-width": 2, "stroke-dasharray": "6 5", fill: "none" })); }
    const tk = Hn.ticks.map(([x, y, l]) => `M${x.toFixed(2)} ${(y + OFFY - 1).toFixed(2)} L${(x + (l ? 1.6 : -1.6)).toFixed(2)} ${(y + OFFY - 6).toFixed(2)}`).join(" ");
    const line = pl(Hn.line);
    g.appendChild(mk("path", { d: tk, stroke: NAVY, "stroke-width": 4.2, "stroke-linecap": "round", fill: "none" }));
    g.appendChild(mk("path", { d: line, stroke: NAVY, "stroke-width": 7.4, "stroke-linecap": "round", "stroke-linejoin": "round", fill: "none" }));
    g.appendChild(mk("path", { d: tk, stroke: "#FFFFFF", "stroke-width": 1.8, "stroke-linecap": "round", fill: "none" }));
    g.appendChild(mk("path", { d: line, stroke: "#FFFFFF", "stroke-width": 3.4, "stroke-linecap": "round", "stroke-linejoin": "round", fill: "none" }));
    if (Hn.green.length) { const gd = pl(Hn.green.map(([x, y]) => [x, y - 0.6]));
      g.appendChild(mk("path", { d: gd, stroke: NAVY, "stroke-width": 10, "stroke-linecap": "round", fill: "none" }));
      g.appendChild(mk("path", { d: gd, stroke: "#FFFFFF", "stroke-width": 6, "stroke-linecap": "round", fill: "none" })); }
    for (const [x, gy, cy, sz] of Hn.trees) { const r = Math.max(9, sz * 0.5);
      g.appendChild(mk("line", { x1: x, y1: gy + OFFY, x2: x, y2: cy + OFFY + r * 0.4, stroke: NAVY, "stroke-width": 7.5, "stroke-linecap": "round" }));
      g.appendChild(mk("line", { x1: x, y1: gy + OFFY, x2: x, y2: cy + OFFY + r * 0.4, stroke: "#FFFFFF", "stroke-width": 3.6, "stroke-linecap": "round" }));
      g.appendChild(mk("circle", { cx: x, cy: cy + OFFY, r, fill: "rgba(255,255,255,.22)", stroke: "#FFFFFF", "stroke-width": 3, "paint-order": "stroke" })); }
    if (Hn.flag) { const [fx, fy] = Hn.flag, y0 = fy + OFFY;
      g.appendChild(mk("line", { x1: fx, y1: y0, x2: fx, y2: y0 - 34, stroke: NAVY, "stroke-width": 5.4, "stroke-linecap": "round" }));
      g.appendChild(mk("line", { x1: fx, y1: y0, x2: fx, y2: y0 - 34, stroke: "#FFFFFF", "stroke-width": 2.4, "stroke-linecap": "round" }));
      g.appendChild(mk("path", { d: `M${fx + 1.2} ${y0 - 34} L${fx + 19} ${y0 - 28} L${fx + 1.2} ${y0 - 22} Z`, fill: "#E5483A", stroke: NAVY, "stroke-width": 1.2, "stroke-linejoin": "round" })); }
    // HUD (게임 화면 아래 줄): 왼쪽 클럽, 오른쪽 홀 — 게임과 같은 자리(화면 가장자리 기준), 실제 값
    const hudY = 1046 + OFFY;
    if (!Hn.mirror && !Hn.seq) { const t1 = mk("text", { x: 14, y: hudY, class: "hud b" }); t1.textContent = "드라이버"; g.appendChild(t1);
      const t2 = mk("text", { x: 14, y: hudY + 17, class: "hud s" }); t2.textContent = "우드"; g.appendChild(t2); }
    const t3 = mk("text", { x: DW - 14, y: hudY, class: "hud b", "text-anchor": "end" }); t3.textContent = Hn.hud; g.appendChild(t3);
    const t4 = mk("text", { x: DW - 14, y: hudY + 17, class: "hud s", "text-anchor": "end" }); t4.textContent = "타수 0 · 합계 E"; g.appendChild(t4);
  }
  function showHole(n, vis, dx, blur) { const g = holeG[n]; g.style.visibility = vis ? "visible" : "hidden"; if (vis) { g.setAttribute("transform", dx ? `translate(${dx.toFixed(2)} 0)` : ""); g.setAttribute("filter", blur ? "url(#whip)" : ""); } }
  const trailCase = mk("polyline", { fill: "none", stroke: NAVY, "stroke-width": 6.2, "stroke-linecap": "round", "stroke-linejoin": "round" }); svg.appendChild(trailCase);
  const trailEl = mk("polyline", { fill: "none", stroke: "#FFFFFF", "stroke-width": 3.2, "stroke-linecap": "round", "stroke-linejoin": "round" }); svg.appendChild(trailEl);
  const ghosts = [1, 2, 3, 4, 5, 6].map(() => { const c = mk("circle", { fill: "#FFFFFF", stroke: NAVY, "stroke-width": 1.4, r: 0, opacity: 0 }); svg.appendChild(c); return c; });
  const ripples = [0, 1].map(() => { const c = mk("circle", { fill: "none", stroke: "#FFFFFF", "stroke-width": 3, r: 0, opacity: 0 }); svg.appendChild(c); return c; });
  const mkMan = () => { const g = mk("g", {}); svg.appendChild(g); const Q = {
    ctrail: mk("path", { fill: "none", stroke: "rgba(11,30,107,.45)", "stroke-width": 9, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    trail: mk("path", { fill: "none", stroke: "rgba(255,255,255,.7)", "stroke-width": 5.5, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    cbody: mk("path", { fill: "none", stroke: NAVY, "stroke-width": 11.5, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    cshaft: mk("path", { fill: "none", stroke: NAVY, "stroke-width": 7.6, "stroke-linecap": "round" }),
    cchead: mk("path", { fill: "none", stroke: NAVY, "stroke-width": 18, "stroke-linecap": "round" }),
    chead: mk("circle", { r: 12.6, fill: NAVY }),
    body: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 7, "stroke-linecap": "round", "stroke-linejoin": "round" }),
    shaft: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 3.6, "stroke-linecap": "round" }),
    chead2: mk("path", { fill: "none", stroke: "#FFFFFF", "stroke-width": 13.6, "stroke-linecap": "round" }),
    grip: mk("path", { fill: "none", stroke: "#DCDCDC", "stroke-width": 4.8, "stroke-linecap": "round" }),
    head: mk("circle", { r: 10.4, fill: "#FFFFFF" }),
    hat: mk("path", { fill: "#FFFFFF", stroke: NAVY, "stroke-width": 1.6, "stroke-linejoin": "round" }),
  }; for (const k of ["ctrail", "trail", "cbody", "cshaft", "cchead", "chead", "body", "shaft", "chead2", "grip", "head", "hat"]) g.appendChild(Q[k]); return { g, P: Q }; };
  const MEN = [mkMan(), mkMan()];
  const ballEl = h("div"); ballEl.id = "ball"; desk.appendChild(ballEl);
  const BALLS = [0, 1].map(() => { const e = h("div", "ball2"); e.style.visibility = "hidden"; desk.appendChild(e); return e; });
  const cursor = h("div"); cursor.innerHTML = `<svg viewBox="0 0 22 32" width="22" height="32"><path d="M2 2 L2 25 L7.6 19.8 L11.4 28.6 L15 27 L11.3 18.4 L18.8 18.4 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
  cursor.style.cssText = "position:absolute;left:0;top:0;width:22px;height:32px;transform-origin:2px 2px"; desk.appendChild(cursor);

  /* ── 화면 고정층: 엔드카드(원형 마스크) → 자막(검정 띠 키네틱) · 플립 시계 ── */
  const END_H = 1170, END_C = [420, 1170];
  const endLayer = px(h("div"), 0, 0, 1080, END_H); endLayer.id = "endlayer"; root.appendChild(endLayer);
  const E = { wm: 132, l1: 58, l2: 36, url: 34 };
  const endItems = [
    px(h("div", "dash"), 72, 470, 84, 10),
    px(h("div", "wm", "mini-golf"), 72, 516),
    px(h("div", "l1", "화면 맨 아래 띠에서."), 72, 682),
    px(h("div", "l2", "macOS 메뉴바 앱 · 무료 · 오픈소스"), 72, 784),
    px(h("div", "url", "github.com/w0uldy0udaestar/mini-golf"), 72, 846),
  ];
  endItems[1].style.fontSize = E.wm + "px"; endItems[1].style.letterSpacing = (-0.035 * E.wm) + "px";
  endItems[2].style.fontSize = E.l1 + "px"; endItems[2].style.letterSpacing = (-0.02 * E.l1) + "px";
  endItems[3].style.fontSize = E.l2 + "px"; endItems[4].style.fontSize = E.url + "px";
  endItems.forEach((e) => endLayer.appendChild(e));

  // 자막: 줄마다 검정 띠 + 흰 글자. 띠가 왼쪽에서 펼쳐지고 글자가 날아들어 멈춘다(스프링), 나갈 때는 오른쪽으로 접힌다
  const CAPS = [
    { lines: ["회의 중입니다."], size: 120, y: 104, fin: -99, fout: 92 },
    { lines: ["클릭은", "아래 앱으로 간다."], size: 110, y: 92, fin: 98, fout: 160 },
    { lines: ["회의 중에도 9홀."], size: 112, y: 104, fin: 312, fout: 99999 },
  ];
  const capLines = [];
  CAPS.forEach((c, ci) => c.lines.forEach((t, li) => {
    const lh = Math.round(c.size * 1.2), wrap = px(h("div", "capline"), 72, c.y + li * (lh + 12), null, lh);
    wrap.innerHTML = `<div class="band"></div><div class="txt" style="font-size:${c.size}px;letter-spacing:${-0.035 * c.size}px;line-height:${lh}px">${t}</div>`;
    root.appendChild(wrap); capLines.push({ ci, li, wrap, band: wrap.firstChild, txt: wrap.lastChild, LH: lh, BW: null });
  }));

  // 플립 시계: 흰 카드·검정 숫자. 넘김은 2D만(위 반쪽 scaleY 1→0, 아래 반쪽 0→1)
  const CK = { y: 104, h: 196, cw: 108, ch: 172, gap: 10, font: 150 };
  const clockBox = px(h("div", "flipbox"), 72, CK.y, 800, CK.h); root.appendChild(clockBox);
  const clockIn = h("div", "flipin"); clockBox.appendChild(clockIn);
  const cardX = [0, CK.cw + CK.gap, 2 * (CK.cw + CK.gap) + 36, 3 * (CK.cw + CK.gap) + 36];
  const half = (top, cls) => { const e = px(h("div", "half " + cls), 0, top ? 0 : CK.ch / 2, CK.cw, CK.ch / 2); e.innerHTML = `<div class="dg" style="top:${top ? 0 : -CK.ch / 2}px;height:${CK.ch}px;line-height:${CK.ch}px;font-size:${CK.font}px"></div>`; return e; };
  const cards = cardX.map((x) => { const c = px(h("div", "card"), x, 0, CK.cw, CK.ch); const L = { topNew: half(true, ""), botOld: half(false, ""), flapTop: half(true, "flap ft"), flapBot: half(false, "flap fb") };
    for (const k of ["topNew", "botOld", "flapTop", "flapBot"]) c.appendChild(L[k]); c.appendChild(h("div", "split")); clockIn.appendChild(c); return L; });
  const colon = px(h("div", "colon", ":"), 2 * (CK.cw + CK.gap) - 4, 0, 40, CK.ch); colon.style.fontSize = CK.font * 0.8 + "px"; colon.style.lineHeight = CK.ch - 14 + "px"; clockIn.appendChild(colon);
  const holeTag = px(h("div", "holetag"), cardX[3] + CK.cw + 26, CK.ch - 62, 220, 56); clockIn.appendChild(holeTag);
  const TIMES = { 1: "1400", 2: "1407", 3: "1414", 4: "1421", 5: "1428", 7: "1437", 9: "1445" };
  const setDigit = (el, d) => { const g = el.firstChild; if (g.textContent !== d) g.textContent = d; };

  /* ── 공 경로: 실제 드라이브 궤적의 아치 모양 그대로, 정점이 참가자 격자 윗줄 위를 지나게 ── */
  const F_IMP = 11, F_LAND = 84, APEX_Y = 330;     // F_* 는 '행동 시각'(히트스톱 2f 뒤로 밀린 시계) 기준
  const BS = [153.5, H[1].ground[153] + OFFY - 8.1];   // 티 위 공 중심 = 지면 + 8.1pt (공 반지름 + 티 페그, 실캡처와 같다)
  const LX = 600, BE = [LX, H[1].ground[LX] + OFFY - 5.5];
  let PATH = null, UT = null;
  (function buildPath() {
    const R0 = TR.ball.f73, R1 = TR.ball.f184;
    const arch = TR.pts.map(([x, y]) => { const u = (x - R0[0]) / (R1[0] - R0[0]); return [u, y - (R0[1] + (R1[1] - R0[1]) * u)]; });
    arch.unshift([0, 0]); arch.push([1, 0]);
    const hAt = (u) => { for (let i = 1; i < arch.length; i++) if (arch[i][0] >= u) { const a = arch[i - 1], b = arch[i]; return lerp(a[1], b[1], (u - a[0]) / Math.max(1e-6, b[0] - a[0])); } return 0; };
    let uA = 0, hA = 0; for (let i = 0; i <= 400; i++) { const v = hAt(i / 400); if (v < hA) { hA = v; uA = i / 400; } }
    const k = (lerp(BS[1], BE[1], uA) - APEX_Y) / -hA;
    PATH = []; for (let i = 0; i <= 400; i++) { const u = i / 400; PATH.push([lerp(BS[0], BE[0], u), lerp(BS[1], BE[1], u) + hAt(u) * k]); }
    const v = (u) => (1.3 - 0.6 * u) * (1 - 0.7 * Math.exp(-Math.pow((u - uA) / 0.055, 2)));   // 정점에서 0.3배속
    const T = [0]; for (let i = 1; i <= 2000; i++) T.push(T[i - 1] + (1 / 2000) / v((i - 0.5) / 2000));
    UT = T.map((x) => x / T[2000]);
  })();
  const pathAt = (u) => { const i = u * 400, a = Math.floor(clamp(i, 0, 399)), fr = i - a; return [lerp(PATH[a][0], PATH[a + 1][0], fr), lerp(PATH[a][1], PATH[a + 1][1], fr)]; };
  const flightU = (fa) => { const tau = clamp((fa - F_IMP) / (F_LAND - F_IMP)); let lo = 0, hi = 2000;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; UT[mid] < tau ? lo = mid : hi = mid; }
    const a = UT[lo], b = UT[hi]; return (lo + (b > a ? (tau - a) / (b - a) : 0)) / 2000; };

  /* ── 스틱맨 (실제 리그 → StickmanNode 렌더 규칙 그대로, 흰 선 + 남색 케이싱) ── */
  const MAN = { 1: { off: 0, C: 0 }, 3: { off: 40, C: 0 }, 4: { off: -39, C: -30 }, 9: { off: -2, C: 293 } };
  function drawMan(n, fr0, set) {
    const P = set.P, Hn = H[n];
    let r, plX, d;
    if (Hn.seq) { r = Hn.seq.rig[clamp(fr0 - Hn.seq.f0, 0, Hn.seq.n - 1)]; plX = r.x; d = r.dir; }   // 30초판 실캡처 때 받은 60Hz 리그
    else { const M = MAN[n]; r = RIG[clamp(fr0 + M.off, 0, RIG.length - 1)]; plX = Hn.mirror ? 1920 - r.x + M.C : r.x; d = Hn.mirror ? -r.dir : r.dir; }
    const gx = plX - Hn.sx, gy = Hn.ground[Math.round(clamp(plX, 0, 1919))] + 0.6 + OFFY;
    const T = (p) => [gx + p[0] * d, gy - p[1]];
    const [hip, sh, f1, f2, k1, k2, grip, ht, el, et] = r.pts.map(T);
    const ff = (p) => `${p[0].toFixed(2)} ${p[1].toFixed(2)}`;
    const ctl = [(sh[0] + hip[0]) / 2 - d * 0.8, (sh[1] + hip[1]) / 2];
    const arm = (a, e, b) => r.curved ? `M${ff(a)} Q${ff(e)} ${ff(b)}` : `M${ff(a)} L${ff(e)} L${ff(b)}`;
    const body = `M${ff(sh)} Q${ff(ctl)} ${ff(hip)} M${ff(hip)} L${ff(k1)} L${ff(f1)} M${ff(hip)} L${ff(k2)} L${ff(f2)} ${arm(sh, el, grip)}`;
    P.body.setAttribute("d", body); P.cbody.setAttribute("d", body);
    P.trail.setAttribute("d", arm(sh, et, ht)); P.ctrail.setAttribute("d", arm(sh, et, ht));
    const sp = Math.sin(r.phi), cp = Math.cos(r.phi);
    const tip = [grip[0] + sp * r.len * d, grip[1] + cp * r.len];
    const butt = [grip[0] - sp * r.butt * d, grip[1] - cp * r.butt];
    P.shaft.setAttribute("d", `M${ff(butt)} L${ff(tip)}`); P.cshaft.setAttribute("d", `M${ff(butt)} L${ff(tip)}`);
    P.grip.setAttribute("d", `M${ff(butt)} L${ff([grip[0] + sp * 8 * d, grip[1] + cp * 8])}`);
    const perp = [Math.cos(r.phi) * d, -Math.sin(r.phi)];
    const c = [tip[0] + perp[0] * 4.5, tip[1] + perp[1] * 4.5], hf = (17 - 13.6) / 2;
    const ch = `M${ff([c[0] - perp[0] * hf, c[1] - perp[1] * hf])} L${ff([c[0] + perp[0] * hf, c[1] + perp[1] * hf])}`;
    P.chead2.setAttribute("d", ch); P.cchead.setAttribute("d", ch);
    const hd = [sh[0] + d * r.head[0], sh[1] - r.head[1]];
    for (const e of [P.head, P.chead]) { e.setAttribute("cx", hd[0].toFixed(2)); e.setAttribute("cy", hd[1].toFixed(2)); }
    const crown = [[-9, 7], [-9, 15], [-4.5, 10], [0, 16], [4.5, 10], [9, 15], [9, 7]];
    P.hat.setAttribute("d", "M" + crown.map(([x, y]) => ff([hd[0] + x * d, hd[1] - y])).join(" L") + " Z");
  }

  /* ── 카메라 (2D scale/translate만) ── */
  const M0 = 2.1, FX = 250, V0 = [153 - FX / (S * M0), 868 - 1395 / (S * M0)];
  function camera(f) {
    const u = ease3(seg(f, 14, 70)); const m = Math.exp(Math.log(M0) * (1 - u));
    let vx = lerp(V0[0], 0, u), vy = lerp(V0[1], 0, u), sc = S * m;
    let tx = -vx * sc, ty = -vy * sc;
    // 임팩트 줌 펀치: f11 1.00 → f13 1.12 (3f) → f22 1.00, 스틱맨 발(화면 310,1395) 기준
    const k = f < 13 ? 1 + 0.12 * smooth(seg(f, 11, 13)) : 1 + 0.12 * (1 - smooth(seg(f, 13, 22)));
    tx = FX + k * (tx - FX); ty = 1395 + k * (ty - 1395); sc *= k;
    // 화면 흔들림: f11–16, ±8px 감쇠 (정해진 값 — 난수 없음)
    const SH = { 11: [8, -5], 12: [-7, 4], 13: [5, -3], 14: [-3, 2], 15: [2, -1], 16: [-1, 0] };
    if (SH[f]) { tx += SH[f][0]; ty += SH[f][1]; }
    return [tx, ty, sc];
  }
  const actionF = (f) => f < 11 ? f : f < 13 ? 11 : f - 2;   // 히트스톱: 임팩트 프레임을 2f 더 붙든다

  /* ── 커서 (데스크탑 좌표) ── */
  const CUR0 = [252, 600], F_MOVE = 88, F_ARRIVE = 114, F_PRESS = 118, F_REL = 122, CS = 1.5;
  function cursorAt(f) {
    const u = ease3(seg(f, F_MOVE, F_ARRIVE)), a = CUR0, b = [MUTE_C[0] + 2, MUTE_C[1] - 4];
    const bow = Math.sin(Math.PI * u) * 22;
    const nx = -(b[1] - a[1]), ny = b[0] - a[0], nl = Math.hypot(nx, ny);
    const press = f >= F_PRESS - 2 && f < F_REL ? 1 - 0.14 * smooth(seg(f, F_PRESS - 2, F_PRESS)) : (f >= F_REL && f < F_REL + 3 ? 1 - 0.14 * (1 - smooth(seg(f, F_REL, F_REL + 3))) : 1);
    return [lerp(a[0], b[0], u) + nx / nl * bow, lerp(a[1], b[1], u) + ny / nl * bow, press];
  }

  /* ── 상태 함수 ── */
  const holeAt = (f) => { let k = 0; for (let i = 0; i < SCHED.length; i++) if (f >= SCHED[i][1]) k = i; return k; };
  const typedAt = (f) => {
    for (const [txt, f0, rate, fs] of TYPE) { const ch = [...txt]; if (f >= f0 && f < fs) { const n = Math.min(ch.length, Math.floor((f - f0) / rate) + 1); return [ch.slice(0, n).join(""), n < ch.length || f - (f0 + (ch.length - 1) * rate) < 6]; } }
    return ["", false];
  };
  // 띠 상태: 휩 팬 구간(컷 c의 [c-2, c+2))에서는 나가는 홀이 왼쪽으로, 들어오는 홀이 오른쪽에서 4f 동안 밀려온다
  function stripAt(f) {
    for (const c of CUTS) if (f >= c - 2 && f < c + 2) {
      const i = SCHED.findIndex((s) => s[1] === c), w = ease3((f - (c - 2) + 1) / 5);
      return [[SCHED[i - 1][0], -DW * w, true], [SCHED[i][0], DW * (1 - w), true]];
    }
    return [[SCHED[holeAt(f)][0], 0, false]];
  }

  const fontsOk = () => ["800 120px Pretendard", "800 132px Pretendard", "700 58px Pretendard", "500 18px Pretendard", "500 34px JBM"].every((s) => document.fonts.check(s)) && document.fonts.status === "loaded";
  function render(t) {
    const f = Math.round(t * FPS), fa = actionF(f);
    const [tx, ty, sc] = camera(f);
    desk.style.transform = `translate(${tx.toFixed(3)}px,${ty.toFixed(3)}px) scale(${sc.toFixed(5)})`;

    // 띠: 홀 벡터 + 휩 팬
    const k = holeAt(f), [n, fs] = SCHED[k];
    const st = stripAt(f), shown = new Set(st.map((s) => s[0]));
    for (const [m] of SCHED) if (!shown.has(m)) showHole(m, false, 0, false);
    st.forEach(([m, dx, blur]) => showHole(m, true, dx, blur));
    const tm = TIMES[n];
    document.getElementById("clock").textContent = `${tm.slice(0, 2)}:${tm.slice(2)}`;

    // 스틱맨: 전부 실제 리그 벡터 — 1번(훅, 히트스톱 포함)·3·4·9번 = 15초판 hero-drive 리그, 2·5·7번 = 30초판 캡처 리그
    const want = st;
    MEN.forEach((set, i) => { const w = want[i]; set.g.style.visibility = w ? "visible" : "hidden";
      if (w) { drawMan(w[0], w[0] === 1 ? fa : f, set); set.g.setAttribute("transform", w[1] ? `translate(${w[1].toFixed(2)} 0)` : ""); set.g.setAttribute("filter", w[2] ? "url(#whip)" : ""); } });
    // 2·5·7번 컷의 공 (코드 근사: 로그의 샷·컵인 시각에 맞춘다) — 티/러프 위 → 샷에 출발, 7번은 퍼트로 굴러 컵에 든다
    BALLS.forEach((b) => { b.style.visibility = "hidden"; });
    st.forEach(([m, dx], i) => { const Hm = H[m]; if (!Hm.seq || !Hm.seq.shotF) return; const sq = Hm.seq, r0 = sq.rig[0], d = r0.dir, b = BALLS[i];
      const x0 = r0.x - Hm.sx + d * 1.5, y0 = Hm.ground[Math.round(r0.x)] + OFFY - (m === 2 ? 8.1 : 5.5);
      let bx = x0, by = y0, vis = true;
      if (f > sq.shotF) { const tt = (f - sq.shotF) / FPS;
        if (m === 7) { const cx = Hm.flag[0], u = clamp((f - sq.shotF) / (sq.holedF - sq.shotF)); bx = lerp(x0, cx, 1 - Math.pow(1 - u, 1.8)); by = Hm.ground[Math.round(bx + Hm.sx)] + OFFY - 5.5 + (u >= 1 ? 9 : 0); vis = f < sq.holedF + 2; }
        else { bx = x0 + d * 760 * tt; by = y0 - (430 * tt - 450 * tt * tt); vis = bx > -20 && bx < DW + 20; } }
      if (vis) { b.style.visibility = "visible"; b.style.transform = `translate(${(dx || 0).toFixed(2)}px,0)`; px(b, bx - 5.5, by - 5.5, 11, 11); } });

    // 공 + 궤적 + 잔상 (1번 홀) — 행동 시각 fa 기준
    const bo = 1 - smooth(seg(f, 158, 166));
    ghosts.forEach((g) => g.setAttribute("opacity", 0));
    if (fa > F_IMP - 1 && bo > 0.001) {
      const fu = flightU(fa), nn = Math.max(2, Math.round(fu * 400));
      const pts = fa > F_IMP ? PATH.slice(0, nn + 1).map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ") : "";
      const to = ((1 - smooth(seg(f, 128, 156))) * bo).toFixed(3);
      trailEl.setAttribute("points", pts); trailCase.setAttribute("points", pts); trailEl.setAttribute("opacity", to); trailCase.setAttribute("opacity", to);
      let [bx, by] = pathAt(fu);
      if (fa > F_LAND) { const hop = seg(fa, F_LAND, F_LAND + 9); by -= Math.sin(Math.PI * hop) * 7; bx += 9 * (1 - Math.pow(1 - seg(fa, F_LAND, F_LAND + 22), 2)); by = Math.min(by, H[1].ground[Math.round(bx)] + OFFY - 5.5); }
      if (fa > F_IMP && fa <= F_LAND) ghosts.forEach((g, i) => { const [gx, gy] = pathAt(flightU(fa - 0.7 * (i + 1)));
        g.setAttribute("cx", gx.toFixed(2)); g.setAttribute("cy", gy.toFixed(2)); g.setAttribute("r", (5.5 * (1 - 0.1 * (i + 1))).toFixed(2)); g.setAttribute("opacity", (0.6 * (1 - (i + 1) / 7) * bo).toFixed(3)); });
      const dia = 11;
      ballEl.style.visibility = "visible"; ballEl.style.opacity = bo.toFixed(3);
      px(ballEl, bx - dia / 2, by - dia / 2, dia, dia);
    } else { ballEl.style.visibility = "hidden"; trailEl.setAttribute("points", ""); trailCase.setAttribute("points", ""); }

    // 커서 + 클릭(원형 파동 2겹)
    const [cx, cy, cs] = cursorAt(f);
    cursor.style.transform = `translate(${cx.toFixed(2)}px,${cy.toFixed(2)}px) scale(${(cs * CS).toFixed(3)})`;
    cursor.style.opacity = (1 - smooth(seg(f, 150, 157))).toFixed(3);
    ripples.forEach((rp, i) => { const s0 = F_PRESS + 5 * i, u = seg(f, s0, s0 + 15);
      rp.setAttribute("cx", MUTE_C[0].toFixed(1)); rp.setAttribute("cy", MUTE_C[1].toFixed(1));
      rp.setAttribute("r", (6 + 44 * eout(u)).toFixed(2)); rp.setAttribute("stroke-width", (3.2 * (1 - 0.6 * u)).toFixed(2));
      rp.setAttribute("opacity", f >= s0 && f < s0 + 15 ? (0.95 * (1 - u)).toFixed(3) : 0); });
    const on = f >= F_PRESS + 2;
    tMute.innerHTML = on ? MIC(true, "#FFFFFF") + "음소거" : MIC(false, "#FFFFFF") + "음소거 해제";
    tMute.style.background = f >= F_PRESS - 2 && f < F_REL + 3 ? "rgba(255,255,255,.28)" : (f >= F_ARRIVE - 3 && f < 150 ? "rgba(255,255,255,.16)" : "rgba(255,255,255,.08)");
    document.getElementById("selfmic").innerHTML = MIC(on, on ? "#2350E8" : INK);
    document.getElementById("selfring").style.opacity = smooth(seg(f, F_PRESS + 2, F_PRESS + 8)).toFixed(3);
    bar.style.opacity = (1 - smooth(seg(f, 336, 350))).toFixed(3);

    // 채팅 목록
    let c = 0; MSGS.forEach((m) => { c += smooth((f - m.f) / 6); });
    MSGS.forEach((m, i) => { const e = msgEls[i]; const y = LIST_H - 30 - (c - i - 1) * PITCH; e.style.top = y.toFixed(2) + "px"; e.style.opacity = (smooth((f - m.f) / 6) * smooth((y + 2) / 6)).toFixed(3); });
    const [tx2, typing] = typedAt(f);
    const lastSent = Math.max(...TYPE.map((r) => (f >= r[3] ? r[3] : -99)));
    const caretOn = tx2 ? (typing || Math.floor(f / 16) % 2 === 0) : (f - lastSent > 4 && Math.floor((f - lastSent) / 16) % 2 === 1 && f < 330);
    input.innerHTML = tx2 ? `<span class="tt">${tx2}</span>` + (caretOn ? `<span class="caret"></span>` : "") : (caretOn ? `<span class="caret" style="margin-left:0;margin-right:4px"></span>` : "") + `<span class="ph">메시지 입력…</span>`;

    // 자막 (키네틱): 들어올 때 띠 6f 펼침 + 글자 스프링 착지, 나갈 때 띠 접힘 + 글자 빠짐
    capLines.forEach((L) => {
      const C = CAPS[L.ci], d = 3 * L.li, fin = C.fin + d, fout = C.fout + d;
      let bs, bo2, tx3, to;
      if (f < fin) { bs = 0; tx3 = -50; to = 0; bo2 = "left"; }
      else if (f < fout) { bs = eout(seg(f, fin, fin + 6)); tx3 = -50 * (1 - Sk((f - fin - 2) / FPS, "pop")); to = smooth(seg(f, fin + 1, fin + 5)); bo2 = "left"; }
      else { const u = seg(f, fout, fout + 7); bs = 1 - ease3(u); tx3 = 60 * ease3(u); to = 1 - smooth(seg(f, fout, fout + 5)); bo2 = "right"; }
      if (C.fin < 0 && f < fout) { bs = 1; tx3 = 0; to = 1; }
      L.band.style.transformOrigin = bo2 + " center"; L.band.style.transform = `scaleX(${bs.toFixed(4)})`;
      L.txt.style.transform = `translateX(${tx3.toFixed(2)}px)`; L.txt.style.opacity = to.toFixed(3);
      L.wrap.style.visibility = bs <= 0.0001 && to <= 0.001 ? "hidden" : "visible";
    });

    // 플립 시계: f160 들어오고 f306 나간다(마스크 밀어 올리기), 컷마다 바뀌는 자리만 6f 넘김
    const slotY = (ff, fin, fout, H0) => ff < fin ? H0 : ff < fout ? H0 * (1 - eout(seg(ff, fin, fin + 8))) : -H0 * ease3(seg(ff, fout, fout + 7));
    const cy0 = slotY(f, 166, 306, CK.h);
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

    // 엔드카드: 흰 판이 스틱맨 쪽(화면 420,1170)에서 원형으로 열린다(f336–354) → 내용이 차례로 떠오른다
    const er = 1500 * ease3(seg(f, 334, 362));
    endLayer.style.clipPath = `circle(${er.toFixed(1)}px at ${END_C[0]}px ${END_C[1]}px)`; endLayer.style.visibility = er > 0.5 ? "visible" : "hidden";
    endItems.forEach((e, i) => { const s0 = 344 + 4 * i, u = Sk((f - s0) / FPS, "calm"); e.style.opacity = u.toFixed(3); e.style.transform = `translateY(${(26 * (1 - u)).toFixed(2)}px)`; });
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
    for (let f = 0; f < NF; f += 3) {
      render(f / FPS); const fr = { f, items: [] };
      capLines.forEach((L) => { if (L.wrap.style.visibility === "visible" && parseFloat(L.txt.style.opacity) > 0.5) for (const r of textRects(L.txt)) fr.items.push({ name: "caption", r }); });
      if (endLayer.style.visibility === "visible") endItems.forEach((e) => { if (parseFloat(e.style.opacity) > 0.3) for (const r of textRects(e)) fr.items.push({ name: "end", r }); });
      msgEls.forEach((e) => { if (vis(e) > 0.3) { const r = R(e.getBoundingClientRect()); const lb = list.getBoundingClientRect(); if (r[1] >= lb.top - 1 && r[3] <= lb.bottom + 1) fr.items.push({ name: "chat", r }); } });
      const tt = input.querySelector(".tt"); if (tt) for (const r of textRects(tt)) fr.items.push({ name: "typing", r });
      MEN.forEach((m) => { if (m.g.style.visibility === "visible" && !m.g.getAttribute("filter")) fr.items.push({ name: "man", r: R(m.g.getBoundingClientRect()) }); });
      if (clockBox.style.visibility === "visible") { const cb = clockBox.getBoundingClientRect(); for (const c of clockIn.querySelectorAll(".card,.holetag")) { const r = c.getBoundingClientRect(); const rr = [r.left, Math.max(r.top, cb.top), r.right, Math.min(r.bottom, cb.bottom)].map(Math.round); if (rr[3] - rr[1] > 8) fr.items.push({ name: "clock", r: rr }); } }
      if (ballEl.style.visibility === "visible") fr.items.push({ name: "ball", r: R(ballEl.getBoundingClientRect()) });
      if (parseFloat(cursor.style.opacity) > 0.3) fr.items.push({ name: "cursor", r: R(cursor.getBoundingClientRect()) });
      if (f >= 100 && f <= 150) fr.items.push({ name: "mute", r: R(tMute.getBoundingClientRect()) });
      out.frames.push(fr);
    }
    const pre = document.createElement("pre"); pre.id = "audit"; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
  }
  Promise.all(["400 20px Pretendard", "500 20px Pretendard", "600 20px Pretendard", "700 20px Pretendard", "800 20px Pretendard", "500 20px JBM"].map((x) => document.fonts.load(x))).then(() => document.fonts.ready).then(() => { if (q.has("audit")) audit(); render(q.has("t") ? parseFloat(q.get("t")) : tl.time()); window.__ready = true; });
})();
