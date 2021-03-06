import Foundation
import simd
import SceneKit

fileprivate var i = 0

public enum Shape {
    /**
     A `Leaf` represents a physical leaf in a physical tree (i.e., the plant) as opposed to a node in a datastructure with no children. It's shape is a very thin flat plate where (0,0,0) is the stem-end of the leaf. When interacting with the wind it is subject to lift forces and so on.
    */
    case leaf(area: Float)

    /**
     An `Internode` is a branch in a tree, or a segment of a branch if the branch is divided into multiple pieces. Its shape is a cylinder where its pivot is the end of the cylinder where it connects to its parent `Joint`. An `Internode` always branches off from its parent joint at a rotation of (0,0,0); the rotation of the `Joint` encodes the resting state branch angle.
    */
    case internode(area: Float, length: Float, radius: Float)
}

public enum Kind {
    case `static`
    case `dynamic`
}

public class RigidBody {
    let name: String
    let kind: Kind

    // Invariant attributes
    let mass: Float
    let localInertiaTensor: float3x3 // relative to the center of mass
    let shape: Shape?

    var force: simd_float3 = .zero
    var torque: simd_float3 = .zero

    // State attributes that vary as a function of the simulation
    public var centerOfMass: simd_float3
    public var orientation: simd_quatf
    var velocity: simd_float3
    var acceleration: simd_float3
    var inertiaTensor: float3x3
    var angularVelocity: simd_float3
    var angularAcceleration: simd_float3
    var angularMomentum: simd_float3

    public var node: SCNNode

    public init(kind: Kind, mass: Float, localInertiaTensor: float3x3, shape: Shape? = nil, node: SCNNode) {
        self.name = "RigidBody[\(i)]"
        i += 1

        self.kind = kind
        self.mass = mass
        self.localInertiaTensor = localInertiaTensor
        self.shape = shape

        self.centerOfMass = .zero
        self.orientation = simd_quatf.identity
        self.velocity = .zero
        self.acceleration = .zero
        self.angularVelocity = .zero
        self.angularAcceleration = .zero
        self.angularMomentum = .zero
        self.inertiaTensor = localInertiaTensor

        self.node = node
    }

    func apply(force: simd_float3, torque: simd_float3 = .zero) {
        self.force += force
        self.torque += torque
    }

    func resetForces() {
        self.force = .zero
        self.torque = .zero
    }

    func updateTransform() {
        node.simdPosition = self.centerOfMass
        node.simdOrientation = self.orientation
    }

    var isFinite: Bool {
        return
            orientation.isFinite &&
            inertiaTensor.isFinite &&
            angularVelocity.isFinite &&
            angularAcceleration.isFinite &&
            velocity.isFinite &&
            acceleration.isFinite &&
            centerOfMass.isFinite
    }
}
