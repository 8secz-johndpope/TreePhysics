import XCTest
@testable import TreePhysics
import simd

fileprivate let sqrt2: Float = sqrtf(2)
fileprivate let delta: TimeInterval = 1/60

/*
 The simplest test: One vertical node (attached to a root) with a force applied in the x direction.
 */
class SimpleCPUSimulatorTests: XCTestCase {
    var simulator: CPUSimulator!
    var b0: ArticulatedRigidBody!
    var joint: Joint!
    var forceAppliedPosition: simd_float3!
    let force = simd_float3(1, 0, 0)

    override func setUp() {
        super.setUp()

        let root = ArticulatedRigidBody.static()
        b0 = Tree.internode(length: 1, radius: 1)
        joint = root.add(b0, orientation: .identity, position: .zero)
        joint.stiffness = 1
        joint.torqueThreshold = .infinity
        joint.damping = 1

        let world = PhysicsWorld()
        simulator = CPUSimulator(world: world)
        world.add(rigidBody: root)

        b0.apply(force: force)
        self.forceAppliedPosition = b0.pivot + b0.orientation.act(simd_float3(0, 1/2, 0))
    }

    func testPreconditions() {
        XCTAssertEqual(b0.pivot, .zero)
        XCTAssertEqual(b0.centerOfMass, simd_float3(0,1/2,0))
        XCTAssertEqual(b0.mass, 1)
        XCTAssertEqual(b0.force, force)
        XCTAssertEqual(b0.torque, cross(forceAppliedPosition, force))
        XCTAssertEqual(b0.torque, cross(forceAppliedPosition - b0.pivot, force), accuracy: 0.0001)
        XCTAssertEqual(float3x3(b0.orientation.normalized) * b0.inertiaTensor * float3x3(b0.orientation.normalized).transpose,
                       float3x3(diagonal: simd_float3(
                        1.0/4 + 1.0/12,
                        1.0/2,
                        1.0/4 + 1.0/12
                       )), accuracy: 0.0001)

        XCTAssertEqual(joint.stiffness, 1)
        XCTAssertEqual(joint.damping, 1)
    }

    func testComposite() {
        simulator.updateCompositeBodies()

        XCTAssertEqual(b0.composite.mass, b0.mass)
        XCTAssertEqual(b0.composite.force, b0.force)
        XCTAssertEqual(b0.composite.torque, b0.torque)
        XCTAssertEqual(b0.composite.centerOfMass, b0.centerOfMass)
        XCTAssertEqual(b0.composite.inertiaTensor, b0.inertiaTensor)
    }

    func testUpdateJoints() {
        simulator.updateCompositeBodies()
        simulator.updateJoints(at: delta)

        let momentOfInertia: Float = 1/4 + 1/12
        let compositeInertiaRelativeToJoint = momentOfInertia +
            b0.composite.mass * sqr(distance(b0.composite.centerOfMass, joint.position))

        let θ = evaluateDifferential(a: compositeInertiaRelativeToJoint, b: joint.damping * joint.stiffness, c: joint.stiffness, g: b0.composite.torque.z, y_0: 0, y_ddt_0: 0, at: Float(delta))

        XCTAssertEqual(
            float3x3(
                simd_float3(0,0,θ[0]),
                simd_float3(0,0,θ[1]),
                simd_float3(0,0,θ[2])
            ),
            b0.parentJoint!.θ, accuracy: 0.0001)
    }

    func testUpdateRigidBodies() {
        simulator.update(at: delta)

        let momentOfInertia: Float = 1/4 + 1/12
        let compositeInertiaRelativeToJoint = momentOfInertia +
            b0.composite.mass * sqr(distance(b0.composite.centerOfMass, joint.position))
        let θ = evaluateDifferential(a: compositeInertiaRelativeToJoint, b: joint.damping * joint.stiffness, c: joint.stiffness, g: b0.composite.torque.z, y_0: 0, y_ddt_0: 0, at: Float(delta))

        let orientation = simd_quatf(angle: θ[0], axis: .z)
        XCTAssertEqual(
            orientation.act(simd_float3(0, 0.5, 0)),
            b0.centerOfMass, accuracy: 0.0001)
        XCTAssertEqual(
            orientation,
            b0.orientation, accuracy: 0.0001)
    }
}

/*
 The second simplest test: One vertical node with a child at orientation -π/4 and a force applied in the x direction.
 */
