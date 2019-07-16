import Foundation
import SceneKit

class Tree {
    let root: Branch

    init(_ root: Branch) {
        self.root = root
    }
}

var i = 0

class Branch {
    var children: [Branch] = []
    weak var parent: Branch? {
        didSet {
            self.angle = -Float.pi / 4
        }
    }
    let name: String

    var angle: Float = 0 {
        didSet {
            node.simdRotation = float4(0, 0, 1, self.angle)
        }
    }

    init() {
        self.name = "Branch[\(i)]"
        i += 1
    }

    lazy var node: SCNNode = {
        let cylinder = SCNCylinder(radius: CGFloat(0.1), height: CGFloat(1))
        let node = SCNNode(geometry: cylinder)
        node.name = name

        node.pivot = SCNMatrix4MakeTranslation(0, -0.5, 0)

        node.simdPosition = float3(0,0.5,0)

        return node
    }()

    func add(_ child: Branch) {
        child.parent = self
        self.children.append(child)
        self.node.addChildNode(child.node)
    }

    // on rigid body:

    let mass: Float = 1
    var force: float2 = float2.zero
    var torque: float3 = float3.zero
    var inertia: Float = 0

    // NOTE: location is along the Y axis of the cylinder/branch, relative to the pivot/parent's end
    func apply(force: float2, at distance: Float) {
        self.force += force
        self.torque += cross(force, convert(position: float2(0, distance)) - worldPosition)
    }

    // of composite body:
    /*
     composite rigid body, we compute the mass, the world
     space inertia tensor, and the total external force and torque
     applied to the composite body evaluated about its parent
     joint.
     */

    var compositeMass: Float = 0
    var compositeInertia: Float = 0
    var compositeForce: float2 = float2.zero
    var compositeTorque: float3 = float3.zero

    func updateComposite() {
        print(self.name, self.force, self.torque)
        for child in children {
            child.updateComposite()
            print(child.name, self.force, child.torque, child.compositeTorque)
        }
        self.compositeMass = mass + children.map { $0.compositeMass }.sum
        self.compositeForce = force + children.map { $0.compositeForce }.sum
        self.compositeTorque = torque + children.map { child in
            return cross(child.compositeForce, child.worldPosition - self.worldPosition) + child.compositeTorque
            }.sum
    }

    func reset() {
        self.compositeMass = 0
        self.compositeInertia = 0
        self.compositeForce = float2.zero
        self.compositeTorque = float3.zero
    }

    var rotation: float3x3 {
        return matrix3x3_rotation(radians: angle)
    }

    var translation: float3x3 {
        if parent != nil {
            return matrix3x3_translation(0, 1)
        } else {
            return matrix_identity_float3x3
        }
    }

    var transform: float3x3 {
        return translation * rotation
    }

    var worldTransform: float3x3 {
        if let parent = parent {
            return parent.worldTransform * transform
        } else {
            return transform
        }
    }

    var position: float2 {
        return (transform * float3(0,0,1)).xy
    }

    var worldPosition: float2 {
        return (worldTransform * float3(0,0,1)).xy
    }

    func convert(position: float2) -> float2 {
        return (worldTransform * float3(position, 1)).xy
    }
}

extension Array where Element == Float {
    var sum: Float {
        return reduce(0, +)
    }
}

extension Array where Element == float2 {
    var sum: float2 {
        return reduce(float2.zero, +)
    }
}

extension Array where Element == float3 {
    var sum: float3 {
        return reduce(float3.zero, +)
    }
}

func matrix3x3_rotation(radians: Float) -> float3x3 {
    let cs = cosf(radians)
    let sn = sinf(radians)
    return matrix_float3x3.init(columns:
        (float3(cs, sn, 0),
         float3(-sn, cs, 0),
         float3(0, 0, 1)))
}

func matrix3x3_translation(_ translationX: Float, _ translationY: Float) -> float3x3 {
    return matrix_float3x3.init(columns:(vector_float3(1, 0, 0),
                                         vector_float3(0, 1, 0),
                                         vector_float3(translationX, translationY, 1)))
}

extension float3 {
    init(_ float2: float2, _ z: Float) {
        self = float3(float2.x, float2.y, z)
    }

    var xy: float2 {
        return float2(x, y)
    }
}
