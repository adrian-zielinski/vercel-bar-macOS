import SwiftUI
import VercelBarKit

/// Jeden wiersz projektu w popoverze.
struct ProjectRowView: View {
    let project: Project
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var flash = false

    private var deploy: DeploymentSummary? { project.latest }
    private var isError: Bool { deploy?.state == .error }
    private var isBuilding: Bool { deploy?.state == .building || deploy?.state == .initializing }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    badge
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(deploy?.branch ?? "—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(deploy?.commitMessage ?? "brak danych o commicie")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if isBuilding { progressBar.padding(.top, 5) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text((deploy?.createdAt).map { Format.relative($0) } ?? "")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    durationLabel
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(hovered ? 1 : 0)
                    .offset(x: hovered ? 0 : -6)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 8))
        .background(rowBackground)
        .overlay( // rozbłysk Building → Ready
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: Theme.successFlash))
                .opacity(flash ? 1 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 5)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { open() }
        .onChange(of: deploy?.state) { old, new in
            guard !reduceMotion, old == .building || old == .initializing, new == .ready else { return }
            withAnimation(.spring(duration: 0.12, bounce: 0.3)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.easeOut(duration: 0.3)) { flash = false }
            }
        }
    }

    private var badge: some View {
        Text(badgeLabel)
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, 5.5).padding(.vertical, 1.5)
            .background(Color(nsColor: badgeBg))
            .foregroundStyle(Color(nsColor: badgeFg))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .id(badgeLabel) // wymusza przejście przy zmianie stanu
            .transition(reduceMotion ? .identity :
                .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                            removal: .opacity))
    }

    private var badgeLabel: String {
        switch deploy?.state {
        case .ready: "Ready"
        case .error: "Error"
        case .building, .initializing: "Building"
        case .canceled: "Canceled"
        case .unknown: "—"
        default: "Queued"
        }
    }

    private var badgeFg: NSColor {
        switch deploy?.state {
        case .ready: Theme.ready
        case .error: Theme.error
        case .building, .initializing: Theme.building
        default: Theme.badgeQueuedFg
        }
    }

    private var badgeBg: NSColor {
        switch deploy?.state {
        case .ready: Theme.badgeReadyBg
        case .error: Theme.badgeErrorBg
        case .building, .initializing: Theme.badgeBuildingBg
        default: Theme.badgeQueuedBg
        }
    }

    @ViewBuilder private var durationLabel: some View {
        if let text = durationText {
            HStack(spacing: 3) {
                Image(systemName: "stopwatch").font(.system(size: 7.5))
                Text(text).monospacedDigit()
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
    }

    private var durationText: String? {
        guard let deploy else { return nil }
        if let done = deploy.duration { return Format.duration(done) }
        if isBuilding, let start = deploy.buildingAt ?? deploy.createdAt {
            return Format.duration(Date().timeIntervalSince(start))
        }
        return nil
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(isError
                  ? Color(nsColor: hovered ? Theme.rowErrorHoverBg : Theme.rowErrorBg)
                  : Color.primary.opacity(hovered ? 0.045 : 0))
            .overlay {
                if isError {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color(nsColor: Theme.rowErrorRing), lineWidth: 0.5)
                }
            }
    }

    /// Pasek postępu (nieokreślony) przy buildzie — jak w makiecie: 34 % szerokości, przelot 1,5 s.
    private var progressBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if reduceMotion {
                    Capsule().fill(Color(nsColor: Theme.building)).frame(width: w * 0.34)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.5) / 1.5
                        Capsule()
                            .fill(Color(nsColor: Theme.building))
                            .frame(width: w * 0.34)
                            .offset(x: (w * 1.34) * t - w * 0.34)
                    }
                }
            }
        }
        .frame(height: 2)
        .clipShape(Capsule())
    }

    private func open() {
        guard let url = deploy?.inspectorURL ?? deploy?.previewURL else { return }
        NSWorkspace.shared.open(url)
    }
}
