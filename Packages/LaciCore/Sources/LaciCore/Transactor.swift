import Foundation
import SwiftData

/// One unit of work over the main context. Every repository write runs inside `perform`, so nested
/// calls (importer → create → adjust) save once at the outermost level and a throw anywhere rolls
/// back everything. Autosave is off: a forgotten rollback can never be persisted later by the run loop.
@MainActor
public final class Transactor {
    public let context: ModelContext
    private var depth = 0

    public init(container: ModelContainer) {
        context = container.mainContext
        context.autosaveEnabled = false
    }

    public func perform<T>(_ body: () throws -> T) throws -> T {
        depth += 1
        defer { depth -= 1 }
        do {
            let value = try body()
            if depth == 1 {
                try context.save()
            }
            return value
        } catch {
            if depth == 1 {
                context.rollback()
            }
            throw error
        }
    }
}
