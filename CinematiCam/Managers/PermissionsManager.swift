import AVFoundation
import Photos

class PermissionsManager {

    func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Camera permission granted")
                } else {
                    print("Camera permission denied")
                }
                completion(granted)
            }
        }
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Mic permission granted")
                } else {
                    print("Mic permission denied")
                }
                completion(granted)
            }
        }
    }

    func requestPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                let granted = status == .authorized
                if granted {
                    print("Library permission granted")
                } else {
                    print("Library permission denied")
                }
                completion(granted)
            }
        }
    }
}
