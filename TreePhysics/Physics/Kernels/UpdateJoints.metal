#include <metal_stdlib>
#import "ShaderTypes.h"
#import "Math.metal"
#import "Diagonalize.metal"

using namespace metal;

struct UpdateJointsIn {
    device packed_float3 *theta;
    device float *stiffness;
    device float *damping;
    device packed_float3 *torque;
    device InertiaTensor *inertiaTensor;
};

inline float3x3
update(
       const uint id,
       const UpdateJointsIn in,
       const float time)
{
    float3x3 inertiaTensor_jointSpace = float3x3_from_inertiaTensor(in.inertiaTensor[id]);
    float3 torque_jointSpace = (float3)in.torque[id];

    // Solve: Iθ'' + (αI + βK)θ' + Kθ = τ; where I = inertia tensor, τ = torque,
    // K is a spring stiffness matrix, θ = euler angles of the joint,
    // θ' = angular velocities (i.e., first derivative), etc.

    // 1. First we need to diagonalize I and K (so we can solve the diff equations) --
    // i.e., produce the generalized eigendecomposition of I and K

    // 1.a. the cholesky decomposition of I
    float3x3 L = cholesky(inertiaTensor_jointSpace);
    float3x3 L_inverse = inverse_lowerTriangular(L);
    float3x3 L_transpose_inverse = transpose(L_inverse);

    // 1.b. the generalized eigenvalue problem A * X = X * Λ
    // where A = L^(−1) * K * L^(−T); note: A is (approximately) symmetric
    float3x3 A = L_inverse * (float3x3(in.stiffness[id])) * L_transpose_inverse;

    quatf q = diagonalize(A);
    float3x3 Eigenvectors = float3x3_from_quat(q);
    // Eigenvalues are the diagonal entries of transpose(Eigenvectors) * A * Eigenvectors:
    A = A * Eigenvectors;
    float3 Λ = float3(dot(Eigenvectors[0], A[0]),
                      dot(Eigenvectors[1], A[1]),
                      dot(Eigenvectors[2], A[2]));

    // 2. Now we can restate the differential equation in terms of other (diagonal)
    // values: Θ'' + βΛΘ' + ΛΘ = U^T τ, where Θ = U^(-1) θ

    float3x3 U = L_transpose_inverse * Eigenvectors;
    float3x3 U_inverse = inverse(U);

    float3 torque_diagonal = transpose(U) * torque_jointSpace;
    float3 angle = (float3)in.theta[id*3+0];
    float3 θ_diagonal_0 = U_inverse * angle;
    float3 angularVelocity = (float3)in.theta[id*3+1];
    float3 θ_ddt_diagonal_0 = U_inverse * angularVelocity;
    float damping = in.damping[id];

    // 2.a. thanks to diagonalization, we now have three independent 2nd-order
    // differential equations, θ'' + bθ' + kθ = f

    float3 solution_i = evaluateDifferential(1.0, damping * Λ.x, Λ.x, torque_diagonal.x, θ_diagonal_0.x, θ_ddt_diagonal_0.x, time);
    float3 solution_ii = evaluateDifferential(1.0, damping * Λ.y, Λ.y, torque_diagonal.y, θ_diagonal_0.y, θ_ddt_diagonal_0.y, time);
    float3 solution_iii = evaluateDifferential(1.0, damping * Λ.z, Λ.z, torque_diagonal.z, θ_diagonal_0.z, θ_ddt_diagonal_0.z, time);

    float3x3 θ_diagonal = transpose(float3x3(solution_i, solution_ii, solution_iii));

    return U * θ_diagonal;
}

kernel void
updateJoints(
             device packed_float3 *joint_theta,
             device float *joint_stiffness,
             device float *joint_damping,

             device packed_float3 *joint_torque,
             device InertiaTensor *joint_inertiaTensor,

             constant float & time,
             uint gid [[ thread_position_in_grid ]])
{
    UpdateJointsIn in = {
        .theta = joint_theta,
        .stiffness = joint_stiffness,
        .damping = joint_damping,
        .torque = joint_torque,
        .inertiaTensor = joint_inertiaTensor,
    };
    const float3x3 theta = gid == 0 ? float3x3(0) : update(gid, in, time);
    joint_theta[gid*3+0] = (packed_float3)theta[0];
    joint_theta[gid*3+1] = (packed_float3)theta[1];
    joint_theta[gid*3+2] = (packed_float3)theta[2];
}
