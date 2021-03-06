import Foundation
import simd

public struct SimulatorConfig {
    let torqueFictitiousMultiplier_i: Float
    let torqueFictitiousMultiplier_ii: Float
    let torqueFictitiousMultiplier_iii: Float

    public init(
        torqueFictitiousMultiplier_i: Float = 0.0,
        torqueFictitiousMultiplier_ii: Float = 0.0,
        torqueFictitiousMultiplier_iii: Float = 0.0) {
        self.torqueFictitiousMultiplier_i = torqueFictitiousMultiplier_i
        self.torqueFictitiousMultiplier_ii = torqueFictitiousMultiplier_ii
        self.torqueFictitiousMultiplier_iii = torqueFictitiousMultiplier_iii
    }
}

public final class CPUSimulator {
    let configuration: SimulatorConfig
    let world: PhysicsWorld

    public init(configuration: SimulatorConfig = SimulatorConfig(), world: PhysicsWorld) {
        self.configuration = configuration
        self.world = world
    }

    public func update(at time: TimeInterval) {
        updateFields(at: time)
        updateCompositeBodies()
        deArticulateBodies()
        updateJoints(at: time)
        updateArticulatedBodies()
        updateFreeBodies(at: time)
        resetForces()
    }

    let start = Date()

    func updateFields(at time: TimeInterval) {
        for rigidBody in world.rigidBodiesUnordered {
            for field in world.fields {
                if field.applies(to: rigidBody.centerOfMass) {
                    let time = Date().timeIntervalSince(start)
                    field.apply(rigidBody: rigidBody, time: time)
                }
            }
        }
    }

    func updateCompositeBodies() {
        for rigidBody in world.rigidBodiesLevelOrderReversed {
            let composite = rigidBody.composite

            composite.mass = rigidBody.mass
            composite.force = rigidBody.force
            composite.torque = rigidBody.torque
            composite.centerOfMass = rigidBody.centerOfMass
            composite.inertiaTensor = rigidBody.inertiaTensor

            for childJoint in rigidBody.childJoints {
                let childRigidBody = childJoint.childRigidBody
                let childComposite = childRigidBody.composite

                let prevMass = composite.mass
                composite.mass += childComposite.mass
                composite.force += childComposite.force

                composite.torque +=
                    cross(childJoint.position - rigidBody.pivot, childComposite.force) + childComposite.torque

                let prevCenterOfMass = composite.centerOfMass
                composite.centerOfMass = (prevMass * composite.centerOfMass + childComposite.mass * childComposite.centerOfMass) / composite.mass

                composite.inertiaTensor -= prevMass * sqr((prevCenterOfMass - composite.centerOfMass).skew)
                composite.inertiaTensor += childComposite.inertiaTensor - childComposite.mass * sqr((childComposite.centerOfMass - composite.centerOfMass).skew)
            }
        }
    }

    func deArticulateBodies() {
        for rigidBody in world.rigidBodiesUnordered {
            if let parentJoint = rigidBody.parentJoint {
                if length(rigidBody.torque) > parentJoint.torqueThreshold {
                    world.free(articulatedBody: rigidBody)
                }
            }
        }
    }

    func updateJoints(at time: TimeInterval) {
        let time = Float(time)
        for rigidBody in world.rigidBodiesUnordered {
            if let parentJoint = rigidBody.parentJoint {
                let pr = parentJoint.rotate(vector: rigidBody.composite.centerOfMass - rigidBody.pivot)

                let inertiaTensor_jointSpace = parentJoint.rotate(tensor: rigidBody.composite.inertiaTensor) -
                    rigidBody.composite.mass * sqr(pr.skew)

                let torque_jointSpace = parentJoint.rotate(vector: rigidBody.composite.torque)

                // Calculate any fictitious forces:
                let parentAngularAcceleration_jointSpace = parentJoint.rotate(vector: parentJoint.parentRigidBody.angularAcceleration)
                let parentAngularVelocity_jointSpace = parentJoint.rotate(vector: parentJoint.parentRigidBody.angularVelocity)
                let childAngularVelocity_jointSpace = parentJoint.rotate(vector: rigidBody.angularVelocity)

                let torqueFictitious_jointSpace_i: simd_float3 = configuration.torqueFictitiousMultiplier_i *
                    -rigidBody.composite.mass * pr.skew * parentJoint.rotate(vector: parentJoint.acceleration)
                let torqueFictitious_jointSpace_ii: simd_float3 = configuration.torqueFictitiousMultiplier_ii *
                    -inertiaTensor_jointSpace * (parentAngularAcceleration_jointSpace + parentAngularVelocity_jointSpace.skew * childAngularVelocity_jointSpace)
                let torqueFictitious_jointSpace_iii: simd_float3 = configuration.torqueFictitiousMultiplier_ii *
                    -childAngularVelocity_jointSpace.skew * inertiaTensor_jointSpace * childAngularVelocity_jointSpace

                let torqueFictitious_jointSpace = torqueFictitious_jointSpace_i + torqueFictitious_jointSpace_ii + torqueFictitious_jointSpace_iii

                let torqueTotal_jointSpace = torque_jointSpace + torqueFictitious_jointSpace

                // Solve: Iθ'' + (αI + βK)θ' + Kθ = τ; where I = inertia tensor, τ = torque,
                // K is a spring stiffness matrix, θ = euler angles of the joint,
                // θ' = angular velocities (i.e., first derivative), etc.

                // 1. First we need to diagonalize I and K (so we can solve the diff equations) --
                // i.e., produce the generalized eigendecomposition of I and K

                // 1.a. the cholesky decomposition of I
                let L = inertiaTensor_jointSpace.cholesky
                let L_inverse = L.inverse, L_transpose_inverse = L_inverse.transpose

                // 1.b. the generalized eigenvalue problem A * X = X * Λ
                // where A = L^(−1) * K * L^(−T); note: A is (approximately) symmetric
                let A = L_inverse * (parentJoint.stiffness * matrix_identity_float3x3) * L_transpose_inverse
                let (Λ, X) = A.eigen_ql!

                // 2. Now we can restate the differential equation in terms of other (diagonal)
                // values: Θ'' + βΛΘ' + ΛΘ = U^T τ, where Θ = U^(-1) θ
                let U = L_transpose_inverse * X
                let U_transpose = U.transpose, U_inverse = U.inverse

                let torque_diagonal = U_transpose * torqueTotal_jointSpace
                let θ_diagonal_0 = U_inverse * parentJoint.θ[0]
                let θ_ddt_diagonal_0 = U_inverse * parentJoint.θ[1]
                let βΛ = parentJoint.damping * Λ

                // 2.a. thanks to diagonalization, we now have three independent 2nd-order
                // differential equations, θ'' + bθ' + kθ = f
                let θ_diagonal = float3x3(rows: [
                    evaluateDifferential(a: 1, b: βΛ.x, c: Λ.x, g: torque_diagonal.x, y_0: θ_diagonal_0.x, y_ddt_0: θ_ddt_diagonal_0.x, at: time),
                    evaluateDifferential(a: 1, b: βΛ.y, c: Λ.y, g: torque_diagonal.y, y_0: θ_diagonal_0.y, y_ddt_0: θ_ddt_diagonal_0.y, at: time),
                    evaluateDifferential(a: 1, b: βΛ.z, c: Λ.z, g: torque_diagonal.z, y_0: θ_diagonal_0.z, y_ddt_0: θ_ddt_diagonal_0.z, at: time)])

                parentJoint.θ = U * θ_diagonal
            }
        }
    }

