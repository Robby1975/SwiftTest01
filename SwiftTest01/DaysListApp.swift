// DaysListApp.swift
// Mit Login davor und REST-Aufruf getAccess(username, password)

import SwiftUI

// MARK: - Auth / Networking

struct AuthResponse: Decodable {
    let access: Bool
    let token: String?
    let message: String?
}

enum AuthError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case serverMessage(String)
    case decoding
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige Server-URL."
        case .badStatus(let code): return "Anmeldung unbekannt (\(code))."
        case .serverMessage(let msg): return msg
        case .decoding: return "Antwort konnte nicht gelesen werden."
        case .unknown: return "Unbekannter Fehler."
        }
    }
}

struct AuthAPI {
    /// <#Ersetze#> durch deine echte Basis-URL, z. B. "https://api.example.com"
    static let BASE_URL = "https://schulessenapi.itsrs.de"

    /// Ruft /getAccess als POST auf. Erwartet JSON: { username, password }
    static func getAccess(username: String, password: String) async throws -> String {
        guard let url = URL(string: "\(BASE_URL)/getAccess") else { throw AuthError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["username": username, "password": password]
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.unknown }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.badStatus(http.statusCode) }

        do {
            let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
            if decoded.access, let token = decoded.token, !token.isEmpty {
                return token
            } else {
                throw AuthError.serverMessage(decoded.message ?? "Zugang verweigert.")
            }
        } catch {
            throw AuthError.decoding
        }
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorText: String?

    @AppStorage("authToken") private var storedToken: String = ""
    var isAuthenticated: Bool { !storedToken.isEmpty }

    func login() async {
        errorText = nil
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else {
            errorText = "Bitte Benutzername und Passwort eingeben."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await AuthAPI.getAccess(username: username, password: password)
            storedToken = token
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Login fehlgeschlagen."
        }
    }

    func logout() {
        storedToken = ""
        username = ""
        password = ""
        errorText = nil
    }
}

// MARK: - App Entry

@main
struct DaysListApp: App {
    @StateObject private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            if authVM.isAuthenticated {
                ContentView()
                    .environmentObject(authVM)
            } else {
                LoginView()
                    .environmentObject(authVM)
            }
        }
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @FocusState private var focusedField: Field?

    enum Field { case user, pass }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Benutzername", text: $auth.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .user)
                        .onSubmit { focusedField = .pass }

                    SecureField("Passwort", text: $auth.password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .pass)
                        .onSubmit { Task { await auth.login() } }
                }
                .textFieldStyle(.roundedBorder)

                if let msg = auth.errorText {
                    Text(msg)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                Button {
                    Task { await auth.login() }
                } label: {
                    if auth.isLoading {
                        ProgressView().padding(.vertical, 6)
                    } else {
                        Text("Anmelden")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isLoading || auth.username.trimmingCharacters(in: .whitespaces).isEmpty || auth.password.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Anmeldung")
        }
    }
}

// MARK: - Dein bestehender Content

struct DayItem: Identifiable, Equatable {
    let id: UUID
    var name: String
}

struct ContentView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var days: [DayItem] = [
        DayItem(id: UUID(), name: "Montag"),
        DayItem(id: UUID(), name: "Dienstag"),
        DayItem(id: UUID(), name: "Mittwoch"),
        DayItem(id: UUID(), name: "Donnerstag"),
        DayItem(id: UUID(), name: "Freitag"),
        DayItem(id: UUID(), name: "Samstag"),
        DayItem(id: UUID(), name: "Sonntag")
    ]

    @State private var itemToEdit: DayItem? = nil
    @State private var addingNewItem = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(days) { item in
                    Text(item.name)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                itemToEdit = item
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                }
            }
            .navigationTitle("Notizliste")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Logout") { auth.logout() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(action: { addingNewItem = true }) {
                        Label("Neuer Eintrag", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $itemToEdit) { item in
                EditDayView(
                    initialText: item.name,
                    onCancel: { itemToEdit = nil },
                    onSave: { newName in
                        update(item: item, with: newName)
                        itemToEdit = nil
                    }
                )
            }
            .sheet(isPresented: $addingNewItem) {
                EditDayView(
                    initialText: "",
                    onCancel: { addingNewItem = false },
                    onSave: { newName in
                        addNew(name: newName)
                        addingNewItem = false
                    }
                )
            }
        }
    }

    private func delete(_ item: DayItem) {
        if let idx = days.firstIndex(where: { $0.id == item.id }) {
            withAnimation { days.remove(at: idx) }
        }
    }

    private func update(item: DayItem, with newName: String) {
        guard let idx = days.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        days[idx].name = trimmed
    }

    private func addNew(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation { days.append(DayItem(id: UUID(), name: trimmed)) }
    }
}

struct EditDayView: View {
    @State private var text: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    init(initialText: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self._text = State(initialValue: initialText)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Bezeichnung", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { onSave(text) }

                Spacer()
            }
            .padding()
            .navigationTitle("Bezeichnung bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    // Zum Testen: setze ein Dummy-Token, um direkt ContentView zu sehen
    ContentView().environmentObject(AuthViewModel())
}
