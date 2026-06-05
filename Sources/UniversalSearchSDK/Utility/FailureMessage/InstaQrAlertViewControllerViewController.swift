//
//  InstaQrAlertViewControllerViewController.swift
//  ETBSDK
//
//  Created by Appic Mac on 29/11/22.
//  Copyright © 2022 Chaitanya Soni. All rights reserved.
//

import UIKit

class InstaQrAlertViewControllerViewController: UIViewController {
    
    static func instantiate(backColor: String, iconImage: String, titleColor: String, titleData: String, descData: String, attributedInstruction: String = "", buttonTitle1: String, buttonTitle2: String, hideCloseButton: Bool = false) -> InstaQrAlertViewControllerViewController {
        let bundle = UniversalSearchManager.bundle
        let vc = InstaQrAlertViewControllerViewController(nibName: String(describing: self), bundle: bundle)
        vc.backColor = backColor
        vc.iconImage = iconImage
        vc.titleColor = titleColor
        vc.titleData = titleData
        vc.descData = descData
        vc.attributedInstruction = attributedInstruction
        vc.buttonTitle1 = buttonTitle1
        vc.buttonTitle2 = buttonTitle2
        vc.hideCloseButton = hideCloseButton
        return vc
    }
    
    static func instantiateNew(backColor: String, iconImage: String, titleColor: String, titleData: String, descData: String, buttonTitle1: String, buttonTitle2: String, isFromLogin:Bool) -> InstaQrAlertViewControllerViewController {
        let bundle = UniversalSearchManager.bundle
        let vc = InstaQrAlertViewControllerViewController(nibName: String(describing: self), bundle: bundle)
        vc.backColor = backColor
        vc.iconImage = iconImage
        vc.titleColor = titleColor
        vc.titleData = titleData
        vc.descData = descData
        vc.buttonTitle1 = buttonTitle1
        vc.buttonTitle2 = buttonTitle2
        vc.isFromLogin = isFromLogin
        return vc
    }
    
    static func instantiateInternetError(isForInternetError: Bool) -> InstaQrAlertViewControllerViewController {
        let bundle = UniversalSearchManager.bundle
        let vc = InstaQrAlertViewControllerViewController(nibName: String(describing: self), bundle: bundle)
        vc.isForInternetError = isForInternetError
        return vc
    }
    
    //Outlets
    @IBOutlet weak var containerView: UIView!
    
    @IBOutlet weak var titleView: UIView!
    @IBOutlet weak var titleImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var closeButton: UIButton!
    
    
    @IBOutlet weak var instructionView: UIView!
    @IBOutlet weak var instructionLabel: UILabel!

    
    @IBOutlet weak var actionView: UIView!
    @IBOutlet weak var button1: UIButton!
    @IBOutlet weak var button2: UIButton!
    
