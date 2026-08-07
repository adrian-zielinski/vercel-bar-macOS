import SwiftUI
import VercelBarKit

/// Zawartość okna MenuBarExtra: nagłówek, lista wierszy albo wariant specjalny, stopka.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    /// Puls kropki nagłówka żyje lokalnie — `model.iconAlpha` zostaje wyłącznie dla ikony w pasku menu.
    private var pulsing: Bool { model.iconState == .building && !reduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            if model.phase != .onboarding { header; Divider() }
            content
            // Stopka także w onboardingu (odstępstwo od makiety): bez niej nie ma
            // jak wyjść z aplikacji ani otworzyć Ustawień poza jednym przyciskiem.
            Divider()
            footer
        }
        .frame(width: 340)
    }

    // MARK: nagłówek

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: StatusIconRenderer.color(for: model.iconState)))
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing && pulse ? 1.15 : 1)
                .opacity(pulsing ? (pulse ? 1 : 0.55) : 1)
                .animation(pulsing ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true) : nil,
                           value: pulse)
                .onAppear { pulse = pulsing }
                .onChange(of: pulsing) { _, on in pulse = on }
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
            }
        }
    }

    private var onboarding: some View {
        VStack(spacing: 12) {
            TriangleShape()
                .fill(Color(nsColor: Theme.onboardingLogo))
                .frame(width: 26, height: 23)
            Text("Połącz konto Vercela, aby widzieć swoje deploye w pasku menu.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 232)
            actionButton("Połącz z Vercelem")
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
                .lineSpacing(3)
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
                .lineSpacing(3)
                .frame(maxWidth: 236)
            actionButton("Otwórz Ustawienia")
        }
        .padding(EdgeInsets(top: 26, leading: 26, bottom: 24, trailing: 26))
    }

    private var emptyWatched: some View {
        Text("Zaznacz projekty do obserwowania w Ustawieniach.")
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(EdgeInsets(top: 26, leading: 30, bottom: 24, trailing: 30))
    }

    /// Przycisk wiodący wariantów: `.borderedProminent` + `.tint(.primary)` nie daje
    /// makietowej pary czarny/biały, więc kolory bierzemy wprost z Theme.
    private func actionButton(_ title: String) -> some View {
        Button(action: { openSettings() }) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(nsColor: Theme.actionFg))
                .padding(.horizontal, 16).frame(height: 28)
                .background(Color(nsColor: Theme.actionBg))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: stopka

    private var footer: some View {
        HStack(spacing: 2) {
            if model.phase != .onboarding { // bez tokenu nie ma czego odświeżać
                footerButton("Odśwież", system: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
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

    // Listy projektów nie dociągamy tutaj — robi to `SettingsView.onAppear`.
    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Trójkąt logo (proporcje viewBox 26×23 z makiet).
struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Delikatne tło na hover, jak w makiecie stopki.
struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hoverable(configuration: configuration)
    }

    /// `@State` nie działa wiarygodnie w `ButtonStyle` (to nie `View`) — stan mieszka w zagnieżdżonym widoku.
    private struct Hoverable: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: Theme.controlHoverBg))
                        .opacity(hovered || configuration.isPressed ? 1 : 0)
                )
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }
}
