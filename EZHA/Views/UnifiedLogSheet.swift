import PhotosUI
import SwiftUI

struct UnifiedLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UnifiedLogViewModel()

    // Source input states
    @State private var isShowingCamera: Bool = false
    @State private var isShowingLibraryPicker: Bool = false
    @State private var isShowingTextInput: Bool = false
    @State private var cameraError: String? = nil
    @State private var cameraImageData: Data? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        sourceButtons

                        if viewModel.selectedImageData != nil {
                            photoPreviewSection
                        }

                        if isShowingTextInput && !viewModel.textUsed {
                            textInputSection
                        }

                        if viewModel.isAnalyzing || !viewModel.streamPreview.isEmpty {
                            analysisStatusCard
                        }

                        if !viewModel.items.isEmpty {
                            itemsSection
                            totalsSection
                            saveToLibrarySection
                        } else if !viewModel.isAnalyzing && viewModel.selectedImageData == nil {
                            emptyStateCard
                        }

                        if let error = viewModel.errorMessage ?? viewModel.analysisError ?? cameraError {
                            errorCard(message: error)
                        }

                        if viewModel.canSave {
                            saveButton
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Log your Meal")
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
            .task(id: viewModel.selectedPhotosItem) {
                await viewModel.loadSelectedPhoto()
            }
            .sheet(isPresented: $isShowingLibraryPicker) {
                LibraryMultiSelectSheet { foods, ingredients in
                    viewModel.addLibraryItems(foods)
                    viewModel.addMealIngredients(ingredients)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log your Meal")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Add items from photo, text, or your library.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - Source Buttons

    private var sourceButtons: some View {
        HStack(spacing: 12) {
            // Camera button
            SourceButton(
                icon: "camera.fill",
                label: "Camera",
                isUsed: viewModel.photoUsed,
                isDisabled: viewModel.photoUsed || viewModel.isAnalyzing || viewModel.selectedImageData != nil
            ) {
                openCamera()
            }

            // Gallery button with PhotosPicker
            PhotosPicker(selection: $viewModel.selectedPhotosItem, matching: .images) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(viewModel.photoUsed ? Color(red: 0.8, green: 0.2, blue: 0.6) : Color(.tertiarySystemBackground))
                            .frame(width: 56, height: 56)
                        if viewModel.photoUsed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 22))
                                .foregroundColor(viewModel.isAnalyzing || viewModel.selectedImageData != nil ? .secondary : Color(red: 0.8, green: 0.2, blue: 0.6))
                        }
                    }
                    Text("Gallery")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(viewModel.photoUsed || viewModel.isAnalyzing || viewModel.selectedImageData != nil ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(viewModel.photoUsed || viewModel.isAnalyzing || viewModel.selectedImageData != nil)

            // Text button
            SourceButton(
                icon: "text.bubble.fill",
                label: "Text",
                isUsed: viewModel.textUsed,
                isDisabled: viewModel.textUsed || viewModel.isAnalyzing
            ) {
                withAnimation {
                    isShowingTextInput = true
                }
            }

            // Library button
            SourceButton(
                icon: "book.closed.fill",
                label: "Library",
                isUsed: false,
                isDisabled: viewModel.isAnalyzing
            ) {
                isShowingLibraryPicker = true
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Photo Preview Section

    private var photoPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photo")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.clearPhoto()
                } label: {
                    Text("Remove")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }

            if let imageData = viewModel.selectedImageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Toggle("This is a nutrition label", isOn: $viewModel.isLabelPhoto)
                .font(.subheadline)
                .tint(.blue)
                .onChange(of: viewModel.isLabelPhoto) { _, isOn in
                    viewModel.handleLabelToggle(isOn)
                }

            if viewModel.isLabelPhoto {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Grams eaten (optional)", text: $viewModel.labelGramsText)
                        .keyboardType(.decimalPad)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: viewModel.labelGramsText) { _, _ in
                            viewModel.applyLabelScaling()
                        }

                    Text("If left empty, totals stay per 100g.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.isLabelPhoto {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Edit label macros")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(spacing: 10) {
                        MacroEditField(label: "Calories", value: $viewModel.labelCaloriesText) {
                            viewModel.applyManualLabelEdits()
                        }
                        MacroEditField(label: "Protein (g)", value: $viewModel.labelProteinText) {
                            viewModel.applyManualLabelEdits()
                        }
                        MacroEditField(label: "Carbs (g)", value: $viewModel.labelCarbsText) {
                            viewModel.applyManualLabelEdits()
                        }
                        MacroEditField(label: "Fat (g)", value: $viewModel.labelFatText) {
                            viewModel.applyManualLabelEdits()
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 12) {
                // Analyze button
                Button {
                    Task {
                        dismissKeyboard()
                        await viewModel.analyzePhoto()
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
                .disabled(viewModel.isAnalyzing)

                if viewModel.isLabelPhoto {
                    Button {
                        dismissKeyboard()
                        viewModel.saveLabelEntry()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                            Text("Save")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color(red: 0.8, green: 0.2, blue: 0.6))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isAnalyzing)
                }
            }
        }
        .modifier(CardModifier())
    }

    // MARK: - Text Input Section

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Describe your meal")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    withAnimation {
                        isShowingTextInput = false
                        viewModel.descriptionText = ""
                    }
                }
                .font(.subheadline)
            }

            PlaceholderTextEditor(
                text: $viewModel.descriptionText,
                placeholder: "E.g., grilled chicken 150g, rice 200g, salad"
            )
            .frame(minHeight: 64, maxHeight: 88)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Include grams for better accuracy.")
                .font(.caption)
                .foregroundColor(.secondary)

            if !viewModel.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task {
                        dismissKeyboard()
                        await viewModel.analyzeText()
                        if viewModel.textUsed {
                            withAnimation {
                                isShowingTextInput = false
                            }
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
                .disabled(viewModel.isAnalyzing)
            }
        }
        .modifier(CardModifier())
    }

    // MARK: - Analysis Status

    private var analysisStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProgressView()
                Text("Analyzing...")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if !viewModel.streamPreview.isEmpty {
                Text(viewModel.streamPreview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach($viewModel.items) { $item in
                    VStack(spacing: 0) {
                        LogItemRow(
                            item: $item,
                            onRemove: {
                                withAnimation {
                                    viewModel.removeItem(id: item.id)
                                }
                            }
                        )

                        if item.id != viewModel.items.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .modifier(CardModifier())
    }

    // MARK: - Totals Section

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total")
                .font(.headline)

            HStack(spacing: 12) {
                MacroBadge(label: "Cal", value: formatMacro(viewModel.totalMacros.calories))
                MacroBadge(label: "P", value: formatMacro(viewModel.totalMacros.protein))
                MacroBadge(label: "C", value: formatMacro(viewModel.totalMacros.carbs))
                MacroBadge(label: "F", value: formatMacro(viewModel.totalMacros.fat))
            }
        }
        .modifier(CardModifier())
    }

    // MARK: - Save to Library Section

    private var saveToLibrarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $viewModel.saveToLibrary) {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(.indigo)
                    Text("Save to Library")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .tint(Color(red: 0.8, green: 0.2, blue: 0.6))

            if viewModel.saveToLibrary {
                TextField("Meal name", text: $viewModel.libraryName)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .modifier(CardModifier())
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No items yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Add items using photo, text, or library above.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .modifier(CardModifier())
    }

    // MARK: - Error Card

    private func errorCard(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task {
                let success = await viewModel.saveLog()
                if success {
                    dismiss()
                }
            }
        } label: {
            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Log")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color(red: 0.8, green: 0.2, blue: 0.6))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(viewModel.isSaving || !viewModel.canSave)
        .padding(.horizontal, 16)
    }

    // MARK: - Camera Handling

    private func openCamera() {
        cameraError = nil
        let status = CameraAccess.checkStatus()
        if let error = status.errorMessage {
            cameraError = error
            return
        }
        isShowingCamera = true
    }

    // MARK: - Helpers

    private func formatMacro(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Source Button

private struct SourceButton: View {
    let icon: String
    let label: String
    let isUsed: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 56, height: 56)
                    if isUsed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(iconColor)
                    }
                }
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isDisabled ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var backgroundColor: Color {
        if isUsed {
            return Color(red: 0.8, green: 0.2, blue: 0.6)
        }
        return Color(.tertiarySystemBackground)
    }

    private var iconColor: Color {
        if isDisabled {
            return .secondary
        }
        return Color(red: 0.8, green: 0.2, blue: 0.6)
    }
}

// MARK: - Log Item Row

private struct LogItemRow: View {
    @Binding var item: LogItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(item.source.label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                // Grams input
                HStack(spacing: 4) {
                    TextField("0", text: $item.gramsText)
                        .keyboardType(.decimalPad)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("g")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                // Macros display
                HStack(spacing: 8) {
                    Text("\(Int(item.macros.calories)) cal")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("P \(Int(item.macros.protein))")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("C \(Int(item.macros.carbs))")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("F \(Int(item.macros.fat))")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Macro Badge

private struct MacroBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Macro Edit Field

private struct MacroEditField: View {
    let label: String
    @Binding var value: String
    var onChange: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            TextField("", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: value) { _, _ in
                    onChange()
                }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Card Modifier

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

// MARK: - Placeholder Text Editor

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