class CPUSimulatorTests: XCTestCase {
    var simulator: CPUSimulator!
    var b0: ArticulatedRigidBody!
    var b1: ArticulatedRigidBody!
    let force = simd_float3(1, 0, 0) // world coordinates
    var forceAppliedPosition: simd_float3!
    let momentOfInertiaOfRod: Float = 1/4 + 1/12

    override func setUp() {
        super.setUp()

        let root = ArticulatedRigidBody.static()
        b0 = Tree.internode(length: 1, radius: 1)
        b1 = Tree.internode(length: 1, radius: 1)
        let b0joint = root.add(b0, orientation: .identity, position: .zero)
        b0joint.stiffness = 1
        b0joint.torqueThreshold = .infinity
        b0joint.damping = 1

        let b1Joint = b0.add(b1, orientation: simd_quatf(angle: -.pi/4, axis: .z), position: simd_float3(0,1,0))
        b1Joint.stiffness = 1
        b1Joint.torqueThreshold = .infinity
        b1Joint.damping = 1

        let world = PhysicsWorld()
        simulator = CPUSimulator(world: world)
        world.add(rigidBody: root)

        b1.apply(force: force)
        self.forceAppliedPosition = b1.orientation.act(simd_float3(0, 1/2, 0))
    }

    func testPreconditions() {
        XCTAssertEqual(b0.pivot, .zero)
        XCTAssertEqual(b0.centerOfMass, simd_float3(0,1/2,0))
        XCTAssertEqual(b0.mass, 1)
        XCTAssertEqual(b0.force, .zero)
        XCTAssertEqual(b0.torque, .zero)
        XCTAssertEqual(float3x3(b0.orientation).transpose * b0.inertiaTensor * float3x3(b0.orientation),
                       float3x3(diagonal: simd_float3(
                        1.0/4 + 1.0/12,
                        1.0/2,
                        1.0/4 + 1.0/12
                       )), accuracy: 0.0001)

        XCTAssertEqual(b0.parentJoint!.stiffness, 1)
        XCTAssertEqual(b0.parentJoint!.damping, 1)

        XCTAssertEqual(b1.pivot, simd_float3(0,1,0))
        XCTAssertEqual(b1.centerOfMass, b1.pivot + b1.orientation.act(simd_float3(0,1/2,0)), accuracy: 0.0001)
        XCTAssertEqual(b1.mass, 1)
        XCTAssertEqual(b1.force, force)
        XCTAssertEqual(b1.torque, cross(forceAppliedPosition, force))
        XCTAssertEqual(float3x3(b1.orientation).transpose * b1.inertiaTensor * float3x3(b1.orientation),
                       float3x3(diagonal: simd_float3(
                        1.0/4 + 1.0/12,
                        1.0/2,
                        1.0/4 + 1.0/12
                       )), accuracy: 0.0001)

        XCTAssertEqual(b1.parentJoint!.stiffness, 1)
        XCTAssertEqual(b1.parentJoint!.damping, 1)
    }

    func testComposite() {
        simulator.updateCompositeBodies()

        XCTAssertEqual(b1.composite.mass, b1.mass)
        XCTAssertEqual(b0.composite.mass, b1.mass + b0.mass)

        XCTAssertEqual(b1.composite.force, b1.force)
        XCTAssertEqual(b0.composite.force, b1.force + b0.force)

        XCTAssertEqual(b1.composite.torque, b1.torque)
        XCTAssertEqual(b0.composite.torque, b1.torque + cross(b1.pivot - b0.pivot, force))

        XCTAssertEqual(b1.composite.centerOfMass, b1.centerOfMass)
        XCTAssertEqual(b0.composite.centerOfMass, (b1.centerOfMass + b0.centerOfMass) / 2)

        XCTAssertEqual(b1.composite.inertiaTensor, b1.inertiaTensor)
        var b0_inertiaTensor = b0.inertiaTensor - b0.mass * sqr((b0.centerOfMass - b0.composite.centerOfMass).skew)
        b0_inertiaTensor += b1.composite.inertiaTensor - b1.composite.mass * sqr((b1.composite.centerOfMass - b0.composite.centerOfMass).skew)
        XCTAssertEqual(b0.composite.inertiaTensor, b0_inertiaTensor, accuracy: 0.0001)
    }

