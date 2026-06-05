//
//  XIBed.swift
//  UniversalSearchSDK
//
//  Created by Rajan Patel on 04/06/26.
//

import Foundation
import UIKit

public protocol XIBed {
    static func instantiate() -> Self
}

public extension XIBed where Self: UIViewController {
    static func instantiate() -> Self {
        return Self(nibName: String(describing: self), bundle: UniversalSearchManager.bundle)
    }
}

protocol Refreshable {
    func refreshView()
}
