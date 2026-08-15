import Foundation

/// Portables JSON-Backup der lokalen Datenbank. Format identisch zur
/// Flutter-/Android-App (format=1, app=wickel) – alte Backups bleiben
/// wiederherstellbar und umgekehrt.
enum LocalBackupService {

  private static let app = "wickel"
  private static let format = 1

  /// Vorschlags-Dateiname für den Speichern-Dialog.
  static func dateiname() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd_HHmm"
    return "wickel_backup_\(formatter.string(from: Date())).json"
  }

  /// Serialisiert alle Zeilen als hübsch formatiertes Backup-JSON.
  static func exportJson(_ rows: [EntryRow]) throws -> Data {
    let eintraege: [[String: Any]] = rows.map { row in
      ["id": row.id, "type": row.type, "time": row.time, "stoffwindel": row.stoffwindel]
    }
    let payload: [String: Any] = [
      "format": format,
      "app": app,
      "exported_at": ISO8601DateFormatter().string(from: Date()),
      "entries": eintraege,
    ]
    return try JSONSerialization.data(
      withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  }

  /// Prüft ein Backup und liefert die Zeilen passend zum Tabellenschema.
  static func parseUndValidiere(_ data: Data) throws -> [EntryRow] {
    guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ServiceError(message: "Die Datei ist kein gültiges JSON.")
    }
    guard decoded["format"] as? Int == format, decoded["app"] as? String == app else {
      throw ServiceError(message: "Nicht unterstütztes Backup-Format (falsche App oder Version).")
    }
    guard let rawEntries = decoded["entries"] as? [[String: Any]] else {
      throw ServiceError(message: "Eintragsliste fehlt im Backup.")
    }

    var ids = Set<Int64>()
    return try rawEntries.map { raw in
      guard let id = (raw["id"] as? Int).map(Int64.init), id > 0, ids.insert(id).inserted else {
        throw ServiceError(message: "Ungültige oder doppelte Eintrags-ID.")
      }
      guard let type = raw["type"] as? String,
        WickelType(rawValue: type.lowercased()) != nil
      else {
        throw ServiceError(message: "Eintrag \(id) hat einen ungültigen Typ.")
      }
      guard let time = raw["time"] as? String, IsoZeit.parse(time) != nil else {
        throw ServiceError(message: "Eintrag \(id) hat einen ungültigen Zeitpunkt.")
      }
      guard let stoffwindel = raw["stoffwindel"] as? Int, stoffwindel == 0 || stoffwindel == 1
      else {
        throw ServiceError(message: "Eintrag \(id) hat einen ungültigen Stoffwindel-Wert.")
      }
      return EntryRow(id: id, type: type, time: time, stoffwindel: stoffwindel)
    }
  }
}
