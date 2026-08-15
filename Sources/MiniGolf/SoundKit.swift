import AVFoundation
import GolfCore

/// 합성음 사운드 — 샘플 파일 없이 전부 코드로 생성 (번들 증가 0, 라이선스 걱정 없음)
/// 결: "조용한 계기판" — 작고 마른 소리. 마스터 볼륨을 낮게 잡아 데스크탑 위에서 조용히 머문다
final class SoundKit {
    static let shared = SoundKit()

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "soundEnabled") }
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let sr = 44100.0
    private var ok = false

    private init() {
        enabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { return }
        for _ in 0 ..< 8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: fmt)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.55
        do {
            try engine.start()
            ok = true
        } catch {
            ok = false // 사운드 없이 게임은 계속
        }
        // 출력 장치 변경(헤드폰 연결 등)으로 엔진이 멈추면 재시작
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            do {
                try engine.start()
                ok = true
            } catch {
                ok = false
            }
        }
    }

    // ── 이벤트 사운드 ──

    /// 다운스윙 바람 소리 — 파워에 비례, 임팩트 직전에 정점
    func whoosh(power: Double, dur: Double) {
        let d = max(0.12, dur)
        var bp = Biquad.bandpass(400, q: 0.9, sr: sr)
        var rng = NoiseLCG()
        play(duration: d) { t in
            let u = t / d
            bp.retune(.bandpass, 350 + 550 * u, q: 0.9, sr: self.sr)
            let bell = sin(.pi * u) * sin(.pi * u)
            return bp.process(rng.white()) * bell * (0.10 + 0.25 * power)
        }
    }

    /// 타격음 — 클럽 카테고리별 몸통+크랙, 라이(러프·벙커)가 질감 레이어를 더한다
    func impact(cat: ClubCategory, lie: Surface, power: Double) {
        let vol = 0.4 + 0.45 * power
        var crack = Biquad.bandpass(cat == .iron ? 3200 : cat == .putter ? 1800 : 2000, q: 1.2, sr: sr)
        var turf = Biquad.lowpass(lie == .bunker ? 260 : 420, q: 0.8, sr: sr)
        var soft = Biquad.lowpass(700, q: 0.8, sr: sr)
        var rng = NoiseLCG()
        let lieAmp = lie == .rough ? 0.4 : lie == .bunker ? 0.55 : 0.0
        let dur = lieAmp > 0 ? 0.2 : cat == .putter ? 0.05 : 0.1
        play(duration: dur) { t in
            let n = rng.white()
            var s = 0.0
            switch cat {
            case .wood:
                s += sin(2 * .pi * (170 - 300 * t) * t) * exp(-t / 0.03) * 0.8
                s += crack.process(n) * exp(-t / 0.008) * 0.9
            case .iron:
                s += sin(2 * .pi * 950 * t) * exp(-t / 0.012) * 0.5
                s += crack.process(n) * exp(-t / 0.006) * 0.9
            case .wedge:
                s += soft.process(n) * exp(-t / 0.02) * 0.9
                s += crack.process(n) * exp(-t / 0.005) * 0.3
            case .putter:
                s += sin(2 * .pi * 1200 * t) * exp(-t / 0.008) * 0.35
                s += crack.process(n) * exp(-t / 0.006) * 0.6
            }
            if lieAmp > 0 { // 러프 스치는 소리 / 벙커 모래 퍽
                s += turf.process(n) * exp(-t / 0.06) * lieAmp
            }
            return s * vol
        }
    }

    /// 착지 탭 — 세기·라이별로 음색이 다르다 (그린은 마른 탭, 벙커는 둔한 퍽)
    func bounce(speed: Double, surface: Surface) {
        let cutoff: Double = switch surface {
        case .green: 1000
        case .rough: 450
        case .bunker: 280
        default: 800
        }
        var lp = Biquad.lowpass(cutoff, q: 0.8, sr: sr)
        var rng = NoiseLCG()
        let vol = min(1, speed / 10) * 0.5
        let decay = surface == .bunker ? 0.02 : 0.01
        play(duration: surface == .bunker ? 0.07 : 0.04) { t in
            var s = lp.process(rng.white()) * exp(-t / decay)
            if speed > 8 { // 강한 착지엔 낮은 쿵을 살짝
                s += sin(2 * .pi * 150 * t) * exp(-t / 0.015) * 0.3
            }
            return s * vol
        }
    }

    /// 립아웃 — 컵 턱의 맑은 클랙
    func lipOut() {
        var bp = Biquad.bandpass(2500, q: 1.5, sr: sr)
        var rng = NoiseLCG()
        play(duration: 0.05) { t in
            (sin(2 * .pi * 1500 * t) * exp(-t / 0.01) * 0.5
                + bp.process(rng.white()) * exp(-t / 0.006) * 0.6) * 0.5
        }
    }

    /// 홀인 — 컵 속 달그락 (틱 4번 감쇠) + 낮은 울림
    func holeIn() {
        var bp = Biquad.bandpass(1400, q: 1.2, sr: sr)
        var rng = NoiseLCG()
        let ticks: [(t0: Double, amp: Double)] = [(0, 1), (0.055, 0.8), (0.125, 0.62), (0.21, 0.45)]
        play(duration: 0.45) { t in
            var s = sin(2 * .pi * 240 * t) * exp(-t / 0.12) * 0.22 // 컵 울림
            let fn = bp.process(rng.white()) // 필터는 샘플당 1회만 통과
            for tick in ticks where t >= tick.t0 {
                let dt = t - tick.t0
                s += (fn * exp(-dt / 0.006) + sin(2 * .pi * 900 * dt) * exp(-dt / 0.01) * 0.4) * tick.amp
            }
            return s * 0.55
        }
    }

    /// 입수 — 첨벙 (컷오프가 내려가는 노이즈) + 낮아지는 블룹
    func splash() {
        var lp = Biquad.lowpass(1400, q: 0.8, sr: sr)
        var rng = NoiseLCG()
        let d = 0.35
        play(duration: d) { t in
            let u = t / d
            lp.retune(.lowpass, 1400 - 1100 * u, q: 0.8, sr: self.sr)
            let attack = min(1, t / 0.005)
            var s = lp.process(rng.white()) * exp(-t / 0.12) * attack * 0.7
            s += sin(2 * .pi * (280 - 850 * min(t, 0.2)) * t) * exp(-t / 0.07) * 0.45
            return s * 0.55
        }
    }

    /// 화면 가장자리 반사 — 조용한 탭
    func wall(speed: Double) {
        var lp = Biquad.lowpass(900, q: 0.8, sr: sr)
        var rng = NoiseLCG()
        let vol = min(1, speed / 8) * 0.35
        play(duration: 0.035) { t in
            lp.process(rng.white()) * exp(-t / 0.008) * vol
        }
    }

    /// 라운드 종료 — 아주 조용한 두 음
    func chime() {
        play(duration: 0.6) { t in
            var s = sin(2 * .pi * 660 * t) * exp(-t / 0.3)
            if t >= 0.14 {
                s += sin(2 * .pi * 880 * (t - 0.14)) * exp(-(t - 0.14) / 0.3)
            }
            return s * 0.16
        }
    }

    // ── 합성 ──

    private func play(duration: Double, _ sample: (Double) -> Double) {
        guard enabled, ok else { return }
        let n = Int(duration * sr)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)),
              let data = buf.floatChannelData?[0]
        else { return }
        buf.frameLength = AVAudioFrameCount(n)
        for i in 0 ..< n {
            data[i] = Float(max(-1, min(1, sample(Double(i) / sr))))
        }
        let player = players[next]
        next = (next + 1) % players.count
        player.stop()
        player.scheduleBuffer(buf, at: nil)
        player.play()
    }
}

