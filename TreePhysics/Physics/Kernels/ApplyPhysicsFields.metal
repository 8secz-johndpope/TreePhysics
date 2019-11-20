#include <metal_stdlib>
#import "ShaderTypes.h"
#import "Math.metal"

using namespace metal;

constant int fieldCount [[ function_constant(FunctionConstantIndexPhysicsFieldCount) ]];

struct ApplyPhysicsFieldsIn {
    device half *mass;
    device packed_half3 *centerOfMass;
    device quath *orientation;
    device packed_half3 *velocity;
    device half *area;
};

bool appliesTo(const PhysicsField field, const half3 centerOfMass) {
    const half3 rel = metal::abs(field.position - centerOfMass);
    return rel.x <= field.halfExtent.x && rel.y <= field.halfExtent.y && rel.z <= field.halfExtent.z;
}

half2x3 apply(const GravityField gravity, const ApplyPhysicsFieldsIn in, uint id, float time) {
    half3 force = in.mass[id] * gravity.g;
    return half2x3(force, half3(0));
}

half2x3 apply(const WindField wind, const ApplyPhysicsFieldsIn in, uint id, float time) {
    half3 relativeVelocity = (abs(sin(time*10)))*wind.windVelocity - in.velocity[id];
    half3 normal = (half3)quat_heading((quatf)in.orientation[id]);
    half3 relativeVelocity_normal = relativeVelocity - dot(relativeVelocity, normal) * normal;
    half3 force = wind.branchScale * wind.airDensity * in.area[id] * length(relativeVelocity_normal) * relativeVelocity_normal;
    return half2x3(force, half3(0));
}

half2x3 apply(const PhysicsField field, const ApplyPhysicsFieldsIn in, uint id, float time) {
    half2x3 result;
    switch (field.type) {
        case PhysicsFieldTypeGravity:
            result = apply(field.gravity, in, id, time);
            break;
        case PhysicsFieldTypeWind:
            result = apply(field.wind, in, id, time);
            break;
    }
    return result;
}

kernel void
applyPhysicsFields(
                   constant PhysicsField *fields,

                   device half           *in_mass,
                   device packed_half3   *in_centerOfMass,
                   device quath          *in_orientation,
                   device packed_half3   *in_velocity,
                   device half           *in_area,

                   device packed_half3   *out_force,
                   device packed_half3   *out_torque,

                   constant float & time,
                   uint gid [[ thread_position_in_grid ]])
{
    ApplyPhysicsFieldsIn in = {
        .mass = in_mass,
        .centerOfMass = in_centerOfMass,
        .orientation = in_orientation,
        .velocity = in_velocity,
        .area = in_area,
    };
    half2x3 result = half2x3(0);
    for (int i = 0; i < fieldCount; i++) {
        PhysicsField field = fields[i];
        if (appliesTo(field, in_centerOfMass[gid])) {
            result += apply(field, in, gid, time);
        }
    }
    out_force[gid] = result[0];
    out_torque[gid] = result[1];
}
