import PhotosUI
import SwiftUI

struct LogMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LogMealViewModel()
    @State private var isLibraryPickerPresented = false
    @State private var saveToLibrary: Bool = false
    @State private var libraryName: String = ""
    @State private var libraryNameEdited: Bool = false
    @State private var mealNameEdited: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        mealNameCard
                        librarySection
                        descriptionCard
                        photoCard
                        analyzeButton

                        if viewModel.isAnalyzing || !viewModel.streamPreview.isEmpty {
                            statusCard
                                .padding(.horizontal, 16)
                        }

                        if let estimate = viewModel.estimate {
                            aiSummaryCard(estimate: estimate)
                        }

                        if let totals = viewModel.combinedTotals {
                            totalsCard(totals: totals)
                        }

                        if viewModel.canSaveMeal {
                            saveToLibraryCard
                        }

                        saveButton

                        if let errorMessage = viewModel.errorMessage {
                            errorCard(message: errorMessage)
                                .padding(.horizontal, 16)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task(id: viewModel.selectedItem) {
                await viewModel.loadSelectedImage()
            }
            .onChange(of: viewModel.estimate) { _, _ in
                updateMealNameIfNeeded()
                updateLibraryNameIfNeeded()
            }
            .onChange(of: viewModel.descriptionText) { _, _ in
                updateMealNameIfNeeded()
            }
            .onChange(of: viewModel.librarySelections) { _, _ in
                updateMealNameIfNeeded()
            }
            .onChange(of: saveToLibrary) { _, isOn in
                if isOn {
                    updateLibraryNameIfNeeded()
                }
            }
            .sheet(isPresented: $isLibraryPickerPresented) {
                MealLibraryPickerSheet(
                    selections: viewModel.librarySelections,
                    onApply: { selections in
                        viewModel.updateLibrarySelections(selections)
                    }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log meal")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Combine library foods, text notes, and photos.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var mealNameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meal name")
                .font(.headline)
            TextField("Ex: Lunch", text: $viewModel.mealName)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onChange(of: viewModel.mealName) { _, _ in
                    mealNameEdited = true
                }
        }
        .modifier(CardModifier())
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("From Library")
                    .font(.headline)
                Spacer()
                Button("Add") {
                    isLibraryPickerPresented = true
                }
                .font(.subheadline)
            }

            if viewModel.librarySelections.isEmpty {
                Text("Add saved foods with grams.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach($viewModel.librarySelections) { $selection in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                SavedFoodRow(food: selection.food)
                                Spacer()
                                Button {
                                    viewModel.removeLibrarySelection(id: selection.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(selection.food.name)")
                            }

                            TextField("Grams", text: Binding(
                                get: { selection.gramsText },
                                set: { viewModel.updateLibrarySelection(id: selection.id, gramsText: $0) }
                            ))
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            if let errorMessage = selection.errorMessage {
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
            }
        }
        .modifier(CardModifier())
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meal description")
                .font(.headline)

            PlaceholderTextEditor(
                text: $viewModel.descriptionText,
                placeholder: "Ex: Chicken salad with avocado and olive oil"
            )
            .frame(minHeight: 56, maxHeight: 84)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                Label("More detail = better estimate", systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Optional")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .modifier(CardModifier())
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photo")
                    .font(.headline)
                Spacer()
                if viewModel.selectedImageData != nil {
                    Button("Remove") {
                        viewModel.clearPhoto()
                    }
                    .font(.subheadline)
                }
            }

            let imageData = viewModel.selectedImageData
            PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1, dash: [6]))
                        )

                    if let imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .bottomLeading) {
                                Text("Tap to replace")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(12)
                            }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 28, weight: .semibold))
                            Text("Add a photo or label")
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                        .padding(.vertical, 22)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }

            if viewModel.selectedImageData != nil {
                Toggle("This is a nutrition label", isOn: $viewModel.isLabelPhoto)
                    .font(.subheadline)
                    .tint(.blue)
                    .onChange(of: viewModel.isLabelPhoto) { _, isOn in
                        viewModel.handleLabelToggle(isOn)
                    }
            }

            if viewModel.selectedImageData != nil, viewModel.isLabelPhoto {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Grams eaten (optional)", text: $viewModel.labelGramsText)
                        .keyboardType(.decimalPad)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: viewModel.labelGramsText) { _, _ in
                            viewModel.applyLabelScaling()
                        }

                    if viewModel.estimate != nil,
                       viewModel.labelGramsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No grams entered; totals are per 100g.")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("If left empty, totals stay per 100g.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .modifier(CardModifier())
    }

    private var analyzeButton: some View {
        Button {
            Task {
                dismissKeyboard()
                await viewModel.analyze()
                updateMealNameIfNeeded()
                updateLibraryNameIfNeeded()
            }
        } label: {
            HStack {
                if viewModel.isAnalyzing {
                    ProgressView()
                        .tint(.white)
                }
                Text("Analyze")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .background(.linearGradient(colors: [Color(red: 0.9, green: 0.4, blue: 0.8), Color(red: 0.5, green: 0.2, blue: 0.7)], startPoint: .leading, endPoint: .trailing))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 6)
        .disabled(!viewModel.canAnalyze)
        .opacity(viewModel.canAnalyze ? 1 : 0.6)
        .padding(.horizontal, 16)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.analysisStage.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("We will fill in the estimate as results arrive.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !viewModel.streamPreview.isEmpty {
                Text(viewModel.streamPreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }
        }
        .modifier(CardModifier())
    }

    private func aiSummaryCard(estimate: MacroEstimate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI estimate")
                    .font(.headline)
                Spacer()
                ConfidenceBadge(confidence: estimate.confidence, source: estimate.source)
            }

            HStack(spacing: 8) {
                MacroBadge(label: "Cal", value: formattedMacro(estimate.calories))
                MacroBadge(label: "P", value: formattedMacro(estimate.protein))
                MacroBadge(label: "C", value: formattedMacro(estimate.carbs))
                MacroBadge(label: "F", value: formattedMacro(estimate.fat))
            }
        }
        .modifier(CardModifier())
    }

    private func totalsCard(totals: MacroDoubles) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total")
                .font(.headline)

            HStack(spacing: 8) {
                MacroBadge(label: "Cal", value: formattedMacro(totals.calories))
                MacroBadge(label: "P", value: formattedMacro(totals.protein))
                MacroBadge(label: "C", value: formattedMacro(totals.carbs))
                MacroBadge(label: "F", value: formattedMacro(totals.fat))
            }

            HStack(spacing: 8) {
                Text("Library: \(formattedMacro(viewModel.libraryTotals.calories)) cal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let estimate = viewModel.estimate {
                    Text("AI: \(formattedMacro(estimate.calories)) cal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .modifier(CardModifier())
        .padding(.horizontal, 16)
    }

    private var saveToLibraryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Save to Library", isOn: $saveToLibrary)
                .font(.headline)
                .tint(.blue)

            if saveToLibrary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal name")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    TextField("Ex: Chicken lunch", text: $libraryName)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onChange(of: libraryName) { _, _ in
                            libraryNameEdited = true
                        }
                }
            }
        }
        .modifier(CardModifier())
    }

    private var saveButton: some View {
        Button {
            Task {
                await handleSave()
            }
        } label: {
            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.isSaving ? "Saving..." : "Save meal")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .background(.linearGradient(colors: [Color(red: 0.9, green: 0.4, blue: 0.8), Color(red: 0.5, green: 0.2, blue: 0.7)], startPoint: .leading, endPoint: .trailing))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(!viewModel.canSaveMeal || viewModel.isSaving)
        .opacity(viewModel.canSaveMeal ? 1 : 0.6)
        .padding(.horizontal, 16)
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func handleSave() async {
        if !viewModel.validateLibrarySelections() {
            return
        }

        let resolvedMealName = resolvedMealNameText()
        let libraryNameText = saveToLibrary ? resolvedLibraryNameText() : nil
        let didSave = await viewModel.saveMeal(
            mealName: resolvedMealName,
            saveToLibrary: saveToLibrary,
            libraryName: libraryNameText
        )
        if didSave {
            viewModel.reset()
            libraryName = ""
            libraryNameEdited = false
            saveToLibrary = false
            mealNameEdited = false
            dismiss()
            NotificationCenter.default.post(name: .foodEntrySaved, object: nil)
        }
    }

    private func resolvedMealNameText() -> String {
        let trimmed = viewModel.mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return viewModel.suggestedMealName
        }
        return trimmed
    }

    private func resolvedLibraryNameText() -> String {
        let trimmed = libraryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return resolvedMealNameText()
        }
        return trimmed
    }

    private func updateMealNameIfNeeded() {
        guard !mealNameEdited else { return }
        viewModel.mealName = viewModel.suggestedMealName
    }

    private func updateLibraryNameIfNeeded() {
        guard saveToLibrary, !libraryNameEdited else { return }
        libraryName = resolvedMealNameText()
    }

    private func formattedMacro(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        if let text = formatter.string(from: NSNumber(value: value)) {
            return text
        }
        return String(value)
    }
}

