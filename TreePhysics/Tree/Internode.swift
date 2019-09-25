import Foundation
import SceneKit

fileprivate var i = 0

extension Internode {
    static let K: Float = 200
    static let β: Float = 0.01
    static let maxAngle: Float = Float.pi / 3
    static let minAngle: Float = -Float.pi / 3
}

public final class Internode: RigidBody {
    public let kind: Kind
    let name: String
    weak public var parentJoint: Joint?
    public var childJoints: [Joint] = []
    
    public let composite: CompositeBody
    
    public let mass: Float
    let length: Float
    let radius: Float
    public let inertiaTensor_local: float3x3
    public let centerOfMass_local: float3

    public var force: float3 = float3.zero
    public var torque: float3 = float3.zero

    public var inertiaTensor: float3x3
    public var rotation: simd_quatf = simd_quatf.identity
    public var translation: float3 = float3.zero
    public var centerOfMass: float3 = float3.zero
    public var angularVelocity: float3 = float3.zero
    public var angularAcceleration: float3 = float3.zero
    public var angularMomentum: float3 = float3.zero
    public var velocity: float3 = float3.zero
    public var acceleration: float3 = float3.zero

    public let node: SCNNode

    // FIXME think about these whether they should be stored properties or what
    var normal: float3 {
        return rotation.act(.y)
    }

    var crossSectionalArea: Float {
        return .pi * radius * length
    }
    
    public init(length: Float = 1.0, radius: Float = 1.0, density: Float = 1.0/Float.pi, kind: Kind = .dynamic) {
        self.name = "Branch[\(i)]"
        print(name)
        i += 1
        
        self.kind = kind
        
        self.mass = Float.pi * radius*radius * length * density
        self.length = length
        self.radius = radius
        let momentOfInertiaAboutY = 1.0/12 * mass * length * length // Moment of Inertia of a rod about its center of mass
        let momentOfInertiaAboutX = 1.0/4 * mass * radius * radius // MoI of a disc about its center
        let momentOfInertiaAboutZ = 1.0/4 * mass * radius * radius // ditto
        
        // Inertia tensor of a rod about its center of mass, see http://scienceworld.wolfram.com/physics/MomentofInertiaCylinder.html
        // and https://en.wikipedia.org/wiki/List_of_moments_of_inertia
        self.inertiaTensor_local = float3x3(diagonal:
            float3(momentOfInertiaAboutY + momentOfInertiaAboutZ,
                   momentOfInertiaAboutZ + momentOfInertiaAboutX,
                   momentOfInertiaAboutX + momentOfInertiaAboutY))

        self.inertiaTensor = inertiaTensor_local
        
        self.centerOfMass_local = float3(0, length/2, 0)

        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        self.node = node
        self.composite = CompositeBody()
        
        node.name = name

        updateTransform()
    }

    func add(_ child: RigidBody, at rotation: simd_quatf) -> Joint {
        let joint = Joint(parent: self, child: child, at: rotation)
        childJoints.append(joint)
        child.parentJoint = joint
        child.updateTransform()
        return joint
    }

    // NOTE: location is along the Y axis of the cylinder/branch, relative to the pivot/parent's end
    // distance is in normalize [0..1] coordinates
    func apply(force: float3, at distance: Float) {
        guard distance >= 0 && distance <= 1 else { fatalError("Force must be applied between 0 and 1") }

        let torque = cross(rotation.act(float3(0, distance * length, 0)), force)
        apply(force: force, torque: torque)
    }

    public func apply(force: float3, torque: float3? = nil) {
        // FIXME: This torque seems wrong
        let torque = torque ?? cross(rotation.act(centerOfMass_local), force)
        self.force += force
        self.torque += torque
    }
    
    public func resetForces() {
        self.force = float3.zero
        self.torque = float3.zero
    }

    public func updateTransform() {
        guard let parentJoint = parentJoint else { return }

        let sora = parentJoint.θ[0]
        let rotation_local = simd_length(sora) < 10e-10 ? simd_quatf.identity : simd_quatf(angle: simd_length(sora), axis: normalize(sora))

        self.rotation = (parentJoint.rotation * rotation_local).normalized
        self.translation = parentJoint.translation

        self.inertiaTensor = float3x3(rotation) * inertiaTensor_local * float3x3(rotation).transpose

        self.centerOfMass = translation + rotation.act(centerOfMass_local)

        node.simdPosition = self.translation
        node.simdOrientation = self.rotation
    }
}

// MARK: Flattening & Leveling

struct UnitOfWork {
    let rigidBody: RigidBody
    let climbers: [RigidBody]
}
typealias Level = [UnitOfWork]

extension Internode {
    func levels() -> [Level] {
        var result: [Level] = []
        var visited = Set<HashRigidBody>()

        var remaining = self.leaves
        repeat {
            var level: Level = []
            var nextRemaining: [RigidBody] = []
            while var n = remaining.popLast() {
                if n.childJoints.allSatisfy({ visited.contains(HashRigidBody($0.childRigidBody)) }) && !visited.contains(HashRigidBody(n)) {
                    var climbers: [RigidBody] = []
                    let beforeClimb = n
                    while let parentRigidBody = n.parentRigidBody, parentRigidBody.hasOneChild {
                        n = parentRigidBody
                        if !visited.contains(HashRigidBody(n)) {
                            visited.insert(HashRigidBody(n))
                            if !n.isRoot {
                                climbers.append(n)
                            }
                        }
                    }
                    if !beforeClimb.isRoot {
                        level.append(
                            UnitOfWork(rigidBody: beforeClimb, climbers: climbers))
                    }
                    if let parentJoint = n.parentJoint {
                        nextRemaining.append(parentJoint.parentRigidBody)
                    }
                }
            }
            if !level.isEmpty {
                result.append(level)
            }
            let beforeClimbs = level.map { HashRigidBody($0.rigidBody) }
            visited.formUnion(beforeClimbs)
            remaining = Array(Set(nextRemaining.map { HashRigidBody($0) })).map { $0.underlying }
        } while !remaining.isEmpty
        return result
    }
}

extension Internode: Hashable {
    public static func == (lhs: Internode, rhs: Internode) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}