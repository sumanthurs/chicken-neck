import Foundation
import AVFoundation
import Vision

/// One frame of raw, calibration-independent posture geometry from the camera.
struct PostureReading {
    var pitch: Double?         // head tilt up(+)/down(-), degrees; nil if Vision can't supply it
    var roll: Double           // lateral head tilt toward a shoulder, degrees
    var yaw: Double            // head rotation left/right, degrees
    var boxHeight: Double      // face size, 0…1 of frame (proxy for closeness/forward lean)
    var centerY: Double        // face vertical position, 0…1 (drops as you slump down)
    var eyeChinSpan: Double?   // eye→chin vertical span in face-box units; nil w/o landmarks.
                               // Intrinsic & scale-free: shrinks as you tuck the chin / look down.
}

/// Watches you through the Mac camera with Apple's Vision framework, fully
/// on-device, nothing recorded or sent, and reports head/neck geometry every
/// frame. All the clinical interpretation happens in `PostureAnalyzer`.
final class PostureCameraService: NSObject, ObservableObject {

    // MARK: Published state (main thread only)

    @Published private(set) var isAvailable = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var hasFace = false
    @Published private(set) var deviceName = ""
    @Published private(set) var lastError: String?
    /// False when Vision isn't supplying head-pitch on this OS, so the chin-tuck
    /// cue is silently absent rather than wrong. Surfaced for diagnostics.
    @Published private(set) var pitchAvailable = true

    /// Called for every processed frame, or nil when no face is visible.
    var onReading: ((PostureReading?) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "chickenneck.camera")
    // start()/stop() are user-driven and run on the main thread; these flags are
    // only touched there to keep the lifecycle race-free.
    private var isRunning = false
    private var isStarting = false

    // Reused across frames; safe because perform() runs serially on videoQueue.
    private lazy var faceRequest: VNDetectFaceLandmarksRequest = {
        let req = VNDetectFaceLandmarksRequest()
        req.revision = VNDetectFaceLandmarksRequestRevision3   // landmarks + roll/yaw/pitch
        return req
    }()

    // Touched only on `videoQueue`.
    private var lastFaceSeen = Date.distantPast
    private var faceCleared = true        // latches the "no face" edge so we emit nil once
    private var lastProcessed = Date.distantPast

    // Software throttle backstopping the hardware frame-rate pin (see
    // `capCameraFrameRate`), in case that pin fails to apply: never detect faster
    // than the target rate. The 0.9 margin avoids dropping jittery-but-valid frames.
    private let minProcessInterval = 0.9 / PostureDynamics.minUsableFPS

    // Session-health observers (D14). `shouldRun` mirrors the desired run state on
    // `videoQueue` so a recovery restart can't resurrect a session the user
    // stopped; `restartAttempts` bounds the retry loop on permanent failure.
    private var observers: [NSObjectProtocol] = []
    private var shouldRun = false           // videoQueue only
    private var restartAttempts = 0         // videoQueue only
    private let maxRestartAttempts = 5

    override init() {
        super.init()
        let device = AVCaptureDevice.default(for: .video)
        isAvailable = device != nil
        deviceName = device?.localizedName ?? ""
        refreshAuth()
    }

    deinit { removeObservers() }

    private func refreshAuth() {
        isAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    private static let accessDeniedMessage =
        "Camera access denied. Enable it in System Settings ▸ Privacy & Security ▸ Camera."

    func start() {
        guard !isRunning, !isStarting else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isStarting = true
            configureAndRun()
        case .notDetermined:
            isStarting = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.refreshAuth()
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.isStarting = false
                        self.lastError = Self.accessDeniedMessage
                    }
                }
            }
        default:
            refreshAuth()
            lastError = Self.accessDeniedMessage
        }
    }

    private func configureAndRun() {
        defer { isStarting = false }
        guard let device = AVCaptureDevice.default(for: .video) else {
            lastError = "No camera found."
            return
        }
        deviceName = device.localizedName
        isAvailable = true

        session.beginConfiguration()
        // Low resolution is plenty for face geometry and far cheaper on CPU/battery.
        for preset in [AVCaptureSession.Preset.cif352x288, .low, .vga640x480] {
            if session.canSetSessionPreset(preset) { session.sessionPreset = preset; break }
        }

        session.inputs.forEach { session.removeInput($0) }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            capCameraFrameRate(device)
        } catch {
            session.commitConfiguration()
            lastError = error.localizedDescription
            return
        }

        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        session.commitConfiguration()

        registerObservers()
        isRunning = true
        lastError = nil
        videoQueue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = true
            self.restartAttempts = 0
            self.session.startRunning()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeObservers()
        videoQueue.async { [weak self] in
            self?.shouldRun = false
            self?.session.stopRunning()
        }
        hasFace = false
    }

    // MARK: Session-health recovery (D14)

    private func registerObservers() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVCaptureSessionRuntimeError,
                                        object: session, queue: .main) { [weak self] note in
            guard let self, self.isRunning else { return }
            let err = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self.lastError = err?.localizedDescription ?? "Camera session error; recovering..."
            // Common when the camera was briefly grabbed by another app.
            self.attemptSessionRestart()
        })
        observers.append(nc.addObserver(forName: .AVCaptureSessionWasInterrupted,
                                        object: session, queue: .main) { [weak self] _ in
            self?.lastError = "Camera in use by another app or unavailable."
        })
        observers.append(nc.addObserver(forName: .AVCaptureSessionInterruptionEnded,
                                        object: session, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.lastError = nil
            self.attemptSessionRestart()
        })
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    /// Restart after a recoverable fault, on `videoQueue` so it's ordered with
    /// start()/stop(). `shouldRun` stops it resurrecting a session the user
    /// stopped; the attempt cap stops a tight loop on a permanently-gone camera.
    private func attemptSessionRestart() {
        videoQueue.async { [weak self] in
            guard let self, self.shouldRun, !self.session.isRunning,
                  self.restartAttempts < self.maxRestartAttempts else { return }
            self.restartAttempts += 1
            self.session.startRunning()
        }
    }

    /// Pin the capture to a constant `minUsableFPS`, clamped into the supported
    /// range. Setting *both* min and max frame duration fixes the rate: the min
    /// caps the ceiling (cheap on CPU/heat), the max enforces the floor so the
    /// camera can't drift below it in low light and alias posture changes.
    /// Clamping is also load-bearing: an out-of-range duration throws an
    /// uncatchable Objective-C exception that aborts the app.
    private func capCameraFrameRate(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        guard let range = device.activeFormat.videoSupportedFrameRateRanges
            .max(by: { $0.maxFrameRate < $1.maxFrameRate }) else { return }
        let fps = min(max(PostureDynamics.minUsableFPS, range.minFrameRate), range.maxFrameRate)
        let duration = CMTime(value: 1, timescale: Int32(fps.rounded()))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }
}

