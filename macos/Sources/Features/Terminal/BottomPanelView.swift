import SwiftUI

/// Container model and state for the Ghostty widget bottom panel (chin).
final class BottomPanelModel: ObservableObject {
    @Published var panelHeight: CGFloat = 32
    @Published var collapsedHeight: CGFloat = 20
    @Published var isExpanded: Bool = true
    @Published var pwd: String?
}

/// The SwiftUI bottom panel component ("chin") embedded below Ghostty's terminal view.
struct BottomPanelView: View {
    @ObservedObject var model: BottomPanelModel
    @StateObject private var gitModel = GitBranchModel()

    var body: some View {
        Group {
            if model.isExpanded {
                HStack(alignment: .center, spacing: 8) {
                    GitBranchWidget(model: gitModel)

                    Spacer()

                    Button {
                        withAnimation { model.isExpanded = false }
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse widget bar")
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: model.panelHeight)
            } else {
                HStack {
                    Spacer()
                    Button {
                        withAnimation { model.isExpanded = true }
                    } label: {
                        Image(systemName: "chevron.up")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Expand widget bar")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: model.collapsedHeight)
            }
        }
        .background(.ultraThinMaterial)
        .onChange(of: model.pwd) { newPwd in
            gitModel.update(for: newPwd)
        }
        .onAppear {
            gitModel.update(for: model.pwd)
        }
    }
}
