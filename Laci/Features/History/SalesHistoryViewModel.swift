import Foundation
import LaciCore
import Observation

/// The history list: newest first, paged by sale number, or one sale when the query is a number.
@MainActor
@Observable
final class SalesHistoryViewModel {
    private(set) var sales: [Sale] = []
    var query = ""
    private(set) var loadFailed = false
    private(set) var isExhausted = false

    private let repository: any SaleRepository
    private let pageSize: Int

    init(dependencies: Dependencies, pageSize: Int = 50) {
        repository = dependencies.sales
        self.pageSize = pageSize
    }

    /// Sale numbers are what the cashier reads off a receipt, so a numeric query is an exact match.
    private var searchedNumber: Int? {
        Int(query.trimmingCharacters(in: .whitespaces))
    }

    func reload() {
        do {
            if let number = searchedNumber {
                sales = try repository.sale(number: number).map { [$0] } ?? []
                isExhausted = true
            } else {
                sales = try repository.recent(before: nil, limit: pageSize)
                isExhausted = sales.count < pageSize
            }
            loadFailed = false
        } catch {
            sales = []
            isExhausted = true
            loadFailed = true
        }
    }

    func loadMore() {
        guard !isExhausted, searchedNumber == nil, let last = sales.last else { return }
        do {
            let page = try repository.recent(before: last.number, limit: pageSize)
            sales.append(contentsOf: page)
            isExhausted = page.count < pageSize
        } catch {
            loadFailed = true
        }
    }
}
