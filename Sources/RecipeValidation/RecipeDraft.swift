import Foundation

// Adapted from Naerim by Suheon Yi. See README.md for source revision and scope.
public enum RecipeStepKind: String, Sendable {
    case pour, wait, action, drawdown
}

/// A deliberately small value model; metadata lets tests verify edit isolation.
public struct RecipeStep: Equatable, Sendable {
    public var id: UUID
    public var kind: RecipeStepKind
    public var durationSeconds: Int
    public var waterGrams: Double
    public var instruction: String

    public init(
        id: UUID = UUID(),
        kind: RecipeStepKind,
        durationSeconds: Int,
        waterGrams: Double,
        instruction: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.waterGrams = waterGrams
        self.instruction = instruction
    }

    /// Invalid or overflowing totals are unknown; they must not crash display.
    public static func totalDuration(in steps: [RecipeStep]) -> Int? {
        var total = 0
        for step in steps {
            guard step.durationSeconds >= 0 else { return nil }
            let addition = total.addingReportingOverflow(step.durationSeconds)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }
}

public struct RecipeDraft: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var dose: Double?
    public var steps: [RecipeStep]

    public init(
        id: UUID = UUID(),
        name: String = "",
        summary: String = "",
        dose: Double? = nil,
        steps: [RecipeStep] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.dose = dose
        self.steps = steps
    }

    public var totalSeconds: Int? { RecipeStep.totalDuration(in: steps) }

    public enum WaterAdjustmentError: Error, Equatable, Sendable {
        case invalidTarget
        case invalidPours
        case targetTooSmall
    }

    /// Returns a replacement draft. An incomplete dose or duration is allowed.
    /// Only pour quantities change; the caller decides whether to adopt the result.
    public func adjustingWater(to target: Double) throws -> RecipeDraft {
        guard let targetTenths = Self.waterTenths(target), targetTenths > 0 else {
            throw WaterAdjustmentError.invalidTarget
        }
        let pourIndices = steps.indices.filter { steps[$0].kind == .pour }
        let source = pourIndices.compactMap { Self.waterTenths(steps[$0].waterGrams) }
        guard !pourIndices.isEmpty, source.count == pourIndices.count,
              source.allSatisfy({ $0 > 0 }) else {
            throw WaterAdjustmentError.invalidPours
        }

        var sourceTotal = 0
        for amount in source {
            let addition = sourceTotal.addingReportingOverflow(amount)
            guard !addition.overflow else { throw WaterAdjustmentError.invalidPours }
            sourceTotal = addition.partialValue
        }

        var remaining = targetTenths
        var adjusted: [Int] = []
        for amount in source.dropLast() {
            guard let scaled = Self.roundedWaterTenths(
                Decimal(amount) * Decimal(targetTenths) / Decimal(sourceTotal)
            ), scaled > 0, scaled < remaining else {
                throw WaterAdjustmentError.targetTooSmall
            }
            adjusted.append(scaled)
            remaining -= scaled
        }
        adjusted.append(remaining)

        var result = self
        for (index, amount) in zip(pourIndices, adjusted) {
            let water = Double(amount) / 10
            // Large Double values cannot represent every tenth. Do not silently
            // accept a value that would change the validated integer quantity.
            guard Self.waterTenths(water) == amount else {
                throw WaterAdjustmentError.invalidTarget
            }
            result.steps[index].waterGrams = water
        }
        return result
    }

    /// Convert nonnegative grams at 0.1 g precision to an exactly representable Int.
    /// Zero is valid here; adjustment separately requires positive pour quantities.
    public static func waterTenths(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0 else { return nil }
        let scaled = value * 10
        let rounded = scaled.rounded()
        guard abs(scaled - rounded) <= 0.000_000_001 else { return nil }
        // Double(Int.max) rounds beyond the Int range on 64-bit platforms.
        return Int(exactly: rounded)
    }

    private static func roundedWaterTenths(_ value: Decimal) -> Int? {
        guard !value.isNaN else { return nil }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        guard rounded >= 0, rounded <= Decimal(Int.max) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
