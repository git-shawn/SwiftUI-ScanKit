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

#if os(macOS)
import SwiftUI
import AppKit
import AVFoundation
import Vision
import OSLog

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.fromshawn.scankit", category: "ScanKit")

struct ScanKitPreview: NSViewControllerRepresentable {
    var camera: ScanKitCamera
    
    init(camera: ScanKitCamera, startScanningOnLoad: Bool = true) {
        self.camera = camera
    }
    
    func makeNSViewController(context: Context) -> NSCodeScanner {
        return NSCodeScanner(camera: camera)
    }
    
    func updateNSViewController(_ nsViewController: NSCodeScanner, context: Context) {
        // do nothing
    }
}

class NSCodeScanner: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    weak var camera: ScanKitCamera?
    
    init(camera: ScanKitCamera) {
        self.camera = camera
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = NSView(frame: .zero)
        view.layerContentsRedrawPolicy = .crossfade
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addPreviewLayer()
        
        // Start the camera
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.camera?.start()
        }
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        camera?.stop()
    }
    
    override func viewWillLayout() {
        super.viewWillLayout()
        self.camera?.previewLayer.frame = self.view.bounds
    }

    private func addPreviewLayer() {
        if let previewLayer = self.camera?.previewLayer {
            self.view.wantsLayer = true
            self.view.layer?.addSublayer(previewLayer)
        }
    }
}

#endif
