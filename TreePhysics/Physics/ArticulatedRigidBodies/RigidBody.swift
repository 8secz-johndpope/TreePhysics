import Foundation
import simd
import SceneKit

fileprivate var i = 0

public enum Kind {
    case `static`
    case `dynamic`
}

public class RigidBody {
    let name: String
    var kind: Kind = .dynamic

    // Invariant attributes
    let mass: Float
    let localInertiaTensor: float3x3 // relative to the center of mass

    var force: float3 = float3.zero
    var torque: float3 = float3.zero

    // State attributes that vary as a function of the simulation
    public var centerOfMass: float3
    public var rotation: simd_quatf
    var velocity: float3
    var acceleration: float3
    var inertiaTensor: float3x3
    var angularVelocity: float3
    var angularAcceleration: float3
    var angularMomentum: float3

    var node: SCNNode

    public init(mass: Float, localInertiaTensor: float3x3, node: SCNNode) {
        self.name = "RigidBody[\(i)]"
        i += 1

        self.mass = mass
        self.localInertiaTensor = localInertiaTensor

        self.centerOfMass = float3.zero
        self.rotation = simd_quatf.identity
        self.velocity = float3.zero
        self.acceleration = float3.zero
        self.angularVelocity = float3.zero
        self.angularAcceleration = float3.zero
        self.angularMomentum = float3.zero
        self.inertiaTensor = localInertiaTensor

        self.rotation = simd_quatf.identity

        self.node = node
    }

    func apply(force: float3, torque: float3 = float3.zero) {
        self.force += force
        self.torque += torque
    }

    func resetForces() {
        self.force = float3.zero
        self.torque = float3.zero
    }

    func updateTransform() {
        node.simdPosition = self.centerOfMass
        node.simdOrientation = self.rotation
    }

    var isFinite: Bool {
        return
            rotation.isFinite &&
            inertiaTensor.isFinite &&
            angularVelocity.isFinite &&
            angularAcceleration.isFinite &&
            velocity.isFinite &&
            acceleration.isFinite &&
            centerOfMass.isFinite
    }
}