import XCTest
@testable import codepet

final class StarfieldParallaxTests: XCTestCase {
    func testClampNormMapsRangeToMinusOneToOne() {
        XCTAssertEqual(clampNorm(0, 0, 100), -1, accuracy: 0.001)   // min → -1
        XCTAssertEqual(clampNorm(100, 0, 100), 1, accuracy: 0.001)  // max → +1
        XCTAssertEqual(clampNorm(50, 0, 100), 0, accuracy: 0.001)   // mid → 0
    }
    func testClampNormClampsOutOfRangeAndDegenerate() {
        XCTAssertEqual(clampNorm(-50, 0, 100), -1, accuracy: 0.001) // below → -1
        XCTAssertEqual(clampNorm(200, 0, 100), 1, accuracy: 0.001)  // above → +1
        XCTAssertEqual(clampNorm(5, 10, 10), 0, accuracy: 0.001)    // max<=min → 0
    }
}