    // Variables
    var hideCloseButton: Bool = false
    var newFailedAlert: Bool = false
    var backColor: String = ""
    var iconImage: String = ""
    var titleColor: String = ""
    var titleData: String = ""
    var descData: String = ""
    var buttonTitle1: String = ""
    var buttonTitle2: String = ""
    var attributedInstruction : String = ""
    var completionClose: (() -> ())? = nil
    var completionButton1: (() -> ())? = nil
    var completionButton2: (() -> ())? = nil
    var isFromLogin = false
    var isForInternetError = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpUI()
    }

    func setUpUI() {
        containerView.layer.cornerRadius = 10.0
        containerView.clipsToBounds = true
        
        self.containerView.backgroundColor = UIColor.hex(backColor)
        self.closeButton.isHidden = hideCloseButton
        if iconImage == PopupImageName.failIcon.rawValue {
            if !iconImage.isEmpty {
                self.titleImageView.image = UIImage(named: iconImage,in: UniversalSearchManager.bundle, compatibleWith: nil)
            } else {
                self.titleImageView.image = nil // Clear image if name is empty
            }
        } else {
            self.titleImageView.image = UIImage(named: "alertIconNew",in: UniversalSearchManager.bundle, compatibleWith: nil)
            self.titleImageView.image = self.titleImageView.image?.withRenderingMode(.alwaysTemplate)
            self.titleImageView.tintColor = UIColor.hex(titleColor)
        }
        self.closeButton.setImage(UIImage.init(named: "imgRedClose",in: UniversalSearchManager.bundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeButton.tintColor = UIColor.hex(titleColor)

        self.titleLabel.textColor = UIColor.hex(titleColor)
        self.titleLabel.text = titleData
        self.instructionLabel.text = descData
        if attributedInstruction != "" {
            self.instructionLabel.attributedText = getAttributedBoldString(str: descData, boldTxt: attributedInstruction)
        }
        let attrTitle1 = NSAttributedString(string: buttonTitle1,
                                            attributes: [NSAttributedString.Key.foregroundColor: UIColor.black, NSAttributedString.Key.font: AppFonts.FONT_REGULAR(size: 12), NSAttributedString.Key.underlineColor: UIColor.black, NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue])

        button1.setAttributedTitle(attrTitle1, for: .normal)
        
        button2.setTitle(buttonTitle2, for: .normal)
        
        button1.isHidden = buttonTitle1 == ""
        button2.isHidden = buttonTitle2 == ""
        instructionView.isHidden = descData == ""
        actionView.isHidden = (buttonTitle1 == "") && (buttonTitle2 == "")
        
        if isFromLogin {
            self.instructionView.isHidden = true
            self.closeButton.isHidden = true
            self.button2.setBackgroundColor(UIColor.appThemeBlueButtonTitleColor, forState: .normal)
            self.button2.setTitleColor(.white, for: .normal)
            self.view.backgroundColor = .clear
        }
        else if isForInternetError {
            self.containerView.backgroundColor = UIColor.commonSdkBackColor
            self.instructionView.isHidden = true
            self.button2.isHidden = true
            self.closeButton.setImage(UIImage.init(named: "imgRedClose",in: UniversalSearchManager.bundle, compatibleWith: nil), for: .normal)
            self.titleImageView.image = UIImage.init(named: "imgRedAlert",in: UniversalSearchManager.bundle, compatibleWith: nil)
        }
    }

    @IBAction func closeButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true){
            self.completionClose?()
        }
    }
    
    @IBAction func button1Tapped(_ sender: UIButton) {
        self.dismiss(animated: true){
            self.completionButton1?()
        }
    }
    
    @IBAction func button2Tapped(_ sender: UIButton) {
        self.dismiss(animated: true){
            self.completionButton2?()
        }
    }
    
    func getAttributedBoldString(str : String, boldTxt : String) -> NSMutableAttributedString {
            let attrStr = NSMutableAttributedString.init(string: str)
            let boldedRange = NSRange(str.range(of: boldTxt)!, in: str)
        attrStr.addAttributes([NSAttributedString.Key.font : AppFonts.FONT_REGULAR(size: 12)], range: boldedRange)
            return attrStr
        }

}

enum PopupImageName: String {
    case failIcon = "imgRedAlert"
    case infoIcon = "infoBlueIcon"
    case alertIcon = "alertIcon"
    case alertNewIcon = "alertIconNew"
    case successIcon = "greenSuccessIcon"
}

extension InstaQrAlertViewControllerViewController {

    //var appDelegate = UIApplication.shared.delegate as! AppDelegate

    class func showAlert(titleString: String?, messageString: String? = "", isWarning: Bool = true, viewController: UIViewController?=nil, action: (() -> ())? = nil) {
        if !(titleString == "" && messageString == ""){
            
            let alertController = InstaQrAlertViewControllerViewController.instantiate(backColor: isWarning ? PopupBackColor.alertNewColor.rawValue : PopupBackColor.redColor.rawValue, iconImage: isWarning ? PopupImageName.alertNewIcon.rawValue : PopupImageName.failIcon.rawValue, titleColor: isWarning ? PopupTitleColor.alertNewColor.rawValue : PopupTitleColor.redColor.rawValue, titleData: titleString ?? "", descData: messageString ?? "", buttonTitle1: "", buttonTitle2: "")
            alertController.modalPresentationStyle = UIModalPresentationStyle.overCurrentContext
            alertController.completionClose = {
                action?()
            }
            var topController: UIViewController? = UIApplication.shared.delegate?.window??.rootViewController
            while topController?.presentedViewController != nil {
                topController = topController?.presentedViewController
            }
            if (viewController != nil) {
                viewController!.present(alertController, animated: true, completion: nil)

            }else if (topController != nil) {
                topController?.present(alertController, animated: true)
            }
            else {
                let window = UIApplication.shared.delegate?.window
                let vc = window??.rootViewController?.presentedViewController ?? window??.rootViewController
                vc?.present(alertController, animated: true, completion: nil)
            }
            
        }
    }


}

enum PopupBackColor: String {
    case redColor = "#FFD0D0"
    case blueColor = "#E6EFFC"
    case alertColor = "#FDEECF"
    case greenColor = "#D8EBD9"
    case alertNewColor = "#FEF8E6"
    case newGreenColor = "#EBF9EF"
    case newBlueColor = "#D0DDFC"
    case lightRedColor = "#FDEFED"
}

enum PopupTitleColor: String {
    case redColor = "#D50000"
    case blueColor = "#0060E5"
    case alertColor = "#CC8734"
    case greenColor = "#43A047"
    case newGreenColor = "#00875F"
    case alertNewColor = "#F99F35"
    case newBlueColor = "#1C3FCA"
    case titleRedColor = "#E22853"
}
