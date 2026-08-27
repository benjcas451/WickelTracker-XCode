import Foundation
import Security

/// Welche Datenquelle die App verwendet. Rohwerte identisch zur Flutter-App.
enum DataSourceMode: String {
  /// Die mTLS-Server-API.
  case api
  /// Server-API mit API-Key (X-API-Key-Header) statt Client-Zertifikat.
  case apiKey
  /// Immer die lokale SQLite-Datenbank.
  case demo
}

/// Lädt und speichert App-Einstellungen (UserDefaults) – mit einer Ausnahme:
/// der API-Key liegt in der Keychain, siehe `ApiKeyStore` am Dateiende.
///
/// Beim ersten Start nach dem Umstieg von der Flutter-App werden deren Werte
/// übernommen: Flutters shared_preferences speichert auf iOS in denselben
/// UserDefaults, nur mit dem Präfix `flutter.` (gleiche Bundle-ID = gleicher
/// Container, deshalb funktioniert das nahtlos).
enum AppSettings {

  // Computed statt stored: UserDefaults ist thread-sicher, aber als
  // gespeicherte Globale würde der Compiler Sendable-Warnungen melden.
  private static var defaults: UserDefaults { .standard }

  private enum Key {
    static let mode = "data_source_mode"
    static let apiKey = "api_key"
    static let apiBaseUrl = "api_base_url"
    static let apiKeyBaseUrl = "api_key_base_url"
    static let stoffwindel = "stoffwindel_enabled"
    static let migriert = "migriert_von_flutter"
    static let keychainMigriert = "api_key_in_keychain"
  }

  static func migrationAusfuehren() {
    apiKeyInKeychainUebernehmen()
    guard !defaults.bool(forKey: Key.migriert) else { return }
    for key in [Key.mode, Key.apiBaseUrl, Key.apiKeyBaseUrl] {
      if defaults.object(forKey: key) == nil,
        let wert = defaults.string(forKey: "flutter." + key)
      {
        defaults.set(wert, forKey: key)
      }
    }
    // Bool-Einstellung: shared_preferences legt sie als Bool ab.
    if defaults.object(forKey: Key.stoffwindel) == nil,
      defaults.object(forKey: "flutter." + Key.stoffwindel) != nil
    {
      defaults.set(defaults.bool(forKey: "flutter." + Key.stoffwindel), forKey: Key.stoffwindel)
    }
    defaults.set(true, forKey: Key.migriert)
  }

  /// Holt einen noch im Klartext hinterlegten API-Key einmalig in die Keychain
  /// und räumt ihn aus den UserDefaults – damit verschwindet er auch aus jedem
  /// künftigen iCloud-Backup. Eigener Marker, weil `migriert_von_flutter` bei
  /// Bestandsnutzern längst gesetzt ist und die Übernahme sonst nie liefe.
  private static func apiKeyInKeychainUebernehmen() {
    guard !defaults.bool(forKey: Key.keychainMigriert) else { return }
    let klartext =
      (defaults.string(forKey: Key.apiKey) ?? defaults.string(forKey: "flutter." + Key.apiKey))?
      .trimmingCharacters(in: .whitespaces) ?? ""
    if !klartext.isEmpty {
      ApiKeyStore.speichere(klartext)
    }
    defaults.removeObject(forKey: Key.apiKey)
    defaults.removeObject(forKey: "flutter." + Key.apiKey)
    defaults.set(true, forKey: Key.keychainMigriert)
  }

  static var mode: DataSourceMode {
    get { defaults.string(forKey: Key.mode).flatMap(DataSourceMode.init) ?? .demo }
    set { defaults.set(newValue.rawValue, forKey: Key.mode) }
  }

  /// Liegt in der Keychain statt in den UserDefaults – siehe `ApiKeyStore`.
  static var apiKey: String {
    get { ApiKeyStore.lade() }
    set { ApiKeyStore.speichere(newValue.trimmingCharacters(in: .whitespaces)) }
  }

  /// Basis-URL der mTLS-API; leer, solange keine hinterlegt ist.
  static var apiBaseUrl: String {
    get { ladeUrl(Key.apiBaseUrl) }
    set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.apiBaseUrl) }
  }

  /// Basis-URL der API-Key-API; leer, solange keine hinterlegt ist.
  static var apiKeyBaseUrl: String {
    get { ladeUrl(Key.apiKeyBaseUrl) }
    set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.apiKeyBaseUrl) }
  }

  /// Zeigt beim Eintragen die Stoffwindel-Umschaltfläche an.
  static var stoffwindelEnabled: Bool {
    get { defaults.bool(forKey: Key.stoffwindel) }
    set { defaults.set(newValue, forKey: Key.stoffwindel) }
  }

  private static func ladeUrl(_ key: String) -> String {
    let url = (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
    if url.isEmpty { return "" }
    return url.hasSuffix("/") ? url : url + "/"
  }
}

/// Der API-Key gehört nicht in die UserDefaults – die landen vollständig in
/// jedem iCloud-Backup. In der Keychain steuert `kSecAttrAccessible`, wie weit
/// er mitwandert: `AfterFirstUnlock` ohne `kSecAttrSynchronizable` heißt beim
/// Direkttransfer auf ein neues Gerät (Quick Start) und im verschlüsselten
/// Finder-Backup dabei, aus einem iCloud-Backup dagegen nicht
/// wiederherstellbar. Das ist die iOS-Entsprechung der Android-Trennung
/// „`<device-transfer>` ja, `<cloud-backup>` nein“; die Uhr legt ihre
/// übernommene Verbindung in `ServerConnectionStore` mit demselben Attribut ab.
private enum ApiKeyStore {

  private static let service = "org.dwarftsch.wickel"
  private static let account = "api-key"

  static func lade() -> String {
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
      let daten = result as? Data
    else { return "" }
    return String(data: daten, encoding: .utf8) ?? ""
  }

  /// Ein leerer Key bedeutet „kein Key hinterlegt“ – dann bleibt auch nichts
  /// in der Keychain liegen.
  static func speichere(_ key: String) {
    loesche()
    guard !key.isEmpty else { return }
    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: Data(key.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    SecItemAdd(item as CFDictionary, nil)
  }

  static func loesche() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