    func updateArticulatedBodies() {
        for rigidBody in world.rigidBodiesLevelOrder {
            updateArticulatedBody(rigidBody: rigidBody)
            for joint in rigidBody.childJoints {
                updateArticulatedBody(joint: joint, parentRigidBody: rigidBody)
            }
        }
    }

    func updateFreeBodies(at time: TimeInterval) {
        let time = Float(time)
        for rigidBody in world.rigidBodies {
            updateFreeBody(rigidBody: rigidBody, at: time)
        }
    }

    func resetForces() {
        for rigidBody in world.rigidBodiesLevelOrder {
            rigidBody.resetForces()
        }
    }

    private func updateArticulatedBody(rigidBody: ArticulatedRigidBody) {
        guard let parentJoint = rigidBody.parentJoint else { return }
        let parentRigidBody = parentJoint.parentRigidBody

        rigidBody.updateTransform()
        assert(rigidBody.isFinite)

        rigidBody.angularVelocity = parentRigidBody.angularVelocity + parentJoint.orientation.act(parentJoint.θ[1])
        rigidBody.angularAcceleration = parentRigidBody.angularAcceleration + parentJoint.orientation.act(parentJoint.θ[2]) + parentRigidBody.angularVelocity.skew * rigidBody.angularVelocity

        rigidBody.velocity = parentRigidBody.velocity
        rigidBody.velocity += parentRigidBody.angularVelocity.skew * parentRigidBody.orientation.act(parentJoint.localPosition)
        rigidBody.velocity -= rigidBody.angularVelocity.skew * rigidBody.orientation.act(rigidBody.localPivot)
        rigidBody.acceleration = parentJoint.acceleration - (rigidBody.angularAcceleration.skew + sqr(rigidBody.angularVelocity.skew)) * rigidBody.orientation.act(rigidBody.localPivot)
    }

    private func updateArticulatedBody(joint: Joint, parentRigidBody: RigidBody) {
        joint.updateTransform()

        assert(joint.isFinite, "\(joint)")
    }

    private func updateFreeBody(rigidBody: RigidBody, at time: Float) {
        guard rigidBody.kind != .static else { return }

        // FIXME untested
        let force, torque: simd_float3
        let mass: Float
        let inertiaTensor: float3x3
        switch rigidBody {
        case let rigidBody as ArticulatedRigidBody:
            force = rigidBody.composite.force
            torque = rigidBody.composite.torque
            mass = rigidBody.composite.mass
            inertiaTensor = rigidBody.composite.inertiaTensor
        default:
            force = rigidBody.force
            torque = rigidBody.torque
            mass = rigidBody.mass
            inertiaTensor = rigidBody.inertiaTensor
        }

        rigidBody.acceleration = force / mass

        rigidBody.angularMomentum = rigidBody.angularMomentum + time * torque

        rigidBody.velocity = rigidBody.velocity + time * rigidBody.acceleration
        rigidBody.angularVelocity = inertiaTensor.inverse * rigidBody.angularMomentum

        rigidBody.centerOfMass = rigidBody.centerOfMass + time * rigidBody.velocity
        let angularVelocityQuat = simd_quatf(real: 0, imag: rigidBody.angularVelocity)
        rigidBody.orientation = rigidBody.orientation + time/2 * angularVelocityQuat * rigidBody.orientation
        rigidBody.orientation = rigidBody.orientation.normalized

        rigidBody.inertiaTensor = float3x3(rigidBody.orientation) * rigidBody.localInertiaTensor * float3x3(rigidBody.orientation).transpose

        rigidBody.updateTransform()
        
        assert(rigidBody.isFinite)
    }
}
