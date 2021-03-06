import Foundation
import XCTest
@testable import TreePhysics
import SceneKit

class SkinnerTests: XCTestCase {
    func testFoo() {
        let pen = CylinderPen<UInt16>(radialSegmentCount: 5)
        let configuration = InterpreterConfig(angle: .pi / 4, stepSize: 1)
        let interpreter = Interpreter(configuration: configuration, pen: pen)
        interpreter.interpret("""
F[-F]
""")

        let bone1 = SCNNode()
        bone1.simdPosition = simd_float3(0,1,0)
        let bone2 = SCNNode()
        bone2.simdPosition = simd_float3(0,1,0) + normalize(simd_float3(-1,1,0))
        let bones = [bone1, bone2]

        let boneInverseBindTransforms: [NSValue]? = bones.map { NSValue(scnMatrix4: SCNMatrix4Invert($0.transform)) }
        var boneWeights: [Float] = [1.0, 1.0]
        var boneIndices: [UInt16] = [0, 1]

        let boneWeightsData = Data(bytesNoCopy: &boneWeights, count: boneWeights.count, deallocator: .none)
        let boneIndicesData = Data(bytesNoCopy: &boneIndices, count: boneWeights.count, deallocator: .none)

        let boneWeightsGeometrySource = SCNGeometrySource(data: boneWeightsData, semantic: .boneWeights, vectorCount: boneWeights.count, usesFloatComponents: true, componentsPerVector: 1, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size)
        let boneIndicesGeometrySource = SCNGeometrySource(data: boneIndicesData, semantic: .boneIndices, vectorCount: boneIndices.count, usesFloatComponents: false, componentsPerVector: 1, bytesPerComponent: MemoryLayout<UInt16>.size, dataOffset: 0, dataStride: MemoryLayout<UInt16>.size)

        let skinner = SCNSkinner(baseGeometry: pen.branchGeometry.geometry, bones: bones, boneInverseBindTransforms: boneInverseBindTransforms, boneWeights: boneWeightsGeometrySource, boneIndices: boneIndicesGeometrySource)

        let node = SCNNode(geometry: pen.branchGeometry.geometry)
        node.skinner = skinner
    }
}
