# SwiftUI ScanKit
ScanKit is a simple SwiftUI package for scanning various machine-readable codes using Apple's [Vision Framework](https://developer.apple.com/documentation/vision).

<p align="center">
    <img alt="SwiftUI ScanKit Logo Image" src="https://github.com/git-shawn/SwiftUI-ScanKit/blob/main/Resources/logo.png?raw=true" width="200">
</p>

<p align="center">
    <img src="https://img.shields.io/github/v/tag/git-shawn/SwiftUI-ScanKit" />
    <img src="https://img.shields.io/badge/License-MIT-lightgrey" />
    <a href="https://swift.org/package-manager">
        <img src="https://img.shields.io/badge/spm-compatible-brightgreen.svg?style=flat" alt="Swift Package Manager" />
    </a>
</p>

<p align="center">
    <img src="https://img.shields.io/badge/iOS-14%2B-blue" />
    <img src="https://img.shields.io/badge/macOS-12%2B-blue" />
    <img src="https://img.shields.io/badge/Swift-5.8%2B-orange" />
</p>

## Getting Started
ScanKit comes in two flavors: as a View-Model pair or as an easy to plug-in SwiftUI View.

Before using either version, you should make sure your project is capable of accessing the camera.

**iOS & macOS**: You must include "Privacy - Camera Usage Description", or `NSCameraUsageDescription`, in your `info.plist`.

**macOS**: "Camera" must be selected under "Resource Access" in "Hardened Runtime." 

### ScannerView
`ScannerView` is a drop-in code scanner for SwiftUI that returns its results as a completion. It accepts the following parameters
- `symbology`: One of Apple's [VNBarcodeSymbology](https://developer.apple.com/documentation/vision/vnbarcodesymbology) varieties to scan for.
- `showViewfinder`: A `Boolean` indicating whether or not to display a "viewfinder" symbol over the camera preview.
- `isScanning`: A `Boolean` binding that dictates whether or not to scan the camera feed for codes. The preview will continue to be available when `false`, but no further results will be sent to the completion until `true`.

If ScannerView is wrapped within some Navigation container, it will send two buttons to the Toolbar.
- A *torch* button on iOS.
- A camera picker/toggle on all platforms.

On macOS the camera picker displays all available cameras, including the continuity camera. On iOS the camera toggle switches between the front and back camera.

`ScannerView`'s completion returns a stream of `Result<String, ScanKitError>`. A `ScanKitError` can be either:
- `notAuthorized` which indicates that camera access was not authorized.
- `visionFailure` which indicates that initialization failed in some way. Check the log for additional details.

Minimal Example:

```
@State var scanning: Bool = true

ScannerView(for: .qr, isScanning: $scanning) { result in
    switch result {
        case .success(let string):
        // To only scan once, call `self.scanning = false` here
        print(string)
        case .failure(let error):
        print(error)
    }
}
```

### ScanKitPreview & ScanKitCamera

For a more custom experience, ScanKit exposes a unique View-Model combination of `ScanKitPreview` and `ScanKitCamera`.

`ScanKitPreview` is a representable wrapper around `AVCapturePreviewLayer` that can display the feed returned from `ScanKitCamera`.

`ScanKitCamera`  interfaces directly with `AVFoundation` and `Vision` to handle available capture devices and Vision requests. It is an `ObservableObject` that can update the view when one of its variables change.

Results are streamed from `ScanKitCamera` as `String` via an `AsyncThrowingStream`. The stream finishes when `ScanKitCamera().isScanning` is set to `false` or when it encounters an error. To scan only one code at a time, simply set `isScanning` to false immediately upon receipt of the first result.

The `resultStream` can throw only two types of errors:
- `notAuthorized` which indicates that camera access was not authorized.
- `visionFailure` which indicates that initialization failed in some way. Check the log for additional details.

Various variables and functions are available from your `ScanKitCamera` object that allow you to interface with the device's camera directly from SwiftUI.

| Kind          | Name                 | Purpose                                                                                                                                                                                       |
|---------------|----------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| var (get)     | isCapturing          | A Boolean indicating whether or not the camera is active.                                                                                                                                     |
| var (get/set) | isScanning           | A Boolean indicating whether or not the camera is scanning for machine readable codes.                                                                                                        |
| var (get)     | isTorchAvailable     | A Boolean indicating whether or not the current camera has a torch available.                                                                                                                 |
| var (get)     | isTorchOn            | A Boolean indicating whether or not the torch is on. If there's no torch, this is always false.                                                                                               |
| var (get)     | isUsingBackCamera    | A Boolean indicating whether or not the rear camera is active. On macOS this is always false.                                                                                                 |
| var (get)     | isUsingFrontCamera   | A Boolean indicating whether or not the front camera is active. On macOS this is always false.                                                                                                |
| var (get)     | resultsStream        | An AsyncThrowingStream presenting the results of the scan operation.                                                                                                                          |
| var (get/set) | symbology            | The current code symbology being scanned for.                                                                                                                                                 |
| var (get)     | supportedSymbologies | An array of all supported symbologies.                                                                                                                                                        |
| func          | cycleCaptureDevices  | Cycles through available cameras. On iOS this simply toggles between the front-facing and rear-facing cameras.                                                                                |
| func          | getCamerasAsButtons  | Returns a `View` containing all available cameras as individual `Button`. Each `Button` switches `ScanKitCamera` to that particular camera when pressed. This is best called within a `Menu`. |
| func          | toggleTorch          | Toggles the torch, if one is available.                                                                                                                                                       |
| func          | start                | Starts the camera. This is automatically called during appear within `ScanKitPreview`.                                                                                                        |
| func          | stop                 | Stops the camera. This is automatically called during disappear within `ScanKitPreview`.                                                                                                      |

Minimal Example:

```
@StateObject camera = ScanKitCamera()

var body: some View {
    ScanKitPreview(camera: camera)
        .task {
            do {
                for try await result in camera.resultsStream {
                    print(result)
                }
            } catch let error {
                print(error)
            }
        }
}
```

Consider looking at the implementation of `ScanView` for inspiration.

## Considerations
It should be noted up-front that the Vision framework is not the most efficient way to handle machine readable codes. However, it is cross-platform.

If you are only targeting iOS, or are planning to target macOS via Mac Catalyst, then packages like [CodeScanner](https://github.com/twostraws/CodeScanner) that utilize [AVCaptureMetadataOutput](https://developer.apple.com/documentation/avfoundation/avcapturemetadataoutput) would be worth considering.

## License
SwiftUI ScanKit is available under the MIT license, which permits commercial use, modification, distribution, and private use. Feel free to use it wherever and however you want!
