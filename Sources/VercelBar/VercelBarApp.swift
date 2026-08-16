import SwiftUI
import VercelBarKit

/// Teksty wędrują przez Environment, a nie przez `L10n()` w każdym widoku — dzięki temu
/// zmiana języka w Ustawieniach przerysowuje całe UI od razu, bez restartu aplikacji.
private struct L10nKey: EnvironmentKey {
    // Obie sceny wstrzykują własny `L10n`, więc to tylko asekuracja — ale i ona
    // ma respektować wybór z Ustawień, a nie ślepo iść za systemem.
    static let defaultValue = L10n(lang: .effective(override: SettingsStore().languageOverride))
}

extension EnvironmentValues {
    var l10n: L10n {
        get { self[L10nKey.self] }
        set { self[L10nKey.self] = newValue }
    }
}

@main
struct VercelBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .environment(\.l10n, L10n(lang: model.lang))
                .onAppear { model.start() }
        } label: {
            StatusIconLabel(state: model.iconState, pulsing: model.shouldPulse)
                .onAppear { model.start() } // etykieta renderuje się od razu — pętla rusza bez klikania
        }
        .menuBarExtraStyle(.window)

        // Tytuł sceny czyta `model.lang`, ale AppKit potrafi go zapamiętać przy tworzeniu
        // okna — po przełączeniu języka nazwa w pasku okna może zostać do restartu.
        Window(L10n(lang: model.lang).settingsWindowTitle, id: "settings") {
            SettingsView(model: model)
                .environment(\.l10n, L10n(lang: model.lang))
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Jedna NSImage na stan. Puls to `opacity` w TimelineView (8 FPS), bez alokacji trójkąta
/// i bez `@Published` na całym AppModel co 100 ms.
private struct StatusIconLabel: View {
    let state: AggregateState
    let pulsing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let image = StatusIconRenderer.image(state: state)
        if pulsing && !reduceMotion {
            TimelineView(.periodic(from: .now, by: StatusIconRenderer.pulseFrameInterval)) { context in
                Image(nsImage: image)
                    .opacity(StatusIconRenderer.pulseAlpha(
                        phase: StatusIconRenderer.pulsePhase(at: context.date)))
                    .id(colorScheme)
            }
        } else {
            Image(nsImage: image)
                .id(colorScheme)
        }
    }
}
