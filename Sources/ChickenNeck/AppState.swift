import Foundation
import Combine
import ServiceManagement
import AppKit

/// One point in the live forward-head-load chart.
struct DeviationSample: Identifiable {
    let id: Int
    let t: Double      // seconds since the session started (chart x-axis)
    let drop: Double
}

/// Central view-model. Wires camera → analysis → alerts, tracks sit-time and
/// session stats, runs the coop-break and lunch reminders, and persists settings.
final class AppState: ObservableObject {

    static let shared = AppState()

    let camera = PostureCameraService()
    let analyzer = PostureAnalyzer()
    let alerts = AlertManager()
    let history = HistoryStore()

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var ticker: Timer?           // posture/sit-time loop (only while monitoring)
    private var wellnessTicker: Timer?   // hydration/eye/lunch (always, even when not monitoring)

    // MARK: Live state

    @Published private(set) var isMonitoring = false
    @Published private(set) var isCalibrated = false
    @Published private(set) var severity: PostureSeverity = .unknown
    @Published private(set) var issue: PostureIssue = .none
    @Published private(set) var forwardLoad: Double = 0
    @Published private(set) var tilt: Double = 0
    @Published private(set) var rotation: Double = 0

    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginItemError: String?

    // MARK: Session + sit-time stats

    @Published private(set) var goodSeconds: Double = 0
    @Published private(set) var badSeconds: Double = 0
    @Published private(set) var slouchEvents = 0
    @Published private(set) var recentSamples: [DeviationSample] = []

    @Published private(set) var seatedContinuous: Double = 0   // since last time you got up
    @Published private(set) var seatedToday: Double = 0
    @Published private(set) var breaksToday: Int = 0

    private var breakAccrued: Double = 0    // seconds since last coop-break prompt
    private var hydrationAccrued: Double = 0
    private var eyeAccrued: Double = 0
    private var awaySeconds: Double = 0
    private var previousSeverity: PostureSeverity = .unknown
    private var sampleIndex = 0
    private var sessionStartTime: Date?
    private var lastChartTime: Date?
    private let chartWindowSeconds: Double = 60

    // MARK: Settings (persisted)

