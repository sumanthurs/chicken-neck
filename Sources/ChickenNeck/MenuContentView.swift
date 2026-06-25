import SwiftUI
import Charts

struct MenuContentView: View {
    @ObservedObject var state: AppState
    @State private var showSettings = false
    @State private var showHistory = true
    @State private var showWellness = false
    @State private var historyRange: HistoryRange = .daily

    enum HistoryRange: String, CaseIterable { case daily = "Daily", weekly = "Weekly", monthly = "Monthly" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            statusSection
            if state.isMonitoring && state.isCalibrated {
                axisSection
                sitTimeSection
                statsSection
            }
            controls
            Divider()
            historySection
            Divider()
            settingsSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text("Chicken Neck").font(.headline)
            Spacer()
            Text(state.connectionText).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Status (traffic light)

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.statusHeadline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)

            if state.isMonitoring && state.isCalibrated {
                ProgressView(value: state.forwardFraction)
                    .tint(statusColor)
                Text("Forward-head load — green ▸ orange ▸ red as you crane toward the screen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if state.isMonitoring {
                Text("Forward load: \(Int(state.forwardLoad))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Per-axis neck indicators

    private var axisSection: some View {
        VStack(spacing: 6) {
            axisRow("Forward head",
                    value: "\(Int(state.forwardLoad))",
                    flag: state.severity == .severe ? .red : (state.forwardLoad >= state.threshold ? .orange : .green))
            axisRow(tiltLabel,
                    value: String(format: "%.0f°", abs(state.tilt)),
                    flag: state.tiltExceeded ? .orange : .green)
            axisRow("Rotation",
                    value: String(format: "%.0f°", state.rotation),
                    flag: state.rotationExceeded ? .orange : .green)
        }
    }

    private var tiltLabel: String {
        guard state.tiltExceeded else { return "Side tilt" }
        return state.tilt > 0 ? "Side tilt ◀" : "Side tilt ▶"
    }

    private func axisRow(_ title: String, value: String, flag: Color) -> some View {
        HStack {
            Circle().fill(flag).frame(width: 7, height: 7)
            Text(title).font(.caption)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    // MARK: Sit-time

    private var sitTimeSection: some View {
        HStack(spacing: 0) {
            statTile("On the perch", state.seatedContinuousString)
            statTile("Seated today", state.seatedTodayString)
            statTile("Coop breaks", "\(state.breaksToday)")
        }
    }

    // MARK: Session stats + chart

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                statTile("Good posture", String(format: "%.0f%%", state.goodPosturePercent))
                statTile("Pecks", "\(state.slouchEvents)")
                statTile("Session", state.monitoredTimeString)
            }

            Chart {
                ForEach(state.recentSamples) { sample in
                    LineMark(x: .value("Time", sample.t), y: .value("Forward load", sample.drop))
                        .interpolationMethod(.monotone)
                        // Colour by value, not current state: spikes into the
                        // orange/red bands are drawn orange/red and stay that way.
                        .foregroundStyle(loadGradient)
                }
                RuleMark(y: .value("Red line", state.threshold * 2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.red.opacity(0.5))
                RuleMark(y: .value("Orange line", state.threshold))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(.orange.opacity(0.5))
            }
            .chartXScale(domain: state.chartXDomain)
            .chartYScale(domain: 0...chartUpperBound)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: 64)
        }
    }

    /// Vertical gradient with stops at the orange (threshold) and red (2×) lines,
    /// so the chart line is green/orange/red according to how bad each point is.
    private var loadGradient: LinearGradient {
        let top = chartUpperBound
        let orange = min(0.999, state.threshold / top)
        let red = min(1.0, state.threshold * 2 / top)
        return LinearGradient(stops: [
            .init(color: .green,  location: 0),
            .init(color: .green,  location: orange),
            .init(color: .orange, location: orange),
            .init(color: .orange, location: red),
            .init(color: .red,    location: red),
            .init(color: .red,    location: 1)
        ], startPoint: .bottom, endPoint: .top)
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var chartUpperBound: Double {
        let peak = state.recentSamples.map(\.drop).max() ?? 0
        return max(state.threshold * 2.4, peak + 2)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            if state.isMonitoring {
                Button { state.stopMonitoring() } label: {
                    Label("Stop monitoring", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }
                Button {
                    state.isCalibrated ? state.recalibrate() : state.calibrate()
                } label: {
                    Label(state.isCalibrated ? "Recalibrate" : "Calibrate (sit tall)",
                          systemImage: state.isCalibrated ? "arrow.counterclockwise" : "scope")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!state.camera.hasFace)
            } else {
                Button { state.startMonitoring() } label: {
                    Label("Start monitoring", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { showHistory.toggle() } } label: {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                    Text("History")
                    Spacer()
                    Image(systemName: showHistory ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showHistory { historyBody }
        }
    }

    private var buckets: [HistoryBucket] {
        switch historyRange {
        case .daily:   return state.history.dailyBuckets(7)
        case .weekly:  return state.history.weeklyBuckets(8)
        case .monthly: return state.history.monthlyBuckets(6)
        }
    }

    private var historyChart: HistoryChart {
        HistoryChart(title: "\(historyRange.rawValue) — good vs. slouch (min)", buckets: buckets)
    }

    private var historyBody: some View {
        let data = buckets
        let totalAll = data.reduce(0) { $0 + $1.totalSeconds }
        let totalGood = data.reduce(0) { $0 + $1.goodSeconds }
        let percent = totalAll > 0 ? totalGood / totalAll * 100 : 0

        return VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $historyRange) {
                ForEach(HistoryRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if totalAll < 1 {
                Text("No history yet — finish a session to see your trends.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(String(format: "%@ overall: %.0f%% good · %.0f min tracked",
                            historyRange.rawValue, percent, totalAll / 60))
                    .font(.caption).foregroundStyle(.secondary)
                historyChart

                HStack(spacing: 8) {
                    Button {
                        DataExport.saveCSV(DataExport.csv(buckets: data, periodColumn: historyRange.rawValue),
                                           suggestedName: "ChickenNeck-\(historyRange.rawValue).csv")
                    } label: { Label("Export CSV", systemImage: "tablecells").frame(maxWidth: .infinity) }
                    Button {
                        DataExport.savePNG(of: historyChart,
                                           suggestedName: "ChickenNeck-\(historyRange.rawValue).png")
                    } label: { Label("Save graph", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                }
                .controlSize(.small)
                .font(.caption)
            }
        }
    }

    // MARK: Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { showSettings.toggle() } } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                    Spacer()
                    Image(systemName: showSettings ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showSettings { settingsBody }
        }
    }

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRow(title: "Forward sensitivity", value: $state.threshold, range: 5...30, suffix: "")
            sliderRow(title: "Side-tilt sensitivity", value: $state.tiltLimit, range: 5...30, suffix: "°")
            sliderRow(title: "Hold before alert", value: $state.holdSeconds, range: 1...10, suffix: "s")
            sliderRow(title: "Alert cooldown", value: $state.cooldown, range: 5...120, suffix: "s")

            Divider()

            Button { withAnimation(.easeInOut(duration: 0.18)) { showWellness.toggle() } } label: {
                HStack {
                    Image(systemName: "heart.text.square")
                    Text("Wellness reminders")
                    Spacer()
                    Image(systemName: showWellness ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showWellness {
                VStack(alignment: .leading, spacing: 10) {
                    Text("These fire whenever the app is open — no monitoring or calibration needed.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Toggle("Coop breaks (stand & stretch)", isOn: $state.breakRemindersOn)
                    if state.breakRemindersOn {
                        sliderRow(title: "Remind me every", value: $state.breakIntervalMin, range: 15...90, suffix: " min")
                    }
                    Toggle("Drink water reminder", isOn: $state.hydrationOn)
                    if state.hydrationOn {
                        sliderRow(title: "Remind me every", value: $state.hydrationIntervalMin, range: 20...120, suffix: " min")
                    }
                    Toggle("Rest your eyes (20-20-20)", isOn: $state.eyeRestOn)
                    if state.eyeRestOn {
                        sliderRow(title: "Eye break every", value: $state.eyeRestIntervalMin, range: 10...60, suffix: " min")
                    }
                    Toggle("Lunch reminder (1–2pm)", isOn: $state.lunchReminderOn)
                }
                .padding(.leading, 6)
            }

            Divider()

            HStack {
                Text("Alert sound")
                Spacer()
                Picker("", selection: $state.soundName) {
                    ForEach(AlertManager.availableSounds, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 110)
                Button { state.previewSound() } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.borderless).help("Preview sound")
            }
            .disabled(!state.soundEnabled)

            Toggle("Sound cue", isOn: $state.soundEnabled)
            Toggle("Spoken cue", isOn: $state.voiceEnabled)
            Toggle("On-screen popup alerts", isOn: $state.popupAlertsOn)
                .help("Chicken Neck draws its own banner — works without notification permission.")
            if state.popupAlertsOn {
                sliderRow(title: "Popup stays for", value: $state.popupSeconds, range: 2...15, suffix: "s")
            }
            Toggle("System notifications", isOn: $state.notificationsEnabled)
            Button {
                state.alerts.triggerTest()
            } label: {
                Label("Test alert", systemImage: "bell.badge").frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            Toggle("Show menu-bar chicken", isOn: $state.showMenuBarIcon)
            Toggle("Reverse forward detection", isOn: $state.invert)
                .help("Enable if alerts fire when you sit up instead of craning forward.")

            Divider()

            Toggle("Start at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }))
            if let loginError = state.loginItemError {
                Text(loginError).font(.caption2).foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(.top, 2)
    }

    private func sliderRow(title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))\(suffix)").foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("🐔 Keep your neck happy")
                Text("Built by Sumanth Raj Urs + Claude")
            }
            .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var statusColor: Color {
        if state.camera.lastError != nil { return .orange }
        if !state.isMonitoring { return state.isConnected ? .green : .secondary }
        if !state.camera.hasFace || !state.isCalibrated { return .blue }
        switch state.severity {
        case .good:    return .green
        case .mild:    return .orange
        case .severe:  return .red
        case .unknown: return .secondary
        }
    }
}
