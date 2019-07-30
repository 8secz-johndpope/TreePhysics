import SceneKit

class GameViewController: NSViewController {
    var simulator: Simulator!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let scene = SCNScene()
        
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0
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

        let configuration = Interpreter<SkinningPen>.Configuration(
            angle: 18 * .pi / 180, thickness: 0.003*0.003*Float.pi, thicknessScale: 0.9, stepSize: 0.05, stepSizeScale: 0.9)
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
        scnView.delegate = self
    }

    var scnView: SCNView {
        return self.view as! SCNView
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
            Tree.gravity = float3(0, -9.81, 0)
        } else {
            Tree.gravity = float3.zero
        }

        simulator.update(at: 1.0 / 30)
        renderer.isPlaying = true
    }
}
