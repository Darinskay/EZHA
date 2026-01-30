import SwiftUI

struct SuggestionsView: View {
    @StateObject private var viewModel = SuggestionsViewModel()
    @State private var showRefineDialog = false
    @State private var showIngredientPrompt = false
    @State private var showTimePrompt = false
    @State private var ingredientInput = ""
    @State private var timeInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Remaining Today") {
                    MacroRemainingRow(label: "Calories", value: viewModel.remaining.calories, suffix: "kcal")
                    MacroRemainingRow(label: "Protein", value: viewModel.remaining.protein, suffix: "g")
                    MacroRemainingRow(label: "Carbs", value: viewModel.remaining.carbs, suffix: "g")
                    MacroRemainingRow(label: "Fat", value: viewModel.remaining.fat, suffix: "g")

                    if viewModel.targets.calories == 0 && viewModel.targets.protein == 0 &&
                        viewModel.targets.carbs == 0 && viewModel.targets.fat == 0 {
                        Text("Set your daily targets in Settings for better suggestions.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if let message = viewModel.contextErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                Section("Preferences") {
                    Picker("Meal type", selection: $viewModel.mealType) {
                        ForEach(SuggestionMealType.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    Stepper(value: $viewModel.maxPrepTimeMinutes, in: 1...240) {
                        Text("Max prep time: \(viewModel.maxPrepTimeMinutes) min")
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.fetchSuggestions() }
                    } label: {
                        if viewModel.isLoadingSuggestions {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Get suggestions")
                        }
                    }
                    .disabled(viewModel.isLoadingSuggestions || viewModel.isLoadingContext)
                }

                Section("Suggestions") {
                    if let message = viewModel.suggestionErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }

                    if viewModel.isLoadingSuggestions {
                        ProgressView("Asking AI...")
                    } else if viewModel.suggestions.isEmpty {
                        Text("No suggestions yet. Fill the form and tap Get suggestions.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.suggestions) { suggestion in
                            SuggestionRow(suggestion: suggestion)
                        }

                        Button("Try again") {
                            showRefineDialog = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("Suggestions")
            .confirmationDialog("What to change?", isPresented: $showRefineDialog, titleVisibility: .visible) {
                Button("Ingredients") {
                    ingredientInput = viewModel.ingredientNotes
                    showIngredientPrompt = true
                }
                Button("Time to cook") {
                    timeInput = "\(viewModel.maxPrepTimeMinutes)"
                    showTimePrompt = true
                }
                Button("Another options") {
                    Task { await viewModel.regenerate(reason: .different) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Update ingredients", isPresented: $showIngredientPrompt) {
                TextField("Ingredients to include or avoid", text: $ingredientInput)
                Button("Apply") {
                    Task { await viewModel.regenerate(reason: .ingredients(ingredientInput)) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Example: no peanuts, add berries")
            }
            .alert("Update prep time (minutes)", isPresented: $showTimePrompt) {
                TextField("Minutes", text: $timeInput)
                    .keyboardType(.numberPad)
                Button("Apply") {
                    let sanitized = Int(timeInput.trimmingCharacters(in: .whitespacesAndNewlines))
                        ?? viewModel.maxPrepTimeMinutes
                    Task { await viewModel.regenerate(reason: .time(sanitized)) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Max prep time for suggestions.")
            }
            .task {
                await viewModel.loadContext()
            }
        }
    }
}

private struct MacroRemainingRow: View {
    let label: String
    let value: Int
    let suffix: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value) \(suffix)")
                .foregroundColor(value < 0 ? .red : .primary)
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: MealSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.title)
                .font(.headline)

            Text(suggestion.description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(macroLine)
                .font(.footnote)
                .foregroundColor(.secondary)

            if let warning = suggestion.warning {
                Text(warning)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            if let notes = suggestion.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var macroLine: String {
        "\(suggestion.calories) kcal • P\(suggestion.protein)g • C\(suggestion.carbs)g • F\(suggestion.fat)g"
    }
}
