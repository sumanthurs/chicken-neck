import Foundation
import AppKit
import AVFoundation
import UserNotifications

/// Delivers nudges: a system sound, an optional spoken cue, and a macOS
/// notification. Posture nudges share a cooldown; the coop-break and lunch
/// reminders are gated by `AppState` instead.
final class AlertManager {

    /// macOS system sounds (from /System/Library/Sounds) offered as alert cues.
    static let availableSounds = [
        "Funk", "Glass", "Ping", "Submarine", "Hero",
        "Tink", "Sosumi", "Pop", "Purr", "Bottle", "Blow"
    ]

    var soundEnabled = true
    var voiceEnabled = false
    var notificationEnabled = true     // macOS Notification Center (best-effort)
    var popupEnabled = true            // our own on-screen banner (always works)
    var popupSeconds: TimeInterval = 4 // how long the banner stays on screen
    var cooldown: TimeInterval = 30
    var soundName = "Funk" {
        didSet { reloadSound() }
    }

    private var lastPostureAlert: Date?
    private let synth = AVSpeechSynthesizer()
    private var sound = NSSound(named: "Funk")

    private func reloadSound() {
        sound = NSSound(named: NSSound.Name(soundName)) ?? NSSound(named: "Funk")
    }

    func previewSound() {
        sound?.stop()
        sound?.play()
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func resetCooldown() { lastPostureAlert = nil }

    // MARK: Posture nudge (red / severe forward head)

    func triggerPostureAlert(issue: PostureIssue, severe: Bool, now: Date = Date()) {
        if let last = lastPostureAlert, now.timeIntervalSince(last) < cooldown { return }
        lastPostureAlert = now

        let (title, body, spoken): (String, String, String)
        switch issue {
        case .tooClose:
            title = "Back off the feed! 🐔"
            body  = "You're pecking at the screen. Sit back and stack your head over your shoulders."
            spoken = "Sit back. Keep your neck straight."
        case .forward, .none:
            if severe {
                title = "FULL CHICKEN PECK! 🐔🚨"
                body  = "Sit up straight — neck straight, chin tucked, head back over your shoulders. Now!"
                spoken = "Sit up straight. Keep your neck straight."
            } else {
                title = "Easy there, hen 🐔"
                body  = "Your head's creeping forward. Pull it back over your shoulders and keep your neck straight."
                spoken = "Keep your neck straight."
            }
        case .tiltLeft, .tiltRight:
            title = "Head-cock alert 🐤"
            body  = "You've been tilting to one side. Level your noggin and keep your neck straight."
            spoken = "Level your head. Keep your neck straight."
        case .rotated:
            title = "Curious cluck 🐔"
            body  = "You've been craning to the side. Square up and keep your neck straight."
            spoken = "Face the screen. Keep your neck straight."
        }
        fire(title: title, body: body, spoken: spoken)
    }

    // MARK: Coop break (sat too long)

    func triggerCoopBreak(minutes: Int) {
        fire(title: "Off the perch! 🐔💨",
             body: "You've been roosting for \(minutes) min straight. Stand up, flap your wings, take a quick lap.",
             spoken: "Time to stand up and stretch.")
    }

    // MARK: Lunch (1–2pm)

    func triggerLunch() {
        fire(title: "Feed the chicken! 🐔🌽",
             body: "It's grub o'clock. Go peck some lunch before you turn into a hangry hen.",
             spoken: "Time to grab some lunch.")
    }

    // MARK: Hydration

    func triggerHydration() {
        fire(title: "Drink some water 💧",
             body: "Time for a sip of water — stay hydrated.",
             spoken: "Time to drink some water.")
    }

    // MARK: Eye rest (20-20-20)

    func triggerEyeRest() {
        fire(title: "Rest your eyes 👀",
             body: "Look at something about 20 feet away for 20 seconds.",
             spoken: "Look away from the screen and rest your eyes.")
    }

    // MARK: Plumbing

    /// Fire a test alert so the user can confirm popups/sound work.
    func triggerTest() {
        lastPostureAlert = nil
        fire(title: "Test cluck 🐔", body: "If you can see this, your alerts are working. Bawk!",
             spoken: "Alerts are working.")
    }

    private func fire(title: String, body: String, spoken: String) {
        if soundEnabled {
            sound?.stop()
            sound?.play()
        }
        if voiceEnabled {
            let u = AVSpeechUtterance(string: spoken)
            u.rate = 0.5
            synth.speak(u)
        }
        // Our own on-screen banner — reliable without notification permission.
        if popupEnabled {
            let seconds = popupSeconds
            DispatchQueue.main.async { PopupAlert.shared.show(title: title, message: body, duration: seconds) }
        }
        // Also post to Notification Center if it happens to be authorized.
        if notificationEnabled {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil   // we play our own cue
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
