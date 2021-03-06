import Foundation
import TreePhysics
import simd
import SceneKit

public class Plot<I> where I: FixedWidthInteger {
    private var builders: [GeometryBuilder<I>] = []

    public init() {}

    public func scatter(points: [simd_float3], scale: Float = 1.0) {
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(red: 1, green: 0.718, blue: 0.773, alpha: 0.9)
        let builder = GeometryBuilder<I>(primitiveType: .triangles, material: material)

        let vertices = [simd_float3(-0.5, 0, 0), simd_float3(0, 1, 0),
                        simd_float3(0, 1, 0), simd_float3(0.5, 0, 0)]
        let indices: [I] = [0,1,2, 0,2,3,
                            2,1,0, 3,2,0]

        for point in points {
            let verticesForPoint = vertices.map { point + scale * $0 }
            _ = builder.addSegment(verticesForPoint, indices)
        }

        builders.append(builder)
    }

    let vertices = [simd_float3(0, 0, 0), simd_float3(0, 1, 0),
                    simd_float3(1, 0, 0), simd_float3(1, 1, 0),
                    simd_float3(0, 0, 1), simd_float3(0, 1, 1),
                    simd_float3(1, 0, 1), simd_float3(1, 1, 1)]
    let indices: [I] = [0,1,2,
                        3,2,1,
                        2,3,6,
                        7,6,3,
                        6,7,4,
                        5,4,7,
                        4,5,0,
                        1,0,5,
                        1,5,3,
                        3,5,7,
                        2,4,0,
                        6,4,2,
                        ]

    public func voxels(data: [Float], size: Int, scale: Float = 1.0) {
        var builders: [Float:GeometryBuilder<I>] = [:]

        for i in 0..<size {
            for j in 0..<size {
                for k in 0..<size {
                    let ijk = simd_float3(Float(i),Float(j),Float(k)) - Float(size/2)
                    let datum = data[i*size*size + j*size + k]
                    if datum != 0 {
                        let verticesForPoint = vertices.map { ijk * scale + 0.9 * scale * $0 }
                        if builders[datum] == nil {
                            let material = SCNMaterial()
                            material.diffuse.contents = NSColor(red: 0, green: 0, blue: 0, alpha: CGFloat(datum))
                            let builder = GeometryBuilder<I>(primitiveType: .triangles, material: material)
                            builders[datum] = builder
                        }
                        let builder = builders[datum]!
                        _ = builder.addSegment(verticesForPoint, indices)
                    }
                }
            }
        }
        self.builders.append(contentsOf: builders.values)
    }

    public func node() -> SCNNode {
        let node = SCNNode()
        for builder in builders {
            let plot = SCNNode(geometry: builder.geometry)
            node.addChildNode(plot)
        }

        return node
    }

}
