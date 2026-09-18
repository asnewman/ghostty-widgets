import SwiftUI

/// Container model and state for the Ghostty widget side panel.
final class SidePanelModel: ObservableObject {
    @Published var isExpanded: Bool = true
    @Published var panelWidth: CGFloat = 240
}

/// The SwiftUI side panel component embedded alongside Ghostty's terminal view.
struct SidePanelView: View {
    @ObservedObject var model: SidePanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Widgets", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.isExpanded.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Toggle Sidebar")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            // Widget List / Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    WidgetCard(title: "Clock", icon: "clock.fill") {
                        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                            Text(timeline.date, style: .time)
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        }
                    }

                    WidgetCard(title: "Quick Actions", icon: "bolt.fill") {
                        VStack(spacing: 8) {
                            QuickActionButton(title: "Git Status", icon: "arrow.triangle.branch")
                            QuickActionButton(title: "Clear", icon: "trash")
                        }
                    }

                    WidgetCard(title: "System", icon: "cpu") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Memory")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Normal")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
        }
        .frame(width: model.panelWidth)
        .background(.ultraThinMaterial)
    }
}

private struct WidgetCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct QuickActionButton: View {
    let title: String
    let icon: String

    var body: some View {
        Button(action: {}) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .font(.caption)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}
