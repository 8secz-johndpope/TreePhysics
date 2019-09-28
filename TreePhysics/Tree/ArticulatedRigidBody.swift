import Foundation
import simd
import SceneKit

public class ArticulatedRigidBody: RigidBody {
    weak var parentJoint: Joint? = nil
    public var childJoints: Set<Joint> = []
    let composite = CompositeBody()

    let localPivot: float3
    var pivot: float3 // The `pivot` is the point at which the object connects to its parent, relative to the center of mass.

    public class func `static`() -> ArticulatedRigidBody {
        let rigidBody = ArticulatedRigidBody(mass: 0, localInertiaTensor: float3x3(0), localPivot: float3.zero, node: SCNNode())
        rigidBody.kind = .static
        return rigidBody
    }

    public class func dynamic() -> ArticulatedRigidBody {
        let rigidBody = ArticulatedRigidBody(mass: 0, localInertiaTensor: float3x3(0), localPivot: float3.zero, node: SCNNode())
        rigidBody.kind = .dynamic
        return rigidBody
    }

    public init(mass: Float, localInertiaTensor: float3x3, localPivot: float3, node: SCNNode) {
        self.localPivot = localPivot
        self.pivot = localPivot

        super.init(mass: mass, localInertiaTensor: localInertiaTensor, node: node)
    }

    func add(_ child: ArticulatedRigidBody, rotation: simd_quatf, position: float3) -> Joint {
        let joint = Joint(parent: self, child: child, localRotation: rotation, localPosition: position)
        childJoints.insert(joint)
        child.parentJoint = joint
        joint.updateTransform()
        child.updateTransform()
        return joint
    }

    override func apply(force: float3, torque: float3 = float3.zero) {
        var torque = torque
        if parentJoint != nil {
            torque += cross(rotation.act(-localPivot), force)
        }

        super.apply(force: force, torque: torque)
    }

    override func updateTransform() {
        if let parentJoint = parentJoint {
            let sora = parentJoint.θ[0]
            let rotation_local = simd_length(sora) < 10e-10 ? simd_quatf.identity : simd_quatf(angle: simd_length(sora), axis: normalize(sora))

            // FIXME rename all _local
            self.rotation = (parentJoint.rotation * rotation_local).normalized
            self.pivot = parentJoint.position
            
            self.inertiaTensor = float3x3(rotation) * localInertiaTensor * float3x3(rotation).transpose
            
            self.centerOfMass = self.pivot + rotation.act(-localPivot)
        }

        self.pivot = centerOfMass + rotation.act(localPivot)

        super.updateTransform()
    }

    func removeFromParent() {
        guard let parentJoint = parentJoint else { return }
        let parentRigidBody = parentJoint.parentRigidBody

        self.parentJoint = nil
        parentRigidBody.childJoints.remove(parentJoint)
    }

    var isRoot: Bool {
        return parentJoint == nil
    }

    var isLeaf: Bool {
        return childJoints.isEmpty
    }

    var hasOneChild: Bool {
        return childJoints.count == 1
    }

    var parentRigidBody: ArticulatedRigidBody? {
        return parentJoint?.parentRigidBody
    }

    func flattened() -> [ArticulatedRigidBody] {
        var result: [ArticulatedRigidBody] = []
        var queue: [ArticulatedRigidBody] = [self]
        searchBreadthFirst(queue: &queue, result: &result)
        return result
    }

    private func searchBreadthFirst(queue: inout [ArticulatedRigidBody], result: inout [ArticulatedRigidBody]) {
        while !queue.isEmpty {
            let start = queue.removeFirst()
            result.append(start)
            for childJoint in start.childJoints {
                queue.append(childJoint.childRigidBody)
            }
        }
    }

    var leaves: [ArticulatedRigidBody] {
        var result: [ArticulatedRigidBody] = []
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

    func levels() -> [Level] {
        var result: [Level] = []
        var visited = Set<ArticulatedRigidBody>()

        var remaining = self.leaves
        repeat {
            var level: Level = []
            var nextRemaining: [ArticulatedRigidBody] = []
            while var n = remaining.popLast() {
                if n.childJoints.allSatisfy({ visited.contains($0.childRigidBody) }) && !visited.contains(n) {
                    var climbers: [ArticulatedRigidBody] = []
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
            visited.formUnion(beforeClimbs)
            remaining = Array(Set(nextRemaining))
        } while !remaining.isEmpty
        return result
    }

    override var isFinite: Bool {
        return super.isFinite && pivot.isFinite
    }
}

struct UnitOfWork {
    let rigidBody: ArticulatedRigidBody
    let climbers: [ArticulatedRigidBody]
}
typealias Level = [UnitOfWork]