    func testUpdateJoints() {
        simulator.updateCompositeBodies()
        simulator.updateJoints(at: delta)

        do {
            let joint = b1.parentJoint!
            let momentOfInertia: Float = momentOfInertiaOfRod
            let compositeInertiaRelativeToJoint = momentOfInertia +
                b1.mass * sqr(distance(b1.centerOfMass, b1.pivot))
            let θ = evaluateDifferential(a: compositeInertiaRelativeToJoint, b: joint.damping * joint.stiffness, c: joint.stiffness, g: b1.torque.z, y_0: 0, y_ddt_0: 0, at: Float(delta))

            XCTAssertEqual(
                float3x3(
                    simd_float3(0,0,θ[0]),
                    simd_float3(0,0,θ[1]),
                    simd_float3(0,0,θ[2])
                ),
                joint.θ, accuracy: 0.0001)
        }

        do {
            let joint = b0.parentJoint!
            var centerOfMass: simd_float3 = (b0.mass * b0.centerOfMass + b1.mass * b1.centerOfMass)
            centerOfMass /= (b0.mass + b1.mass)
            var momentOfInertia: Float = 0
            momentOfInertia += momentOfInertiaOfRod + b1.mass * distance_squared(b1.centerOfMass, centerOfMass)
            momentOfInertia += momentOfInertiaOfRod + b0.mass * distance_squared(b0.centerOfMass, centerOfMass)
            let compositeInertiaRelativeToJoint = momentOfInertia +
                (b0.mass + b1.mass) * sqr(distance(centerOfMass, joint.position))
            let torque = cross(b1.centerOfMass - b0.pivot, force)

            let θ = evaluateDifferential(a: compositeInertiaRelativeToJoint, b: joint.damping * joint.stiffness, c: joint.stiffness, g: torque.z, y_0: 0, y_ddt_0: 0, at: Float(delta))

            XCTAssertEqual(
                float3x3(
                    simd_float3(0,0,θ[0]),
                    simd_float3(0,0,θ[1]),
                    simd_float3(0,0,θ[2])
                ),
                joint.θ, accuracy: 0.0001)
        }
    }

    func testUpdateRigidBodies() {
        simulator.update(at: delta)

        do {
            let joint = b0.parentJoint!
            var centerOfMass: simd_float3 = (b0.mass * b0.centerOfMass + b1.mass * b1.centerOfMass)
            centerOfMass /= (b0.mass + b1.mass)
            var momentOfInertia: Float = 0
            momentOfInertia += momentOfInertiaOfRod + b1.mass * distance_squared(b1.centerOfMass, centerOfMass)
            momentOfInertia += momentOfInertiaOfRod + b0.mass * distance_squared(b0.centerOfMass, centerOfMass)
            let compositeInertiaRelativeToJoint = momentOfInertia +
                (b0.mass + b1.mass) * sqr(distance(centerOfMass, joint.position))
            let torque = cross(b1.centerOfMass - b0.pivot, force)
            let θ = evaluateDifferential(a: compositeInertiaRelativeToJoint, b: joint.damping * joint.stiffness, c: joint.stiffness, g: torque.z, y_0: 0, y_ddt_0: 0, at: Float(delta))

            let orientation = simd_quatf(angle: θ[0], axis: .z)
            XCTAssertEqual(
                b0.pivot + orientation.act(simd_float3(0, 0.5, 0)),
                b0.centerOfMass, accuracy: 0.0001)
            XCTAssertEqual(
                orientation,
                b0.orientation, accuracy: 0.0001)
        }

        do {
            let joint = b1.parentJoint!
            let momentOfInertia: Float = momentOfInertiaOfRod
            let compositeInertiaRelativeToJoint = momentOfInertia +
                b1.mass * sqr(distance(b1.centerOfMass, b1.pivot))
            let θ = evaluateDifferential(a: compositeInertiaRelativeToJoint, b: joint.damping * joint.stiffness, c: joint.stiffness, g: b1.torque.z, y_0: 0, y_ddt_0: 0, at: Float(delta))

            let orientation = simd_quatf(angle: θ[0], axis: .z)
            XCTAssertEqual(
                b1.pivot + (joint.orientation * orientation).normalized.act(simd_float3(0, 0.5, 0)),
                b1.centerOfMass, accuracy: 0.0001)
            XCTAssertEqual(
                (joint.orientation * orientation).normalized,
                b1.orientation, accuracy: 0.0001)
        }
    }

}
