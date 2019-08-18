import Foundation
import MetalKit
import Metal

final class UpdateCompositeBodiesKernel: MetalKernel {
    let rigidBodiesBuffer: MTLBuffer
    let compositeBodiesBuffer: MTLBuffer
    let ranges: [Range<Int>]

    init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, rigidBodiesBuffer: MTLBuffer, ranges: [Range<Int>], compositeBodiesBuffer: MTLBuffer) {
        precondition(ranges.count > 0)

        self.ranges = ranges
        self.rigidBodiesBuffer = rigidBodiesBuffer
        self.compositeBodiesBuffer = compositeBodiesBuffer

        let library = device.makeDefaultLibrary()!
        let constantValues = MTLFunctionConstantValues()
        var rangeCount = ranges.count
        constantValues.setConstantValue(&rangeCount, type: .int, index: FunctionConstantIndex.rangeCount.rawValue)
        let function = try! library.makeFunction(name: "updateCompositeBodies", constantValues: constantValues)

        super.init(device: device, function: function)
    }

    func encode(commandBuffer: MTLCommandBuffer) {
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(computePipelineState)
        commandEncoder.label  = "Update Composite Bodies"
        commandEncoder.setBuffer(rigidBodiesBuffer, offset: 0, index: BufferIndex.rigidBodies.rawValue)
        commandEncoder.setBuffer(compositeBodiesBuffer, offset: 0, index: BufferIndex.compositeBodies.rawValue)
        var ranges = self.ranges.map { int2(Int32($0.lowerBound), Int32($0.upperBound)) }
        commandEncoder.setBytes(&ranges, length: MemoryLayout<int2>.stride * ranges.count, index: BufferIndex.ranges.rawValue)

        let maxWidth = self.ranges.first!.count

        let threadGroupWidth = computePipelineState.maxTotalThreadsPerThreadgroup
        let threadsPerThreadgroup = MTLSizeMake(threadGroupWidth, 1, 1)
        let threadsPerGrid = MTLSize(
            width: maxWidth,
            height: 1,
            depth: 1)

        commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
    }

    static func buffer(root: RigidBody, device: MTLDevice) -> (Int, MTLBuffer, [Range<Int>]) {
        var rangesOfWork: [Range<Int>] = []
        let levels = root.levels()
        var offset = 0
        var id = 0
        var index: [RigidBody:Int] = [:]
        var allClimbers: [RigidBody] = []

        // Step 1: Determine the buffer memory layout (i.e., the index and the ranges of work)
        for level in levels {
            for unitOfWork in level {
                allClimbers.append(contentsOf: unitOfWork.climbers)
                index[unitOfWork.rigidBody] = id
                id += 1
            }

            let range = offset..<(offset+level.count)
            rangesOfWork.append(range)
            offset += level.count
        }
        for rigidBody in allClimbers {
            index[rigidBody] = id
            id += 1
        }
        index[root] = id

        // Step 1: Allocate the buffer
        let count = offset + allClimbers.count + 1 // +1 for root
        let buffer = device.makeBuffer(length: count * MemoryLayout<RigidBodyStruct>.stride, options: [.storageModeShared])!

        // Step 3: Store data into the buffer
        let rigidBodyStructs = UnsafeMutableRawPointer(buffer.contents())!.bindMemory(to: RigidBodyStruct.self, capacity: count)
        for level in levels {
            for unitOfWork in level {
                let id = index[unitOfWork.rigidBody]!
                rigidBodyStructs[id] = `struct`(rigidBody: unitOfWork.rigidBody, climbers: unitOfWork.climbers, index: index)
            }
        }
        for rigidBody in allClimbers {
            let id = index[rigidBody]!
            rigidBodyStructs[id] = `struct`(rigidBody: rigidBody, index: index)
        }
        rigidBodyStructs[index[root]!] = `struct`(rigidBody: root, index: index)
        return (count, buffer, rangesOfWork)
    }

    typealias ChildIdsType = (Int32, Int32, Int32)

    private static func `struct`(rigidBody: RigidBody, climbers: [RigidBody] = [], index: [RigidBody:Int]) -> RigidBodyStruct {
        // Parent
        let parentId: Int32
        if let parentJoint = rigidBody.parentJoint {
            parentId = Int32(index[parentJoint.parentRigidBody]!)
        } else {
            parentId = -1
        }

        // Child
        let childRigidBodies = rigidBody.childJoints.map { $0.childRigidBody }
        assert(childRigidBodies.count <= 5)
        var childRigidBodyIndices: [Int32] = childRigidBodies.map { Int32(index[$0]!) }
        var childIds: ChildIdsType = (0,0,0)
        memcpy(&childIds, &childRigidBodyIndices, childRigidBodyIndices.count * MemoryLayout<Int32>.stride)

        // Climbers
        assert(climbers.count <= 10)
        let climberOffset = Int32(climbers.first.map { index[$0]! } ?? 0)

        let strct = RigidBodyStruct(
            parentId: parentId,
            childIds: childIds,
            climberOffset: climberOffset,
            childCount: ushort(childRigidBodies.count),
            climberCount: ushort(climbers.count),
            mass: half(rigidBody.mass),
            length: half(rigidBody.length),
            radius: half(rigidBody.radius),
            localRotation: half3x3(matrix3x3_rotation(rotation: rigidBody.rotation_local)),

            position: half3(rigidBody.position),
            rotation: half3x3(rigidBody.rotation),
            inertiaTensor: half3x3(rigidBody.inertiaTensor),
            centerOfMass: half3(rigidBody.centerOfMass),

            force: half3(rigidBody.force),
            torque: half3(rigidBody.torque))
        return strct
    }
}
