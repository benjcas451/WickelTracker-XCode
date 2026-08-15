import Foundation

/// Art des Wickel-Eintrags. `apiValue` ist exakt der String, den die API
/// erwartet bzw. liefert (urin, stuhlgang, beides). Die Farbzuordnung
/// (Honig/Grau/Flieder) liegt im Theme (Theme.swift).
enum WickelType: String, CaseIterable, Identifiable {
  case urin
  case stuhlgang
  case beides

  var id: String { rawValue }
  var apiValue: String { rawValue }

  var label: String {
    switch self {
    case .urin: "Urin"
    case .stuhlgang: "Stuhlgang"
    case .beides: "Beides"
    }
  }

  /// SF-Symbol analog zu den Material-Icons der Android-App.
  var symbol: String {
    switch self {
    case .urin: "drop.fill"
    case .stuhlgang: "cloud.fill"
    case .beides: "circle.grid.2x1.fill"
    }
  }

  static func fromApi(_ value: String?) -> WickelType {
    value.flatMap { WickelType(rawValue: $0.lowercased()) } ?? .urin
  }
}

/// Statistik eines Zeitraums: Gesamtzahl + Prozentanteil je Typ
/// (so liefert es `GET api.php?action=stats`).
struct PeriodStats: Equatable {
  var total = 0
  var urinPct = 0
  var stuhlgangPct = 0
  var beidesPct = 0
  var stoffwindelPct = 0

  func pctOf(_ type: WickelType) -> Int {
    switch type {
    case .urin: urinPct
    case .stuhlgang: stuhlgangPct
    case .beides: beidesPct
    }
  }

  static let leer = PeriodStats()
}

/// Letzter Eintrag (Typ + Zeitpunkt) oder „keiner“.
struct LastEntry: Equatable {
  var type: WickelType?
  var time: Date?
  var stoffwindel = false

  var isEmpty: Bool { type == nil }
}

/// Vollständige Statistik-Antwort (`action=stats`): Zeiträume heute / Woche /
/// 3 Wochen / Monat plus letzter Eintrag.
struct WickelStats: Equatable {
  var today = PeriodStats.leer
  var week = PeriodStats.leer
  var threeWeeks = PeriodStats.leer
  var month = PeriodStats.leer
  var last = LastEntry()
}

// MARK: - Zeitformate

/// Liest ISO-8601-Zeitstempel tolerant: mit Offset (`+02:00`), mit `Z`,
/// mit 3 oder 6 Nachkommastellen (Dart schrieb Mikrosekunden in die lokale
/// Datenbank!) oder ganz ohne Zeitzone (dann lokale Zeit, wie in Dart).
enum IsoZeit {

  static func parse(_ text: String) -> Date? {
    if let date = fractional.date(from: text) { return date }
    if let date = plain.date(from: text) { return date }
    for formatter in posixFormatter {
      if let date = formatter.date(from: text) { return date }
    }
    return nil
  }

  /// Fürs Schreiben in die lokale Datenbank: UTC mit Millisekunden, damit die
  /// lexikalische Sortierung der Strings der zeitlichen entspricht (identisch
  /// zu Flutter/Android).
  static func dbString(from date: Date) -> String {
    fractional.string(from: date)
  }

  // (ISO8601-)DateFormatter sind laut Apple-Doku thread-sicher.
  nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let posixFormatter: [DateFormatter] = [
    // Mikrosekunden (Dart), UTC
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'", utc: true),
    make("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", utc: true),
    // Offset-Formen mit Bruchteilen
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", utc: false),
    // Ohne Zeitzone: als lokale Zeit interpretieren
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSS", utc: false),
    make("yyyy-MM-dd'T'HH:mm:ss", utc: false),
  ]

  private static func make(_ format: String, utc: Bool) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    if utc { formatter.timeZone = TimeZone(identifier: "UTC") }
    return formatter
  }
}
