import PhotosUI
import SwiftUI
import UIKit

struct AddLogSheet: View {
    enum Mode {
        case log
        case library
    }

    enum LibraryEntryMode: String, CaseIterable, Identifiable {
        case photo
        case manual

        var id: String { rawValue }
        var title: String {
            switch self {
            case .photo: return "Photo"
            case .manual: return "Manual"
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AddLogViewModel()
    @State private var saveToLibrary: Bool = false
    @State private var libraryName: String = ""
    @State private var libraryNameEdited: Bool = false
    @State private var pendingDuplicate: (existing: SavedFood, draft: SavedFoodDraft)? = nil
    @State private var isShowingDuplicatePrompt: Bool = false
    @State private var isShowingCamera: Bool = false
    @State private var cameraImageData: Data? = nil
    @State private var cameraError: String? = nil
    @State private var isShowingLibraryPicker: Bool = false
    @State private var libraryEntryMode: LibraryEntryMode = .photo
    // Manual entry state (for library mode)
    @State private var manualUnitType: FoodUnitType = .per100g
    @State private var manualServingSizeText: String = ""
    @State private var manualServingUnit: String = "serving"
    @State private var manualCaloriesText: String = ""
    @State private var manualProteinText: String = ""
    @State private var manualCarbsText: String = ""
    @State private var manualFatText: String = ""
    @State private var manualErrorMessage: String? = nil
    @State private var mealToLog: SavedFood? = nil

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
                            // Entry mode picker for library
                            libraryEntryModePicker
                            
                            if libraryEntryMode == .photo {
                                // Photo-based entry flow
                                libraryNameCard
                                if viewModel.isLibrarySelectionActive {
                                    selectedLibraryFoodCard
                                } else {
                                    photoCard
                                        .id(viewModel.selectedImageData == nil ? "no-image" : "has-image")
                                    analyzeButton
                                }

                                if viewModel.isAnalyzing || !viewModel.streamPreview.isEmpty {
                                    statusCard
                                        .padding(.horizontal, 16)
                                }

                                if viewModel.estimate != nil && !viewModel.isLibrarySelectionActive {
                                    estimateCard
                                }
                                if viewModel.estimate != nil {
                                    saveLibraryButton
                                }

                                if let errorMessage = viewModel.errorMessage {
                                    errorCard(message: errorMessage, allowManual: !viewModel.isLibrarySelectionActive && viewModel.estimate == nil)
                                        .padding(.horizontal, 16)
                                }
                            } else {
                                // Manual entry flow
                                manualEntryForm
                            }
                        } else {
                            // Log mode (unchanged)
                            if viewModel.isLibrarySelectionActive {
                                selectedLibraryFoodCard
                            } else {
                                photoCard
                                    .id(viewModel.selectedImageData == nil ? "no-image" : "has-image")
                                analyzeButton
                            }

                            if viewModel.isAnalyzing || !viewModel.streamPreview.isEmpty {
                                statusCard
                                    .padding(.horizontal, 16)
                            }

                            if viewModel.estimate != nil && !viewModel.isLibrarySelectionActive {
                                estimateCard
                                if viewModel.showSaveToLibrary {
                                    saveToLibraryCard
                                }
                            }
                            if canSaveLog {
                                saveButton
                            }

                            if let errorMessage = viewModel.errorMessage {
                                errorCard(message: errorMessage, allowManual: !viewModel.isLibrarySelectionActive && viewModel.estimate == nil)
                                    .padding(.horizontal, 16)
                            }
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
            .sheet(item: $mealToLog) { meal in
                MealQuickLogSheet(meal: meal, onSaved: {
                    dismiss()
                })
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

    private var libraryEntryModePicker: some View {
        Picker("Entry mode", selection: $libraryEntryMode) {
            ForEach(LibraryEntryMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    private var manualEntryForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Food name
            VStack(alignment: .leading, spacing: 8) {
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
            }
            .modifier(CardModifier())

            // Unit type
            VStack(alignment: .leading, spacing: 12) {
                Text("Units")
                    .font(.headline)
                Picker("Unit type", selection: $manualUnitType) {
                    ForEach(FoodUnitType.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                if manualUnitType == .perServing {
                    HStack(spacing: 12) {
                        TextField("Grams", text: $manualServingSizeText)
                            .keyboardType(.decimalPad)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        TextField("Unit (e.g. slice)", text: $manualServingUnit)
                            .textInputAutocapitalization(.never)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .modifier(CardModifier())

            // Macros
            VStack(alignment: .leading, spacing: 12) {
                Text(manualUnitType == .perServing ? "Macros (per 100g)" : "Macros")
                    .font(.headline)

                VStack(spacing: 10) {
                    MacroEditField(label: "Calories", value: $manualCaloriesText)
                    MacroEditField(label: "Protein (g)", value: $manualProteinText)
                    MacroEditField(label: "Carbs (g)", value: $manualCarbsText)
                    MacroEditField(label: "Fat (g)", value: $manualFatText)
                }

                if manualUnitType == .perServing, let preview = manualPerServingPreview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Per serving")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            MacroBadge(label: "Cal", value: formatManualMacro(preview.calories))
                            MacroBadge(label: "P", value: formatManualMacro(preview.protein))
                            MacroBadge(label: "C", value: formatManualMacro(preview.carbs))
                            MacroBadge(label: "F", value: formatManualMacro(preview.fat))
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .modifier(CardModifier())

            if let errorMessage = manualErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }

            // Save button
            saveManualLibraryButton
        }
    }

    private var manualPerServingPreview: MacroDoubles? {
        guard let calories = parseManualMacro(manualCaloriesText),
              let protein = parseManualMacro(manualProteinText),
              let carbs = parseManualMacro(manualCarbsText),
              let fat = parseManualMacro(manualFatText),
              let servingSize = Double(manualServingSizeText),
              servingSize > 0 else {
            return nil
        }
        let multiplier = servingSize / 100.0
        return MacroDoubles(
            calories: calories * multiplier,
            protein: protein * multiplier,
            carbs: carbs * multiplier,
            fat: fat * multiplier
        )
    }

    private func parseManualMacro(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formatManualMacro(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private var saveManualLibraryButton: some View {
        Button {
            Task {
                await handleSaveManualLibrary()
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
        .background(Color(red: 0.8, green: 0.2, blue: 0.6))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(viewModel.isSaving)
        .opacity(viewModel.isSaving ? 0.7 : 1)
        .padding(.horizontal, 16)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Library search button
            Button {
                isShowingLibraryPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search Library")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Choose from your saved foods")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            // Divider with "or"
            HStack {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
            }
            .padding(.vertical, 4)

            // AI description input
            VStack(alignment: .leading, spacing: 8) {
                PlaceholderTextEditor(
                    text: $viewModel.searchText,
                    placeholder: "Describe your meal for AI"
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
                }

                Text("Include grams (e.g. \"banana 120g\").")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !viewModel.searchText.isEmpty {
                aiAnalyzeRow
            }
        }
        .modifier(CardModifier())
        .sheet(isPresented: $isShowingLibraryPicker) {
            LibrarySearchSheet(
                onSelect: { food in
                    viewModel.selectLibraryFood(food)
                    isShowingLibraryPicker = false
                },
                onMealSelected: { meal in
                    isShowingLibraryPicker = false
                    mealToLog = meal
                }
            )
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
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                Text("Analyze with AI")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20))
            }
            .font(.subheadline)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
            }

            if let imageData = viewModel.selectedImageData, let uiImage = UIImage(data: imageData) {
                // Show captured/selected image with replace options
                ZStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Button {
                                handleCameraButtonTap()
                            } label: {
                                Label("Retake", systemImage: "camera")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())

                            PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                                Label("Gallery", systemImage: "photo")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .padding(.bottom, 12)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
            } else {
                // Show camera and gallery buttons when no image
                HStack(spacing: 12) {
                    Button {
                        handleCameraButtonTap()
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 28, weight: .semibold))
                            Text("Take Photo")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1, dash: [6]))
                        )
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 28, weight: .semibold))
                            Text("Gallery")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1, dash: [6]))
                        )
                    }
                }
            }

            if let cameraError {
                Text(cameraError)
                    .font(.caption)
                    .foregroundColor(.red)
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
        .overlay(alignment: .topTrailing) {
            if viewModel.selectedImageData != nil {
                Button {
                    print("DEBUG: Remove tapped")
                    cameraImageData = nil
                    viewModel.clearPhoto()
                } label: {
                    Text("Remove")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .zIndex(1)
                .padding(.top, 2)
            }
        }
        .modifier(CardModifier())
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(imageData: $cameraImageData)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImageData) { _, newData in
            if let newData {
                viewModel.setCameraImage(newData)
                cameraImageData = nil
            }
        }
    }

    private func handleCameraButtonTap() {
        cameraError = nil
        let status = CameraAccess.checkStatus()
        if let errorMessage = status.errorMessage {
            cameraError = errorMessage
        } else {
            isShowingCamera = true
        }
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
        .background(Color(red: 0.8, green: 0.2, blue: 0.6))
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
        .background(Color(red: 0.8, green: 0.2, blue: 0.6))
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
        .background(Color(red: 0.8, green: 0.2, blue: 0.6))
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

    private func handleSaveManualLibrary() async {
        manualErrorMessage = nil

        let trimmedName = libraryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            manualErrorMessage = "Please enter a food name."
            return
        }

        guard let calories = parseManualMacro(manualCaloriesText),
              let protein = parseManualMacro(manualProteinText),
              let carbs = parseManualMacro(manualCarbsText),
              let fat = parseManualMacro(manualFatText) else {
            manualErrorMessage = "Please enter valid macro values."
            return
        }

        var servingSize: Double? = nil
        var servingLabel: String? = nil
        if manualUnitType == .perServing {
            guard let size = Double(manualServingSizeText), size > 0 else {
                manualErrorMessage = "Please enter grams per serving."
                return
            }
            servingSize = size
            let trimmedUnit = manualServingUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            servingLabel = trimmedUnit.isEmpty ? nil : trimmedUnit
        }

        let perServing = computeManualPerServing(
            per100g: MacroDoubles(calories: calories, protein: protein, carbs: carbs, fat: fat),
            servingSize: servingSize
        )

        let draft = SavedFoodDraft(
            name: trimmedName,
            unitType: manualUnitType,
            servingSize: servingSize,
            servingUnit: servingLabel,
            caloriesPer100g: calories,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat,
            caloriesPerServing: perServing.calories,
            proteinPerServing: perServing.protein,
            carbsPerServing: perServing.carbs,
            fatPerServing: perServing.fat
        )

        let result = await viewModel.saveLibraryDraft(draft)
        switch result {
        case .saved:
            resetManualAndDismiss()
        case .duplicate(let existing, let draft):
            pendingDuplicate = (existing: existing, draft: draft)
            isShowingDuplicatePrompt = true
        case .failed:
            manualErrorMessage = viewModel.errorMessage ?? "Failed to save food."
        }
    }

    private func computeManualPerServing(per100g: MacroDoubles, servingSize: Double?) -> MacroDoubles {
        guard let servingSize, servingSize > 0 else {
            return MacroDoubles(calories: 0, protein: 0, carbs: 0, fat: 0)
        }
        let multiplier = servingSize / 100.0
        return MacroDoubles(
            calories: per100g.calories * multiplier,
            protein: per100g.protein * multiplier,
            carbs: per100g.carbs * multiplier,
            fat: per100g.fat * multiplier
        )
    }

    private func resetManualAndDismiss() {
        libraryName = ""
        libraryNameEdited = false
        manualUnitType = .per100g
        manualServingSizeText = ""
        manualServingUnit = "serving"
        manualCaloriesText = ""
        manualProteinText = ""
        manualCarbsText = ""
        manualFatText = ""
        manualErrorMessage = nil
        pendingDuplicate = nil
        dismiss()
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
            if mode == .library && libraryEntryMode == .manual {
                resetManualAndDismiss()
            } else {
                resetAndDismiss()
            }
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

// MARK: - Library Search Sheet

private struct LibrarySearchSheet: View {
    let onSelect: (SavedFood) -> Void
    let onMealSelected: (SavedFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FoodLibraryViewModel()
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search your library...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                Divider()

                // Results list
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else if filteredFoods.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredFoods) { food in
                                LibraryFoodRow(food: food) {
                                    if food.isMeal {
                                        onMealSelected(food)
                                        dismiss()
                                    } else {
                                        onSelect(food)
                                    }
                                }

                                if food.id != filteredFoods.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Your Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadFoods()
                isSearchFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var filteredFoods: [SavedFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.foods }
        return viewModel.foods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if searchText.isEmpty {
                Image(systemName: "leaf")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No saved foods")
                    .font(.headline)
                Text("Add foods to your Library to quickly log them here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No results for \"\(searchText)\"")
                    .font(.headline)
                Text("Try a different search term.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

private struct LibraryFoodRow: View {
    let food: SavedFood
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Food icon
                ZStack {
                    Circle()
                        .fill(food.isMeal ? Color.indigo.opacity(0.1) : Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: food.isMeal ? "fork.knife" : "leaf.fill")
                        .foregroundColor(food.isMeal ? .indigo : .blue)
                }

                // Food details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(food.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if food.isMeal {
                            Text("meal")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.indigo)
                                .clipShape(Capsule())
                        }
                    }

                    if food.isMeal {
                        Text("Tap to log with custom portions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            MacroTag(value: Int(displayMacros.calories), label: "cal", color: .orange)
                            MacroTag(value: Int(displayMacros.protein), label: "P", color: .blue)
                            MacroTag(value: Int(displayMacros.carbs), label: "C", color: .green)
                            MacroTag(value: Int(displayMacros.fat), label: "F", color: .purple)
                        }

                        Text(unitLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayMacros: MacroDoubles {
        switch food.unitType {
        case .per100g:
            return MacroDoubles(
                calories: food.caloriesPer100g,
                protein: food.proteinPer100g,
                carbs: food.carbsPer100g,
                fat: food.fatPer100g
            )
        case .perServing:
            return food.resolvedPerServingMacros()
        }
    }

    private var unitLabel: String {
        food.unitType == .per100g ? "per 100g" : "per serving"
    }
}

private struct MacroTag: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(color)
    }
}
