import SwiftUI

struct FoodLibraryView: View {
    @StateObject private var viewModel = FoodLibraryViewModel()
    @State private var isPresentingScan: Bool = false
    @State private var editingFood: SavedFood? = nil
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isPresentingScan = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add food")
                                    .font(.headline)
                                Text("Add manually or use AI to estimate macros.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .foregroundColor(.white)
                    .listRowBackground(Color(red: 0.8, green: 0.2, blue: 0.6))
                }

                if viewModel.foods.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No saved foods",
                        systemImage: "leaf",
                        description: Text("Save foods for quick logging.")
                    )
                } else {
                    ForEach(filteredFoods) { food in
                        Button {
                            editingFood = food
                        } label: {
                            SavedFoodRow(food: food)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                let food = filteredFoods[index]
                                await viewModel.deleteFood(id: food.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {}
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .task {
                await viewModel.loadFoods()
            }
            .onChange(of: isPresentingScan) { _, isPresented in
                if !isPresented {
                    Task { await viewModel.loadFoods() }
                }
            }
            .refreshable {
                await viewModel.loadFoods()
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.errorMessage = nil
                    }
                }
            )) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .dismissKeyboardOnTap()
        .keyboardDoneToolbar()
        .sheet(isPresented: $isPresentingScan) {
            AddLogSheet(mode: .library)
        }
        .sheet(item: $editingFood) { food in
            FoodEditorView(food: food) { draft in
                let didSave = await viewModel.saveFood(id: food.id, draft: draft)
                return didSave
            }
        }
    }

    private var filteredFoods: [SavedFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.foods }
        return viewModel.foods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}
