import Foundation
import SceneKit

fileprivate var i = 0

extension RigidBody {
    static let K: Float = 200
    static let β: Float = 0.02
    static let maxAngle: Float = Float.pi / 3
    static let minAngle: Float = -Float.pi / 3
}

final class RigidBody {
    enum Kind {
        case `static`
        case `dynamic`
    }
    let kind: Kind
    
    let name: String
    weak var parentJoint: Joint?
    var childJoints: [Joint] = []
    
    let composite: CompositeBody
    
    let mass: Float
    let length: Float
    let radius: Float
    let inertiaTensor_local: float3x3
    let centerOfMass_local: float3

    var force: float3 = float3.zero
    var torque: float3 = float3.zero

    var inertiaTensor: float3x3
    var rotation: float3x3 = matrix_identity_float3x3
    var translation: float3 = float3.zero
    var centerOfMass: float3 = float3.zero
    var angularVelocity: float3 = float3.zero
    var angularAcceleration: float3 = float3.zero
    var velocity: float3 = float3.zero
    var acceleration: float3 = float3.zero

    let node: SCNNode
    
    init(length: Float = 1.0, radius: Float = 1.0, density: Float = 1.0/Float.pi, kind: Kind = .dynamic) {
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
        self.inertiaTensor_local = matrix_float3x3(diagonal:
            float3(momentOfInertiaAboutY + momentOfInertiaAboutZ,
                   momentOfInertiaAboutZ + momentOfInertiaAboutX,
                   momentOfInertiaAboutX + momentOfInertiaAboutY))

        self.inertiaTensor = inertiaTensor_local
        
        self.centerOfMass_local = float3(0, 1, 0) * length / 2
        
        let node = SCNNode(geometry: SCNSphere(radius: 0.01))
        self.node = node
        self.composite = CompositeBody()
        
        node.name = name

        updateTransform()
    }

    var position: float3 {
        return translation // FIXME should be center of mass
    }

    // FIXME test only
    func add(_ child: RigidBody, at eulerAngles: float3 = float3(0, 0, -.pi / 4)) -> Joint {
        return add(child, at: matrix3x3_rotation(rotation: eulerAngles))
    }
    
    func add(_ child: RigidBody, at rotation: matrix_float3x3) -> Joint {
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
        
        self.force += force
        self.torque += cross(translation + rotation * float3(0, distance * length, 0) - self.position, force)
    }
    
    func resetForces() {
        self.force = float3.zero
        self.torque = float3.zero
    }

    var rotation_local: float3x3 {
        guard let parentJoint = parentJoint else { return matrix_identity_float3x3 }
        let sora = parentJoint.θ[0]
        guard simd_length(sora) > 10e-10 else {
            // otherwise matrix3x3_rotation will return NaNs
            return matrix_identity_float3x3
        }
        return matrix3x3_rotation(radians: simd_length(sora), axis: sora)
    }
    
    func updateTransform() {
        guard let parentJoint = parentJoint else { return }
        let parentRigidBody = parentJoint.parentRigidBody

        self.rotation = parentJoint.rotation * rotation_local
        self.translation = parentJoint.translation

        node.simdPosition = self.position
//        node.simdRotation = ... FIXME

        self.inertiaTensor = rotation * inertiaTensor_local * rotation.transpose

        self.angularVelocity = parentRigidBody.angularVelocity + parentJoint.rotation * parentJoint.θ[1]
        self.angularAcceleration = parentRigidBody.angularAcceleration + parentJoint.rotation * parentJoint.θ[2] + parentRigidBody.angularVelocity.crossMatrix * self.angularVelocity

        self.velocity = parentRigidBody.velocity + parentRigidBody.angularVelocity.crossMatrix * parentRigidBody.rotation * parentJoint.position_local - self.angularVelocity.crossMatrix * rotation * (-centerOfMass_local)
        self.acceleration = parentJoint.acceleration - (self.angularAcceleration.crossMatrix + sqr(self.angularVelocity.crossMatrix)) * rotation * (-centerOfMass_local)

        self.centerOfMass = translation + rotation * centerOfMass_local
    }
}

// MARK: Flattening & Leveling

struct UnitOfWork {
    let rigidBody: RigidBody
    let climbers: [RigidBody]
}
typealias Level = [UnitOfWork]

extension RigidBody {
    var hasOneChild: Bool {
        return childJoints.count == 1
    }
    
    var parentRigidBody: RigidBody? {
        return parentJoint?.parentRigidBody
    }
    
    func levels() -> [Level] {
        var result: [Level] = []
        var visited: Set<RigidBody> = []
        
        var remaining = self.leaves
        repeat {
            var level: Level = []
            var nextRemaining: [RigidBody] = []
            while var n = remaining.popLast() {
                if n.childJoints.allSatisfy({ visited.contains($0.childRigidBody) }) && !visited.contains(n) {
                    var climbers: [RigidBody] = []
                    let beforeClimb = n
                    while let parentRigidBody = n.parentRigidBody, parentRigidBody.hasOneChild {
                        n = parentRigidBody
                        if !visited.contains(n) {
                            visited.insert(n)
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
            let beforeClimbs = level.map { $0.rigidBody }
            visited = visited.union(beforeClimbs)
            remaining = Array(Set(nextRemaining))
        } while !remaining.isEmpty
        return result
    }
    
    var isRoot: Bool {
        return parentJoint == nil
    }
    
    func flattened() -> [RigidBody] {
        var result: [RigidBody] = []
        var queue: [RigidBody] = [self]
        searchBreadthFirst(queue: &queue, result: &result)
        return result
    }
    
    var leaves: [RigidBody] {
        var result: [RigidBody] = []
        for childJoint in childJoints {
            let childRigidBody = childJoint.childRigidBody
            if childRigidBody.isLeaf {
                result.append(childRigidBody)
            } else {
                result.append(contentsOf: childRigidBody.leaves)
            }
        }
        return result
    }
    
    var isLeaf: Bool {
        return childJoints.count == 0
    }
    
    private func searchBreadthFirst(queue: inout [RigidBody], result: inout [RigidBody]) {
        while !queue.isEmpty {
            let start = queue.removeFirst()
            result.append(start)
            for childJoint in start.childJoints {
                queue.append(childJoint.childRigidBody)
            }
        }
    }
}

extension RigidBody: Equatable, Hashable {
    static func == (lhs: RigidBody, rhs: RigidBody) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
