import Foundation

final class HistoryViewModel: ObservableObject {
    let daysToShow: Int = 7

    func recentTotals(from store: FoodLogStore) -> [(date: Date, totals: MacroTotals)] {
        store.groupedTotals(lastDays: daysToShow)
    }
}
