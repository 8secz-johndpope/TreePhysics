import Foundation
import XCTest
@testable import TreePhysics
import simd

class LocalitySensitiveHashTests: XCTestCase {
    var h: LocalitySensitiveHash<simd_float3>!

    override func setUp() {
        super.setUp()
        self.h = LocalitySensitiveHash<simd_float3>(cellSize: 1)
        for i in 0...10 {
            for j in 0...10 {
                for k in 0...10 {
                    let cell = simd_float3(Float(i),Float(j),Float(k))
                    h.add(cell + simd_float3(0.1,0.1,0.1))
                    h.add(cell + simd_float3(0.9,0.9,0.9))
                }
            }
        }
    }

    func testElementsNear() {
        let position = simd_float3(5,5,5)
        let nearby = h.elements(near: position)
        XCTAssertEqual(3 * 3 * 3 * 2, nearby.count) // all adjacent cells have 2 items
        let maxDistance = distance(.zero, simd_float3(3,3,3))
        for o in nearby {
            XCTAssertLessThanOrEqual(distance(o.position, position), maxDistance)
        }
    }

    func testElementsNearWithSomeEmptyCells() {
        let position = simd_float3(0,0,0)
        let nearby = h.elements(near: position)
        XCTAssertEqual(2 * 2 * 2 * 2, nearby.count) // there are only elements in non-negative cells
        let maxDistance = distance(.zero, simd_float3(3,3,3))
        for o in nearby {
            XCTAssertLessThanOrEqual(distance(o.position, position), maxDistance)
        }
    }

    func testElementsNearWithAllEmptyCells() {
        let position = simd_float3(100,100,100)
        let nearby = h.elements(near: position)
        XCTAssertEqual(0, nearby.count)
    }
}

extension float3: HasPosition {
    public var position: simd_float3 { return self }
}
