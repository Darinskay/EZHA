import PhotosUI
import SwiftUI
import UIKit

struct AddLogSheet: View {
    enum Mode {
        case log
        case library
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AddLogViewModel()
    @State private var saveToLibrary: Bool = false
    @State private var libraryName: String = ""
    @State private var libraryNameEdited: Bool = false
    @State private var pendingDuplicate: (existing: SavedFood, draft: SavedFoodDraft)? = nil
    @State private var isShowingDuplicatePrompt: Bool = false

    init(mode: Mode = .log) {
        self.mode = mode
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                    header
                    if mode == .log {
                        searchSection
                    }
                        if mode == .library {
                            libraryNameCard
                        }
                        if viewModel.isLibrarySelectionActive {
                            selectedLibraryFoodCard
                        } else {
                            photoCard
                            analyzeButton
                        }

                        if viewModel.isAnalyzing || !viewModel.streamPreview.isEmpty {
                            statusCard
                                .padding(.horizontal, 16)
                        }

                        if viewModel.estimate != nil && !viewModel.isLibrarySelectionActive {
                            estimateCard
                            if mode == .log, viewModel.showSaveToLibrary {
                                saveToLibraryCard
                            }
                        }
                        if mode == .log, canSaveLog {
                            saveButton
                        } else if mode == .library, viewModel.estimate != nil {
                            saveLibraryButton
                        }

                        if let errorMessage = viewModel.errorMessage {
                            errorCard(message: errorMessage, allowManual: !viewModel.isLibrarySelectionActive && viewModel.estimate == nil)
                                .padding(.horizontal, 16)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(mode == .log ? "Add Log" : "Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .log ? "Close" : "Cancel") {
                        dismiss()
                    }
                }
            }
            .task(id: viewModel.selectedItem) {
                await viewModel.loadSelectedImage()
            }
            .onChange(of: viewModel.estimate) { _, _ in
                guard !libraryNameEdited else { return }
                libraryName = viewModel.suggestedFoodName()
            }
            .onChange(of: viewModel.descriptionText) { _, _ in
                guard !libraryNameEdited else { return }
                libraryName = viewModel.suggestedFoodName()
            }
            .onChange(of: viewModel.items) { _, _ in
                guard !libraryNameEdited else { return }
                libraryName = viewModel.suggestedFoodName()
            }
            .onChange(of: viewModel.entryMode) { _, _ in
                guard !libraryNameEdited else { return }
                libraryName = viewModel.suggestedFoodName()
            }
            .onChange(of: saveToLibrary) { _, isOn in
                guard isOn, !libraryNameEdited else { return }
                libraryName = viewModel.suggestedFoodName()
            }
            .onChange(of: viewModel.isLibrarySelectionActive) { _, isActive in
                if isActive {
                    saveToLibrary = false
                }
            }
            .confirmationDialog(
                "Food already exists",
                isPresented: $isShowingDuplicatePrompt,
                titleVisibility: .visible
            ) {
                Button("Update existing") {
                    Task { await handleDuplicateChoice(.updateExisting) }
                }
                Button("Create new") {
                    Task { await handleDuplicateChoice(.createNew) }
                }
                Button("Cancel", role: .cancel) {
                    pendingDuplicate = nil
                }
            } message: {
                if let pendingDuplicate {
                    Text("\"\(pendingDuplicate.existing.name)\" is already in your Library.")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(headerSubtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                PlaceholderTextEditor(
                    text: $viewModel.searchText,
                    placeholder: "Search library or describe your meal"
                )
                .frame(minHeight: 64, maxHeight: 88)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: viewModel.searchText) { _, newValue in
                    if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       viewModel.isLibrarySelectionActive {
                        viewModel.clearLibrarySelection()
                    }
                    viewModel.searchLibraryFoods(newValue)
                }

                Text("Include grams (e.g. \"banana 120g\").")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !viewModel.searchText.isEmpty, !viewModel.filteredLibraryFoods.isEmpty {
                libraryResultsList
            }
            if !viewModel.searchText.isEmpty {
                aiAnalyzeRow
            }
        }
        .modifier(CardModifier())
    }

