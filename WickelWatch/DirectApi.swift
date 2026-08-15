import Foundation
@preconcurrency import Security

enum DirectApiError: LocalizedError {
  /// Der Server war nicht erreichbar — es wurde garantiert nichts gesendet.
  /// Der Aufrufer darf gefahrlos auf den Weg über das iPhone ausweichen.
  case unreachable(String)
  /// Der Server hat geantwortet, aber mit einem Fehler — oder die Antwort war
  /// unbrauchbar. Hier darf **nicht** über das iPhone wiederholt werden: die
  /// Anfrage könnte bereits ausgeführt worden sein.
  case response(String)

  var errorDescription: String? {
    switch self {
    case .unreachable(let text): return text
    case .response(let text): return text
    }
  }
}

/// Der vom Server gemeldete Stand — dasselbe, was das iPhone sonst per
/// `applicationContext` spiegelt.
struct DirectSnapshot {
  let lastType: WickelType?
  let lastTime: Date?
  let lastStoffwindel: Bool
  let todayTotal: Int

  /// Liest die Antwort von `?action=stats`; Aufbau wie `WickelStats.fromJson`
  /// in `lib/models.dart`.
  init(_ json: [String: Any]) {
    let last = json["last"] as? [String: Any]
    lastType = (last?["type"] as? String).flatMap { WickelType(rawValue: $0.lowercased()) }
    lastTime = (last?["time"] as? String).flatMap(DirectSnapshot.parseDate)
    lastStoffwindel = last?["stoffwindel"] as? Bool ?? false
    todayTotal = (json["today"] as? [String: Any])?["total"] as? Int ?? 0
  }

  /// Die `api.php` liefert den Zeitstempel als `2026-08-10 14:30:00` (SQLite,
  /// ohne Zone), je nach Aufbau aber auch als ISO-8601. Dart nimmt beides über
  /// `DateTime.parse` entgegen — hier ebenso, zonenlose Angaben gelten als
  /// lokale Zeit.
  static func parseDate(_ text: String) -> Date? {
    if let date = isoFractional.date(from: text) { return date }
    if let date = iso.date(from: text) { return date }
    return sqlTimestamp.date(from: text)
  }

  // (ISO8601-)DateFormatter sind laut Apple-Doku thread-sicher.
  nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let sqlTimestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = .current
    return formatter
  }()
}

/// Spricht die Wickel-Tracker-API (`<baseURL>api.php?action=…`) direkt von der
/// Uhr aus — mit derselben Basis-URL und denselben Zugangsdaten wie die
/// iPhone-App.
final class DirectApi: NSObject, Sendable {

  private let connection: ServerConnection
  private let identity: SecIdentity?

  // Im init erzeugt (delegate braucht self) und danach nie mehr geschrieben;
  // lazy wäre bei parallelen Erst-Requests nicht threadsicher.
  nonisolated(unsafe) private var session: URLSession!

  /// Wirft, wenn das Client-Zertifikat nicht verwendbar ist — dadurch fällt
  /// das schon beim Import auf und nicht erst beim Speichern eines Eintrags.
  init(connection: ServerConnection) throws {
    self.connection = connection
    if connection.isMutualTLS, let cert = connection.clientCertPEM,
      let key = connection.clientKeyPEM
    {
      identity = try ClientIdentity.make(certPEM: cert, keyPEM: key)
    } else {
      identity = nil
    }
    super.init()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.waitsForConnectivity = false
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }

  func close() {
    session.finishTasksAndInvalidate()
  }

  // MARK: - Aktionen

  /// Legt einen Eintrag an. Einen Zeit-Parameter kennt `?action=wickeln`
  /// nicht (`time DEFAULT CURRENT_TIMESTAMP`) — es zählt der Zeitpunkt der
  /// Übertragung, genau wie beim Weg über das iPhone.
  func addEntry(type: WickelType, stoffwindel: Bool) async throws {
    _ = try await send(
      "POST", action: "wickeln",
      body: ["typ": type.rawValue, "stoffwindel": stoffwindel])
  }

  /// Aktueller Stand (letzter Eintrag + Anzahl von heute).
  func stats() async throws -> DirectSnapshot {
    DirectSnapshot(try await send("GET", action: "stats", body: nil))
  }

  // MARK: - Transport

  private func send(_ method: String, action: String, body: [String: Any]?) async throws
    -> [String: Any]
  {
    guard var components = URLComponents(string: connection.baseURL + "api.php") else {
      throw DirectApiError.response("Ungültige API-URL: \(connection.baseURL)")
    }
    components.queryItems = [URLQueryItem(name: "action", value: action)]
    guard let url = components.url else {
      throw DirectApiError.response("Ungültige API-URL: \(connection.baseURL)")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let apiKey = connection.apiKey {
      request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw DirectApi.classify(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw DirectApiError.response("Unerwartete Antwort des Servers.")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw DirectApiError.response("Fehler \(http.statusCode): \(DirectApi.message(from: data))")
    }
    if data.isEmpty { return [:] }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw DirectApiError.response("Unerwartete Antwort des Servers.")
    }
    return json
  }

  /// Nur Fehler, bei denen die Verbindung nachweislich nie zustande kam,
  /// gelten als „ausweichen erlaubt“. Alles Mehrdeutige (Timeout, Abbruch
  /// mitten in der Übertragung) wird gemeldet, statt es zu wiederholen.
  private static func classify(_ error: Error) -> DirectApiError {
    guard let urlError = error as? URLError else {
      return .response(error.localizedDescription)
    }
    switch urlError.code {
    case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
      .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
      .secureConnectionFailed, .serverCertificateUntrusted,
      .serverCertificateHasBadDate, .serverCertificateNotYetValid,
      .serverCertificateHasUnknownRoot, .clientCertificateRejected,
      .clientCertificateRequired:
      return .unreachable(urlError.localizedDescription)
    default:
      return .response(urlError.localizedDescription)
    }
  }

  /// Zieht `{"error": "..."}` heraus bzw. kürzt eine HTML-Fehlerseite.
  private static func message(from data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = json["error"] as? String, !text.isEmpty
    {
      return text
    }
    let text = String(data: data, encoding: .utf8) ?? ""
    let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if clean.isEmpty { return "Anfrage fehlgeschlagen" }
    return clean.count > 120 ? String(clean.prefix(120)) + "…" : clean
  }
}

extension DirectApi: URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate,
      let identity
    else {
      // Server-Zertifikat weiterhin normal gegen den System-Trust-Store prüfen.
      completionHandler(.performDefaultHandling, nil)
      return
    }
    let credential = URLCredential(
      identity: identity, certificates: nil, persistence: .forSession)
    completionHandler(.useCredential, credential)
  }
}
