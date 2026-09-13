import Foundation

/// Die vom iPhone übernommene Server-Verbindung. Solange keine hinterlegt ist,
/// läuft alles über das iPhone (Relay).
struct ServerConnection: Codable {
  /// Basis-URL inklusive abschließendem Slash; `api.php` hängt der Client an.
  let baseURL: String
  /// Wird als `X-API-Key` mitgesendet. Die `api.php` verlangt den Key in jedem
  /// Fall — auch hinter mTLS —, deshalb ist er in beiden Modi gesetzt.
  let apiKey: String?
  /// PEM-Bytes des Client-Zertifikats; nil im reinen API-Key-Modus.
  let clientCertPEM: Data?
  /// PEM-Bytes des privaten Schlüssels; nil im reinen API-Key-Modus.
  let clientKeyPEM: Data?
  /// Client-ID des Cloudflare Service Tokens; nil ausserhalb des
  /// Cloudflare-Modus. Bei Verbindungen, die vor 2.1.0 übernommen wurden,
  /// fehlt das Feld in der Ablage und wird zu nil decodiert.
  let cfAccessClientId: String?
  /// Client-Secret des Cloudflare Service Tokens; nil ausserhalb des Modus.
  let cfAccessClientSecret: String?

  var isMutualTLS: Bool { clientCertPEM != nil && clientKeyPEM != nil }

  /// Läuft die Verbindung über ein Cloudflare Service Token?
  var isCloudflare: Bool { cfAccessClientId != nil && cfAccessClientSecret != nil }

  /// Kurzbeschreibung für die Statusanzeige auf der Uhr.
  var label: String {
    if isCloudflare { return "Direkt · Cloudflare" }
    return isMutualTLS ? "Direkt · mTLS" : "Direkt · API-Key"
  }
}

extension ServerConnection {
  /// Baut die Verbindung aus der Antwort auf `getConnection`.
  /// nil bedeutet: auf dem iPhone ist keine Server-Quelle eingerichtet.
  init?(reply: [String: Any]) {
    let raw = (reply["base_url"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    let normalized = raw.hasSuffix("/") ? raw : raw + "/"
    let key = (reply["api_key"] as? String).flatMap { $0.isEmpty ? nil : $0 }

    switch reply["mode"] as? String {
    case "apiKey":
      guard let key else { return nil }
      self.init(
        baseURL: normalized, apiKey: key, clientCertPEM: nil, clientKeyPEM: nil,
        cfAccessClientId: nil, cfAccessClientSecret: nil)

    case "cloudflare":
      // Ein halbes Service Token ist so gut wie keines — dann lieber weiter
      // über das iPhone, statt am Rand abgewiesen zu werden.
      guard
        let id = reply["cf_access_client_id"] as? String, !id.isEmpty,
        let secret = reply["cf_access_client_secret"] as? String, !secret.isEmpty
      else { return nil }
      self.init(
        baseURL: normalized, apiKey: key, clientCertPEM: nil, clientKeyPEM: nil,
        cfAccessClientId: id, cfAccessClientSecret: secret)

    case "api":
      guard
        let certText = reply["client_cert"] as? String,
        let keyText = reply["client_key"] as? String,
        let cert = Data(base64Encoded: certText),
        let privateKey = Data(base64Encoded: keyText)
      else { return nil }
      self.init(
        baseURL: normalized, apiKey: key, clientCertPEM: cert, clientKeyPEM: privateKey,
        cfAccessClientId: nil, cfAccessClientSecret: nil)

    default:
      return nil
    }
  }
}

/// Legt die übernommene Verbindung im Keychain der Uhr ab — dort ist das
/// Schlüsselmaterial besser aufgehoben als in den UserDefaults.
enum ServerConnectionStore {

  private static let service = "org.dwarftsch.wickel.watch"
  private static let account = "server-connection"

  static func load() -> ServerConnection? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard
      SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return try? JSONDecoder().decode(ServerConnection.self, from: data)
  }

  static func save(_ connection: ServerConnection) {
    guard let data = try? JSONEncoder().encode(connection) else { return }
    delete()
    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    SecItemAdd(item as CFDictionary, nil)
  }

  static func delete() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
