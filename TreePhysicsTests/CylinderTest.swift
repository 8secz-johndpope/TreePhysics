import Foundation
import XCTest
@testable import TreePhysics
import simd

class CylinderPenTests: XCTestCase {
    var pen: CylinderPen<UInt16>!
    var arcLength: Float!

    override func setUp() {
        super.setUp()
        self.pen = CylinderPen<UInt16>(radialSegmentCount: 3)
        self.arcLength = 2.0 * .pi / 3

        pen.start(at: .zero, orientation: .identity, thickness: .pi)
        _ = pen.cont(distance: 1, orientation: .identity, thickness: .pi)
    }

    func testVertices() {
        XCTAssertEqual([
            simd_float3(cos(0), 0, sin(0)),
            simd_float3(cos(arcLength), 0, sin(arcLength)),
            simd_float3(cos(2*arcLength), 0, sin(2*arcLength)),

            simd_float3(cos(0), 1, sin(0)),
            simd_float3(cos(arcLength), 1, sin(arcLength)),
            simd_float3(cos(2*arcLength), 1, sin(2*arcLength)),

            ], pen.branchGeometry.vertices)
    }

    func testIndices() {
        XCTAssertEqual([
            0,4,1,
            5,
            2,
            6,
            3,
            7,
            ], pen.branchGeometry.indices)
    }
}
