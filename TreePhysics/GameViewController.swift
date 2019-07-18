import SceneKit

class GameViewController: NSViewController {
    var tree: Tree!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let scene = SCNScene()
        
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        cameraNode.position = SCNVector3(x: 0, y: 0.3, z: 0.5)
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

    var b4: RigidBody!
    var b3: RigidBody!
    var b2: RigidBody!
    var b1: RigidBody!

    override func viewDidAppear() {
        self.tree = TreeMaker().make()
        scnView.scene!.rootNode.addChildNode(tree.root.node)
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
    }

}

var previousTime: TimeInterval? = nil

extension GameViewController: SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let delta = time - (previousTime ?? time)
        if toggle {
            Tree.gravity = float2(0, -9.81)
        } else {
            Tree.gravity = float2.zero
        }

        tree.update(delta: 1.0/30)
        renderer.isPlaying = true
        previousTime = time
    }
}

class TreeMaker {
    let depth = 4
    let branchAngles: [Float] = [Float.pi / 4, 0.1, -Float.pi / 3]
    let segments = 3

    let lengthInitial: Float = 3.2
    let widthInitial: Float = 0.3
    let lengthFactor: Float = 0.6
    let widthFactor: Float = 0.4

    func make() -> Tree {
        let root = RigidBody(mass: 1, length: lengthInitial)
        make(parent: root, depth: depth, length: lengthInitial * lengthFactor, width: widthInitial * widthFactor)
        return Tree(root)
    }

    private func make(parent: RigidBody, depth: Int, length: Float, width: Float) {
        guard depth >= 0 else { return }
        for branchAngle in branchAngles {
            let branch = RigidBody(mass: 1, length: length / Float(segments))
            parent.add(branch, at: branchAngle)
            var segment = branch
            for i in 1..<segments {
                let branch = RigidBody(mass: 1, length: length / Float(segments))
                segment.add(branch, at: 0)
                segment = branch
            }
            make(parent: segment, depth: depth - 1, length: length * lengthFactor, width: width * widthFactor)
        }
    }
}