extension PostureCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        // Software backstop in case the hardware frame-rate pin didn't apply.
        if now.timeIntervalSince(lastProcessed) < minProcessInterval { return }
        lastProcessed = now
        // Frames are flowing, so any recovery succeeded; allow future retries.
        restartAttempts = 0

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([faceRequest])
        } catch {
            return
        }

        // Largest face = the person at the desk; ignore background faces.
        guard let face = (faceRequest.results)?.max(by: { $0.boundingBox.height < $1.boundingBox.height }) else {
            // Emit the "no face" event exactly once on the falling edge, then stay
            // quiet until a face returns, no per-frame nil spam while you're away.
            if !faceCleared, now.timeIntervalSince(lastFaceSeen) > 1.0 {
                faceCleared = true
                DispatchQueue.main.async { [weak self] in
                    self?.hasFace = false
                    self?.onReading?(nil)
                }
            }
            return
        }
        lastFaceSeen = now
        faceCleared = false

        let box = face.boundingBox          // normalized, origin bottom-left, y up
        let deg = 180.0 / Double.pi
        let pitch = face.pitch.map { $0.doubleValue * deg }
        let reading = PostureReading(
            pitch: pitch,
            roll:  (face.roll?.doubleValue ?? 0) * deg,
            yaw:   (face.yaw?.doubleValue  ?? 0) * deg,
            boxHeight: box.height,
            centerY: box.midY,
            eyeChinSpan: Self.eyeChinSpan(face.landmarks)
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasFace = true
            self.pitchAvailable = (pitch != nil)
            self.lastError = nil
            self.onReading?(reading)
        }
    }

    /// Distance from the eye line down to the chin, in face-box units. Landmarks
    /// are normalized within the face box, so this ratio is intrinsic: it doesn't
    /// change with distance or position, only with chin-tuck / looking down
    /// (foreshortening), which is exactly the forward-head signal we want.
    ///
    /// Two choices keep it from drifting with lateral head roll: the chin is the
    /// extreme of the face *midline* (which tracks the chin tip, not a jaw corner
    /// that a tilt would push lowest), and the eye->chin span is a Euclidean
    /// distance (rotation-invariant), not a raw vertical delta (which would
    /// shrink by cos(roll) as you tilt).
    private static func eyeChinSpan(_ landmarks: VNFaceLandmarks2D?) -> Double? {
        guard let landmarks,
              let leftEye = landmarks.leftEye?.normalizedPoints,
              let rightEye = landmarks.rightEye?.normalizedPoints,
              !leftEye.isEmpty, !rightEye.isEmpty else { return nil }

        // Chin = lowest point of the face midline (fallback to the jaw contour).
        let chinPoints = landmarks.medianLine?.normalizedPoints
            ?? landmarks.faceContour?.normalizedPoints
        guard let chin = chinPoints?.min(by: { $0.y < $1.y }) else { return nil }

        let eyePoints = leftEye + rightEye
        let n = Double(eyePoints.count)
        let eyeX = eyePoints.reduce(0.0) { $0 + Double($1.x) } / n
        let eyeY = eyePoints.reduce(0.0) { $0 + Double($1.y) } / n
        let dx = eyeX - Double(chin.x)
        let dy = eyeY - Double(chin.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
