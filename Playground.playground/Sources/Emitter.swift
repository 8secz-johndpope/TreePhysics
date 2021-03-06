import Foundation
import simd
@testable import TreePhysics

public class Emitter {
    let maxAge: TimeInterval
    let world: PhysicsWorld
    let birthRate: Float

    var bucket: (Float, Int)? = nil

    public var count = 0
    public var particles: [(ArticulatedRigidBody, Date)?]
    public var ticks = 0
    let noise = Noise()
    var total = 0

    public init(birthRate: Float, max: Int, maxAge: TimeInterval, world: PhysicsWorld) {
        precondition(birthRate <= 1)
        
        self.birthRate = birthRate
        self.maxAge = maxAge
        self.particles = [(ArticulatedRigidBody, Date)?](repeating: nil, count: max)
        self.world = world
    }

    public func emit() -> ArticulatedRigidBody? {
        ticks += 1
        guard ticks % Int(1/birthRate) == 0 else { return nil }
        guard count + 1 < particles.count else { return nil }

        let leaf = Tree.leaf(length: 1, density: 500)
        let seed = 1 + total
        leaf.orientation =
            simd_quatf(angle: noise.random(seed + 0) * 2 * .pi, axis: .x) *
            simd_quatf(angle: noise.random(seed + 1) * 2 * .pi, axis: .y) *
            simd_quatf(angle: noise.random(seed + 2) * 2 * .pi, axis: .z)

        leaf.orientation = leaf.orientation.normalized
        leaf.updateTransform()

        particles[count] = (leaf, Date())
        world.add(rigidBody: leaf)

        count += 1
        count %= particles.count
        total += 1
        total %= Int.max
        return leaf
    }

    public func update() {
        let now = Date()
        for i in 0..<count {
            let (leaf, createdAt) = particles[i]!
            if abs(createdAt.timeIntervalSince(now)) > maxAge {
                leaf.node.removeFromParentNode()
                world.remove(rigidBody: leaf)
                particles[i] = particles[count - 1]
                count -= 1
            }
        }
    }
}