    @Published var threshold: Double {            // forward "mild" (orange) limit; red = 2×
        didSet { analyzer.forwardMild = threshold; defaults.set(threshold, forKey: "threshold") }
    }
    @Published var tiltLimit: Double {
        didSet { analyzer.tiltLimit = tiltLimit; defaults.set(tiltLimit, forKey: "tiltLimit") }
    }
    @Published var holdSeconds: Double {
        didSet { analyzer.holdSeconds = holdSeconds; defaults.set(holdSeconds, forKey: "holdSeconds") }
    }
    @Published var cooldown: Double {
        didSet { alerts.cooldown = cooldown; defaults.set(cooldown, forKey: "cooldown") }
    }
    @Published var breakIntervalMin: Double {
        didSet { defaults.set(breakIntervalMin, forKey: "breakIntervalMin") }
    }
    @Published var breakRemindersOn: Bool {
        didSet { defaults.set(breakRemindersOn, forKey: "breakRemindersOn") }
    }
    @Published var lunchReminderOn: Bool {
        didSet { defaults.set(lunchReminderOn, forKey: "lunchReminderOn") }
    }
    @Published var hydrationOn: Bool {
        didSet { defaults.set(hydrationOn, forKey: "hydrationOn") }
    }
    @Published var hydrationIntervalMin: Double {
        didSet { defaults.set(hydrationIntervalMin, forKey: "hydrationIntervalMin") }
    }
    @Published var eyeRestOn: Bool {
        didSet { defaults.set(eyeRestOn, forKey: "eyeRestOn") }
    }
    @Published var eyeRestIntervalMin: Double {
        didSet { defaults.set(eyeRestIntervalMin, forKey: "eyeRestIntervalMin") }
    }
    @Published var soundEnabled: Bool {
        didSet { alerts.soundEnabled = soundEnabled; defaults.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var soundName: String {
        didSet { alerts.soundName = soundName; defaults.set(soundName, forKey: "soundName") }
    }
    @Published var voiceEnabled: Bool {
        didSet { alerts.voiceEnabled = voiceEnabled; defaults.set(voiceEnabled, forKey: "voiceEnabled") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { alerts.notificationEnabled = notificationsEnabled; defaults.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var popupAlertsOn: Bool {
        didSet { alerts.popupEnabled = popupAlertsOn; defaults.set(popupAlertsOn, forKey: "popupAlertsOn") }
    }
    @Published var popupSeconds: Double {
        didSet { alerts.popupSeconds = popupSeconds; defaults.set(popupSeconds, forKey: "popupSeconds") }
    }
    @Published var invert: Bool {
        didSet { analyzer.invert = invert; defaults.set(invert, forKey: "invert") }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    init() {
        defaults.register(defaults: [
            "threshold": 6.0,
            "tiltLimit": 12.0,
            "holdSeconds": 3.0,
            "cooldown": 20.0,
            "breakIntervalMin": 30.0,
            "breakRemindersOn": true,
            "lunchReminderOn": true,
            "hydrationOn": true,
            "hydrationIntervalMin": 60.0,
            "eyeRestOn": true,
            "eyeRestIntervalMin": 20.0,
            "soundEnabled": true,
            "soundName": "Funk",
            "voiceEnabled": false,
            "notificationsEnabled": true,
            "popupAlertsOn": true,
            "popupSeconds": 4.0,
            "invert": false,
            "showMenuBarIcon": true
        ])

        threshold = defaults.double(forKey: "threshold")
        tiltLimit = defaults.double(forKey: "tiltLimit")
        holdSeconds = defaults.double(forKey: "holdSeconds")
        cooldown = defaults.double(forKey: "cooldown")
        breakIntervalMin = defaults.double(forKey: "breakIntervalMin")
        breakRemindersOn = defaults.bool(forKey: "breakRemindersOn")
        lunchReminderOn = defaults.bool(forKey: "lunchReminderOn")
        hydrationOn = defaults.bool(forKey: "hydrationOn")
        hydrationIntervalMin = defaults.double(forKey: "hydrationIntervalMin")
        eyeRestOn = defaults.bool(forKey: "eyeRestOn")
        eyeRestIntervalMin = defaults.double(forKey: "eyeRestIntervalMin")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        soundName = defaults.string(forKey: "soundName") ?? "Funk"
        voiceEnabled = defaults.bool(forKey: "voiceEnabled")
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        popupAlertsOn = defaults.bool(forKey: "popupAlertsOn")
        popupSeconds = defaults.double(forKey: "popupSeconds")
        invert = defaults.bool(forKey: "invert")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")

        analyzer.forwardMild = threshold
        analyzer.tiltLimit = tiltLimit
        analyzer.holdSeconds = holdSeconds
        analyzer.invert = invert
        alerts.cooldown = cooldown
        alerts.soundEnabled = soundEnabled
        alerts.soundName = soundName
        alerts.voiceEnabled = voiceEnabled
        alerts.notificationEnabled = notificationsEnabled
        alerts.popupEnabled = popupAlertsOn
        alerts.popupSeconds = popupSeconds
        alerts.requestNotificationAuthorization()

        // One-time retune: warn at forward-load 6 (orange) / 12 (red), and
        // repeat the nudge every 20s while you stay out of line (not once, not spammy).
        if !defaults.bool(forKey: "tuning_v4") {
            threshold = 6
            cooldown = 20
            defaults.set(true, forKey: "tuning_v4")
        }

        seatedToday = defaults.double(forKey: seatedTodayKey)
        breaksToday = defaults.integer(forKey: breaksTodayKey)

        camera.onReading = { [weak self] reading in self?.handle(reading: reading) }

        camera.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        history.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.flushSessionToHistory() }
            .store(in: &cancellables)

        refreshLoginItemStatus()
        startWellnessTicker()
    }

    // MARK: Intents

    func startMonitoring() {
        resetSession()
        camera.start()
        isMonitoring = true
        startTicker()
    }

    func stopMonitoring() {
        flushSessionToHistory()
        camera.stop()
        ticker?.invalidate(); ticker = nil
        isMonitoring = false
        severity = .unknown
        issue = .none
        forwardLoad = 0
    }

    func calibrate() {
        if analyzer.calibrate() {
            isCalibrated = true
            severity = .good
            alerts.resetCooldown()
            resetSession()
        }
    }

    func recalibrate() {
        flushSessionToHistory()
        analyzer.reset()
        isCalibrated = false
        severity = .unknown
        issue = .none
        forwardLoad = 0
        resetSession()
    }

    func previewSound() { alerts.previewSound() }

    // MARK: Launch at login

    func refreshLoginItemStatus() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            else if !enabled, SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }

    // MARK: Per-frame pipeline (≈10 Hz)

    private func handle(reading: PostureReading?) {
        let now = Date()
        let v = analyzer.update(reading: reading, now: now)
        guard isMonitoring else { return }

        severity = v.severity
        issue = v.issue
        forwardLoad = v.forwardLoad
        tilt = v.tilt
        rotation = v.rotation

        guard isCalibrated, reading != nil else { return }

        if v.severity == .severe, previousSeverity != .severe { slouchEvents += 1 }
        previousSeverity = v.severity

        // Downsample the chart to ~5 Hz.
        let chartDue = lastChartTime.map { now.timeIntervalSince($0) >= 0.2 } ?? true
        if chartDue {
            if sessionStartTime == nil { sessionStartTime = now }
            let t = now.timeIntervalSince(sessionStartTime ?? now)
            sampleIndex += 1
            recentSamples.append(DeviationSample(id: sampleIndex, t: t, drop: v.forwardLoad))
            let cutoff = t - chartWindowSeconds
            while let first = recentSamples.first, first.t < cutoff { recentSamples.removeFirst() }
            lastChartTime = now
        }

        if analyzer.alarm {
            alerts.triggerPostureAlert(issue: v.issue, severe: v.severity == .severe, now: now)
        }
    }

    // MARK: 1 Hz ticker — sit-time, breaks, lunch, posture-time stats

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard isMonitoring else { return }
        rolloverIfNewDay()

        if camera.hasFace {
            awaySeconds = 0
            seatedContinuous += 1
            seatedToday += 1
            defaults.set(seatedToday, forKey: seatedTodayKey)

            if isCalibrated {
                if severity == .good { goodSeconds += 1 }
                else if severity == .mild || severity == .severe { badSeconds += 1 }
            }

            if breakRemindersOn {
                breakAccrued += 1
                if breakAccrued >= breakIntervalMin * 60 {
                    alerts.triggerCoopBreak(minutes: Int(breakIntervalMin))
                    breakAccrued = 0
                }
            }
        } else {
            // Face gone for 30s while monitoring = you got up. Count it as a break.
            awaySeconds += 1
            if awaySeconds == 30, seatedContinuous > 60 {
                breaksToday += 1
                defaults.set(breaksToday, forKey: breaksTodayKey)
                seatedContinuous = 0
                breakAccrued = 0
            }
        }

    }

    // MARK: Always-on wellness ticker (runs even when not monitoring/calibrated)

    private func startWellnessTicker() {
        wellnessTicker?.invalidate()
        wellnessTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.wellnessTick()
        }
    }

    private func wellnessTick() {
        if hydrationOn {
            hydrationAccrued += 1
            if hydrationAccrued >= hydrationIntervalMin * 60 {
                alerts.triggerHydration()
                hydrationAccrued = 0
            }
        }
        if eyeRestOn {
            eyeAccrued += 1
            if eyeAccrued >= eyeRestIntervalMin * 60 {
                alerts.triggerEyeRest()
                eyeAccrued = 0
            }
        }
        checkLunch()
    }

    private func checkLunch() {
        guard lunchReminderOn else { return }
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        guard hour >= 13, hour < 14 else { return }
        let today = HistoryStore.dayKey(now)
        if defaults.string(forKey: "lastLunchDay") != today {
            defaults.set(today, forKey: "lastLunchDay")
            alerts.triggerLunch()
        }
    }

    // MARK: History + day rollover

    func flushSessionToHistory() {
        let total = goodSeconds + badSeconds
        guard total >= 5 else { return }
        history.record(good: goodSeconds, bad: badSeconds, slouches: slouchEvents, on: Date())
        goodSeconds = 0; badSeconds = 0; slouchEvents = 0
    }

    private var todayKey = HistoryStore.dayKey(Date())
    private var seatedTodayKey: String { "seated-\(HistoryStore.dayKey(Date()))" }
    private var breaksTodayKey: String { "breaks-\(HistoryStore.dayKey(Date()))" }

    private func rolloverIfNewDay() {
        let key = HistoryStore.dayKey(Date())
        if key != todayKey {
            todayKey = key
            seatedToday = defaults.double(forKey: seatedTodayKey)
            breaksToday = defaults.integer(forKey: breaksTodayKey)
            seatedContinuous = 0
            breakAccrued = 0
        }
    }

    private func resetSession() {
        goodSeconds = 0; badSeconds = 0; slouchEvents = 0
        recentSamples = []
        sampleIndex = 0
        lastChartTime = nil
        sessionStartTime = nil
        previousSeverity = .unknown
        seatedContinuous = 0
        breakAccrued = 0
        awaySeconds = 0
    }

    // MARK: Derived UI helpers

    var connectionText: String {
        if !camera.isAvailable { return "No camera found" }
        if camera.hasFace { return "Watching your neck" }
        if isMonitoring { return camera.isAuthorized ? "Looking for you…" : "Camera access needed" }
        return camera.deviceName.isEmpty ? "Camera ready" : camera.deviceName
    }

    var isConnected: Bool { camera.hasFace || (camera.isAvailable && !isMonitoring) }

    var statusHeadline: String {
        if let err = camera.lastError { return err }
        if !isMonitoring { return "Paused" }
        if !camera.hasFace { return "Get your face in frame" }
        if !isCalibrated { return "Sit tall, then Calibrate" }
        switch severity {
        case .good:    return "Proud rooster 🐓"
        case .mild:    return mildHeadline
        case .severe:  return "Chicken peck! Pull back 🐔"
        case .unknown: return "Reading…"
        }
    }

    private var mildHeadline: String {
        switch issue {
        case .tiltLeft, .tiltRight: return "Head-cock — level up 🐤"
        case .rotated:              return "Craning sideways 🐔"
        case .tooClose:             return "Easing toward the screen"
        default:                    return "Drifting forward…"
        }
    }

    /// 0…1 toward the red line (the forward-severe threshold).
    var forwardFraction: Double {
        guard analyzer.forwardSevere > 0 else { return 0 }
        return min(1, max(0, forwardLoad / analyzer.forwardSevere))
    }

    var tiltExceeded: Bool { abs(tilt) >= tiltLimit }
    var rotationExceeded: Bool { rotation >= analyzer.rotationLimit }

    var chartXDomain: ClosedRange<Double> {
        let last = recentSamples.last?.t ?? 0
        if last <= chartWindowSeconds { return 0...chartWindowSeconds }
        return (last - chartWindowSeconds)...last
    }

    var goodPosturePercent: Double {
        let total = goodSeconds + badSeconds
        return total > 0 ? (goodSeconds / total) * 100 : 100
    }

    var monitoredTimeString: String { Self.clock(goodSeconds + badSeconds) }
    var seatedContinuousString: String { Self.clock(seatedContinuous) }
    var seatedTodayString: String { Self.clock(seatedToday) }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var menuBarSymbol: String {
        guard isMonitoring else { return "figure.seated.side" }
        if !isCalibrated { return "scope" }
        switch severity {
        case .severe:  return "exclamationmark.triangle.fill"
        case .mild:    return "figure.seated.side"
        case .good:    return "figure.stand"
        case .unknown: return "figure.seated.side"
        }
    }

    /// Colour for the live menu-bar chicken icon.
    var menuBarNSColor: NSColor {
        switch severity {
        case .good:    return NSColor.systemGreen
        case .mild:    return NSColor.systemOrange
        case .severe:  return NSColor.systemRed
        case .unknown: return NSColor.secondaryLabelColor
        }
    }
}
