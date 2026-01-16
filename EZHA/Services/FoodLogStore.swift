import Foundation
import SwiftUI

final class FoodLogStore: ObservableObject {
    @Published private(set) var entries: [FoodEntry] = []

    func add(_ entry: FoodEntry) {
        entries.insert(entry, at: 0)
    }

    func totals(for date: Date) -> MacroTotals {
        let calendar = Calendar.current
        let dayEntries = entries.filter { entry in
            guard let entryDate = Self.dateFormatter.date(from: entry.date) else { return false }
            return calendar.isDate(entryDate, inSameDayAs: date)
        }
        var calories = 0
        var protein = 0
        var carbs = 0
        var fat = 0
        for entry in dayEntries {
            calories += Int(entry.calories)
            protein += Int(entry.protein)
            carbs += Int(entry.carbs)
            fat += Int(entry.fat)
        }
        return MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    func groupedTotals(lastDays days: Int) -> [(date: Date, totals: MacroTotals)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, totals(for: day))
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
