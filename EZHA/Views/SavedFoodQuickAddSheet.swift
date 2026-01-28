import SwiftUI

struct SavedFoodQuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AddLogViewModel
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isSavedFoodsLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading saved foods...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else if let errorMessage = viewModel.savedFoodsError {
                    ContentUnavailableView(
                        "Unable to load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if viewModel.savedFoods.isEmpty {
                    ContentUnavailableView(
                        "No saved foods",
                        systemImage: "leaf",
                        description: Text("Add foods in Library to reuse them.")
                    )
                } else {
                    List {
                        Section {
                            if selectedFoods.isEmpty {
                                Text("Select up to \(viewModel.maxSavedFoodsAllowed) items below.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(selectedFoods) { food in
                                    SelectedFoodRow(
                                        food: food,
                                        quantityText: Binding(
                                            get: { viewModel.savedFoodState(for: food).gramsText },
                                            set: { viewModel.updateSavedFoodQuantityText(food, text: $0) }
                                        ),
                                        errorMessage: viewModel.savedFoodState(for: food).errorMessage,
                                        onRemove: { viewModel.toggleSavedFood(food) }
                                    )
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            viewModel.toggleSavedFood(food)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Selected items (\(viewModel.selectedSavedFoodCount)/\(viewModel.maxSavedFoodsAllowed))")
                        } footer: {
                            Text("Enter grams for each selected item.")
                        }

                        Section {
                            ForEach(filteredFoods) { food in
                                AvailableFoodRow(
                                    food: food,
                                    isSelected: viewModel.savedFoodState(for: food).isActive,
                                    canAddMore: viewModel.selectedSavedFoodCount < viewModel.maxSavedFoodsAllowed,
                                    onAdd: { viewModel.toggleSavedFood(food) }
                                )
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        } header: {
                            Text("All saved foods")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollDismissesKeyboard(.interactively)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                }
            }
            .navigationTitle("Saved Foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .dismissKeyboardOnTap()
            .keyboardDoneToolbar()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let errorMessage = viewModel.savedFoodsSelectionError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Button("Apply Selection") {
                        if viewModel.analyzeSavedFoodsSelection() {
                            dismiss()
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(viewModel.canAnalyzeSavedFoodsSelection ? Color(red: 0.8, green: 0.2, blue: 0.6) : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(!viewModel.canAnalyzeSavedFoodsSelection)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .task {
                await viewModel.loadSavedFoods()
            }
        }
    }

    private var selectedFoods: [SavedFood] {
        viewModel.savedFoods.filter { viewModel.savedFoodState(for: $0).isActive }
    }

    private var filteredFoods: [SavedFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.savedFoods }
        return viewModel.savedFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}

private struct SelectedFoodRow: View {
    let food: SavedFood
    @Binding var quantityText: String
    let errorMessage: String?
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                SavedFoodRow(food: food)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(food.name)")
            }

            HStack(spacing: 10) {
                TextField("0", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(food.unitType.quantityLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct AvailableFoodRow: View {
    let food: SavedFood
    let isSelected: Bool
    let canAddMore: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SavedFoodRow(food: food)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isSelected ? .green : (canAddMore ? .blue : .gray))
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(isSelected || !canAddMore)
            .accessibilityLabel(isSelected ? "Selected" : "Add \(food.name)")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isSelected && canAddMore {
                onAdd()
            }
        }
    }
}
