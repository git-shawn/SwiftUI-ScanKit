//
//  ScanKit.swift
//  SwiftUI ScanKit
//
//  Copyright © 2023 Shawn Davis
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import AVFoundation
import Vision
import OSLog
import SwiftUI
import Combine

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.fromshawn.scankit", category: "ScanKitCamera")

public class ScanKitCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private var isCaptureSessionConfigured: Bool = false
    weak private var deviceInput: AVCaptureDeviceInput?
    weak private var videoOutput: AVCaptureVideoDataOutput?
    private var sessionQueue: DispatchQueue = DispatchQueue(label: "ScanKitCameraQueue")
    
    // MARK: - Capture Devices
    
    /// Results of a comprehensive capture device discovery session.
    private var allCaptureDevices: [AVCaptureDevice] {
#if os(iOS)
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera, .builtInDualWideCamera], mediaType: .video, position: .unspecified).devices
#else
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified).devices
#endif
    }
    
    /// The results of `allCaptureDevices` reduced to only those positioned at `.front`.
    private var frontCaptureDevices: [AVCaptureDevice] {
        allCaptureDevices
            .filter { $0.position == .front }
    }
    
    /// The results of `allCaptureDevices` reduced to only those positioned at `.back`.
    private var backCaptureDevices: [AVCaptureDevice] {
        allCaptureDevices
            .filter { $0.position == .back }
    }
    
    private var captureDevices: [AVCaptureDevice] {
        var devices = [AVCaptureDevice]()
#if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
        devices += allCaptureDevices
#else
        if let backDevice = backCaptureDevices.first {
            devices += [backDevice]
        }
        if let frontDevice = frontCaptureDevices.first {
            devices += [frontDevice]
        }
#endif
        return devices
    }
    
    /// All capture devices, reduced from `captureDevices`, that are both available and not suspended.
    private var availableCaptureDevices: [AVCaptureDevice] {
        captureDevices
            .filter( { $0.isConnected } )
            .filter( { !$0.isSuspended } )
    }
    
    /// The capture device in use.
    private var captureDevice: AVCaptureDevice? {
        didSet {
            guard let captureDevice = captureDevice else { return }
            logger.debug("ScanKit connected to \(captureDevice.localizedName)")
            sessionQueue.async {
                self.updateSessionForCaptureDevice(captureDevice)
            }
        }
    }
    
    /// Creates a SwiftUI `View` containing all available cameras as `Button`s.
    /// When a button is selected, the camera it represents will be made active.
    /// - Returns: A `View` containing a dynamic number of `Button`s.
    public func getCamerasAsButtons() -> some View {
        ForEach(availableCaptureDevices, id: \.modelID) { device in
            Button(device.localizedName, action: {
                self.captureDevice = device
            })
        }
    }
    
    /// A Boolean value indicating whether or not the camera is active.
    public var isCapturing: Bool {
        captureSession.isRunning
    }
    
    /// A Boolean value indicating whether or not the camera is front-facing. On macOS this is always false.
    public var isUsingFrontCamera: Bool {
        guard let captureDevice = captureDevice else { return false }
        return frontCaptureDevices.contains(captureDevice)
    }
    
    /// A Boolean value indicating whether or not the camera is rear-facing. On macOS this is always false.
    public var isUsingBackCamera: Bool {
        guard let captureDevice = captureDevice else { return false }
        return backCaptureDevices.contains(captureDevice)
    }
    
    /// A Boolean value indicating whether or not the current device has multiple cameras available to access.
    public var hasMultipleCaptureDevices: Bool {
        availableCaptureDevices.count > 1
    }
    
    /// Switch between known capture devices cyclically.
    /// On iOS devices this function cycles between only the front and rear cameras.
    public func cycleCaptureDevices() {
        if let captureDevice = captureDevice, let index = availableCaptureDevices.firstIndex(of: captureDevice) {
            let nextIndex = (index + 1) % availableCaptureDevices.count
            self.captureDevice = availableCaptureDevices[nextIndex]
        } else {
            self.captureDevice = AVCaptureDevice.default(for: .video)
            self.previewLayer.session = captureSession
        }
    }
    
    // MARK: - Init/Configure
    
    /// Create a ScanKit camera with the first available camera.
    override public init() {
        super.init()
        initialize()
    }
    
    /// Create a ScanKit camera with the first available camera.
    private func initialize() {
        captureDevice = availableCaptureDevices.first ?? AVCaptureDevice.default(for: .video)
    }
    
    /// Configure the capture delegate with relevent parameters and properties.
    /// - Parameter completionHandler: `true` if configuration completely successfully, `false` if not.
    private func configureCaptureSession(completionHandler: (_ success: Bool) -> ()) {
        var success = false
        self.captureSession.beginConfiguration()
        defer {
            self.captureSession.commitConfiguration()
            completionHandler(success)
        }
        
        guard let captureDevice = captureDevice,
              let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
        else {
            logger.error("Could not configure camera for capture.")
            return
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "ScanKitVideoDataOutputQueue"))
        
        guard captureSession.canAddInput(deviceInput) else {
            logger.error("Could not add camera input to configuration.")
            return
        }
        
        guard captureSession.canAddOutput(videoOutput) else {
            logger.error("Could not add camera output to configuration.")
            return
        }
        
        captureSession.addInput(deviceInput)
        captureSession.addOutput(videoOutput)
        
        self.deviceInput = deviceInput
        self.videoOutput = videoOutput
        
