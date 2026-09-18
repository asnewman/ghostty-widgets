import SwiftUI

/// Container model and state for the Ghostty widget bottom panel (chin).
final class BottomPanelModel: ObservableObject {
    @Published var panelHeight: CGFloat = 80
}

/// The SwiftUI bottom panel component ("chin") embedded below Ghostty's terminal view.
struct BottomPanelView: View {
    @ObservedObject var model: BottomPanelModel

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: model.panelHeight)
        .background(.ultraThinMaterial)
    }
}
