//
//  Thread.swift
//  UniversalSearchSDK
//
//  Created by Rajan Patel on 04/06/26.
//

import Foundation

//MARK: Runs a block in the main thread
public func runOnMainThread(_ block: @escaping () -> ()) {
    DispatchQueue.main.async(execute: {
        block()
    })
}

//MARK: Runs a block in background
public func runInBackground(_ block: @escaping () -> ()) {
    DispatchQueue.global(qos: .userInitiated).async {
        block()
    }
}

//MARK: Runs code after delay using time
public func runAfterTime(_ time: Double ,block : @escaping () -> ()){
    let delayTime = DispatchTime.now() + Double(Int64(time * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    DispatchQueue.main.asyncAfter(deadline: delayTime) {
        block()
    }
}
