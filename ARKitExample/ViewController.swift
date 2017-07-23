/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import Foundation
import SceneKit
import UIKit
import Photos

class ViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    
    var sceneViewManager : ARSCNViewManager?
    @IBOutlet weak var addObjectButton: UIButton!
    
    
    // MARK: - Main Setup & View Controller methods
    override func viewDidLoad() {
        super.viewDidLoad()

        Setting.registerDefaults()
        setupScene()
        setupDebug()
        setupUIControls()
		setupFocusSquare()
		updateSettings()
		resetVirtualObject()
    }

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		// Prevent the screen from being dimmed after a while.
		UIApplication.shared.isIdleTimerDisabled = true
		
		// Start the ARSession.
        sceneViewManager?.sessionManager.restartPlaneDetection()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		session.pause()
	}
	
    // MARK: - ARKit / ARSCNView
    @IBOutlet var sceneView: ARSCNView!
	var screenCenter: CGPoint?
    
    func setupScene() {
        // set up sceneView
        sceneViewManager = ARSCNViewManager(sceneView: sceneView)
        
        DispatchQueue.main.async {
            self.screenCenter = self.sceneView.bounds.mid
        }
        
    }
	

    // MARK: - Gesture Recognizers
	
	var currentGesture: Gesture?
	
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		guard let object = virtualObject else {
			return
		}
		
		if currentGesture == nil {
			currentGesture = Gesture.startGestureFromTouches(touches, self.sceneView, object)
		} else {
			currentGesture = currentGesture!.updateGestureFromTouches(touches, .touchBegan)
		}
		
		displayVirtualObjectTransform()
	}
	
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		if virtualObject == nil {
			return
		}
		currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchMoved)
		displayVirtualObjectTransform()
	}
	
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		if virtualObject == nil {
			chooseObject(addObjectButton)
			return
		}
		
		currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchEnded)
	}
	
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		if virtualObject == nil {
			return
		}
		currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchCancelled)
	}
	
    // MARK: - Focus Square
    var focusSquare: FocusSquare?
	
    func setupFocusSquare() {
		focusSquare?.isHidden = true
		focusSquare?.removeFromParentNode()
		focusSquare = FocusSquare()
		sceneView.scene.rootNode.addChildNode(focusSquare!)
		
		textManager.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
    }
	
	func updateFocusSquare() {
		guard let screenCenter = screenCenter else { return }
		
		if virtualObject != nil && sceneView.isNode(virtualObject!, insideFrustumOf: sceneView.pointOfView!) {
			focusSquare?.hide()
		} else {
			focusSquare?.unhide()
		}
		let (worldPos, planeAnchor, _) = worldPositionFromScreenPosition(screenCenter, objectPos: focusSquare?.position)
		if let worldPos = worldPos {
			focusSquare?.update(for: worldPos, planeAnchor: planeAnchor, camera: self.session.currentFrame?.camera)
			textManager.cancelScheduledMessage(forType: .focusSquare)
		}
	}
	
	// MARK: - Hit Test Visualization
	
	var hitTestVisualization: HitTestVisualization?
	
	var showHitTestAPIVisualization = UserDefaults.standard.bool(for: .showHitTestAPI) {
		didSet {
			UserDefaults.standard.set(showHitTestAPIVisualization, for: .showHitTestAPI)
			if showHitTestAPIVisualization {
				hitTestVisualization = HitTestVisualization(sceneView: sceneView)
			} else {
				hitTestVisualization = nil
			}
		}
	}
	
    // MARK: - Debug Visualizations
	
	@IBOutlet var featurePointCountLabel: UILabel!
	
	func refreshFeaturePoints() {
		guard showDebugVisuals else {
			return
		}
		
		// retrieve cloud
		guard let cloud = session.currentFrame?.rawFeaturePoints else {
			return
		}
		
		DispatchQueue.main.async {
			self.featurePointCountLabel.text = "Features: \(cloud.count)".uppercased()
		}
	}
	
    var showDebugVisuals: Bool = UserDefaults.standard.bool(for: .debugMode) {
        didSet {
			featurePointCountLabel.isHidden = !showDebugVisuals
			debugMessageLabel.isHidden = !showDebugVisuals
			messagePanel.isHidden = !showDebugVisuals
			planes.values.forEach { $0.showDebugVisualization(showDebugVisuals) }
			
			if showDebugVisuals {
				sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
			} else {
				sceneView.debugOptions = []
			}
			
            // save pref
            UserDefaults.standard.set(showDebugVisuals, for: .debugMode)
        }
    }
    
    func setupDebug() {
		// Set appearance of debug output panel
		messagePanel.layer.cornerRadius = 3.0
		messagePanel.clipsToBounds = true
    }
    
    // MARK: - UI Elements and Actions
	
	@IBOutlet weak var messagePanel: UIView!
	@IBOutlet weak var messageLabel: UILabel!
	@IBOutlet weak var debugMessageLabel: UILabel!
	
	var textManager: TextManager!
	
    func setupUIControls() {
		textManager = TextManager(viewController: self)
		
        // hide debug message view
		debugMessageLabel.isHidden = true
		
		featurePointCountLabel.text = ""
		debugMessageLabel.text = ""
		messageLabel.text = ""
    }
	
	@IBOutlet weak var restartExperienceButton: UIButton!
	var restartExperienceButtonIsEnabled = true
	
	@IBAction func restartExperience(_ sender: Any) {
        self.sceneViewManager?.sessionManager.restartExperience()
	}
	
	@IBOutlet weak var screenshotButton: UIButton!
	
	@IBAction func takeScreenshot() {
		guard screenshotButton.isEnabled else {
			return
		}
		
		let takeScreenshotBlock = {
			UIImageWriteToSavedPhotosAlbum(self.sceneView.snapshot(), nil, nil, nil)
			DispatchQueue.main.async {
				// Briefly flash the screen.
				let flashOverlay = UIView(frame: self.sceneView.frame)
				flashOverlay.backgroundColor = UIColor.white
				self.sceneView.addSubview(flashOverlay)
				UIView.animate(withDuration: 0.25, animations: {
					flashOverlay.alpha = 0.0
				}, completion: { _ in
					flashOverlay.removeFromSuperview()
				})
			}
		}
		
		switch PHPhotoLibrary.authorizationStatus() {
		case .authorized:
			takeScreenshotBlock()
		case .restricted, .denied:
			let title = "Photos access denied"
			let message = "Please enable Photos access for this application in Settings > Privacy to allow saving screenshots."
			textManager.showAlert(title: title, message: message)
		case .notDetermined:
			PHPhotoLibrary.requestAuthorization({ (authorizationStatus) in
				if authorizationStatus == .authorized {
					takeScreenshotBlock()
				}
			})
		}
	}
		
	// MARK: - Settings
	
	@IBOutlet weak var settingsButton: UIButton!
	
	@IBAction func showSettings(_ button: UIButton) {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		guard let settingsViewController = storyboard.instantiateViewController(withIdentifier: "settingsViewController") as? SettingsViewController else {
			return
		}
		
		let barButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSettings))
		settingsViewController.navigationItem.rightBarButtonItem = barButtonItem
		settingsViewController.title = "Options"
		
		let navigationController = UINavigationController(rootViewController: settingsViewController)
		navigationController.modalPresentationStyle = .popover
		navigationController.popoverPresentationController?.delegate = self
		navigationController.preferredContentSize = CGSize(width: sceneView.bounds.size.width - 20, height: sceneView.bounds.size.height - 50)
		self.present(navigationController, animated: true, completion: nil)
		
		navigationController.popoverPresentationController?.sourceView = settingsButton
		navigationController.popoverPresentationController?.sourceRect = settingsButton.bounds
	}
	
    @objc
    func dismissSettings() {
		self.dismiss(animated: true, completion: nil)
		updateSettings()
	}
	
	private func updateSettings() {
		let defaults = UserDefaults.standard
		
		showDebugVisuals = defaults.bool(for: .debugMode)
		toggleAmbientLightEstimation(defaults.bool(for: .ambientLightEstimation))
		dragOnInfinitePlanesEnabled = defaults.bool(for: .dragOnInfinitePlanes)
		showHitTestAPIVisualization = defaults.bool(for: .showHitTestAPI)
		use3DOFTracking	= defaults.bool(for: .use3DOFTracking)
		use3DOFTrackingFallback = defaults.bool(for: .use3DOFFallback)
		for (_, plane) in planes {
			plane.updateOcclusionSetting()
		}
	}

	
	// MARK: - UIPopoverPresentationControllerDelegate
	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		return .none
	}
	
	func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
		updateSettings()
	}
}
