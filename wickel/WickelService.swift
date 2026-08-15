import Foundation

/// Fehler einer API-/Datenbank-Aktion mit sprechender Meldung.
struct ServiceError: LocalizedError {
  let message: String
  /// HTTP-Status, falls der Fehler von der API kam (404 = „nichts da“).
  var statusCode: Int?
  var errorDescription: String? { message }
}

/// Gemeinsame Schnittstelle für Wickel-Quellen: die Server-API ([ApiService],
/// mTLS und/oder API-Key) oder die lokale SQLite-Datenbank ([DemoService]).
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
func createConfiguredWickelService() -> WickelService {
  switch AppSettings.mode {
  case .api:
    // Die api.php verlangt den API-Key in jedem Fall – auch hinter mTLS.
    ApiService(baseURL: AppSettings.apiBaseUrl, certSource: CertSource(), apiKey: AppSettings.apiKey)
  case .apiKey:
    ApiService(baseURL: AppSettings.apiKeyBaseUrl, apiKey: AppSettings.apiKey)
  case .demo:
    DemoService.shared
  }
}