private struct MealLibraryPickerSheet: View {
    let selections: [MealLibrarySelection]
    let onApply: ([MealLibrarySelection]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MealLibraryPickerViewModel()
    @State private var searchText: String = ""
    @State private var localSelections: [MealLibrarySelection] = []
    @State private var selectionError: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading saved foods...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Unable to load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if viewModel.foods.isEmpty {
                    ContentUnavailableView(
                        "No saved foods",
                        systemImage: "leaf",
                        description: Text("Add foods in Library to reuse them.")
                    )
                } else {
                    List {
                        Section {
                            if localSelections.isEmpty {
                                Text("Select foods and add grams.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(localSelections) { selection in
                                    MealSelectedFoodRow(
                                        selection: selection,
                                        onUpdate: updateSelection,
                                        onRemove: removeSelection
                                    )
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            removeSelection(selection.id)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Selected items (\(localSelections.count))")
                        } footer: {
                            Text("Enter grams for each selected item.")
                        }

                        Section {
                            ForEach(filteredFoods) { food in
                                MealAvailableFoodRow(
                                    food: food,
                                    isSelected: localSelections.contains(where: { $0.id == food.id }),
                                    onAdd: { toggleFood(food) }
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
            .navigationTitle("Choose Foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .dismissKeyboardOnTap()
            .keyboardDoneToolbar()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let selectionError {
                        Text(selectionError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Button("Apply Selection") {
                        if validateSelections() {
                            onApply(localSelections)
                            dismiss()
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(localSelections.isEmpty ? Color.gray.opacity(0.4) : Color(.systemBlue))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(localSelections.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .task {
                localSelections = selections
                await viewModel.loadFoods()
            }
        }
    }

    private var filteredFoods: [SavedFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.foods }
        return viewModel.foods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func toggleFood(_ food: SavedFood) {
        if let index = localSelections.firstIndex(where: { $0.id == food.id }) {
            localSelections.remove(at: index)
        } else {
            localSelections.append(MealLibrarySelection(food: food))
        }
    }

    private func updateSelection(_ selection: MealLibrarySelection) {
        if let index = localSelections.firstIndex(where: { $0.id == selection.id }) {
            localSelections[index] = selection
        }
        selectionError = nil
    }

    private func removeSelection(_ id: UUID) {
        localSelections.removeAll { $0.id == id }
    }

    private func validateSelections() -> Bool {
        var isValid = true
        for index in localSelections.indices {
            guard let grams = parseMacro(localSelections[index].gramsText), grams > 0 else {
                localSelections[index].errorMessage = "Enter grams."
                isValid = false
                continue
            }
            localSelections[index].errorMessage = nil
        }
        selectionError = isValid ? nil : "Please enter grams for each item."
        return isValid
    }

    private func parseMacro(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let noSpaces = trimmed.replacingOccurrences(of: " ", with: "")
        if noSpaces.contains(",") && !noSpaces.contains(".") {
            return Double(noSpaces.replacingOccurrences(of: ",", with: "."))
        }
        return Double(noSpaces)
    }
}

private struct MealSelectedFoodRow: View {
    let selection: MealLibrarySelection
    let onUpdate: (MealLibrarySelection) -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                SavedFoodRow(food: selection.food)
                Spacer()
                Button {
                    onRemove(selection.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(selection.food.name)")
            }

            HStack(spacing: 10) {
                TextField("0", text: Binding(
                    get: { selection.gramsText },
                    set: { newValue in
                        var updated = selection
                        updated.gramsText = newValue
                        updated.errorMessage = nil
                        onUpdate(updated)
                    }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(selection.food.unitType.quantityLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            if let errorMessage = selection.errorMessage {
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

private struct MealAvailableFoodRow: View {
    let food: SavedFood
    let isSelected: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SavedFoodRow(food: food)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isSelected ? .green : .blue)
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Selected" : "Add \(food.name)")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onAdd()
        }
    }
}

@MainActor
private final class MealLibraryPickerViewModel: ObservableObject {
    @Published var foods: [SavedFood] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let repository: SavedFoodRepository

    init(repository: SavedFoodRepository = SavedFoodRepository()) {
        self.repository = repository
    }

    func loadFoods() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            foods = try await repository.fetchFoods()
        } catch {
            errorMessage = "Unable to load saved foods: \(error.localizedDescription)"
        }
    }
}

private struct ConfidenceBadge: View {
    let confidence: Double?
    let source: String

    var body: some View {
        HStack(spacing: 6) {
            Text(sourceLabel)
                .font(.caption)
                .foregroundColor(.secondary)
            if let confidence {
                Text("\(Int(confidence * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private var sourceLabel: String {
        switch source {
        case "label_photo":
            return "Label"
        case "food_photo":
            return "Photo"
        case "text":
            return "Text"
        default:
            return "AI"
        }
    }
}

private struct MacroBadge: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "--" : value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
}

private struct PlaceholderTextEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(.system(.body, design: .rounded))
        }
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
