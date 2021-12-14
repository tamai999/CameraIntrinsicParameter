import AVFoundation
import UIKit

protocol ImageCaptureDelegate {
    func captureOutput(ciImage: CIImage,
                       intrinsicParameter: ImageCapture.IntrinsicParameter,
                       resolution: ImageCapture.ResolutionType)
}

fileprivate struct Const {
    static let deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    static let resolution: ImageCapture.ResolutionType = .wide_hd
}

class ImageCapture: NSObject {
    enum ResolutionType {
        // 広角 Full HD
        case wide_hd
        // 広角 4K
    //    case wide_4k

        var preset: AVCaptureSession.Preset {
            switch self {
            case .wide_hd:
                return .hd1920x1080
    //        case .wide_4k:
    //            return .hd4K3840x2160
            }
        }
        
        var pixelSize: Float {
            switch self {
            case .wide_hd:
                return 0.000_003_374_92  // iPhone12Pro
    //        case .wide_4k:
    //            return 0.000_004_550_51
            }
        }
        
        var focalLength: Float {
            switch self {
            case .wide_hd:
                return 1383.95  // iPhone12Pro
    //        case .wide_4k:
    //            return 2724.43
            }
        }
    }
    
    struct IntrinsicParameter {
        // 水平画像サイズ
        let imageWidth: Int
        // 垂直画像サイズ
        let imageHeight: Int
        // カメラ内部パラメータ
        let intrinsicMatrix: matrix_float3x3
        // レンズポジション。0.0(最短距離)~1.0(無限遠)
        let lensPosition: Float
        // 焦点距離（水平方向のピクセルサイズ換算）
        var hFocalLength: Float {
            intrinsicMatrix.columns.0.x
        }
        // 焦点距離（垂直方向のピクセルサイズ換算）
        var vFocalLength: Float {
            intrinsicMatrix.columns.1.y
        }
        // 水平画像中心
        var hImageCenter: Float {
            intrinsicMatrix.columns.2.x
        }
        // 垂直画像中心
        var vImageCenter: Float {
            intrinsicMatrix.columns.2.y
        }
        // 水平画角（焦点距離から計算）
        var hFov: Float {
            atan((Float(imageWidth) / 2.0) / hFocalLength) * 180.0 / Float.pi * 2.0
        }
        // 垂直画角（焦点距離から計算）
        var vFov: Float {
            atan((Float(imageHeight) / 2.0) / vFocalLength) * 180.0 / Float.pi * 2.0
        }
    }
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput",
                                                     qos: .userInitiated,
                                                     attributes: [],
                                                     autoreleaseFrequency: .workItem)
    private(set) var session = AVCaptureSession()

    var delegate: ImageCaptureDelegate?
    var captureDevice: AVCaptureDeviceInput?
    
    override init() {
        super.init()
        
        setupAVCapture()
    }
    
    func setInfinityFocus(_ isOn: Bool, completion: @escaping (Bool) -> ()) {
        guard let device = captureDevice?.device else {
            completion(false)
            return
        }

        DispatchQueue.global().async {
            do {
                try device.lockForConfiguration()
                
                if isOn {
                    // 焦点を無限遠に設定
                    device.setFocusModeLocked(lensPosition: 1.0) { _ in
                        completion(true)
                    }
                } else {
                    // オートフォーカスに設定
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                        completion(true)
                    } else {
                        completion(false)
                    }
                }

                device.unlockForConfiguration()
            } catch {
                completion(false)
            }
        }
    }
    
    func setCenterFocus() {
        guard let device = captureDevice?.device,
        device.isFocusPointOfInterestSupported else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            device.focusMode = .autoFocus
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            
            device.unlockForConfiguration()
        } catch {
            print("デバイスの設定ができません")
            return
        }
    }
    
    private func setupAVCapture() {
        guard let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [Const.deviceType],
                                                                 mediaType: .video,
                                                                 position: .back).devices.first,
              let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                  return
              }
        captureDevice = deviceInput
        
        // capture セッション セットアップ
        session.beginConfiguration()
        session.sessionPreset = Const.resolution.preset
        
        // 入力デバイス指定
        session.addInput(deviceInput)
        
        // 出力先の設定
        session.addOutput(videoDataOutput)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        guard let captureConnection = videoDataOutput.connection(with: .video) else {
            fatalError()
        }
        captureConnection.isEnabled = true
        
        if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
            captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
        } else {
            print("intrinsic matrixの取得ができないデバイスです")
        }
        
        session.commitConfiguration()
    }
}

extension ImageCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let device = captureDevice?.device else { return }
        // 画像サイズ
        let dimensions = device.activeFormat.formatDescription.dimensions
        
        guard let parameterData = sampleBuffer.attachments[.cameraIntrinsicMatrix]?.value as? Data else { return }
        var intrinsicMatrix: matrix_float3x3 = .init()
        parameterData.withUnsafeBytes() {
            intrinsicMatrix = $0.load(as: matrix_float3x3.self)
        }
        
        let parameter = IntrinsicParameter(imageWidth: Int(dimensions.width),
                                           imageHeight: Int(dimensions.height),
                                           intrinsicMatrix: intrinsicMatrix,
                                           lensPosition: device.lensPosition)
        
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        delegate?.captureOutput(ciImage: CIImage(cvPixelBuffer: pb),
                                intrinsicParameter: parameter,
                                resolution: Const.resolution)
    }
}
