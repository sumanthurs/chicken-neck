import Foundation

/// Single source of truth for the posture signal's time scale.
///
/// Everything timing-related derives from one knob, the smoothing time
/// constant, so they can't drift apart: the analyzer's low-pass filter uses it
/// directly, and the camera's minimum capture rate is derived from it (you must
/// sample several times faster than the dynamics you're smoothing, or you'd
/// alias real posture changes). Retune `smoothingTau` and both move together.
enum PostureDynamics {
    /// Low-pass time constant for per-axis smoothing, in seconds
    /// (≈ time to converge ~63% toward a new value).
    static let smoothingTau = 0.3

    /// How many samples we want inside one smoothing time constant. A handful
    /// keeps the exponential filter well-fed and the live chart smooth; this is
    /// the one product-judgment dimensionless factor.
    static let samplesPerTau = 3.0

    /// Minimum usable capture rate (fps): sample fast enough relative to the
    /// smoothing dynamics that we don't miss real posture changes. 3 / 0.3 = 10.
    static var minUsableFPS: Double { samplesPerTau / smoothingTau }
}

/// Overall posture severity, the green / orange / red traffic light.
enum PostureSeverity {
    case unknown    // not calibrated / no face
    case good       // green
    case mild       // orange, drifting
    case severe     // red, sustained forward head, time to act
}

/// Which axis is the worst offender right now (drives the funny copy + arrows).
enum PostureIssue {
    case none
    case forward        // tech-neck: head in front of shoulders / looking down
    case tiltLeft       // lateral cervical flexion
    case tiltRight
    case rotated        // craning to a side
    case tooClose       // leaning into the screen
}

/// The analyzer's verdict for one frame.
struct PostureVerdict {
    var severity: PostureSeverity = .unknown
    var issue: PostureIssue = .none
    var forwardLoad: Double = 0   // 0… ; composite forward-head load (the chart value)
    var tilt: Double = 0          // signed lateral tilt, degrees
    var rotation: Double = 0      // abs rotation, degrees
    var closeness: Double = 0     // how much closer than baseline (0…1 of frame)
}

/// Turns the stream of `PostureReading`s into a posture verdict.
///
/// Calibrate an upright baseline (averaged over a short window), time-constant
/// low-pass filter each axis to kill jitter, then grade three independent neck
/// problems and surface whichever is *worst relative to its own limit*:
///   • forward head posture  → graded mild (orange) / severe (red)
///   • lateral neck flexion   → highlighted past `tiltLimit`
///   • cervical rotation      → highlighted past `rotationLimit`
/// A *forward-head* state sustained for `holdSeconds` raises `.alarm`.
///
/// Threading: this type is **not** thread-safe. All public methods
/// (`update`, `calibrate`, `reset`) must be called from the main thread, which
/// is where `PostureCameraService` delivers readings. A precondition enforces
/// it (it fires in release too).
final class PostureAnalyzer {

    // Tunables (set from settings).
    var forwardMild: Double = 10      // orange threshold (red = 2×)
    var tiltLimit: Double = 12        // degrees of lateral tilt before flagging
    var rotationLimit: Double = 22    // degrees of rotation before flagging
    var holdSeconds: Double = 3
    var recoverSeconds: Double = 1.5
    var invert = false                // flip forward sign if geometry is reversed

    var forwardSevere: Double { forwardMild * 2 }

    // Forward-load model. Each cue is normalised to a dimensionless multiple of
    // a characteristic "clearly notable" delta, then summed and scaled by a
    // single gain. This keeps the cues unit-clean and individually
    // interpretable while preserving the historical `forwardLoad` magnitude.
    private let loadGain = 10.0
    private let dropScale = 0.10        // 10% of frame height = a notable slump
    private let leanScale = 1.0 / 15.0  // ~6.7% face growth = a notable lean-in
    private let pitchScale = 20.0       // 20° of chin-down = a notable tuck
    private let spanScale = 0.06        // 6% of box height of eye->chin foreshortening
    private let closenessLimit = 0.06   // face-growth past this reads as "too close"

