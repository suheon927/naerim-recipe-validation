import Foundation
import RecipeValidation
import XCTest

final class RecipeValidationTests: XCTestCase {
    func testDurationOverflowReturnsNilInsteadOfTrapping() {
        let draft = RecipeDraft(steps: [pour(100, seconds: .max), wait(1)])
        XCTAssertNil(draft.totalSeconds)
    }

    func testNegativeDurationIsNotAValidTotal() {
        XCTAssertNil(RecipeDraft(steps: [pour(100, seconds: -1)]).totalSeconds)
    }

    func testEmptyIncompleteAndValidDurationsRemainDistinct() {
        XCTAssertEqual(RecipeDraft().totalSeconds, 0)
        XCTAssertEqual(RecipeDraft(steps: [pour(100), wait(30)]).totalSeconds, 30)
        XCTAssertEqual(RecipeDraft(steps: [pour(100, seconds: 60), wait(30)]).totalSeconds, 90)
    }

    func testInvalidQuantitiesAreRejectedWithoutIntegerConversionTraps() {
        for value in [Double(Int.max) / 10, Double.greatestFiniteMagnitude,
                      Double.infinity, -Double.infinity, Double.nan, -1, 0.01] {
            XCTAssertNil(RecipeDraft.waterTenths(value), "Unexpectedly accepted \(value)")
        }
    }

    func testNormalFloatingPointNoiseDoesNotRejectTenths() {
        XCTAssertEqual(RecipeDraft.waterTenths(0.1 + 0.2), 3)
        XCTAssertEqual(RecipeDraft.waterTenths(123.4), 1234)
        XCTAssertEqual(RecipeDraft.waterTenths(0), 0)
    }

    func testScalingPreservesSourceAndAllMetadataIncludingNonPourSteps() throws {
        let source = RecipeDraft(name: "Example recipe", summary: "Keep this draft", steps: [
            pour(40),
            RecipeStep(kind: .action, durationSeconds: 0, waterGrams: 0, instruction: "Close valve"),
            pour(110, seconds: 45), wait(10), pour(150, seconds: 30)
        ])
        let original = source
        let adjusted = try source.adjustingWater(to: 250)
        XCTAssertEqual(adjusted.steps.map(\.waterGrams), [33.3, 0, 91.7, 0, 125])
        var expected = source
        expected.steps[0].waterGrams = 33.3
        expected.steps[2].waterGrams = 91.7
        expected.steps[4].waterGrams = 125
        XCTAssertEqual(adjusted, expected)
        XCTAssertEqual(source, original)
        XCTAssertNil(adjusted.dose, "Editing water must not invent a dose")
        XCTAssertEqual(adjusted.steps[0].durationSeconds, 0)
    }

    func testLastPourReceivesTheRoundingResidual() throws {
        let source = RecipeDraft(steps: [pour(1), pour(1), pour(1)])
        let adjusted = try source.adjustingWater(to: 1)
        XCTAssertEqual(adjusted.steps.map(\.waterGrams), [0.3, 0.3, 0.4])
        XCTAssertEqual(try totalTenths(adjusted), 10)
    }

    func testOnePourTakesTheWholeTargetWithoutChangingDoseOrTiming() throws {
        let source = RecipeDraft(dose: 18, steps: [pour(250, seconds: 90)])
        let adjusted = try source.adjustingWater(to: 123.4)
        XCTAssertEqual(adjusted.steps[0].waterGrams, 123.4)
        XCTAssertEqual(adjusted.dose, 18)
        XCTAssertEqual(adjusted.totalSeconds, 90)
    }

    func testTooSmallTargetCannotEraseAPourOrModifyTheSource() {
        let source = RecipeDraft(steps: [pour(100), pour(100)])
        let original = source
        XCTAssertThrowsError(try source.adjustingWater(to: 0.1)) {
            XCTAssertEqual($0 as? RecipeDraft.WaterAdjustmentError, .targetTooSmall)
        }
        XCTAssertEqual(source, original)
    }

    func testMinimumTargetCanKeepBothPoursPositive() throws {
        let adjusted = try RecipeDraft(steps: [pour(100), pour(100)]).adjustingWater(to: 0.2)
        XCTAssertEqual(adjusted.steps.map(\.waterGrams), [0.1, 0.1])
    }

    func testInvalidTargetsLeaveTheWholeDraftUnchanged() {
        let source = RecipeDraft(name: "Example", dose: 18, steps: [pour(100, seconds: 30)])
        let original = source
        for target in [0, -1, 0.01, Double(Int.max) / 10, .infinity, .nan] {
            XCTAssertThrowsError(try source.adjustingWater(to: target)) {
                XCTAssertEqual($0 as? RecipeDraft.WaterAdjustmentError, .invalidTarget)
            }
            XCTAssertEqual(source, original)
        }
    }

    func testMissingZeroNegativeAndNonfinitePoursAreRejected() {
        let invalidSteps: [[RecipeStep]] = [[], [wait(30)], [pour(0)], [pour(-1)],
                                           [pour(.infinity)], [pour(.nan)], [pour(0.01)]]
        for steps in invalidSteps {
            XCTAssertThrowsError(try RecipeDraft(steps: steps).adjustingWater(to: 300)) {
                XCTAssertEqual($0 as? RecipeDraft.WaterAdjustmentError, .invalidPours)
            }
        }
    }

    func testSourceSumOverflowIsRejectedBeforeScaling() {
        let source = RecipeDraft(steps: [pour(500_000_000_000_000_000),
                                         pour(500_000_000_000_000_000)])
        let original = source
        XCTAssertThrowsError(try source.adjustingWater(to: 300)) {
            XCTAssertEqual($0 as? RecipeDraft.WaterAdjustmentError, .invalidPours)
        }
        XCTAssertEqual(source, original)
    }

    func testScalingAcrossRepresentativeRatiosPreservesTargetAndPositivePours() throws {
        for first in 1...9 {
            for second in 1...9 {
                let source = RecipeDraft(steps: [pour(Double(first)), pour(Double(second)), pour(3)])
                for target in [10.0, 23.7, 100.0, 250.0] {
                    let adjusted = try source.adjustingWater(to: target)
                    XCTAssertEqual(try totalTenths(adjusted), RecipeDraft.waterTenths(target))
                    XCTAssertTrue(adjusted.steps.allSatisfy { $0.waterGrams > 0 })
                    XCTAssertEqual(adjusted.steps.map(\.id), source.steps.map(\.id))
                }
            }
        }
    }

    private func pour(_ grams: Double, seconds: Int = 0) -> RecipeStep {
        RecipeStep(kind: .pour, durationSeconds: seconds, waterGrams: grams, instruction: "Pour")
    }

    private func wait(_ seconds: Int) -> RecipeStep {
        RecipeStep(kind: .wait, durationSeconds: seconds, waterGrams: 0)
    }

    private func totalTenths(_ draft: RecipeDraft) throws -> Int {
        try draft.steps.filter { $0.kind == .pour }.reduce(0) { total, step in
            total + (try XCTUnwrap(RecipeDraft.waterTenths(step.waterGrams)))
        }
    }
}
