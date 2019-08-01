import SceneKit

class GameViewController: NSViewController {
    var simulator: Simulator!
    var gravityField: GravityField!
    var attractorField: AttractorField!
    var attractor: SCNNode!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let scene = SCNScene()
        
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0
        camera.zFar = 5
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 1)
        cameraNode.name = "Camera"

        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.name = "Ambient Light"
        scene.rootNode.addChildNode(ambientLightNode)
        
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.showsStatistics = true
        scnView.backgroundColor = NSColor.black

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        var gestureRecognizers = scnView.gestureRecognizers
        gestureRecognizers.insert(clickGesture, at: 0)
        scnView.gestureRecognizers = gestureRecognizers
    }

    override func viewDidAppear() {
        let root = RigidBody(length: 0, radius: 0, density: 0, kind: .static)
        let cylinderPen = CylinderPen(radialSegmentCount: 3, heightSegmentCount: 1)
        let rigidBodyPen = RigidBodyPen(parent: root)
        let skinningPen = SkinningPen(cylinderPen: cylinderPen, rigidBodyPen: rigidBodyPen)

        let rule = Rewriter.Rule(symbol: "A", replacement: #"[!"&FFFFFFA]/////[!"&FFFFFFA]/////[!"&FFFFFFA]"#)
        let lSystem = Rewriter.rewrite(premise: "A", rules: [rule], generations: 5)

        let configuration = Interpreter<SkinningPen>.Configuration(randomScale: 0.4,
            angle: 18 * .pi / 180, thickness: 0.002*0.002*Float.pi, thicknessScale: 0.9, stepSize: 0.1, stepSizeScale: 0.9)
        let interpreter = Interpreter(configuration: configuration, pen: skinningPen)
        interpreter.interpret(lSystem)
        let tree = Tree(root)
        self.simulator = Simulator(tree: tree)

        let geometry = cylinderPen.geometry

        var boneNodes: [SCNNode] = []
        var boneInverseBindTransforms: [NSValue] = []
        var boneWeights: [Float] = Array(repeating: 1.0, count: cylinderPen.vertices.count)
        var boneIndices: Indices = Array(repeating: 0, count: cylinderPen.vertices.count)

        for (boneIndex, bone) in skinningPen.bones.enumerated() {
            let (vertexIndices, rigidBody) = bone
            let node = rigidBody.node
            boneNodes.append(node)
            boneInverseBindTransforms.append(NSValue(scnMatrix4: SCNMatrix4Invert(node.worldTransform)))
            for vertexIndex in vertexIndices {
                boneIndices[Int(vertexIndex)] = UInt16(boneIndex)
            }
        }

        let boneWeightsData = Data(bytesNoCopy: &boneWeights, count: boneWeights.count * MemoryLayout<Float>.size, deallocator: .none)
        let boneIndicesData = Data(bytesNoCopy: &boneIndices, count: boneWeights.count * MemoryLayout<UInt16>.size, deallocator: .none)

        let boneWeightsGeometrySource = SCNGeometrySource(data: boneWeightsData, semantic: .boneWeights, vectorCount: boneWeights.count, usesFloatComponents: true, componentsPerVector: 1, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size)
        let boneIndicesGeometrySource = SCNGeometrySource(data: boneIndicesData, semantic: .boneIndices, vectorCount: boneIndices.count, usesFloatComponents: false, componentsPerVector: 1, bytesPerComponent: MemoryLayout<UInt16>.size, dataOffset: 0, dataStride: MemoryLayout<UInt16>.size)

        let skinner = SCNSkinner(baseGeometry: geometry, bones: boneNodes, boneInverseBindTransforms: boneInverseBindTransforms, boneWeights: boneWeightsGeometrySource, boneIndices: boneIndicesGeometrySource)

        let node = SCNNode(geometry: geometry)
        node.skinner = skinner

        let scene = scnView.scene!
        scene.rootNode.addChildNode(node)

//        for bone in boneNodes {
//            scene.rootNode.addChildNode(bone)
//        }

        let gravityField = GravityField(float3.zero)
        let attractorField = AttractorField()
        self.gravityField = gravityField
        simulator.add(field: gravityField)
        simulator.add(field: attractorField)

        let attractor = SCNNode(geometry: SCNSphere(radius: 0.1))
        scene.rootNode.addChildNode(attractor)
        self.attractorField = attractorField
        self.attractor = attractor

        scnView.delegate = self
        scnView.fooDelegate = self
    }

    var scnView: Foo {
        return self.view as! Foo
    }
}

var toggle: Bool = false

extension GameViewController {
    @objc
    func handleClick(_ gestureRecognizer: NSGestureRecognizer) {
        toggle = !toggle
        print(scnView.hitTest(gestureRecognizer.location(in: scnView), options: nil))
    }

}

extension GameViewController: SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if toggle {
            gravityField.g = float3(0, -9.81, 0)
        } else {
            gravityField.g = float3.zero
        }

        simulator.update(at: 1.0 / 60)
        renderer.isPlaying = true
    }
}

protocol FooDelegate: class {
    func mouseMoved(with event: NSEvent, in view: SCNView)
}

extension GameViewController: FooDelegate {
    func mouseMoved(with event: NSEvent, in view: SCNView) {
        let nsPoint = event.locationInWindow

        let projectedOrigin = view.projectPoint(SCNVector3Zero)
        let vpWithZ = SCNVector3(x: nsPoint.x, y: nsPoint.y, z: projectedOrigin.z)
        let worldPoint = float3(view.unprojectPoint(vpWithZ))

        attractorField.position = worldPoint
        attractor.simdPosition = worldPoint
    }
}

class Foo: SCNView {
    weak var fooDelegate: FooDelegate!
    var trackingArea : NSTrackingArea?

    override func updateTrackingAreas() {
        if trackingArea != nil {
            self.removeTrackingArea(trackingArea!)
        }
        let options : NSTrackingArea.Options =
            [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow]
        trackingArea = NSTrackingArea(rect: self.bounds, options: options,
                                      owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        fooDelegate.mouseMoved(with: event, in: self)
    }


}
