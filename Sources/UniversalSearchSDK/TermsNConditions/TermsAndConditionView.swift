//
//  TermsAndConditionView.swift
//  HDFC Bank SmartHub Vyapar
//
//  Created by Rajan Patel on 27/05/26.
//

import UIKit
import Foundation

class TermsAndConditionView: UIViewController, XIBed {
    
    static func instantiate(redirectionURL: String, onAgree: (() -> Void)? = nil, onClose: (() -> Void)? = nil) -> Self {
        let vc = Self.instantiate()
        vc.redirectionURL = redirectionURL
        vc.onAgree = onAgree
        vc.onClose = onClose
        return vc
    }

    @IBOutlet weak var goToVyaparifyBtn: UIButton!
    @IBOutlet weak var checkBoxBtn: UIButton!
    @IBOutlet weak var detailLbl: UILabel!
    @IBOutlet weak var titleLbl: UILabel!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var closeBtn: UIButton!
    @IBOutlet weak var gradiantView: UIView!
    @IBOutlet weak var termsTextView: UITextView!
    @IBOutlet weak var termsAndCondContView: UIView!

    var redirectionURL: String = ""
    var tid: String = ""
    var onAgree: (() -> Void)?
    var onClose: (() -> Void)?

    var stageName: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpUI()
        self.buttonUnableDisable(isEnable: false)
        self.updateCheckBoxImage()
        self.termsAndCondContView.isHidden = false
    }
    
    override func viewWillAppear(_ animated: Bool) {
    }
    
    
    func setUpUI(){
        self.detailLbl.numberOfLines = 0
        self.gradiantView.isHidden = true

        goToVyaparifyBtn.layer.cornerRadius = 10
        containerView.layer.cornerRadius = 20
        containerView.layer.maskedCorners = [.topLeft, .topRight]

        self.detailLbl.text = "By using this chat, you agree to comply with all applicable laws and regulations. We are not responsible for any losses incurred through the use of our services. You must be at least 18 years old and provide accurate information during registration. We reserve the right to modify these terms at any time, and your continued use constitutes acceptance of any changes."
        self.titleLbl.text = "Terms and conditions"
        
        self.goToVyaparifyBtn.setTitle("I agree", for: .normal)

        let hdfcMainThemeBlueColor = UIColor(red: 35/255, green: 71/255, blue: 191/255, alpha: 1.0)
        
        let privacyPolicyFontHdfcMain = AppFonts.FONT_REGULAR(size: 14)
        
        let fullString = "I accept the Terms & Conditions"
        let linkString = "Terms & Conditions"
        
        let attributedString = NSMutableAttributedString(string: fullString)
        let range = (fullString as NSString).range(of: linkString)
        
        attributedString.addAttributes([
            .foregroundColor: UIColor.darkGrayTxtColor1,
            .font: privacyPolicyFontHdfcMain
        ], range: NSRange(location: 0, length: fullString.count))
        
        attributedString.addAttributes([
            .foregroundColor: hdfcMainThemeBlueColor,
            .font: privacyPolicyFontHdfcMain,
            .link: URL(string: "https://www.mintoak.com/terms-and-conditions")! // Placeholder link
        ], range: range)
        
        termsTextView.attributedText = attributedString
        termsTextView.linkTextAttributes = [.foregroundColor: hdfcMainThemeBlueColor]
        termsTextView.isEditable = false
        termsTextView.isSelectable = true
        checkBoxBtn.isSelected = false
    }

    @IBAction func goToVyaparifyAction(_ sender: Any) {
        if checkBoxBtn.isSelected {
            self.dismiss(animated: true) { [weak self] in
                self?.onAgree?()
            }
        }
    }
    
    @IBAction func detailLabelTapped(_ sender: Any) {
    }
    
    @IBAction func checkBoxClicked(_ sender: UIButton) {
        sender.isSelected.toggle()
        updateCheckBoxImage()
        buttonUnableDisable(isEnable: sender.isSelected)
    }

    private func updateCheckBoxImage() {
        let imageName = checkBoxBtn.isSelected ? "checkBoxFilled" : "checkBoxEmpty"
        let bundle = UniversalSearchManager.bundle
        let image = UIImage(named: imageName, in: bundle, compatibleWith: nil)?.withRenderingMode(.alwaysOriginal)
        checkBoxBtn.setImage(image, for: .normal)
    }
    
    @IBAction func closeBtnAction(_ sender: Any) {
        self.dismiss(animated: true) { [weak self] in
            self?.onClose?()
        }
    }

    func buttonUnableDisable(isEnable:Bool){
        let enabledColor = UIColor(red: 35/255, green: 71/255, blue: 191/255, alpha: 1.0)
        let disabledColor = UIColor.lightGray
        
        if isEnable {
            goToVyaparifyBtn.backgroundColor = enabledColor
            goToVyaparifyBtn.isEnabled = true
        } else {
            goToVyaparifyBtn.backgroundColor = disabledColor
            goToVyaparifyBtn.isEnabled = false
        }
        goToVyaparifyBtn.layer.masksToBounds = true
        goToVyaparifyBtn.layer.cornerRadius = 10
    }
}


//protocol GetRedirectionDetailsAPIProtocol {
//
//    func getData(terminalId:String, completion: @escaping ((RedirectionDetailsResponse?) -> Void))
//}
//
//struct GetRedirectionDetailsAPI : GetRedirectionDetailsAPIProtocol {
//    func getData(terminalId:String, completion: @escaping ((RedirectionDetailsResponse?) -> Void)) {
//        AppDelegate.shared.netWorker.callAPIService(type: .getRedirectionDetails(terminalId: terminalId)) { (data:RedirectionDetailsResponse?) in
//            completion(data)
//        }
//    }
//    
//
//}
//
//// MARK: - Protocol
//protocol captureMerchantConsentAPIProtocol {
//    func getData(agreementTime: String, isagree : Bool, tids: [String], metadata: String, module: String, completion: @escaping ((captureMerchantConsentResponse?) -> Void))
//}
//
//struct captureMerchantConsentAPI: captureMerchantConsentAPIProtocol {
//    func getData(agreementTime: String, isagree : Bool, tids: [String], metadata: String, module: String, completion: @escaping ((captureMerchantConsentResponse?) -> Void)) {
//        AppDelegate.shared.netWorker.callAPIService(type: .v2pCaptureMerchantConsent(isagree: isagree, agreementTime: agreementTime, metadata: metadata, module: module, tids: tids)) { (data: captureMerchantConsentResponse?)  in
//            completion(data)
//        }
//    }
//}
//
//struct captureMerchantConsentResponse: Codable {
//    let status, respMsg, errorCode, module, statusMessage: String?
//    
//}
//
//protocol OnboardVyaparifyAPIProtocol {
//    func getData(terminalId:String, completion: @escaping ((OnboardVyaparifyResponse?) -> Void))
//}
//
//struct OnboardVyaparifyAPI : OnboardVyaparifyAPIProtocol {
//    func getData(terminalId:String, completion: @escaping ((OnboardVyaparifyResponse?) -> Void)) {
//        AppDelegate.shared.netWorker.callAPIService(type: .onboardVyaparify(terminalId: terminalId)) { (data:OnboardVyaparifyResponse?) in
//            completion(data)
//        }
//    }
//    
//
//}