    // Time-constant smoothing: alpha is derived from the wall-clock gap between
    // frames so the response is stable regardless of (variable) frame rate. The
    // time constant lives in `PostureDynamics` so the camera's sample rate stays
    // tied to it.
    private var lastUpdate = Date.distantPast

    private var sPitch, sRoll, sYaw, sBoxH, sCenterY, sSpan: Double?

    // Upright baselines captured at calibration. Pitch and span are optional:
    // pitch is only populated by Vision on supported OS, and span needs face
    // landmarks; when absent, their cues simply drop out of the model.
    private var bRoll, bYaw, bBoxH, bCenterY: Double?
    private var bPitch, bSpan: Double?

    // Rolling buffer of recent raw readings, used to average the calibration
    // baseline over a short window instead of snapshotting one noisy frame.
    private let calibrationWindow = 1.0  // seconds
    private var recent: [(t: Date, r: PostureReading)] = []

    private var badSince: Date?
    private var goodSince: Date?

    private(set) var verdict = PostureVerdict()
    private(set) var alarm = false   // forward-head sustained past holdSeconds

    var isCalibrated: Bool { bCenterY != nil }

    @discardableResult
    func calibrate() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        // Average the recent window so a blink or micro-movement at the moment
        // you press "calibrate" doesn't bias every later reading. Reference the
        // latest frame's clock (same timeline `update` uses), not wall time.
        guard let ref = recent.last?.t else { return false }
        let cutoff = ref.addingTimeInterval(-calibrationWindow)
        let window = recent.filter { $0.t >= cutoff }.map(\.r)
        guard !window.isEmpty else { return false }

        func mean(_ pick: (PostureReading) -> Double) -> Double {
            window.reduce(0) { $0 + pick($1) } / Double(window.count)
        }
        func meanOptional(_ pick: (PostureReading) -> Double?) -> Double? {
            let vals = window.compactMap(pick)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }

        bRoll = mean(\.roll); bYaw = mean(\.yaw)
        bBoxH = mean(\.boxHeight); bCenterY = mean(\.centerY)
        bPitch = meanOptional(\.pitch)
        bSpan = meanOptional(\.eyeChinSpan)

