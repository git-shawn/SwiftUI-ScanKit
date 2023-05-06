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

#if os(iOS)
import SwiftUI
import UIKit
import AVFoundation
import Vision
import OSLog

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.fromshawn.scankit", category: "ScanKit")

//TODO: Decouple model from UIViewController :(

struct ScanKitPreview: UIViewControllerRepresentable {
    var camera: ScanKitCamera
    
    init(camera: ScanKitCamera) {
        self.camera = camera
    }
    
    func makeUIViewController(context: Context) -> UICodeScanner {
        return UICodeScanner(camera: camera)
    }
    
    func updateUIViewController(_ uiViewController: UICodeScanner, context: Context) {
        // Do nothing!
    }
}

class UICodeScanner: UIViewController {
    weak var camera: ScanKitCamera?
    
    private var deviceOrientation: UIDeviceOrientation {
        var orientation = UIDevice.current.orientation
        if orientation == UIDeviceOrientation.unknown {
            orientation = .portrait
        }
        return orientation
    }
    
    init(camera: ScanKitCamera) {
        self.camera = camera
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addPreviewLayer()
        
        // Start the camera
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.camera?.start()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camera?.stop()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update video orientation on rotate
        guard let connection = camera?.previewLayer.connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation(for: deviceOrientation)
        }
        
        self.camera?.previewLayer.frame = self.view.bounds
    }
    
    private func addPreviewLayer() {
        if let previewLayer = self.camera?.previewLayer {
            self.view.layer.addSublayer(previewLayer)
        }
    }
    
    /// Converts a `UIDeviceOrientation` to an appropriate `AVCaptureVideoOrientation` equivalent.
    private func videoOrientation(for deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .portrait: return AVCaptureVideoOrientation.portrait
        case .portraitUpsideDown: return AVCaptureVideoOrientation.portraitUpsideDown
        case .landscapeLeft: return AVCaptureVideoOrientation.landscapeRight
        case .landscapeRight: return AVCaptureVideoOrientation.landscapeLeft
        default: return .portrait
        }
    }
}

#endif
