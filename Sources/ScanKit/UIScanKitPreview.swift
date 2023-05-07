//
//  UIScanKitPreview.swift
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

#if os(iOS)
import SwiftUI
import UIKit
import AVFoundation
import Vision
import OSLog

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.fromshawn.scankit", category: "ScanKit")

//TODO: Decouple model from UIViewController :(

public struct ScanKitPreview: UIViewControllerRepresentable {
    var camera: ScanKitCamera
    
    public init(camera: ScanKitCamera) {
        self.camera = camera
    }
    
    public func makeUIViewController(context: Context) -> UIScanKitPreview {
        return UIScanKitPreview(camera: camera)
    }
    
    public func updateUIViewController(_ uiViewController: UIScanKitPreview, context: Context) {
        // Do nothing
    }
}

public class UIScanKitPreview: UIViewController {
    weak var camera: ScanKitCamera?
    
    init(camera: ScanKitCamera) {
        self.camera = camera
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        addPreviewLayer()
        CATransaction.commit()
        
        // Start the camera
        Task(priority: .userInitiated) { [weak self] in
            await self?.camera?.start()
        }
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        camera?.stop()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update video orientation on rotate
        guard let connection = camera?.previewLayer.connection else { return }
        if connection.isVideoOrientationSupported {
            print("updating orientation...")
            Task { @MainActor in
                connection.videoOrientation = appropriateVideoOrientation
            }
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.camera?.previewLayer.frame = self.view.bounds
        CATransaction.commit()
    }
    
    private func addPreviewLayer() {
        if let previewLayer = self.camera?.previewLayer {
            previewLayer.frame = self.view.bounds
            self.view.layer.addSublayer(previewLayer)
        }
    }
    
    private var appropriateVideoOrientation: AVCaptureVideoOrientation {
        let orientation = UIDevice.current.orientation
        
        // If the device orientation cannot be found, check the UI instead...
        if orientation == .unknown {
            return videOrientationFromInterfaceOrientation(self.preferredInterfaceOrientationForPresentation)
        }
        return videoOrientationFromDeviceOrientation(orientation)
    }
    
    /// Converts a `UIInterfaceOrientation` to an appropriate `AVCaptureVideoOrientation` equivalent.
    private func videOrientationFromInterfaceOrientation(_ interfaceOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch interfaceOrientation {
        case .unknown: return .portrait
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portrait
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }
    
    /// Converts a `UIDeviceOrientation` to an appropriate `AVCaptureVideoOrientation` equivalent.
    private func videoOrientationFromDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .faceUp: return .landscapeRight
        case .faceDown: return .landscapeRight
        default: return .portrait
        }
    }
}

#endif
