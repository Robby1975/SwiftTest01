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

struct NotizRequest: Codable {
    let userID: String
    let notiz: String
}


struct NotizResponse: Codable {
    let id: String
    let userID: String
    let notiz: String?
    let aktiv: Bool
    let letzteAktualisierung: Date   // wir parsen das ISO-Datum -> Date
}

enum APIError: LocalizedError {
    case invalidURL
    case badStatus(Int, String)
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Die URL ist ungültig."
        case .badStatus(let code, let body): return "Serverfehler (\(code)): \(body)"
        case .noData: return "Keine Daten vom Server erhalten."
        }
    }
}



enum SchulessenAPIError: Error {
    case ungültigeURL
    case unerwarteterStatusCode(Int)
}

final class SchulessenAPI {
    private let baseURL = URL(string: "https://schulessenapi.itsrs.de")!
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    /// Decoder, der ISO-8601 mit/ohne Millisekunden versteht
    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        
        // Erst versuchen mit Millisekunden …
        let isoFormatterMS = ISO8601DateFormatter()
        isoFormatterMS.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // … dann ohne Millisekunden.
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = isoFormatterMS.date(from: str) { return d }
            if let d = isoFormatter.date(from: str) { return d }
            // Falls der Server mal ein anderes Format liefert:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültiges ISO-Datum: \(str)")
        }
        return decoder
    }()
    
    /// Holt **eine** Notiz für einen Benutzer (falls Endpoint ein Objekt liefert)
    func fetchNotiz(userID: String) async throws -> NotizResponse {
        var url = baseURL
        url.append(path: "/notizen/\(userID)")
        // Alternativ per URLComponents bauen, wenn userID evtl. Sonderzeichen enthält
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SchulessenAPIError.unerwarteterStatusCode(code)
        }
        return try Self.jsonDecoder.decode(NotizResponse.self, from: data)
    }
    
    /// Holt **mehrere** Notizen (falls Endpoint eine Liste liefert)
    func fetchNotizen(userID: String) async throws -> [NotizResponse] {
        var url = baseURL
        url.append(path: "/notizen/\(userID)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SchulessenAPIError.unerwarteterStatusCode(code)
        }
        return try Self.jsonDecoder.decode([NotizResponse].self, from: data)
    }
}



// MARK: - Notiz Service (async/await)
final class NotizService {
    private let endpoint = "https://schulessenapi.itsrs.de/notizen"
    
    /// ISO8601 mit Millisekunden (z. B. 2025-08-20T11:02:50.747)
    private static let iso8601ms: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Custom Date-Decoding für ISO8601 + fractional seconds
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = NotizService.iso8601ms.date(from: str) {
                return d
            }
            // Fallback ohne Millisekunden
            let plain = ISO8601DateFormatter()
            if let d2 = plain.date(from: str) {
                return d2
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültiges Datumsformat: \(str)")
        }
        return decoder
    }
    
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // (Optional) schön fürs Debuggen
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
    
    // Erstellt eine Notiz REST API CALL (POST /notizen)
    func createNotiz(userID: String, notiz: String) async throws -> NotizResponse {
        guard let url = URL(string: endpoint) else { throw APIError.invalidURL }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Falls nötig, hier z. B. ein Token setzen:
        // req.setValue("Bearer <token>", forHTTPHeaderField: "Authorization")
        
        let body = NotizRequest(userID: userID , notiz: notiz)
        req.httpBody = try makeEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.noData }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<leer>"
            throw APIError.badStatus(http.statusCode, text)
        }
        return try makeDecoder().decode(NotizResponse.self, from: data)
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
    var token: String { storedToken }

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
        
        
        let api = SchulessenAPI()

        Task {
            do {
                // Falls der Endpoint EIN Objekt liefert:
                //let notiz: NotizResponse = try await api.fetchNotiz(userID: "robert")
                //print(notiz)

                // Falls der Endpoint eine LISTE liefert:
                let notizen: [NotizResponse] = try await api.fetchNotizen(userID: "robert")
                print(notizen)
            } catch {
                print("Fehler: \(error)")
            }
        }

        
        
    }

    func logout() {
        storedToken = ""
        username = ""
        password = ""
        errorText = nil
    }
    
    var subject: String? { JWT.subjectIfAny(from: token) }
    
    private struct JWTClaims: Decodable {
        let sub: String?
    }

    enum JWT {
        enum JWTError: Error {
            case malformedToken
            case badBase64
            case badJSON
            case missingSubject
        }

        /// Liest das "sub"-Claim (Subject) aus einem JWT oder "Bearer <jwt>".
        static func subject(from token: String) throws -> String {
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = cleaned.hasPrefix("Bearer ") ? String(cleaned.dropFirst(7)) : cleaned

            let parts = raw.split(separator: ".")
            guard parts.count >= 2 else { throw JWTError.malformedToken }

            let payloadB64URL = String(parts[1])
            guard let payloadData = base64URLDecode(payloadB64URL) else { throw JWTError.badBase64 }

            let claims = try JSONDecoder().decode(JWTClaims.self, from: payloadData)
            guard let sub = claims.sub, !sub.isEmpty else { throw JWTError.missingSubject }
            return sub
        }

        /// Bequeme, nicht-werfende Variante.
        static func subjectIfAny(from token: String) -> String? {
            return (try? subject(from: token))
        }

        // MARK: - Base64URL → Data
        private static func base64URLDecode(_ s: String) -> Data? {
            var str = s.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
            // Padding auf Vielfaches von 4
            let pad = 4 - (str.count % 4)
            if pad < 4 { str.append(String(repeating: "=", count: pad)) }
            return Data(base64Encoded: str)
        }
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
        var myID=UUID()
        
        
        let service = NotizService()

        Task {
            do {
                let res = try await service.createNotiz(
                    userID: auth.subject ?? "",
                    notiz: trimmed
                )
                print("✅ Notiz erstellt:", res)
                print("Aktualisiert am:", res.letzteAktualisierung)
            } catch {
                print("❌ Fehler:", error.localizedDescription)
            }
        }
        withAnimation { days.append(DayItem(id: myID, name: trimmed)) }
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
            .navigationTitle("Notiz bearbeiten")
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
