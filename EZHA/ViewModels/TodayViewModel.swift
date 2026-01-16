import Foundation
import SwiftUI

final class TodayViewModel: ObservableObject {
    @Published private(set) var targets: MacroTargets = .example

    func eatenTotals(from store: FoodLogStore) -> MacroTotals {
        store.totals(for: Date())
    }
}
