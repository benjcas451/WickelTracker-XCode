import Foundation
import Security

/// Spricht die Wickel-Tracker-API an (`<baseURL>api.php?action=...`).
///
/// Authentifizierung:
///  - mTLS-Client-Zertifikat über [certSource] (Transport-Ebene), und/oder
///  - API-Key über den Header `X-API-Key` ([apiKey]).
///
/// Die api.php verlangt den API-Key in jedem Fall – auch hinter mTLS.
/// Endpunkte und JSON-Felder identisch zur Flutter-/Android-App.
final class ApiService: NSObject, WickelService {

  private let baseURL: String
  private let apiKey: String?
  private let certSource: CertSource?
  // Wird beim ersten Request gesetzt; parallele Erst-Requests erzeugen die
  // Identity schlimmstenfalls doppelt (idempotent, gleicher Keychain-Eintrag).
  nonisolated(unsafe) private var identity: SecIdentity?

  // Im init erzeugt (delegate braucht self) und danach nie mehr geschrieben;
  // lazy wäre bei parallelen Erst-Requests nicht threadsicher.
  nonisolated(unsafe) private var session: URLSession!

  init(baseURL: String, certSource: CertSource? = nil, apiKey: String? = nil) {
    self.baseURL = baseURL
    self.certSource = certSource
    self.apiKey = apiKey
    super.init()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }

  // MARK: - WickelService

  func getStats() async throws -> WickelStats {
    let data = try await send("GET", action: "stats")
    func periode(_ key: String) -> PeriodStats {
      guard let json = data[key] as? [String: Any] else { return .leer }
      func v(_ k: String) -> Int { json[k] as? Int ?? 0 }
      return PeriodStats(
        total: v("total"), urinPct: v("urin"), stuhlgangPct: v("stuhlgang"),
        beidesPct: v("beides"), stoffwindelPct: v("stoffwindelPct"))
    }
    var stats = WickelStats(
      today: periode("today"), week: periode("week"),
      threeWeeks: periode("threeWeeks"), month: periode("month"))
    if let last = data["last"] as? [String: Any], let typ = last["type"] as? String {
      stats.last = LastEntry(
        type: WickelType.fromApi(typ),
        time: (last["time"] as? String).flatMap(IsoZeit.parse),
        stoffwindel: last["stoffwindel"] as? Bool ?? false)
    }
    return stats
  }

  /// `time` wird ignoriert: `POST ?action=wickeln` kennt keinen Zeit-Parameter,
  /// die Spalte `time` hat serverseitig `DEFAULT CURRENT_TIMESTAMP`. Ein von
  /// der Watch offline erfasster Eintrag landet in den Server-Modi also mit
  /// dem Zeitpunkt der Übertragung, nicht dem der Erfassung.
  func addEntry(type: WickelType, stoffwindel: Bool, time: Date?) async throws {
    _ = try await send(
      "POST", action: "wickeln",
      body: ["typ": type.apiValue, "stoffwindel": stoffwindel])
  }

  @discardableResult
  func undoLast() async throws -> Bool {
    do {
      let data = try await send("POST", action: "undo_last")
      return data["ok"] as? Bool == true
    } catch let fehler as ServiceError where fehler.statusCode == 404 {
      return false  // kein Eintrag vorhanden
    }
  }

  // MARK: - Transport

  private func send(_ method: String, action: String, body: [String: Any]? = nil)
    async throws -> [String: Any]
  {
    guard !baseURL.isEmpty else {
      throw ServiceError(
        message: "Keine API-URL konfiguriert. Bitte in den Einstellungen die "
          + "Basis-URL des Servers hinterlegen.")
    }
    guard let url = URL(string: "\(baseURL)api.php?action=\(action)") else {
      throw ServiceError(message: "Ungültige API-URL: \(baseURL)")
    }

    // mTLS-Identity beim ersten Zugriff aus den PEM-Dateien bauen.
    if identity == nil, let certSource {
      let (cert, key) = try certSource.readCredentials()
      identity = try ClientIdentity.make(certPEM: cert, keyPEM: key)
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let apiKey, !apiKey.isEmpty {
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
      throw ServiceError(message: error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw ServiceError(message: "Unerwartete Antwort des Servers.")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw ServiceError(
        message: "Fehler \(http.statusCode): \(Self.meldung(aus: data))",
        statusCode: http.statusCode)
    }
    if data.isEmpty { return [:] }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ServiceError(message: "Unerwartete Antwort (kein JSON).")
    }
    return json
  }

  /// Zieht `{"error": "..."}` heraus bzw. kürzt eine HTML-Fehlerseite.
  private static func meldung(aus data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = json["error"] as? String, !text.isEmpty
    {
      return text
    }
    let text = String(data: data, encoding: .utf8) ?? ""
    let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if clean.isEmpty { return "Anfrage fehlgeschlagen" }
    return clean.count > 200 ? String(clean.prefix(200)) + "…" : clean
  }
}

extension ApiService: URLSessionTaskDelegate {
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
    completionHandler(
      .useCredential,
      URLCredential(identity: identity, certificates: nil, persistence: .forSession))
  }
}
