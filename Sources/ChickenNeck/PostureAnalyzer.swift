import Foundation

/// Overall posture severity — the green / orange / red traffic light.
enum PostureSeverity {
    case unknown    // not calibrated / no face
    case good       // green
    case mild       // orange — drifting
    case severe     // red — sustained forward head, time to act
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

/// Turns the stream of `PostureReading`s into a clinical verdict.
///
/// Calibrate an upright baseline, low-pass filter each axis to kill jitter, then
/// grade three independent neck problems against tunable limits:
///   • forward head posture  → graded mild (orange) / severe (red)
///   • lateral neck flexion   → highlighted past `tiltLimit`
///   • cervical rotation      → highlighted past `rotationLimit`
/// A *severe forward* state sustained for `holdSeconds` raises `.alarm`.
final class PostureAnalyzer {

    // Tunables (set from settings).
    var forwardMild: Double = 10      // orange threshold (red = 2×)
    var tiltLimit: Double = 12        // degrees of lateral tilt before flagging
    var rotationLimit: Double = 22    // degrees of rotation before flagging
    var holdSeconds: Double = 3
    var recoverSeconds: Double = 1.5
    var invert = false                // flip forward sign if geometry is reversed

    var forwardSevere: Double { forwardMild * 2 }

    // Forward-load weights — how each cue folds into one "forward head" number.
    private let dropW = 100.0    // face sliding down the frame
    private let leanW = 150.0    // face growing = craning toward the screen
    private let pitchW = 0.5     // head tilting down (per degree)

    private let alpha = 0.2      // low-pass smoothing
    private var sPitch, sRoll, sYaw, sBoxH, sCenterX, sCenterY: Double?

    // Upright baselines captured at calibration.
    private var bPitch, bRoll, bYaw, bBoxH, bCenterY: Double?

    private var badSince: Date?
    private var goodSince: Date?

    private(set) var verdict = PostureVerdict()
    private(set) var alarm = false   // severe-forward sustained past holdSeconds

    var isCalibrated: Bool { bPitch != nil }

    @discardableResult
    func calibrate() -> Bool {
        guard let p = sPitch, let r = sRoll, let yw = sYaw,
              let bh = sBoxH, let cy = sCenterY else { return false }
        bPitch = p; bRoll = r; bYaw = yw; bBoxH = bh; bCenterY = cy
        badSince = nil; goodSince = nil
        alarm = false
        verdict = PostureVerdict(severity: .good)
        return true
    }

    func reset() {
        sPitch = nil; sRoll = nil; sYaw = nil; sBoxH = nil; sCenterX = nil; sCenterY = nil
        bPitch = nil; bRoll = nil; bYaw = nil; bBoxH = nil; bCenterY = nil
        badSince = nil; goodSince = nil
        alarm = false
        verdict = PostureVerdict()
    }

    private func smooth(_ current: inout Double?, _ value: Double) -> Double {
        if let c = current { current = c + alpha * (value - c) } else { current = value }
        return current!
    }

    /// Feed one frame. Pass `nil` when no face is visible.
    @discardableResult
    func update(reading: PostureReading?, now: Date = Date()) -> PostureVerdict {
        guard let reading else {
            // Don't reset baselines — you may just have looked away briefly.
            return verdict
        }

        let pitch = smooth(&sPitch, reading.pitch)
        let roll  = smooth(&sRoll, reading.roll)
        let yaw   = smooth(&sYaw, reading.yaw)
        let boxH  = smooth(&sBoxH, reading.boxHeight)
        _ = smooth(&sCenterX, reading.centerX)
        let cy    = smooth(&sCenterY, reading.centerY)

        guard let bPitch, let bRoll, let bYaw, let bBoxH, let bCenterY else {
            verdict = PostureVerdict(severity: .unknown)
            return verdict
        }

        // Forward head load: head dropping, face growing, chin tucking down.
        var forward = (bCenterY - cy) * dropW
                    + (boxH - bBoxH) * leanW
                    + (bPitch - pitch) * pitchW
        if invert { forward = -forward }
        forward = max(0, forward)

        let tilt = roll - bRoll                 // signed: +/- one shoulder
        let rotation = abs(yaw - bYaw)
        let closeness = max(0, boxH - bBoxH)

        // Pick the worst offender for messaging.
        var issue: PostureIssue = .none
        if forward >= forwardSevere { issue = .forward }
        else if forward >= forwardMild { issue = closeness > 0.06 ? .tooClose : .forward }
        else if abs(tilt) >= tiltLimit { issue = tilt > 0 ? .tiltLeft : .tiltRight }
        else if rotation >= rotationLimit { issue = .rotated }

        // Severity = worst of the neck axes. Forward can reach red; tilt/rotation cap at orange.
        let mildBad = forward >= forwardMild || abs(tilt) >= tiltLimit || rotation >= rotationLimit
        let severity: PostureSeverity = forward >= forwardSevere ? .severe : (mildBad ? .mild : .good)

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