/// 빠르고 결정론적인 화이트 노이즈 (mulberry32 계열 LCG)
private struct NoiseLCG {
    private var state: UInt32 = 0x9E37_79B9

    mutating func white() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / Double(UInt32.max) * 2 - 1
    }
}

/// RBJ 쿡북 2차 필터 — 밴드패스/로우패스 (TDF2)
private struct Biquad {
    enum Kind { case lowpass, bandpass }

    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var z1 = 0.0, z2 = 0.0

    static func lowpass(_ f: Double, q: Double, sr: Double) -> Biquad {
        var bq = Biquad()
        bq.retune(.lowpass, f, q: q, sr: sr)
        return bq
    }

    static func bandpass(_ f: Double, q: Double, sr: Double) -> Biquad {
        var bq = Biquad()
        bq.retune(.bandpass, f, q: q, sr: sr)
        return bq
    }

    /// 필터 상태(z1·z2)는 유지한 채 계수만 갱신 — 스윕에 사용
    mutating func retune(_ kind: Kind, _ f: Double, q: Double, sr: Double) {
        let w = 2 * .pi * max(40, min(f, sr * 0.45)) / sr
        let alpha = sin(w) / (2 * q)
        let cw = cos(w)
        let a0 = 1 + alpha
        switch kind {
        case .lowpass:
            b0 = (1 - cw) / 2 / a0
            b1 = (1 - cw) / a0
            b2 = b0
        case .bandpass:
            b0 = alpha / a0
            b1 = 0
            b2 = -alpha / a0
        }
        a1 = -2 * cw / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}