        badSince = nil; goodSince = nil
        alarm = false
        verdict = PostureVerdict(severity: .good)
        return true
    }

    func reset() {
        dispatchPrecondition(condition: .onQueue(.main))
        sPitch = nil; sRoll = nil; sYaw = nil; sBoxH = nil; sCenterY = nil; sSpan = nil
        bRoll = nil; bYaw = nil; bBoxH = nil; bCenterY = nil; bPitch = nil; bSpan = nil
        lastUpdate = .distantPast
        recent.removeAll()
        badSince = nil; goodSince = nil
        alarm = false
        verdict = PostureVerdict()
    }

    /// Exponential low-pass with a frame-rate-independent coefficient.
    private func smooth(_ current: inout Double?, _ value: Double, alpha: Double) -> Double {
        if let c = current { current = c + alpha * (value - c) } else { current = value }
        return current!
    }

    /// Optional variant: feeds the filter only when the source value is present.
    private func smooth(_ current: inout Double?, optional value: Double?, alpha: Double) -> Double? {
        guard let value else { return current }
        return smooth(&current, value, alpha: alpha)
    }

    /// Feed one frame. Pass `nil` when no face is visible.
    @discardableResult
    func update(reading: PostureReading?, now: Date = Date()) -> PostureVerdict {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let reading else {
            // No face (sent only after ~1s away): keep baselines/filters in case
            // you only glanced away, but clear the stale verdict and alarm so
            // neither sticks while you're gone; both re-arm on return.
            alarm = false
            badSince = nil; goodSince = nil
            verdict = PostureVerdict(severity: .unknown)
            return verdict
        }

        // Frame-rate-independent low-pass coefficient, capped below 1 so one
        // frame can't fully define the state after a long gap (alpha would be
        // ~1). The first frame snaps anyway (no prior value), so the cap only
        // bites on gaps/slow frames.
        let dt = max(0, now.timeIntervalSince(lastUpdate))
        let alpha = min(0.5, 1 - exp(-dt / PostureDynamics.smoothingTau))
        lastUpdate = now

        // Track recent raw readings for window-averaged calibration.
        recent.append((now, reading))
        let cutoff = now.addingTimeInterval(-calibrationWindow)
        while let first = recent.first, first.t < cutoff { recent.removeFirst() }

        let roll  = smooth(&sRoll, reading.roll, alpha: alpha)
        let yaw   = smooth(&sYaw, reading.yaw, alpha: alpha)
        let boxH  = smooth(&sBoxH, reading.boxHeight, alpha: alpha)
        let cy    = smooth(&sCenterY, reading.centerY, alpha: alpha)
        let pitch = smooth(&sPitch, optional: reading.pitch, alpha: alpha)
        let span  = smooth(&sSpan, optional: reading.eyeChinSpan, alpha: alpha)

        guard let bRoll, let bYaw, let bBoxH, let bCenterY else {
            verdict = PostureVerdict(severity: .unknown)
            return verdict
        }

        // Forward-head load: sum of dimensionless, baseline-relative cues.
        //   • head dropping in frame        (always available)
        //   • face growing = craning closer (always available)
        //   • chin tucking down             (pitch, when Vision provides it)
        //   • eye->chin foreshortening      (landmarks: intrinsic, scale-free)
        var load = (bCenterY - cy) / dropScale
                 + (boxH - bBoxH) / leanScale
        if let bPitch, let pitch { load += (bPitch - pitch) / pitchScale }
        if let bSpan, let span { load += (bSpan - span) / spanScale }
        var forward = loadGain * load
        if invert { forward = -forward }
        forward = max(0, forward)

        let tilt = roll - bRoll                 // signed: +/- one shoulder
        let rotation = abs(yaw - bYaw)
        let closeness = max(0, boxH - bBoxH)

        // Worst offender by *magnitude*: each axis is scored as a fraction of
        // its own limit, and the largest exceedance wins, so an egregious tilt
        // is no longer masked by a barely-mild forward lean.
        let forwardScore  = forwardMild   > 0 ? forward       / forwardMild   : 0
        let tiltScore     = tiltLimit     > 0 ? abs(tilt)     / tiltLimit     : 0
        let rotationScore = rotationLimit > 0 ? rotation      / rotationLimit : 0
        let topScore = max(forwardScore, max(tiltScore, rotationScore))

        var issue: PostureIssue = .none
        var severity: PostureSeverity = .good
        if topScore >= 1 {
            if forwardScore == topScore {
                let severe = forward >= forwardSevere
                issue = (!severe && closeness > closenessLimit) ? .tooClose : .forward
                severity = severe ? .severe : .mild
            } else if tiltScore == topScore {
                issue = tilt > 0 ? .tiltLeft : .tiltRight
                severity = .mild        // tilt/rotation cap at orange
            } else {
                issue = .rotated
                severity = .mild
            }
        }

        // Alarm on sustained forward-head (orange or red), with hysteresis.
        // AppState repeats the cue while it stays bad.
        let bad = forward >= forwardMild
        if bad {
            goodSince = nil
            if badSince == nil { badSince = now }
            alarm = now.timeIntervalSince(badSince!) >= holdSeconds
        } else {
            badSince = nil
            if goodSince == nil { goodSince = now }
            if now.timeIntervalSince(goodSince!) >= recoverSeconds { alarm = false }
        }

        verdict = PostureVerdict(severity: severity, issue: issue,
                                 forwardLoad: forward, tilt: tilt,
                                 rotation: rotation, closeness: closeness)
        return verdict
    }
}
