import SwiftUI
import VercelBarKit

/// Zawartość okna MenuBarExtra: nagłówek, lista wierszy albo wariant specjalny, stopka.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if model.phase != .onboarding { header; Divider() }
            content
            if model.phase != .onboarding { Divider(); footer }
        }
        .frame(width: 340)
    }

    // MARK: nagłówek

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: StatusIconRenderer.color(for: model.iconState)))
                .frame(width: 8, height: 8)
                .opacity(model.overall == .building ? model.iconAlpha : 1)
            Text(headline).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(model.lastRefreshed.map { "odświeżono \(Format.clock($0))" } ?? "")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 10, trailing: 13))
    }

    private var headline: String {
        switch model.phase {
        case .offline: "Brak połączenia"
        case .tokenInvalid: "Token nieprawidłowy"
        default: StatusAggregator.headline(for: model.projects.map { $0.latest?.state ?? .unknown })
        }
    }

    // MARK: treść

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .onboarding: onboarding
        case .offline: offline
        case .tokenInvalid: tokenInvalid
        case .normal:
            if model.projects.isEmpty {
                emptyWatched
            } else {
                VStack(spacing: 0) {
                    ForEach(model.projects) { ProjectRowView(project: $0) }
                }
                .padding(.top, 5).padding(.bottom, 6)
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.3),
                           value: model.projects.map(\.id))
            }
        }
    }

    private var onboarding: some View {
        VStack(spacing: 12) {
            Image(nsImage: StatusIconRenderer.image(state: .idle))
                .resizable().frame(width: 26, height: 23)
                .opacity(0.4)
            Text("Połącz konto Vercela, aby widzieć swoje deploye w pasku menu.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 232)
            Button("Połącz z Vercelem") { openSettings() }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .controlSize(.regular)
        }
        .padding(EdgeInsets(top: 30, leading: 26, bottom: 26, trailing: 26))
    }

    private var offline: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("Brak połączenia z internetem. Wznowię monitorowanie automatycznie.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 236)
        }
        .padding(EdgeInsets(top: 26, leading: 30, bottom: 24, trailing: 30))
    }

    private var tokenInvalid: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("Token dostępu został odrzucony przez Vercela. Wklej nowy w Ustawieniach.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 236)
            Button("Otwórz Ustawienia") { openSettings() }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
        }
        .padding(EdgeInsets(top: 26, leading: 26, bottom: 24, trailing: 26))
    }

    private var emptyWatched: some View {
        Text("Zaznacz projekty do obserwowania w Ustawieniach.")
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(EdgeInsets(top: 26, leading: 30, bottom: 24, trailing: 30))
    }

    // MARK: stopka

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("Odśwież", system: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            footerButton("Ustawienia", system: "gearshape") { openSettings() }
            Spacer()
            footerButton("Zakończ", system: "power") { NSApp.terminate(nil) }
        }
        .padding(EdgeInsets(top: 5, leading: 7, bottom: 6, trailing: 7))
    }

    private func footerButton(_ title: String, system: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: system).font(.system(size: 10))
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(FooterButtonStyle())
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        Task { await model.loadAllProjects() }
    }
}

/// Delikatne tło na hover, jak w makiecie stopki.
struct FooterButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(hovered || configuration.isPressed ? 0.05 : 0)))
            .onHover { hovered = $0 }
    }
}
