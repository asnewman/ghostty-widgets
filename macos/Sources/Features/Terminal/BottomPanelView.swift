import SwiftUI

/// Container model and state for the Ghostty widget bottom panel (chin).
final class BottomPanelModel: ObservableObject {
    @Published var panelHeight: CGFloat = 32
    @Published var pwd: String?
}

/// The SwiftUI bottom panel component ("chin") embedded below Ghostty's terminal view.
struct BottomPanelView: View {
    @ObservedObject var model: BottomPanelModel
    @StateObject private var gitModel = GitBranchModel()

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            GitBranchWidget(model: gitModel)

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: model.panelHeight)
        .background(.ultraThinMaterial)
        .onChange(of: model.pwd) { newPwd in
            gitModel.update(for: newPwd)
        }
        .onAppear {
            gitModel.update(for: model.pwd)
        }
    }
}
