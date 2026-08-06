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
            SettingsPlaceholderView(model: model) // zastąpione w Tasku 12
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// Tymczasowa zaślepka — Task 12 wstawia właściwe SettingsView.
struct SettingsPlaceholderView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Text("Ustawienia — w budowie").padding(40)
    }
}
