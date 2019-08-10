#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t

#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, BufferIndex)
{
    BufferIndexRigidBodies = 0,
    BufferIndexCompositeBodies  = 1,
    BufferIndexGridOrigin = 2,
    BufferIndexJoints = 3,
    BufferIndexTime = 4,
    BufferIndexRanges = 5,
    
    BufferIndexDebugRigidBody = 10,
    BufferIndexDebugCompositeBody = 11,
    BufferIndexDebugJoint = 13,
    BufferIndexDebugFloat = 14,
    BufferIndexDebugFloat3 = 15,
    BufferIndexDebugFloat3x3 = 16,
};

typedef NS_ENUM(NSInteger, ThreadGroupIndex)
{
    ThreadGroupIndexRigidBodies = 0,
    ThreadGroupIndexCompositeBodies  = 1,
};

typedef NS_ENUM(NSInteger, FunctionConstantIndex)
{
    FunctionConstantIndexRangeCount = 0,
};

typedef struct {
    vector_float3 position;
    float mass;
    matrix_float3x3 inertiaTensor;
    vector_float3 force;
    vector_float3 torque;
    vector_float3 centerOfMass;
} CompositeBodyStruct;

typedef struct {
    // const:
    int parentId;
    int childIds[5];
    ushort childCount;
    int climberIds[10];
    ushort climberCount;
    float mass;
    float length;
    float radius;
    matrix_float3x3 localRotation;
    
    vector_float3 position;
    matrix_float3x3 rotation;
    matrix_float3x3 inertiaTensor;
    vector_float3 centerOfMass;
    
    vector_float3 force;
    vector_float3 torque;
} RigidBodyStruct;

typedef struct {
    matrix_float3x3 θ;
    float k;
} JointStruct;

#endif /* ShaderTypes_h */
