import Foundation
import MetalKit
import Metal
import SceneKit
import ShaderTypes

public final class FreeBodies: MetalKernelEncoder {
    private let argumentEncoder: ArgumentEncoder

    init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, memoryLayoutManager: MemoryLayoutManager) {
        let library = device.makeDefaultLibrary()!
        let function = library.makeFunction(name: "encodeFreeBodies")!

        self.argumentEncoder = ArgumentEncoder(memoryLayoutManager: memoryLayoutManager, function: function)

        super.init(device: device, function: function)
    }

    func encode(commandBuffer: MTLCommandBuffer) {
        let encodeFreeBodiesCommandEncoder = commandBuffer.makeComputeCommandEncoder()!
        encodeFreeBodiesCommandEncoder.setComputePipelineState(computePipelineState)
        encodeFreeBodiesCommandEncoder.label  = "Encode Free Bodies"
        argumentEncoder.encode(commandEncoder: encodeFreeBodiesCommandEncoder)

        let threadGroupWidth = computePipelineState.maxTotalThreadsPerThreadgroup
        let threadsPerThreadgroup = MTLSizeMake(threadGroupWidth, 1, 1)
        let threadsPerGrid = MTLSize(
            width: 1,
            height: 1,
            depth: 1)

        encodeFreeBodiesCommandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encodeFreeBodiesCommandEncoder.endEncoding()

        let freeBodiesCommandEncoder = commandBuffer.makeComputeCommandEncoder()!
        freeBodiesCommandEncoder.label = "Free Bodies"
        freeBodiesCommandEncoder.executeCommands(in: argumentEncoder.icb, with: NSRange(location: 0, length: 1))
        freeBodiesCommandEncoder.endEncoding()
    }
}

extension FreeBodies {
    class ArgumentEncoder {
        let mem: MemoryLayoutManager
        let function: MTLFunction
        let computePipelineState: MTLComputePipelineState
        let icb: MTLIndirectCommandBuffer

        init(memoryLayoutManager: MemoryLayoutManager, function: MTLFunction) {
            self.mem = memoryLayoutManager
            self.function = function
            let library = function.device.makeDefaultLibrary()!
            let f = library.makeFunction(name: "freeBodies")!
            let descriptor = MTLComputePipelineDescriptor()
            descriptor.supportIndirectCommandBuffers = true
            descriptor.computeFunction = f
            self.computePipelineState = try! f.device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)

            let icbDescriptor = MTLIndirectCommandBufferDescriptor()
            icbDescriptor.commandTypes = .concurrentDispatchThreads
            icbDescriptor.inheritBuffers = true
            let icb = f.device.makeIndirectCommandBuffer(descriptor: icbDescriptor, maxCommandCount: 1, options: .storageModeShared)!
            let command = icb.indirectComputeCommand(at: 0)
            command.setComputePipelineState(computePipelineState)
            self.icb = icb
        }

        func encode(commandEncoder: MTLComputeCommandEncoder) {
            let argumentEncoder = function.makeArgumentEncoder(bufferIndex: 0)
            let buffer = commandEncoder.device.makeBuffer(length: argumentEncoder.encodedLength, options: .storageModeShared)!
            argumentEncoder.setArgumentBuffer(buffer, offset: 0)
            argumentEncoder.setIndirectCommandBuffer(icb, index: 0)

            let bufs = [
                mem.freeBodies.toBeFreedIndexBuffer,
                mem.freeBodies.indexBuffer,
                mem.freeBodies.countBuffer,
                mem.rigidBodies.firstChildIdBuffer,
                mem.rigidBodies.parentIdBuffer,
                mem.rigidBodies.childIndexBuffer,
                mem.rigidBodies.childCountBuffer,
            ]
            argumentEncoder.setBuffers(bufs, offsets: [Int](repeating: 0, count: bufs.count), range: 1..<bufs.count+1)
            commandEncoder.setBuffer(buffer, offset: 0, index: 0)
            commandEncoder.setBuffer(mem.freeBodies.toBeFreedCountBuffer, offset: 0, index: 1)
            commandEncoder.useResource(icb, usage: .read)
            commandEncoder.useResources(bufs, usage: .write)
        }
    }
}
