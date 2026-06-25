import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

/// Reusable bar chart for a set of history buckets, used both on screen and
/// when exporting a graph image.
struct HistoryChart: View {
    let title: String
    let buckets: [HistoryBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart(buckets) { b in
                BarMark(x: .value("Period", b.label), y: .value("Good", b.goodMinutes))
                    .foregroundStyle(.green)
                BarMark(x: .value("Period", b.label), y: .value("Slouch", b.badMinutes))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .chartYAxisLabel("min")
            .frame(height: 110)
            HStack(spacing: 12) {
                Label("Good", systemImage: "square.fill").foregroundStyle(.green)
                Label("Slouch", systemImage: "square.fill").foregroundStyle(.red.opacity(0.7))
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Saves posture history as a CSV file or a PNG of the graph, via a save panel.
enum DataExport {

    static func csv(buckets: [HistoryBucket], periodColumn: String) -> String {
        var s = "\(periodColumn),Good minutes,Slouch minutes,Good %\n"
        for b in buckets {
            s += String(format: "%@,%.1f,%.1f,%.0f\n", b.label, b.goodMinutes, b.badMinutes, b.goodPercent)
        }
        return s
    }

    static func saveCSV(_ text: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.data(using: .utf8)?.write(to: url)
        }
    }

    @MainActor
    static func savePNG(of chart: HistoryChart, suggestedName: String) {
        let renderer = ImageRenderer(content:
            chart.padding(16).frame(width: 520).background(Color(NSColor.windowBackgroundColor)))
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }
}
