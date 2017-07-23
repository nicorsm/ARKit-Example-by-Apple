//
//  ARDebugManager.swift
//  ARKitExample
//
//  Created by Nicola on 22/07/2017.
//  Copyright © 2017 Apple. All rights reserved.
//

import UIKit

class ARDebugManager: NSObject {
    
    static var instance = ARDebugManager()
    
    var textManager : TextManager?
    
    func setup(viewController: ViewController) {
        textManager = TextManager(viewController: viewController)
    }
    
}
