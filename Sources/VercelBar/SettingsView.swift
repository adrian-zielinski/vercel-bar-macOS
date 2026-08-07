import SwiftUI
import ServiceManagement
import VercelBarKit

/// Okno ustawień 480×380: zakładki Konto/Projekty + stopka z przełącznikami.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    enum Tab: String, CaseIterable {
        case konto = "Konto"
        case projekty = "Projekty"
    }

    @State private var tab: Tab = .konto
    @State private var tokenField = ""
    @State private var connectProblem: AppModel.ConnectResult?
    @State private var search = ""
    @State private var launchAtLogin = SettingsView.loginItemRegistered()
    @State private var notifySuccess = true
    @State private var notifyFailure = true
    @State private var loginItemNeedsApproval = SMAppService.mainApp.status == .requiresApproval

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .padding(.top, 12)

            Group {
                switch tab {
                case .konto: kontoTab
                case .projekty: projektyTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22))

            Divider()
            togglesFooter
        }
        .frame(width: 480, height: 380)
        .onAppear {
            notifySuccess = model.settings.notifySuccess
            notifyFailure = model.settings.notifyFailure
            Task { await model.loadAllProjects() }
        }
    }

    // MARK: zakładka Konto

    private var kontoTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(label: "Token dostępu") {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        SecureField(model.hasToken ? "••••••••••••••••••••" : "wklej token…",
                                    text: $tokenField)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            // Czerwona podpowiedź dotyczy tokenu, który właśnie zniknął z pola.
                            .onChange(of: tokenField) { _, _ in connectProblem = nil }
                            .onSubmit { saveToken() }
                        Button("Zapisz") { saveToken() }
                            .disabled(tokenField.isEmpty)
                    }
                    Text(tokenHint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(connectProblem == nil ? Color.secondary : Color(nsColor: Theme.error))
                }
            }

            row(label: "Połączenie") {
                HStack(spacing: 9) {
                    Circle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 26, height: 26)
                        .overlay(Text(initials)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.account?.name ?? model.account?.username ?? "Nie połączono")
                            .font(.system(size: 12.5, weight: .semibold))
                        HStack(spacing: 4) {
                            Circle()
                                .fill(model.account != nil
                                      ? Color(nsColor: Theme.ready) : Color.secondary)
                                .frame(width: 6, height: 6)
                            Text(model.account != nil ? "Połączono" : "Wklej token powyżej")
                                .font(.system(size: 10.5))
                                .foregroundStyle(model.account != nil
                                                 ? Color(nsColor: Theme.ready) : .secondary)
                        }
                    }
                }
            }

            row(label: "Zespół") {
                Picker("", selection: Binding(
                    get: { model.settings.teamID ?? "" },
                    set: { model.selectTeam(id: $0.isEmpty ? nil : $0) }
                )) {
                    Text("Konto osobiste").tag("")
                    // Zanim lista zespołów dojedzie, Picker bez tej pozycji cofnąłby
                    // zaznaczenie na „Konto osobiste" i skłamał o zakresie.
                    if let current = model.settings.teamID,
                       !model.teams.contains(where: { $0.id == current }) {
                        Text("Zespół (\(String(current.prefix(12)))…)").tag(current)
                    }
                    ForEach(model.teams) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 196)
            }
        }
    }

    private var tokenHint: String {
        switch connectProblem {
        case .rejected: "Vercel odrzucił ten token. Sprawdź, czy skopiowany w całości."
        case .network: "Brak połączenia z Vercelem. Sprawdź internet i spróbuj ponownie."
        case .keychainFailure: "Token poprawny, ale zapis w pęku kluczy się nie powiódł. Otwórz Keychain Access i sprawdź dostęp."
        case .unexpectedResponse: "Vercel odpowiedział w nieoczekiwanym formacie — to problem aplikacji, nie tokenu. Zgłoś to autorowi."
        default: "Token z panelu Vercela → Account Settings → Tokens. Zakres (scope): konto lub zespół, który chcesz obserwować."
        }
    }

    private func saveToken() {
        guard !tokenField.isEmpty else { return }
        Task {
            let result = await model.connect(token: tokenField)
            connectProblem = result == .ok ? nil : result
            if result == .ok { tokenField = "" }
        }
    }

    private var initials: String {
        let source = model.account?.name ?? model.account?.username ?? "?"
        let parts = source.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private func row<Content: View>(label: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .trailing)
                .padding(.top, 4)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: zakładka Projekty

    private var projektyTab: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                TextField("Szukaj projektów", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Text(countLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            List(filteredProjects) { project in
                Toggle(isOn: Binding(
                    get: { model.settings.watchedProjectIDs.contains(project.id) },
                    set: { _ in model.toggleWatched(projectID: project.id) }
                )) {
                    Text(project.name).font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.bordered)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.allProjects.isEmpty {
                    Text(emptyListMessage)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Pusta lista znaczy co innego przed połączeniem, co innego bez sieci, a co innego w trakcie wczytywania.
    private var emptyListMessage: String {
        if !model.hasToken { return "Połącz konto w zakładce Konto." }
        if model.phase == .offline { return "Brak połączenia z Vercelem." }
        return "Wczytywanie projektów…"
    }

    /// Zanim lista dojedzie, „3 z 0 projektów monitorowanych" zestawia trwałe ID z pustką.
    private var countLabel: String {
        guard !model.allProjects.isEmpty else { return "" }
        // Zaznaczenia z innego zespołu zostają w ustawieniach — licz przecięcie z widoczną
        // listą, inaczej N zawyża i potrafi przebić M.
        let watched = model.allProjects.filter { model.settings.watchedProjectIDs.contains($0.id) }.count
        return "\(watched) z \(model.allProjects.count) projektów monitorowanych"
    }

    private var filteredProjects: [Project] {
        guard !search.isEmpty else { return model.allProjects }
        return model.allProjects.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    // MARK: stopka z przełącznikami

    private var togglesFooter: some View {
        VStack(spacing: 4) {
            footerToggle("Uruchamiaj przy logowaniu", isOn: $launchAtLogin)
            footerToggle("Powiadamiaj o sukcesach", isOn: $notifySuccess)
            footerToggle("Powiadamiaj o błędach", isOn: $notifyFailure)
            if loginItemNeedsApproval {
                Text("Zatwierdź w Ustawieniach systemowych → Elementy logowania")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 22, bottom: 14, trailing: 22))
        .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
        .onChange(of: notifySuccess) { _, on in model.settings.notifySuccess = on }
        .onChange(of: notifyFailure) { _, on in model.settings.notifyFailure = on }
    }

    private func footerToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(label)
        }
        .frame(height: 27)
    }

    /// Element czekający na zatwierdzenie JEST zarejestrowany — suwak ma to pokazywać,
    /// inaczej stoi na OFF obok podpowiedzi „zatwierdź w Ustawieniach systemowych".
    private static func loginItemRegistered() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // SMAppService działa tylko w bundlu .app; przy `swift run` cicho ignorujemy.
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                // Rejestracja się udała, ale macOS trzyma element wyłączony do czasu
                // zatwierdzenia przez użytkownika — bez podpowiedzi wygląda na awarię.
                loginItemNeedsApproval = SMAppService.mainApp.status == .requiresApproval
            } else {
                try SMAppService.mainApp.unregister()
                loginItemNeedsApproval = false
            }
        } catch {
            launchAtLogin = Self.loginItemRegistered()
            loginItemNeedsApproval = false
        }
    }
}
