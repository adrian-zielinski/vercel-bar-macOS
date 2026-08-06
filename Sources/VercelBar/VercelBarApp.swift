import SwiftUI
import VercelBarKit

@main
struct VercelBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .onAppear { model.start() }
        } label: {
            Image(nsImage: StatusIconRenderer.image(state: model.iconState,
                                                    alpha: model.iconAlpha))
                .onAppear { model.start() } // etykieta renderuje się od razu — pętla rusza bez klikania
        }
        .menuBarExtraStyle(.window)

        Window("Ustawienia VercelBar", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
