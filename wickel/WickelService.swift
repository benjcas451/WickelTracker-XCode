import Foundation

/// Fehler einer API-/Datenbank-Aktion mit sprechender Meldung.
struct ServiceError: LocalizedError {
  let message: String
  /// HTTP-Status, falls der Fehler von der API kam (404 = „nichts da“).
  var statusCode: Int?
  /// Gesetzt, wenn der Fehler ein Verbindungsproblem war – entscheidet
  /// darüber, ob die Aktion in die Offline-Warteschlange darf.
  var netzfehler: Netzfehler?
  var errorDescription: String? { message }
}

/// Gemeinsame Schnittstelle für Wickel-Quellen: die Server-API ([ApiService],
/// mTLS, API-Key und/oder Cloudflare Service Token) oder die lokale
/// SQLite-Datenbank ([DemoService]).
/// Sendable, damit die Dienste zwischen MainActor (UI) und Hintergrund-Tasks
/// wandern dürfen.
protocol WickelService: Sendable {
  /// Vollständige Statistik (heute / Woche / 3 Wochen / Monat + letzter Eintrag).
  func getStats() async throws -> WickelStats

  /// Neuen Wickel-Eintrag anlegen. `time` setzt den Zeitpunkt abweichend von
  /// „jetzt“ — für Einträge, die die Watch offline erfasst hat. Die Server-API
  /// kennt dafür keinen Parameter und stempelt selbst.
  func addEntry(type: WickelType, stoffwindel: Bool, time: Date?) async throws

  /// Letzten Eintrag rückgängig machen.
  /// Liefert true, wenn etwas entfernt wurde, false wenn es keinen gab.
  @discardableResult
  func undoLast() async throws -> Bool
}

/// Erstellt die aktuell konfigurierte Datenquelle. Wird von der Oberfläche und
/// von der Watch-Brücke verwendet, damit Einträge von der Uhr immer im selben
/// Datenbestand landen wie Einträge vom Telefon.
///
/// `offlineFaehig` legt die Warteschlange darüber, die bei einem
/// Verbindungsabbruch einspringt. Die Oberfläche will das; die Watch-Brücke
/// bewusst **nicht** — die Uhr führt eine eigene Outbox und bekäme sonst ein
/// „erledigt“ gemeldet, während der Eintrag noch beim iPhone liegt.
func createConfiguredWickelService(offlineFaehig: Bool = false) -> WickelService {
  let dienst = createServerOderDemoService()
  guard offlineFaehig, let zugang = aktuellerZugang() else { return dienst }
  return OfflineService(innen: dienst, zugang: zugang)
}

/// Kennung des aktuellen Zugangs (Modus + Basis-URL); nil im Demo-Modus, der
/// ohnehin lokal arbeitet und keine Warteschlange braucht.
private func aktuellerZugang() -> String? {
  switch AppSettings.mode {
  case .api: "api|\(AppSettings.apiBaseUrl)"
  case .apiKey: "apiKey|\(AppSettings.apiKeyBaseUrl)"
  case .cloudflare: "cloudflare|\(AppSettings.cloudflareBaseUrl)"
  case .demo: nil
  }
}

private func createServerOderDemoService() -> WickelService {
  switch AppSettings.mode {
  case .api:
    // Die api.php verlangt den API-Key in jedem Fall – auch hinter mTLS.
    ApiService(baseURL: AppSettings.apiBaseUrl, certSource: CertSource(), apiKey: AppSettings.apiKey)
  case .apiKey:
    ApiService(baseURL: AppSettings.apiKeyBaseUrl, apiKey: AppSettings.apiKey)
  case .cloudflare:
    // Cloudflare Access sichert den Zugang am Rand; der API-Key geht wie in
    // den anderen Server-Modi mit — die api.php verlangt ihn auch dort.
    ApiService(
      baseURL: AppSettings.cloudflareBaseUrl, apiKey: AppSettings.apiKey,
      cfToken: .ausEinstellungen)
  case .demo:
    DemoService.shared
  }
}
