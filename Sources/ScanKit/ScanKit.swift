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

import SwiftUI
import Vision
import OSLog

// MARK: - SwiftUI ScannerView

/// A drop-in code symbology scanner.
public struct ScannerView: View {
    let showViewfinder: Bool
    let completion: (Result<String, ScanKitError>) -> ()
    @Binding var scanning: Bool
    @StateObject var camera = ScanKitCamera()
    
    
    /// Create a drop-in code scanner for a specified `symbology`.
    /// ScannerView adds a camera picker and flash button to the toolbar when wrapped in a `NavigationView` or `NavigationStack`.
    ///
    /// ```
    /// @State var scanning = true
    /// ScannerView(for: .qr, showViewfinder: true, isScanning: $scanning) { result in
    ///     switch result {
    ///         case .success(let success):
    ///             self.scanning = false // Only accept one result
    ///             //do something...
    ///         case .failure(let failure):
    ///             //do something...
    ///      }
    /// }
    /// ```
    /// - Parameters:
    ///   - symbology: The symbology to scan for. Defaults to `.qr`.
    ///   - showViewfinder: Whether or not to overlay a viewfinder symbol above the camera preview.
    ///   - isScanning: Whether or not to scan for the selected symbology.
    ///                 When `false` the preview will continue but frames will not be processed for
    ///                 instances of the selected symbology.
    ///   - completion: A completion handler that returns a `Result` of either `String` when information has been found and can be decoded or `ScanKitError` when an error occurs.
    public init(for symbology: VNBarcodeSymbology,
         showViewfinder: Bool = true,
         isScanning: Binding<Bool>,
         completion: @escaping (Result<String, ScanKitError>) -> Void) {
        self.showViewfinder = showViewfinder
        self.completion = completion
        self._scanning = isScanning
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let minDimension = min(proxy.size.width,proxy.size.height)
            
            ZStack {
                // If iOS15+ we'll watch for changes in scanning with a Task.
                if #available(iOS 15.0, macOS 12.0, *) {
                    ScanKitPreview(camera: camera)
                        .task(id: scanning) {
                            camera.isScanning = scanning
                            if scanning {
                                do {
                                    for try await result in camera.resultsStream {
                                        completion(.success(result))
                                    }
                                } catch let error {
                                    completion(.failure(error as! ScanKitError))
                                }
                            }
                        }
                    // Otherwise, we have to initiate the result stream onAppear and re-evaluate it during changes to scanning.
                } else {
                    ScanKitPreview(camera: camera)
                        .onAppear {
                            if scanning {
                                Task {
                                    do {
                                        for try await result in camera.resultsStream {
                                            completion(.success(result))
                                        }
                                    } catch let error {
                                        completion(.failure(error as! ScanKitError))
                                    }
                                }
                            }
                        }
                        .onChange(of: scanning) { isScanning in
                            // Changing isScanning to `false` will cancel any previous tasks by finishing the stream.
                            camera.isScanning = isScanning
                            if isScanning {
                                Task {
                                    do {
                                        for try await result in camera.resultsStream {
                                            completion(.success(result))
                                        }
                                    } catch let error {
                                        completion(.failure(error as! ScanKitError))
                                    }
                                }
                            }
                        }
                }
                
                if showViewfinder {
                    Image(systemName: "viewfinder")
                        .resizable()
                        .scaledToFit()
                        .font(.system(size: 16, weight: .thin, design: .default))
                        .foregroundColor(.white)
                        .opacity(scanning ? 0.75 : 0.15)
                        .animation(.spring(), value: scanning)
                        .frame(width: minDimension*0.5, height: minDimension*0.5)
                }
            }
            .toolbar {
                ToolbarItem {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    Button(action: {
                        camera.cycleCaptureDevices()
                    }, label: {
                        Label("Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera")
                    })
                    .disabled(!camera.hasMultipleCaptureDevices)
#else
                    Menu(content: {
                        camera.getCamerasAsButtons()
                    }, label: {
                        Label("Switch Camera", systemImage: "web.camera")
                    })
#endif
                }
                
#if os(iOS) && !targetEnvironment(macCatalyst)
                ToolbarItem {
                    Button(action: {
                        camera.toggleTorch()
                    }, label: {
                        if camera.isTorchOn {
                            Label("Toggle Torch Off", systemImage: "bolt.slash.circle")
                        } else {
                            Label("Toggle Torch On", systemImage: "bolt.circle")
                        }
                    })
                    .disabled(!camera.isTorchAvailable)
                }
#endif
            }
        }
    }
}

// MARK: - Static ScanKit Functions

public class ScanKit {
    
    /// Decodes any barcodes of a defined `symbology` that may be present within a given `CGImage` as an array of `String`.
    /// If no codes are found, the returned array is empty.
    /// - Parameters:
    ///   - cgImage: The image to search for codes.
    ///   - symbology: The `symbology` of code to search for.
    /// - Returns: An array of `String` containing any decoded results.
    static func decodeImage(cgImage: CGImage, for symbology: VNBarcodeSymbology) async -> [String] {
        var results: [String] = []
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNDetectBarcodesRequest { (request,error) in
            if error != nil {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.fromshawn.scankit", category: "ScanKit").error("ScanKit could not create a Vision request.")
                return
            } else {
                guard let observations = request.results as? [VNBarcodeObservation]
                else { return }
                
                results = observations.compactMap {
                    if $0.symbology == symbology {
                        return $0.payloadStringValue
                    } else {
                        return nil
                    }
                }
            }
        }
        
        Task {
            try handler.perform([request])
        }
        
        return results
    }
}

/// Possible ScanKitCamera errors to throw.
public enum ScanKitError: Error, LocalizedError {
    case visionFailed, notAuthorized
    
    public var errorDescription: String? {
        switch self {
        case .visionFailed:
            return "ScanKit failed to intiailize the scanner."
        case .notAuthorized:
            return "ScanKit was unable to access the camera."
        }
    }
}