#if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 16, *) {
            if captureSession.isMultitaskingCameraAccessSupported {
                captureSession.isMultitaskingCameraAccessEnabled = true
            }
        }
#endif
        updateVideoOutputConnection()
        isCaptureSessionConfigured = true
        success = true
    }
    
    private func updateSessionForCaptureDevice(_ captureDevice: AVCaptureDevice) {
        guard isCaptureSessionConfigured else { return }
        
        Task { @MainActor in
            // Update computed variables across SwiftUI including things like 'isTorchAvailable.'
            objectWillChange.send()
        }
        
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
        }
        
        for input in captureSession.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput {
                captureSession.removeInput(deviceInput)
            }
        }
        
        if let deviceInput = deviceInputFor(device: captureDevice) {
            if !captureSession.inputs.contains(deviceInput),
               captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            }
        }
        
        updateVideoOutputConnection()
    }
    
    private func updateVideoOutputConnection() {
        if let videoOutput = videoOutput, let videoOutputConnection = videoOutput.connection(with: .video) {
            if videoOutputConnection.isVideoMirroringSupported {
#if os(iOS) && !targetEnvironment(macCatalyst)
                videoOutputConnection.isVideoMirrored = isUsingFrontCamera
#endif
            }
        }
    }
    
    // MARK: - Authorize
    
    /// Determine camera authorization status. This method will request camera access if authorization status cannot be determined.
    /// - Returns: `true` if authorized, `false` if not.
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            sessionQueue.suspend()
            let status = await AVCaptureDevice.requestAccess(for: .video)
            sessionQueue.resume()
            return status
        case .denied:
            logger.notice("Camera access was denied.")
            return false
        case .restricted:
            logger.notice("Camera access is restricted.")
            return false
        @unknown default:
            logger.notice("The camera authorization request returned a bizarre, unknown state.")
            return false
        }
    }
    
    /// Determine the `AVCaptureDeviceInput` for an `AVCaptureDevice`
    /// - Parameter device: A capture device to get the input of.
    /// - Returns: An associated `AVCaptureDeviceInput` if any, else `nil`.
    private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else { return nil }
        do {
            return try AVCaptureDeviceInput(device: validDevice)
        } catch {
            logger.error("Could not convert a known capture device into a valid video input source.")
            return nil
        }
    }
    
    // MARK: - Torch
    
    /// A Boolean value indicating whether a persistent flash, or *torch*, is available.
    public var isTorchAvailable: Bool {
        return captureDevice?.isTorchModeSupported(.on) ?? false
    }
    
    /// A Boolean value indicating whether or the persistent flash, or *torch*, is active.
    public var isTorchOn: Bool {
        captureDevice?.isTorchActive ?? false
    }
    
    /// Toggles the camera's persistent flash, or *torch*, if available.
    /// If ``isTorchAvailable`` is false this function does nothing.
    public func toggleTorch() {
        if isTorchAvailable, let captureDevice = captureDevice {
            do {
                try captureDevice.lockForConfiguration()
                defer { captureDevice.unlockForConfiguration() }
                Task { @MainActor in
                    objectWillChange.send()
                }
                captureDevice.torchMode = isTorchOn ? .off : .on
            } catch {
                logger.error("Torch mode could not be set.")
            }
        }
    }
    
    // MARK: - Start/Stop
    
    /// Start capturing video from the camera.
    /// - Warning: ``stop()`` must be called to deactivate the camera.
    /// Leaving the camera active after use is a resource waste and a poor user experience.
    public func start() async {
        guard await checkAuthorization() else {
            if self.isScanning { addToResultStream?(.failure(ScanKitError.notAuthorized)) }
            return
        }
        
        if isCaptureSessionConfigured {
            if !isCapturing {
                sessionQueue.async { [weak self] in
                    self?.captureSession.startRunning()
                }
            }
            return
        }
        
        sessionQueue.async { [weak self] in
            self?.configureCaptureSession { success in
                guard success else { return }
                self?.captureSession.startRunning()
            }
        }
        
    }
    
    /// Stop capturing video from the camera. If``isCapturing`` is false, this function does nothing.
    public func stop() {
        guard isCaptureSessionConfigured, isCapturing else { return }
        
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    // MARK: - Preview Layer
    
    /// The preview layer with a graviety of `resizeAspectFill`.
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
        preview.videoGravity = .resizeAspectFill
        return preview
    }()
    
    // MARK: - Vision
    
    // Vision Iterator will overflow after nine quintillion frames.
    // At 30fps, that would be nearly ten million millennium. <- Fun Fact!
    private var visionIterator: UInt64 = 0
    private let sequenceHandler = VNSequenceRequestHandler()
    
    /// A Boolean value indicating whether or not the camera is scanning for machine readable codes.
    public var isScanning: Bool = false
    
    /// The current symbology being detected by the camera.
    /// Use the ``supportedSymbologies`` property to indicate the specific symbologies the request detects.
    public var symbology: VNBarcodeSymbology = .qr
    
    /// An array of symbologies supported by the scanner.
    public var supportedSymbologies: [VNBarcodeSymbology] {
        VNDetectBarcodesRequest.supportedSymbologies
    }
    
    /// A method of `AVCaptureVideoDataOutputSampleBufferDelegate` that, for the purposes of this class, processes `Vision` requests.
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only process every tenth frame when scanning is true
        visionIterator += 1
        guard (visionIterator % 10 == 0), isScanning else { return }
        
        guard let candidate = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.error("Could not extract frame from sample buffer.")
            addToResultStream?(.failure(ScanKitError.visionFailed))
            return
        }
        
        if let payload = self.detectSymbology(symbology, from: candidate) {
            addToResultStream?(.success(payload))
        }
    }
    
    /// Attemps to detect an instance of the defined `symbology` in a `CVImageBuffer`.
    /// - Parameters:
    ///   - symbology: The `VNBarcodeSymbology` to search for.
    ///   - candidate: A `CVImageBuffer` frame that may potentially contain an instance of the defined `symbology`.
    /// - Returns: The data encoded as the symbology, if any.
    private func detectSymbology(_ symbology: VNBarcodeSymbology, from candidate: CVImageBuffer) -> String? {
        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.qr]
        try? self.sequenceHandler.perform([barcodeRequest], on: candidate)
        guard let results = barcodeRequest.results, let firstBarcode = results.first?.payloadStringValue else {
            return nil
        }
        return firstBarcode
    }
    
    /// Send a value to the `ResultStream`
    private var addToResultStream: ((Result<String, Error>) -> Void)?
    
    /// Results from the scanner as a asynchronous stream of `String`. Any failures in the scan process will throw a ``ScanKitError`` and will terminate the stream.
    ///
    /// Successful instances of ``symbology`` detected by the camera will yield `String` via this stream.
    /// If, at any point during the scanning session, ``isScanning`` is set to `false` the stream will finish and the stream will cease.
    /// You may need to call this function again if you wish to restart the scanning process.
    ///
    /// ```
    /// @StateObject var camera = ScanKitCamera()
    /// ...
    /// .task {
    ///     do {
    ///         for try await result in camera.resultsStream {
    ///             print(result)
    ///         }
    ///     } catch let error {
    ///         print(error)
    ///     }
    /// }
    /// ```
    ///
    /// It is possible to recieve an empty `String` if the code does not contain any data. Be prepared to handle that.
    ///
    /// - Warning: This stream subscribes absolutely to the scanning process and will be retained until `isScanning` is set to `false`.
    /// - Returns: An `AsyncThrowingStream` which yields `String` on success and `ScanKitError` on failure.
    public var resultsStream: AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream<String, Error> { continuation in
            addToResultStream = { [weak self] result in
                if (self?.isScanning ?? false) {
                    switch result {
                    case .success(let payload):
                        continuation.yield(payload)
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                } else {
                    continuation.finish()
                }
            }
        }
    }
}
