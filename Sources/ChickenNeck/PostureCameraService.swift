import Foundation
import AVFoundation
import Vision

/// One frame of raw, calibration-independent posture geometry from the camera.
struct PostureReading {
    var pitch: Double      // head tilt up(+)/down(-), degrees
    var roll: Double       // lateral head tilt toward a shoulder, degrees
    var yaw: Double        // head rotation left/right, degrees
    var boxHeight: Double  // face size, 0…1 of frame (proxy for closeness/forward lean)
    var centerX: Double    // face horizontal position, 0…1
    var centerY: Double    // face vertical position, 0…1 (drops as you slump down)
}

/// Watches you through the Mac camera with Apple's Vision framework — fully
/// on-device, nothing recorded or sent — and reports head/neck geometry every
/// frame. All the clinical interpretation happens in `PostureAnalyzer`.
final class PostureCameraService: NSObject, ObservableObject {

    // MARK: Published state (main thread only)

    @Published private(set) var isAvailable = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var hasFace = false
    @Published private(set) var deviceName = ""
    @Published private(set) var lastError: String?

    /// Called for every processed frame, or nil when no face is visible.
    var onReading: ((PostureReading?) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "chickenneck.camera")
    private var isRunning = false

    // Touched only on `videoQueue`.
    private var lastProcessed = Date.distantPast
    private var lastFaceSeen = Date.distantPast
    // Face-only detection is light, so ~8 fps gives snappy neck tracking while
    // staying easy on CPU/battery/heat. (Other frames are discarded untouched.)
    private let minInterval = 0.12

    override init() {
        super.init()
        let device = AVCaptureDevice.default(for: .video)
        isAvailable = device != nil
        deviceName = device?.localizedName ?? ""
        refreshAuth()
    }

    private func refreshAuth() {
        isAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func start() {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.refreshAuth()
                    if granted {
                        self?.configureAndRun()
                    } else {
                        self?.lastError = "Camera access denied. Enable it in System Settings ▸ Privacy & Security ▸ Camera."
                    }
                }
            }
        default:
            refreshAuth()
            lastError = "Camera access denied. Enable it in System Settings ▸ Privacy & Security ▸ Camera."
        }
    }

    private func configureAndRun() {
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
            // Cap the camera to ~15 fps so the system isn't handing us (then
            // discarding) 30 fps buffers — a big CPU/heat saving.
            if (try? device.lockForConfiguration()) != nil {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
                device.unlockForConfiguration()
            }
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

        isRunning = true
        lastError = nil
        videoQueue.async { [weak self] in self?.session.startRunning() }
    }

    func stop() {
        guard isRunning else { return }
        videoQueue.async { [weak self] in self?.session.stopRunning() }
        isRunning = false
        hasFace = false
    }
}

extension PostureCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        if now.timeIntervalSince(lastProcessed) < minInterval { return }
        lastProcessed = now

        let faceReq = VNDetectFaceRectanglesRequest()
        faceReq.revision = VNDetectFaceRectanglesRequestRevision3   // gives roll/yaw/pitch
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([faceReq])
        } catch {
            return
        }

        // Largest face = the person at the desk; ignore background faces.
        guard let face = (faceReq.results)?.max(by: { $0.boundingBox.height < $1.boundingBox.height }) else {
            let clear = now.timeIntervalSince(lastFaceSeen) > 1.0
            if clear {
                DispatchQueue.main.async { [weak self] in
                    self?.hasFace = false
                    self?.onReading?(nil)
                }
            }
            return
        }
        lastFaceSeen = now

        let box = face.boundingBox          // normalized, origin bottom-left, y up
        let deg = 180.0 / Double.pi
        let reading = PostureReading(
            pitch: (face.pitch?.doubleValue ?? 0) * deg,
            roll:  (face.roll?.doubleValue  ?? 0) * deg,
            yaw:   (face.yaw?.doubleValue   ?? 0) * deg,
            boxHeight: box.height,
            centerX: box.midX,
            centerY: box.midY
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasFace = true
            self.lastError = nil
            self.onReading?(reading)
        }
    }
}