    private var libraryResultsList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.filteredLibraryFoods.prefix(5)) { food in
                Button {
                    viewModel.selectLibraryFood(food)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(Int(food.caloriesPer100g)) cal per 100g")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                if food.id != viewModel.filteredLibraryFoods.prefix(5).last?.id {
                    Divider()
                }
            }
        }
    }

    private var aiAnalyzeRow: some View {
        Button {
            Task {
                dismissKeyboard()
                await viewModel.analyzeQuickText()
                if !libraryNameEdited {
                    libraryName = viewModel.suggestedFoodName()
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                Text("AI analyse \"\(viewModel.searchText)\"")
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
            }
            .font(.subheadline)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundColor(.blue)
    }

    private var selectedLibraryFoodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected from library")
                    .font(.headline)
                Spacer()
                Button("Change") {
                    viewModel.clearLibrarySelection()
                }
                .font(.subheadline)
            }

            if let food = viewModel.selectedLibraryFood {
                VStack(alignment: .leading, spacing: 10) {
                    Text(food.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    TextField("Grams", text: $viewModel.libraryFoodQuantityText)
                        .keyboardType(.decimalPad)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: viewModel.libraryFoodQuantityText) { _, _ in
                            viewModel.calculateLibraryMacros()
                        }

                    if let macros = viewModel.libraryCalculatedMacros {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Total")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack(spacing: 8) {
                                MacroBadge(label: "Cal", value: formattedMacro(macros.calories))
                                MacroBadge(label: "P", value: formattedMacro(macros.protein))
                                MacroBadge(label: "C", value: formattedMacro(macros.carbs))
                                MacroBadge(label: "F", value: formattedMacro(macros.fat))
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
                viewModel.applySearchTextToInputs()
                await viewModel.analyze()
                if !libraryNameEdited {
                    libraryName = viewModel.suggestedFoodName()
                }
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

            if viewModel.isAnalyzing {
                HStack(spacing: 8) {
                    MacroBadge(label: "Cal", value: viewModel.caloriesText)
                    MacroBadge(label: "P", value: viewModel.proteinText)
                    MacroBadge(label: "C", value: viewModel.carbsText)
                    MacroBadge(label: "F", value: viewModel.fatText)
                }
            }
        }
        .modifier(CardModifier())
    }

    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Edit estimate")
                    .font(.headline)
                Spacer()
                if let estimate = viewModel.estimate {
                    ConfidenceBadge(confidence: estimate.confidence, source: estimate.source)
                }
            }

            // Show itemized breakdown if items are available
            if let estimate = viewModel.estimate, !estimate.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Items breakdown")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(estimate.items, id: \.self) { item in
                        ItemBreakdownRow(item: item)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Total")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                VStack(spacing: 10) {
                    MacroEditField(label: "Calories", value: $viewModel.caloriesText)
                    MacroEditField(label: "Protein (g)", value: $viewModel.proteinText)
                    MacroEditField(label: "Carbs (g)", value: $viewModel.carbsText)
                    MacroEditField(label: "Fat (g)", value: $viewModel.fatText)
                }
            }

            if let estimate = viewModel.estimate, !estimate.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(estimate.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .modifier(CardModifier())
    }

    private var libraryNameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Food name")
                .font(.headline)
            TextField("Ex: Apple", text: $libraryName)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onChange(of: libraryName) { _, _ in
                    libraryNameEdited = true
                }
            Text("Leave blank to let AI fill it after analysis.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .modifier(CardModifier())
    }

    private var saveToLibraryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Save to Library", isOn: $saveToLibrary)
                .font(.headline)
                .tint(.blue)

            if saveToLibrary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Food name")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    TextField("Ex: Apple", text: $libraryName)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onChange(of: libraryName) { _, _ in
                            libraryNameEdited = true
                        }
                }
            }
            Text("Save this food to log it faster next time.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .modifier(CardModifier())
    }

    private var saveButton: some View {
        Button {
            Task {
                await handleSaveLog()
            }
        } label: {
            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.isSaving ? "Saving..." : "Save log")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .background(.linearGradient(colors: [Color(red: 0.9, green: 0.4, blue: 0.8), Color(red: 0.5, green: 0.2, blue: 0.7)], startPoint: .leading, endPoint: .trailing))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(viewModel.isSaving)
        .opacity(viewModel.isSaving ? 0.7 : 1)
        .padding(.horizontal, 16)
    }

    private var saveLibraryButton: some View {
        Button {
            Task {
                await handleSaveLibrary()
            }
        } label: {
            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.isSaving ? "Saving..." : "Save to Library")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .background(.linearGradient(colors: [Color(red: 0.9, green: 0.4, blue: 0.8), Color(red: 0.5, green: 0.2, blue: 0.7)], startPoint: .leading, endPoint: .trailing))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(viewModel.isSaving)
        .opacity(viewModel.isSaving ? 0.7 : 1)
        .padding(.horizontal, 16)
    }

    private func errorCard(message: String, allowManual: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.subheadline)
            }
            if allowManual {
                Button("Enter manually") {
                    viewModel.enableManualEntry()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var canSaveLog: Bool {
        if viewModel.isLibrarySelectionActive {
            return viewModel.libraryCalculatedMacros != nil && !viewModel.libraryFoodQuantityText.isEmpty
        }
        return viewModel.estimate != nil
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

    private var headerTitle: String {
        switch mode {
        case .log:
            return "Add your meal"
        case .library:
            return "Add new food"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .log:
            return "List foods with grams or switch to a description. Edit the AI estimate before saving."
        case .library:
            return "Scan a label or describe the food. Edit the AI estimate before saving."
        }
    }

    private func handleSaveLog() async {
        if saveToLibrary, viewModel.showSaveToLibrary, !viewModel.isLibrarySelectionActive {
            guard viewModel.validateLibraryName(libraryName) else { return }
        }

        let didSave = await viewModel.saveEntry()
        if didSave {
            if saveToLibrary, viewModel.showSaveToLibrary, !viewModel.isLibrarySelectionActive {
                let didFinish = await attemptLibrarySave()
                if !didFinish {
                    return
                }
            }
            resetAndDismiss()
            NotificationCenter.default.post(name: .foodEntrySaved, object: nil)
        }
    }

    private func handleSaveLibrary() async {
        guard viewModel.validateLibraryName(libraryName) else { return }
        let didFinish = await attemptLibrarySave()
        if didFinish {
            resetAndDismiss()
        }
    }

    private func attemptLibrarySave() async -> Bool {
        guard let draft = viewModel.buildLibraryDraft(name: libraryName) else { return false }
        let result = await viewModel.saveLibraryDraft(draft)
        switch result {
        case .saved:
            return true
        case .duplicate(let existing, let draft):
            pendingDuplicate = (existing: existing, draft: draft)
            isShowingDuplicatePrompt = true
            return false
        case .failed:
            return false
        }
    }

    private func handleDuplicateChoice(_ choice: LibraryDuplicateChoice) async {
        guard let pendingDuplicate else { return }
        let didSave = await viewModel.resolveLibraryDuplicate(
            choice: choice,
            existing: pendingDuplicate.existing,
            draft: pendingDuplicate.draft
        )
        if didSave {
            resetAndDismiss()
        }
    }

    private func resetAndDismiss() {
        viewModel.reset()
        libraryName = ""
        libraryNameEdited = false
        saveToLibrary = false
        pendingDuplicate = nil
        dismiss()
    }
}

private struct MacroEditField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            TextField("", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ItemBreakdownRow: View {
    let item: MacroItemEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(item.grams))g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                ItemMacroBadge(label: "Cal", value: item.calories)
                ItemMacroBadge(label: "P", value: item.protein)
                ItemMacroBadge(label: "C", value: item.carbs)
                ItemMacroBadge(label: "F", value: item.fat)
                Spacer()
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ItemMacroBadge: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(formattedValue)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private var formattedValue: String {
        if value < 10 {
            return String(format: "%.1f", value)
        }
        return "\(Int(value.rounded()))"
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
