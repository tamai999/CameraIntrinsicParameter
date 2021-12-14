import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var infinitySwitch: UISwitch!
    
    private lazy var imageCapture = ImageCapture()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // キャプチャ開始
        imageCapture.delegate = self
        imageCapture.session.startRunning()
        
        setInfinity(false)
    }
    
    @IBAction func infinityDidTapped(_ sender: UISwitch) {
        setInfinity(sender.isOn)
    }
    
    @IBAction func centerFocusDidTapped(_ sender: Any) {
        setInfinity(false) {
            self.imageCapture.setCenterFocus()
        }
    }
    
    private func setInfinity(_ isOn: Bool, completion: (() -> ())? = nil) {
        infinitySwitch.isOn = isOn
        infinitySwitch.isEnabled = false
        
        imageCapture.setInfinityFocus(isOn) { isCompleted in
            DispatchQueue.main.async {
                if !isCompleted {
                    self.infinitySwitch.isOn = !isOn
                }

                self.infinitySwitch.isEnabled = true
            }
            
            completion?()
        }
    }
}

extension ViewController: ImageCaptureDelegate {    
    func captureOutput(ciImage: CIImage,
                       intrinsicParameter: ImageCapture.IntrinsicParameter,
                       resolution: ImageCapture.ResolutionType) {        
        var label = ""
        label += "■焦点距離[px]\n"
        label += " h[\(intrinsicParameter.hFocalLength.dot2f)] \n v[\(intrinsicParameter.vFocalLength.dot2f)] \n"
        label += "■画像サイズ／画像中心[px]\n"
        label += " h[\(intrinsicParameter.imageWidth)]／[\(intrinsicParameter.hImageCenter.dot2f)]\n"
        label += " v[\(intrinsicParameter.imageHeight)]／[\(intrinsicParameter.vImageCenter.dot2f)] \n"
        label += "■レンズポジション\n"
        label += " [\(intrinsicParameter.lensPosition.dot2f)] ※0.0~1.0(無限遠) \n"
        label += "■画角\n"
        label += " h[\(intrinsicParameter.hFov.dot2f)]° \n v[\(intrinsicParameter.vFov.dot2f)]° \n"
        
        // 対象までの距離計算（レンズの公式）
        var distanceLabel = "-"
        
        let f = resolution.focalLength
        let b = intrinsicParameter.hFocalLength
        if f != 0.0 && b != 0.0 && f != b {
            let a = 1 / (1.0 / f - 1.0 / b)
            let aMeter = a * resolution.pixelSize
            distanceLabel = "\(aMeter.dot2f)m"
        }

        DispatchQueue.main.async {
            self.imageView.image = UIImage(ciImage: ciImage)
            self.label.text = label
            self.distanceLabel.text = distanceLabel
        }
    }
}

extension Float {
    var dot2f: String {
        String(format: "%.2f", self)
    }
}
