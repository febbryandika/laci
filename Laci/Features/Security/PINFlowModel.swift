import Foundation
import Observation

enum PINFlow: Hashable {
    case unlock
    case setup
    case change
    case reset
}

/// One PIN flow, one six-digit entry per step. Entry submits itself at the sixth digit, because a
/// number pad has no Return key.
@MainActor
@Observable
final class PINFlowModel {
    enum Step: Hashable {
        case current
        case new
        case confirm
    }

    enum Notice: Hashable {
        case wrongPIN
        case mismatch
        case storeFailed
    }

    let flow: PINFlow
    private(set) var step: Step
    private(set) var digits = ""
    private(set) var notice: Notice?
    private let lock: AppLock
    private var currentPIN = ""
    private var newPIN = ""

    init(flow: PINFlow, lock: AppLock) {
        self.flow = flow
        self.lock = lock
        step = flow == .setup ? .new : .current
    }

    /// Takes whatever the field holds and returns true when the flow has finished. Synchronous on
    /// purpose: the gate must learn it in the same update in which the lock's status changes, or
    /// it would swap the finished setup flow for an unlock flow first.
    @discardableResult
    func enter(_ text: String) -> Bool {
        digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(PINRecord.length))
        guard digits.count == PINRecord.length else { return false }
        let entered = digits
        digits = ""
        return submit(entered)
    }

    private func submit(_ entered: String) -> Bool {
        notice = nil
        switch step {
        case .current: return submitCurrent(entered)
        case .new:
            newPIN = entered
            step = .confirm
            return false
        case .confirm: return submitConfirmation(entered)
        }
    }

    private func submitCurrent(_ entered: String) -> Bool {
        guard lock.verify(entered) else {
            notice = .wrongPIN
            return false
        }
        switch flow {
        case .unlock:
            return true
        case .reset:
            return perform { try lock.reset(currentPIN: entered) }
        case .change, .setup:
            currentPIN = entered
            step = .new
            return false
        }
    }

    private func submitConfirmation(_ entered: String) -> Bool {
        guard entered == newPIN else {
            newPIN = ""
            step = .new
            notice = .mismatch
            return false
        }
        return flow == .change
            ? perform { try lock.change(currentPIN: currentPIN, to: entered) }
            : perform { try lock.setInitialPIN(entered) }
    }

    private func perform(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            currentPIN = ""
            newPIN = ""
            return true
        } catch {
            notice = .storeFailed
            return false
        }
    }
}
