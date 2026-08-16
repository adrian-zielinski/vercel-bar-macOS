import SwiftUI
import VercelBarKit

/// Jeden deploy w popoverze — jeden projekt może zajmować kilka wierszy.
struct ProjectRowView: View {
    let entry: RefreshCore.FeedEntry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var flash = false
    @Environment(\.l10n) private var l10n

    private var deploy: DeploymentSummary { entry.deployment }
    private var isError: Bool { deploy.state == .error }
    private var isBuilding: Bool { deploy.state == .building || deploy.state == .initializing }
    private var openURL: URL? { deploy.inspectorURL ?? deploy.previewURL }

    /// Strzałka to obietnica otwarcia — wiersz bez adresów jej nie składa. `.disabled`
    /// załatwiłoby to samo, ale przygasza całą treść i rozjeżdża wiersz z makietą.
    private var showsOpenArrow: Bool { hovered && openURL != nil }

    var body: some View {
        Button(action: open) { rowContent }
            .buttonStyle(.plain)
            .background {
                ZStack {
                    rowBackground
                    // Rozbłysk Building → Ready leży POD treścią, jak `background` w makiecie.
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: Theme.successFlash))
                        .opacity(flash ? 1 : 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 5)
            .onHover { hovered = $0 }
            .accessibilityLabel("\(entry.projectName), \(badgeLabel)")
            .accessibilityValue(accessibilityDetails)
            .accessibilityHint(openURL != nil ? l10n.rowOpensInBrowserHint : "")
            .onChange(of: deploy.state) { old, new in
                guard !reduceMotion, old == .building || old == .initializing, new == .ready else { return }
                // Koperta makiety `vb-flash 420ms`: szczyt przy 28 %, wygaszenie do 420 ms.
                withAnimation(.spring(duration: 0.12, bounce: 0.3)) { flash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.3)) { flash = false }
                }
            }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.projectName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    badge
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(deploy.branch ?? "—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(deploy.commitMessage ?? l10n.noCommitInfo)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if isBuilding {
                    ProgressSweep(reduceMotion: reduceMotion).padding(.top, 5)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(deploy.createdAt.map { Format.relative($0, lang: l10n.lang) } ?? "")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                    durationLabel
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(showsOpenArrow ? 1 : 0)
                    .offset(x: showsOpenArrow ? 0 : -6)
                    .animation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.3),
                               value: showsOpenArrow)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 8))
        .contentShape(Rectangle())
    }

    private var accessibilityDetails: String {
        [deploy.branch, deploy.commitMessage].compactMap { $0 }.joined(separator: ", ")
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
        switch deploy.state {
        case .ready: "Ready"
        case .error: "Error"
        case .building, .initializing: "Building"
        case .canceled: "Canceled"
        case .unknown: "—"
        case .queued: "Queued"
        }
    }

    private var badgeFg: NSColor {
        switch deploy.state {
        case .ready: Theme.ready
        case .error: Theme.error
        case .building, .initializing: Theme.building
        default: Theme.badgeQueuedFg
        }
    }

    private var badgeBg: NSColor {
        switch deploy.state {
        case .ready: Theme.badgeReadyBg
        case .error: Theme.badgeErrorBg
        case .building, .initializing: Theme.badgeBuildingBg
        default: Theme.badgeQueuedBg
        }
    }

    /// Trwający build (i kolejka) tyka co sekundę; zakończony deploy ma stałą wartość.
    @ViewBuilder private var durationLabel: some View {
        if deploy.state.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                durationChip(now: context.date)
            }
        } else {
            durationChip(now: .now)
        }
    }

    @ViewBuilder private func durationChip(now: Date) -> some View {
        if let seconds = deploy.elapsed(at: now) {
            HStack(spacing: 3) {
                Image(systemName: "stopwatch").font(.system(size: 7.5))
                Text(Format.duration(seconds)).monospacedDigit()
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(isError
                  ? Color(nsColor: hovered ? Theme.rowErrorHoverBg : Theme.rowErrorBg)
                  : Color(nsColor: Theme.rowHoverBg).opacity(hovered ? 1 : 0))
            .overlay {
                if isError {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color(nsColor: Theme.rowErrorRing), lineWidth: 0.5)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }

    private func open() {
        guard let url = openURL else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Pasek postępu (nieokreślony) przy buildzie — jak w makiecie: 34 % szerokości, przelot 1,5 s.
/// Osobny widok, żeby `@State sweep` startowało od zera przy każdym wejściu paska.
private struct ProgressSweep: View {
    let reduceMotion: Bool
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: Theme.progressTrack))
                Capsule()
                    .fill(Color(nsColor: Theme.building))
                    .frame(width: w * 0.34)
                    .offset(x: sweep ? w : -w * 0.34)
                    .animation(reduceMotion ? nil
                               : .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                               value: sweep)
            }
            .onAppear { if !reduceMotion { sweep = true } }
        }
        .frame(height: 2)
        .clipShape(Capsule())
    }
}
