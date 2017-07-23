//
//  ARPlanesManager.swift
//  ARKitExample
//
//  Created by Nicola on 22/07/2017.
//  Copyright © 2017 Apple. All rights reserved.
//

import UIKit
import ARKit
import SceneKit

class ARSessionManager: NSObject {
    
    let textManager = ARDebugManager.instance.textManager
    var sceneView : ARSCNView!
    var objectsManager : ARVirtualObjectManager!
    var viewController : ViewController!
    
    let session = ARSession()
    var sessionConfig: ARSessionConfiguration = ARWorldTrackingSessionConfiguration()
    var use3DOFTracking = false {
        didSet {
            if use3DOFTracking {
                sessionConfig = ARSessionConfiguration()
            }
            sessionConfig.isLightEstimationEnabled = UserDefaults.standard.bool(for: .ambientLightEstimation)
            session.run(sessionConfig)
        }
    }
    var use3DOFTrackingFallback = false
    
    init(sceneView: ARSCNView, in viewController: ViewController) {
        self.sceneView = sceneView
        self.objectsManager = ARVirtualObjectManager(sessionManager: self)
        self.viewController = viewController
    }
    
    func enableEnvironmentMap(intensity: CGFloat) {
        if sceneView.scene.lightingEnvironment.contents == nil {
            if let environmentMap = UIImage(named: "Models.scnassets/sharedImages/environment_blur.exr") {
                sceneView.scene.lightingEnvironment.contents = environmentMap
            }
        }
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
    
    // MARK: - Planes
    
    var planes = [ARPlaneAnchor: Plane]()
    
    func addPlane(node: SCNNode, anchor: ARPlaneAnchor) {
        
        let pos = SCNVector3.positionFromTransform(anchor.transform)
        textManager?.showDebugMessage("NEW SURFACE DETECTED AT \(pos.friendlyString())")
        
        let plane = Plane(anchor, showDebugVisuals)
        
        planes[anchor] = plane
        node.addChildNode(plane)
        
        textManager?.cancelScheduledMessage(forType: .planeEstimation)
        textManager?.showMessage("SURFACE DETECTED")
        if objectsManager.virtualObject == nil {
            textManager?.scheduleMessage("TAP + TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .contentPlacement)
        }
    }
    
    func updatePlane(anchor: ARPlaneAnchor) {
        if let plane = planes[anchor] {
            plane.update(anchor)
        }
    }
    
    func removePlane(anchor: ARPlaneAnchor) {
        if let plane = planes.removeValue(forKey: anchor) {
            plane.removeFromParentNode()
        }
    }
    
    func restartPlaneDetection() {
        
        // configure session
        if let worldSessionConfig = sessionConfig as? ARWorldTrackingSessionConfiguration {
            worldSessionConfig.planeDetection = .horizontal
            session.run(worldSessionConfig, options: [.resetTracking, .removeExistingAnchors])
        }
        
        // reset timer
        if trackingFallbackTimer != nil {
            trackingFallbackTimer!.invalidate()
            trackingFallbackTimer = nil
        }
        
        textManager?.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT",
                                    inSeconds: 7.5,
                                    messageType: .planeEstimation)
    }
    
    var trackingFallbackTimer: Timer?
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        textManager?.showTrackingQualityInfo(for: camera.trackingState, autoHide: !self.showDebugVisuals)
        
        switch camera.trackingState {
        case .notAvailable:
            textManager?.escalateFeedback(for: camera.trackingState, inSeconds: 5.0)
        case .limited:
            if use3DOFTrackingFallback {
                // After 10 seconds of limited quality, fall back to 3DOF mode.
                trackingFallbackTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { _ in
                    self.use3DOFTracking = true
                    self.trackingFallbackTimer?.invalidate()
                    self.trackingFallbackTimer = nil
                })
            } else {
                textManager?.escalateFeedback(for: camera.trackingState, inSeconds: 10.0)
            }
        case .normal:
            textManager?.cancelScheduledMessage(forType: .trackingStateEscalation)
            if use3DOFTrackingFallback && trackingFallbackTimer != nil {
                trackingFallbackTimer!.invalidate()
                trackingFallbackTimer = nil
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        
        guard let arError = error as? ARError else { return }
        
        let nsError = error as NSError
        var sessionErrorMsg = "\(nsError.localizedDescription) \(nsError.localizedFailureReason ?? "")"
        if let recoveryOptions = nsError.localizedRecoveryOptions {
            for option in recoveryOptions {
                sessionErrorMsg.append("\(option).")
            }
        }
        
        let isRecoverable = (arError.code == .worldTrackingFailed)
        if isRecoverable {
            sessionErrorMsg += "\nYou can try resetting the session or quit the application."
        } else {
            sessionErrorMsg += "\nThis is an unrecoverable error that requires to quit the application."
        }
        
        displayErrorMessage(title: "We're sorry!", message: sessionErrorMsg, allowRestart: isRecoverable)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        textManager?.blurBackground()
        textManager?.showAlert(title: "Session Interrupted", message: "The session will be reset after the interruption has ended.")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        textManager?.unblurBackground()
        session.run(sessionConfig, options: [.resetTracking, .removeExistingAnchors])
        restartExperience(self)
        textManager?.showMessage("RESETTING SESSION")
    }
    
    // MARK: - Ambient Light Estimation
    
    func toggleAmbientLightEstimation(_ enabled: Bool) {
        
        if enabled {
            if !sessionConfig.isLightEstimationEnabled {
                // turn on light estimation
                sessionConfig.isLightEstimationEnabled = true
                session.run(sessionConfig)
            }
        } else {
            if sessionConfig.isLightEstimationEnabled {
                // turn off light estimation
                sessionConfig.isLightEstimationEnabled = false
                session.run(sessionConfig)
            }
        }
    }
    
    func restartExperience() {
        
        guard viewController.restartExperienceButtonIsEnabled, !objectsManager.isLoadingObject else {
            return
        }
        
        DispatchQueue.main.async {
            self.viewController.restartExperienceButtonIsEnabled = false
            
            self.textManager?.cancelAllScheduledMessages()
            self.textManager?.dismissPresentedAlert()
            self.textManager?.showMessage("STARTING A NEW SESSION")
            self.use3DOFTracking = false
            
            self.viewController.setupFocusSquare()
            self.objectsManager.resetVirtualObject()
            self.restartPlaneDetection()
            
            self.viewController.restartExperienceButton.setImage(#imageLiteral(resourceName: "restart"), for: [])
            
            // Disable Restart button for five seconds in order to give the session enough time to restart.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: {
                self.viewController.restartExperienceButtonIsEnabled = true
            })
        }
    }
    
    // MARK: - Error handling
    
    func displayErrorMessage(title: String, message: String, allowRestart: Bool = false) {
        // Blur the background.
        textManager?.blurBackground()
        
        if allowRestart {
            // Present an alert informing about the error that has occurred.
            let restartAction = UIAlertAction(title: "Reset", style: .default) { _ in
                self.textManager?.unblurBackground()
                self.restartExperience(self)
            }
            textManager?.showAlert(title: title, message: message, actions: [restartAction])
        } else {
            textManager?.showAlert(title: title, message: message, actions: [])
        }
    }

}
