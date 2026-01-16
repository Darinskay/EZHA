import Foundation
import SwiftUI

final class FoodLogStore: ObservableObject {
    @Published private(set) var entries: [FoodEntry] = []

    func add(_ entry: FoodEntry) {
        entries.insert(entry, at: 0)
    }

    func totals(for date: Date) -> MacroTotals {
        let calendar = Calendar.current
        let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
        return MacroTotals(
            calories: dayEntries.reduce(0) { $0 + $1.calories },
            protein: dayEntries.reduce(0) { $0 + $1.protein },
            carbs: dayEntries.reduce(0) { $0 + $1.carbs },
            fat: dayEntries.reduce(0) { $0 + $1.fat }
        )
    }

    func groupedTotals(lastDays days: Int) -> [(date: Date, totals: MacroTotals)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, totals(for: day))
        }
    }
}
