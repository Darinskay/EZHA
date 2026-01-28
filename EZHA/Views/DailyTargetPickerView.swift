import SwiftUI

struct DailyTargetPickerView: View {
    let targets: [DailyTarget]
    let onSelect: (DailyTarget) -> Void
    var preselectedTargetId: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTargetId: UUID?

    var body: some View {
        NavigationStack {
            List(targets) { target in
                Button {
                    selectedTargetId = target.id
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(target.name)
                                .font(.headline)
                            Text(targetSummary(target))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedTargetId == target.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .foregroundColor(.primary)
            }
            .navigationTitle("Choose Target")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use") {
                        guard let selected = selectedTarget else { return }
                        onSelect(selected)
                        dismiss()
                    }
                    .disabled(selectedTarget == nil)
                }
            }
        }
        .onAppear {
            if let preselectedTargetId,
               targets.contains(where: { $0.id == preselectedTargetId }) {
                selectedTargetId = preselectedTargetId
            } else {
                selectedTargetId = targets.first?.id
            }
        }
    }

    private var selectedTarget: DailyTarget? {
        guard let selectedTargetId else { return nil }
        return targets.first { $0.id == selectedTargetId }
    }

    private func targetSummary(_ target: DailyTarget) -> String {
        let calories = Int(round(target.caloriesTarget))
        let protein = Int(round(target.proteinTarget))
        let carbs = Int(round(target.carbsTarget))
        let fat = Int(round(target.fatTarget))
        return "\(calories) kcal · P \(protein)g · C \(carbs)g · F \(fat)g"
    }
}
