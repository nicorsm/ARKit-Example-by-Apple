//
//  ARSCNViewManager.swift
//  ARKitExample
//
//  Created by Nicola on 22/07/2017.
//  Copyright © 2017 Apple. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

class ARSCNViewManager: NSObject, ARSCNViewDelegate {
    
    var sceneView : ARSCNView!
    var sessionManager : ARSessionManager!
    var viewController : ViewController!
    
    init(sceneView: ARSCNView, in viewController: ViewController) {
        
        self.sceneView = sceneView
        self.viewController = viewController
        self.sessionManager = ARSessionManager(sceneView: self.sceneView, in: viewController)
        
        sceneView.delegate = self
        sceneView.session = sessionManager.session
        sceneView.antialiasingMode = .multisampling4X
        sceneView.automaticallyUpdatesLighting = false
        
        sceneView.preferredFramesPerSecond = 60
        sceneView.contentScaleFactor = 1.3
        //sceneView.showsStatistics = true
        
        self.sessionManager.enableEnvironmentMap(intensity: 25.0)
        
        if let camera = sceneView.pointOfView?.camera {
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = true
            camera.exposureOffset = -1
            camera.minimumExposure = -1
        }
        
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        refreshFeaturePoints()
        
        DispatchQueue.main.async {
            self.updateFocusSquare()
            self.hitTestVisualization?.render()
            
            // If light estimation is enabled, update the intensity of the model's lights and the environment map
            if let lightEstimate = self.session.currentFrame?.lightEstimate {
                self.sessionManager.enableEnvironmentMap(intensity: lightEstimate.ambientIntensity / 40)
            } else {
                self.sessionManager.enableEnvironmentMap(intensity: 25)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.sessionManager.addPlane(node: node, anchor: planeAnchor)
                self.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.sessionManager.updatePlane(anchor: planeAnchor)
                self.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.sessionManager.removePlane(anchor: planeAnchor)
            }
        }
    }
    
}
