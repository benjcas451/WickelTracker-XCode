import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Eine Roh-Zeile der Tabelle `entries` (für Backup-Export/-Restore).
struct EntryRow {
  let id: Int64
  let type: String
  let time: String
  let stoffwindel: Int
}

/// Lokaler Modus: nutzt exakt die SQLite-Datenbank weiter, die schon die
/// Flutter-App (sqflite) angelegt hat – gleicher Dateiname im Documents-
/// Ordner, gleiches Schema, gleiche Version (PRAGMA user_version = 2,
/// inklusive Upgrade-Pfad von v1). Bestehende Daten werden beim Umstieg
/// dadurch nahtlos übernommen.
///
/// `@unchecked Sendable`: Das einzige veränderliche Feld (`db`) wird
/// ausschließlich auf der seriellen `queue` gelesen und geschrieben – der
/// Compiler kann das bei der SQLite-C-API (OpaquePointer) nur nicht beweisen.
final class DemoService: WickelService, @unchecked Sendable {

  /// Eine Verbindung für die gesamte Prozesslaufzeit: Oberfläche, Backup und
  /// Watch-Brücke dürfen sie sich nicht gegenseitig wegschließen.
  static let shared = DemoService()

  private var db: OpaquePointer?
  private let queue = DispatchQueue(label: "org.dwarftsch.wickel.demo-db")

  private init() {}

  // MARK: - Öffnen & Schema

  private func datenbank() throws -> OpaquePointer {
    if let db { return db }
    let pfad = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("wickel_demo.db").path

    var handle: OpaquePointer?
    guard sqlite3_open(pfad, &handle) == SQLITE_OK, let handle else {
      throw ServiceError(message: "Lokale Datenbank ließ sich nicht öffnen.")
    }
    try migrieren(handle)
    db = handle
    return handle
  }

  /// Identisch zur sqflite-Migration der Flutter-App (Version 1 -> 2).
  private func migrieren(_ db: OpaquePointer) throws {
    let version = skalarInt(db, "PRAGMA user_version") ?? 0
    if version == 0 {
      try ausfuehren(
        db,
        """
        CREATE TABLE IF NOT EXISTS entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          time TEXT NOT NULL,
          stoffwindel INTEGER NOT NULL DEFAULT 0
        )
        """)
    } else if version < 2 {
      try ausfuehren(db, "ALTER TABLE entries ADD COLUMN stoffwindel INTEGER NOT NULL DEFAULT 0")
    }
    if version < 2 {
      try ausfuehren(db, "PRAGMA user_version = 2")
    }
  }

  // MARK: - WickelService

  func getStats() async throws -> WickelStats {
    try await auf { db in
      var stats = WickelStats()
      stats.today = try self.periode(db, seit: Self.tagesbeginn())
      stats.week = try self.periode(db, seit: Self.tagesbeginn(tageZurueck: 7))
      stats.threeWeeks = try self.periode(db, seit: Self.tagesbeginn(tageZurueck: 21))
      stats.month = try self.periode(db, seit: Self.tagesbeginn(tageZurueck: 30))
      // Nach Zeit sortiert, nicht nach id: Einträge von der Watch können
      // nachträglich mit älterem Zeitpunkt eintreffen.
      if let row = try self.zeilen(
        db, "SELECT * FROM entries ORDER BY time DESC, id DESC LIMIT 1", parameter: []
      ).first {
        stats.last = LastEntry(
          type: WickelType.fromApi(row.type),
          time: IsoZeit.parse(row.time),
          stoffwindel: row.stoffwindel == 1)
      }
      return stats
    }
  }

  /// Statistik für alle Einträge ab `seit` (Prozentwerte wie die Server-API).
  private func periode(_ db: OpaquePointer, seit: Date) throws -> PeriodStats {
    let rows = try zeilen(
      db, "SELECT * FROM entries WHERE time >= ?",
      parameter: [IsoZeit.dbString(from: seit)])
    let total = rows.count
    var urin = 0
    var stuhl = 0
    var beides = 0
    var sw = 0
    for row in rows {
      if row.stoffwindel == 1 { sw += 1 }
      switch WickelType.fromApi(row.type) {
      case .urin: urin += 1
      case .stuhlgang: stuhl += 1
      case .beides: beides += 1
      }
    }
    func pct(_ c: Int) -> Int { total > 0 ? Int((Double(c) / Double(total) * 100).rounded()) : 0 }
    return PeriodStats(
      total: total,
      urinPct: pct(urin),
      stuhlgangPct: pct(stuhl),
      beidesPct: pct(beides),
      stoffwindelPct: pct(sw))
  }

