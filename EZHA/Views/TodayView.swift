import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @State private var isPresentingAddLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Today's Progress")
                        .font(.title2.weight(.semibold))
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        MacroProgressTable(
                            targets: viewModel.targets,
                            eaten: viewModel.totals
                        )
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                    Button {
                        isPresentingAddLog = true
                    } label: {
                        Label("Add log", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Today")
        }
        .sheet(isPresented: $isPresentingAddLog) {
            AddLogSheet()
        }
        .task {
            await viewModel.loadToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .foodEntrySaved)) { _ in
            Task {
                await viewModel.loadToday()
            }
        }
    }
}
