//
//  ViewController.swift
//  ARKitRectangleDetection
//
//  Created by Melissa Ludowise on 8/3/17.
//  Copyright © 2017 Mel Ludowise. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision
import CoreML

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - IBOutlets
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var messageView: UIView!
    @IBOutlet weak var clearButton: UIButton!
    @IBOutlet weak var restartButton: UIButton!
    @IBOutlet weak var debugButton: UIButton!
    
    
    // MARK: - Internal properties used to identify the rectangle the user is selecting
    
    // Displayed rectangle outline
    private var selectedRectangleOutlineLayer: CAShapeLayer?
    /// Andrew's
    private var detectedRectangleOutlineLayers = [CAShapeLayer]()
    
    // Observed rectangle currently being touched
    private var selectedRectangleObservation: VNRectangleObservation?
    /// Andrew's
    private var detectedRectangleObservations = [VNRectangleObservation]()
    private var objectiveDetected  = false  /// TODO: is there better way than using global variable like such
    
    // The time the current rectangle selection was last updated
    private var selectedRectangleLastUpdated: Date?
    
    // Current touch location
    private var currTouchLocation: CGPoint?
    
    // Gets set to true when actively searching for rectangles in the current frame
    private var searchingForRectangles = false
    
    
    // MARK: - Rendered items
    
    // RectangleNodes with keys for rectangleObservation.uuid
    private var rectangleNodes = [VNRectangleObservation:RectangleNode]()
    
    // Used to lookup SurfaceNodes by planeAnchor and update them
    private var surfaceNodes = [ARPlaneAnchor:SurfaceNode]()
    
    // MARK: - Debug properties
    
    var showDebugOptions = false {
        didSet {
            if showDebugOptions {
                sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
            } else {
                sceneView.debugOptions = []
            }
        }
    }
    
    
    // MARK: - Message displayed to the user
    
    private var message: Message? {
        didSet {
            DispatchQueue.main.async {
                if let message = self.message {
                    self.messageView.isHidden = false
                    self.messageLabel.text = message.localizedString
                    self.messageLabel.numberOfLines = 0
                    self.messageLabel.sizeToFit()
                    self.messageLabel.superview?.setNeedsLayout()
                } else {
                    self.messageView.isHidden = true
                }
            }
        }
    }
    
    
    // MARK: - UIViewController
    
    override var prefersStatusBarHidden: Bool {
        get {
            return true
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegates
        sceneView.delegate = self
        
        // Comment out to disable rectangle tracking
        sceneView.session.delegate = self
        
        
        
        // Show world origin and feature points if desired
        if showDebugOptions {
            sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
        }
        
        // Enable default lighting
        sceneView.autoenablesDefaultLighting = true
        
        // Create a new scene
        let scene = SCNScene()
        sceneView.scene = scene
        
        // Don't display message
        message = nil
        
        // Style clear button
        styleButton(clearButton, localizedTitle: NSLocalizedString("Clear Rects", comment: ""))
        styleButton(restartButton, localizedTitle: NSLocalizedString("Restart", comment: ""))
        styleButton(debugButton, localizedTitle: NSLocalizedString("Debug", comment: ""))
        debugButton.isSelected = showDebugOptions
        
        /// MARK: Andrew's Code
        //        selectedRectangleLastUpdated = Date()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        //        configuration.worldAlignment = .gravityAndHeading
        
        // Run the view's session
        sceneView.session.run(configuration)
        
        // Tell user to find the a surface if we don't know of any
        if surfaceNodes.isEmpty {
            message = .helpFindSurface
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        //        guard let touch = touches.first,
        //            let currentFrame = sceneView.session.currentFrame else {
        //            return
        //        }
        //
        //        currTouchLocation = touch.location(in: sceneView)
        //        findRectangle(locationInScene: currTouchLocation!, frame: currentFrame)
        //        message = .helpTapReleaseRect
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        //        // Ignore if we're currently searching for a rect
        //        if searchingForRectangles {
        //            return
        //        }
        //
        guard let touch = touches.first,
            let currentFrame = sceneView.session.currentFrame else {
                return
        }
        
        currTouchLocation = touch.location(in: sceneView)
        for observation in detectedRectangleObservations {
            print("hey-=-")
            let convertedRect = self.sceneView.convertFromCamera(observation.boundingBox)
            if convertedRect.contains(currTouchLocation!){
                print("hey again")
                // Create a planeRect and add a RectangleNode
                addPlaneRect(for: observation)
            }
        }
        //        findRectangle(locationInScene: currTouchLocation!, frame: currentFrame)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        currTouchLocation = nil
        message = .helpTapHoldRect
        
        
        /// MARK:- Andrew's Code
        guard let touch = touches.first,
            let currentFrame = sceneView.session.currentFrame else {
                return
        }
        
        currTouchLocation = touch.location(in: sceneView)
        
        for observation in detectedRectangleObservations {
            let convertedRect = self.sceneView.convertFromCamera(observation.boundingBox)
            if convertedRect.contains(currTouchLocation!){
                // Create a planeRect and add a RectangleNode
                addPlaneRect(for: observation)
            }
        }
    }
    
    // MARK: - IBOutlets
    
    @IBAction func onClearButton(_ sender: Any) {
        rectangleNodes.forEach({ $1.removeFromParentNode() })
        rectangleNodes.removeAll()
    }
    
    @IBAction func onRestartButton(_ sender: Any) {
        // Remove all rectangles
        rectangleNodes.forEach({ $1.removeFromParentNode() })
        rectangleNodes.removeAll()
        
        // Remove all surfaces and tell session to forget about anchors
        surfaceNodes.forEach { (anchor, surfaceNode) in
            sceneView.session.remove(anchor: anchor)
            surfaceNode.removeFromParentNode()
        }
        surfaceNodes.removeAll()
        
        // Update message
        message = .helpFindSurface
    }
    
    @IBAction func onDebugButton(_ sender: Any) {
        showDebugOptions = !showDebugOptions
        debugButton.isSelected = showDebugOptions
        
        if showDebugOptions {
            debugButton.layer.backgroundColor = UIColor.yellow.cgColor
            debugButton.layer.borderColor = UIColor.yellow.cgColor
        } else {
            debugButton.layer.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
            debugButton.layer.borderColor = UIColor.white.cgColor
        }
    }
    
    // MARK: - ARSessionDelegate
    
    // Update selected rectangle if it's been more than 1 second and the screen is still being touched
    var frameIncrement = 0
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        //------
        if isTracking {
            for layer in self.detectedRectangleOutlineLayers {
                layer.removeFromSuperlayer()
            }
            self.detectedRectangleOutlineLayers.removeAll()

            guard let lb = lastObservation else {return}
            DispatchQueue.global(qos: .background).async {
                self.performTracking(lb, handler: self.sequenceHandler, currentFrame: frame)
            }
            return
        }
        //------
        
        // Remove outline for observed rectangles
        for layer in self.detectedRectangleOutlineLayers {
            layer.removeFromSuperlayer()
        }
        self.detectedRectangleOutlineLayers.removeAll()
        
        frameIncrement += 1
        if frameIncrement != 8 {
            return
        } else {
            frameIncrement = 0
        }
        
        
        if isTracking {
            return
        }
        
        if searchingForRectangles {
            return
        }
        
        guard let timePassed = selectedRectangleLastUpdated?.timeIntervalSinceNow else {
            findRectangle(currentFrame: frame)
            return
        }
        //        if timePassed > -1 {
        //            return
        //        }
        
        
        findRectangle(currentFrame: frame)
        //
        //        guard let currTouchLocation = currTouchLocation,
        //            let currentFrame = sceneView.session.currentFrame else {
        //                return
        //        }
        //
        //
        //        findRectangle(locationInScene: currTouchLocation, frame: currentFrame)
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let anchor = anchor as? ARPlaneAnchor else {
            return
        }
        
        let surface = SurfaceNode(anchor: anchor)
        surfaceNodes[anchor] = surface
        node.addChildNode(surface)
        
        if message == .helpFindSurface {
            message = .helpTapHoldRect
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // See if this is a plane we are currently rendering
        guard let anchor = anchor as? ARPlaneAnchor,
            let surface = surfaceNodes[anchor] else {
                return
        }
        
        surface.update(anchor)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let anchor = anchor as? ARPlaneAnchor,
            let surface = surfaceNodes[anchor] else {
                return
        }
        
        surface.removeFromParentNode()
        
        surfaceNodes.removeValue(forKey: anchor)
    }
    
    // MARK: - Helper Methods
    
    // Updates selectedRectangleObservation with the the rectangle found in the given ARFrame at the given location
    private func findRectangle(locationInScene location: CGPoint, frame currentFrame: ARFrame) {
        // Note that we're actively searching for rectangles
        searchingForRectangles = true
        selectedRectangleObservation = nil
        
        // Perform request on background thread
        DispatchQueue.global(qos: .background).async {
            let request = VNDetectRectanglesRequest(completionHandler: { (request, error) in
                
                // Jump back onto the main thread
                DispatchQueue.main.async {
                    
                    // Mark that we've finished searching for rectangles
                    self.searchingForRectangles = false
                    
                    // Access the first result in the array after casting the array as a VNClassificationObservation array
                    guard let observations = request.results as? [VNRectangleObservation],
                        let _ = observations.first else {
                            print ("No results")
                            self.message = .errNoRect
                            return
                    }
                    
                    print("\(observations.count) rectangles found")
                    
                    // Remove outline for selected rectangle
                    if let layer = self.selectedRectangleOutlineLayer {
                        layer.removeFromSuperlayer()
                        self.selectedRectangleOutlineLayer = nil
                    }
                    
                    // Find the rect that overlaps with the given location in sceneView
                    guard let selectedRect = observations.filter({ (result) -> Bool in
                        let convertedRect = self.sceneView.convertFromCamera(result.boundingBox)
                        return convertedRect.contains(location)
                    }).first else {
                        print("No results at touch location")
                        self.message = .errNoRect
                        return
                    }
                    
                    // Outline selected rectangle
                    let points = [selectedRect.topLeft, selectedRect.topRight, selectedRect.bottomRight, selectedRect.bottomLeft]
                    let convertedPoints = points.map { self.sceneView.convertFromCamera($0) }
                    self.selectedRectangleOutlineLayer = self.drawPolygon(convertedPoints, color: UIColor.red)
                    self.sceneView.layer.addSublayer(self.selectedRectangleOutlineLayer!)
                    
                    // Track the selected rectangle and when it was found
                    self.selectedRectangleObservation = selectedRect
                    self.selectedRectangleLastUpdated = Date()
                    
                    // Check if the user stopped touching the screen while we were in the background.
                    // If so, then we should add the planeRect here instead of waiting for touches to end.
                    if self.currTouchLocation == nil {
                        // Create a planeRect and add a RectangleNode
                        self.addPlaneRect(for: selectedRect)
                    }
                }
            })
            
            // Don't limit resulting number of observations
            request.maximumObservations = 0
            
            /// MARK:- Andrew's Code:
            /// Additional Parameters for Rectangle Detector
            request.quadratureTolerance = 50.0
            
            // Perform request
            let handler = VNImageRequestHandler(cvPixelBuffer: currentFrame.capturedImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func addPlaneRect(for observedRect: VNRectangleObservation) {
        // Remove old outline of selected rectangle
        if let layer = selectedRectangleOutlineLayer {
            layer.removeFromSuperlayer()
            selectedRectangleOutlineLayer = nil
        }
        
        // Convert to 3D coordinates
        guard let planeRectangle = PlaneRectangle(for: observedRect, in: sceneView) else {
            print("No plane for this rectangle")
            message = .errNoPlaneForRect
            return
        }
        
        let rectangleNode = RectangleNode(planeRectangle)
        rectangleNodes[observedRect] = rectangleNode
        sceneView.scene.rootNode.addChildNode(rectangleNode)
    }
    
    private func drawPolygon(_ points: [CGPoint], color: UIColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = color.cgColor
        layer.lineWidth = 2
        let path = UIBezierPath()
        path.move(to: points.last!)
        points.forEach { point in
            path.addLine(to: point)
        }
        layer.path = path.cgPath
        return layer
    }
    
    private func styleButton(_ button: UIButton, localizedTitle: String?) {
        button.layer.borderColor = UIColor.white.cgColor
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 4
        button.setTitle(localizedTitle, for: .normal)
    }
    
    /// MARK: Andrew's Code
    
    // Check if Rectangle Observation is a window using MobileNet.
    // NOTE: consider running on different thread?
    lazy var model:VNCoreMLModel = {
        do {
            let model = try VNCoreMLModel(for: MobileNet().model)
            return model
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    func checkAndDrawWindow(_ observation: VNRectangleObservation, currentFrame: ARFrame ) {
        DispatchQueue.main.async { // Crop out image around rectangle for localized classification
            let currentImage = CIImage(cvPixelBuffer: currentFrame.capturedImage)
            
            let convertedRect = convertFromCamera(observation.boundingBox, size: currentImage.extent.size)
            print(observation.boundingBox)
//            let rect = expandRect(convertedRect, extent: currentImage.extent)
            let rect = CGRect(x: 0.0, y: 0.0, width: 500, height: 500)
            let croppedImage = currentImage.cropped(to: rect)

            DispatchQueue.global(qos: .background).async {
                let mlRequest = VNCoreMLRequest(model: self.model){ (request, error) in
                    let results = request.results as! [VNClassificationObservation]
                    
                    if results.first!.identifier.contains("window") || results.first!.identifier.contains("shoji") {
                        guard let confidence = results.first?.confidence else {return}
                        if confidence > Float(0.2) {
                            
                            // -----
                            // begin tracking
                            self.lastObservation = observation
                            self.isTracking = true
                            self.performTracking(observation, handler: self.sequenceHandler, currentFrame: currentFrame)
                            // -----
                            
//                            DispatchQueue.main.async{ // Outline the windows
//                                let points = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
//                                let convertedPoints = points.map { self.sceneView.convertFromCamera($0) }
//                                let layer = self.drawPolygon(convertedPoints, color: UIColor.red)
//                                self.sceneView.layer.addSublayer(layer)
//                                self.detectedRectangleOutlineLayers.append(layer)
//
//                                // Track the selected rectangle and when it was found
//                                self.detectedRectangleObservations.append(observation)
//                                self.selectedRectangleLastUpdated = Date()
//                            }
                        }
                    }
                }
                mlRequest.imageCropAndScaleOption = .scaleFit
//                print("current: ", currentImage.extent)
//                print("cropped: ", croppedImage.extent)
                try? VNImageRequestHandler(ciImage: croppedImage, options: [:]).perform([mlRequest])
            }
        }
    }
    
    private func findRectangle(currentFrame: ARFrame) {
        // Note that we're actively searching for rectangles
        //        searchingForRectangles = true
        detectedRectangleObservations.removeAll()
        self.objectiveDetected = false
        
        // Perform request on background thread
        DispatchQueue.global(qos: .background).async {
            let request = VNDetectRectanglesRequest(completionHandler: { (request, error) in
                guard let observations = request.results as? [VNRectangleObservation] else {return}
                

                guard let observation = observations.first else {return}
                self.checkAndDrawWindow(observation, currentFrame: currentFrame)
//                for observation in observations  {
//                    self.checkAndDrawWindow(observation, currentFrame: currentFrame)
//                }
            })
            
            // Don't limit resulting number of observations
            request.maximumObservations = 0
            request.quadratureTolerance = 50.0
            request.minimumAspectRatio  = 0.5
            request.maximumAspectRatio  = 2.0
            request.minimumConfidence   = 0.5
            
            // Perform request
            let handler = VNImageRequestHandler(cvPixelBuffer: currentFrame.capturedImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    
    // Rectangle Tracking Code
    private var lastObservation: VNRectangleObservation?
    private var sequenceHandler = VNSequenceRequestHandler()
    private var isTracking = false
    private func performTracking(_ observation: VNRectangleObservation, handler: VNSequenceRequestHandler,currentFrame: ARFrame) {
        let request = VNTrackRectangleRequest(rectangleObservation: observation) { [unowned self] request, error in
            self.handleTrackingRequest(request, error: error)
        }
        request.trackingLevel = .fast
        
        do {
            print("we're tracking")
            try handler.perform([request], on: currentFrame.capturedImage)
        }
        catch {
//            self.isTracking = false
//            self.sequenceHandler = VNSequenceRequestHandler()
            print("==failed==")
            print(error)
        }
    }
    
    fileprivate func handleTrackingRequest(_ request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let observation = request.results?.first as? VNRectangleObservation else {
                return
            }
            self.lastObservation = observation
            
            // highlight rectangle
            
            let points = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
            let convertedPoints = points.map { self.sceneView.convertFromCamera($0) }
            let layer = self.drawPolygon(convertedPoints, color: UIColor.red)
            self.sceneView.layer.addSublayer(layer)
            self.detectedRectangleOutlineLayers.append(layer)
            
            // Track the selected rectangle and when it was found
//                self.detectedRectangleObservations.append(observation)
            self.selectedRectangleLastUpdated = Date()
            
            
        }
    }
}