  func addEntry(type: WickelType, stoffwindel: Bool, time: Date?) async throws {
    try await auf { db in
      try self.ausfuehren(
        db, "INSERT INTO entries(type, time, stoffwindel) VALUES(?,?,?)",
        parameter: [type.apiValue, IsoZeit.dbString(from: time ?? Date()), stoffwindel ? 1 : 0])
    }
  }

  @discardableResult
  func undoLast() async throws -> Bool {
    try await auf { db in
      // Gleiche Sortierung wie in getStats, damit „rückgängig“ genau den
      // Eintrag entfernt, der als letzter angezeigt wird.
      try self.ausfuehren(
        db,
        "DELETE FROM entries WHERE id = (SELECT id FROM entries ORDER BY time DESC, id DESC LIMIT 1)")
      return sqlite3_changes(db) > 0
    }
  }

  // MARK: - Backup

  /// Alle Roh-Zeilen der lokalen Tabelle (für den Backup-Export).
  func exportRows() async throws -> [EntryRow] {
    try await auf { db in
      try self.zeilen(db, "SELECT * FROM entries ORDER BY id", parameter: [])
    }
  }

  /// Ersetzt den gesamten Bestand durch [rows] (Backup-Restore), transaktional.
  func replaceAll(_ rows: [EntryRow]) async throws {
    try await auf { db in
      try self.ausfuehren(db, "BEGIN")
      do {
        try self.ausfuehren(db, "DELETE FROM entries")
        for row in rows {
          try self.ausfuehren(
            db, "INSERT INTO entries(id, type, time, stoffwindel) VALUES(?,?,?,?)",
            parameter: [row.id, row.type, row.time, row.stoffwindel])
        }
        try self.ausfuehren(db, "COMMIT")
      } catch {
        try? self.ausfuehren(db, "ROLLBACK")
        throw error
      }
    }
  }

  // MARK: - SQLite-Handwerk

  private func auf<T: Sendable>(
    _ arbeit: @Sendable @escaping (OpaquePointer) throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { fortsetzung in
      queue.async {
        do {
          fortsetzung.resume(returning: try arbeit(try self.datenbank()))
        } catch {
          fortsetzung.resume(throwing: error)
        }
      }
    }
  }

  private func ausfuehren(_ db: OpaquePointer, _ sql: String, parameter: [Any?] = []) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(statement) }
    binden(statement, parameter)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
  }

  private func zeilen(_ db: OpaquePointer, _ sql: String, parameter: [Any?]) throws -> [EntryRow] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(statement) }
    binden(statement, parameter)

    // Spaltenindizes anhand der Namen, damit SELECT * robust bleibt.
    var spalten: [String: Int32] = [:]
    for index in 0..<sqlite3_column_count(statement) {
      spalten[String(cString: sqlite3_column_name(statement, index))] = index
    }
    func text(_ name: String) -> String? {
      guard let index = spalten[name],
        let wert = sqlite3_column_text(statement, index)
      else { return nil }
      return String(cString: wert)
    }
    func zahl(_ name: String) -> Int64? {
      guard let index = spalten[name],
        sqlite3_column_type(statement, index) != SQLITE_NULL
      else { return nil }
      return sqlite3_column_int64(statement, index)
    }

    var ergebnis: [EntryRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      ergebnis.append(
        EntryRow(
          id: zahl("id") ?? 0,
          type: text("type") ?? "",
          time: text("time") ?? "",
          stoffwindel: Int(zahl("stoffwindel") ?? 0)))
    }
    return ergebnis
  }

  private func binden(_ statement: OpaquePointer?, _ parameter: [Any?]) {
    for (index, wert) in parameter.enumerated() {
      let position = Int32(index + 1)
      switch wert {
      case nil: sqlite3_bind_null(statement, position)
      case let text as String: sqlite3_bind_text(statement, position, text, -1, SQLITE_TRANSIENT)
      case let zahl as Int: sqlite3_bind_int64(statement, position, Int64(zahl))
      case let zahl as Int64: sqlite3_bind_int64(statement, position, zahl)
      default: sqlite3_bind_null(statement, position)
      }
    }
  }

  private func skalarInt(_ db: OpaquePointer, _ sql: String) -> Int? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return Int(sqlite3_column_int64(statement, 0))
  }

  // MARK: - Helfer

  /// Heutiger Tagesbeginn (lokale Zeit), optional um Tage zurückversetzt.
  private static func tagesbeginn(tageZurueck: Int = 0) -> Date {
    let start = Calendar.current.startOfDay(for: Date())
    return Calendar.current.date(byAdding: .day, value: -tageZurueck, to: start) ?? start
  }
}
