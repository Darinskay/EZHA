import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var logStore: FoodLogStore
    @StateObject private var viewModel = TodayViewModel()
    @State private var isPresentingAddLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Today's Progress")
                        .font(.title2.weight(.semibold))
                    MacroProgressTable(
                        targets: viewModel.targets,
                        eaten: viewModel.eatenTotals(from: logStore)
                    )
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
    }
}
