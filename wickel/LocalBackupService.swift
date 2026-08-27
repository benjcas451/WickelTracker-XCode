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

  /// Obergrenze für ein einzulesendes Backup. Ein JSON-Backup dieser App liegt
  /// bei rund 120 Byte je Eintrag – 16 MB reichen also für weit über 100.000
  /// Einträge. Der Wert ist bewusst derselbe wie in der Android-App.
  static let maxImportBytes = 16 * 1024 * 1024

  /// Liest eine Backup-Datei mit Größengrenze. Ohne sie zieht eine
  /// versehentlich gewählte Riesendatei erst die Datei und dann den daraus
  /// gebauten JSON-Baum in den Speicher – zusammen ein Vielfaches der
  /// Dateigröße, und das System beendet die App.
  static func leseBegrenzt(_ url: URL) throws -> Data {
    let groesse = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    if let groesse, groesse > maxImportBytes {
      throw ServiceError(
        message: "Die Datei ist mit \(groesse / 1024 / 1024) MB zu groß für ein Backup "
          + "(erlaubt sind \(maxImportBytes / 1024 / 1024) MB).")
    }
    let daten = try Data(contentsOf: url, options: .mappedIfSafe)
    // Fällt die Größenabfrage aus (z. B. bei einem Cloud-Platzhalter), greift
    // die Grenze hier immer noch.
    guard daten.count <= maxImportBytes else {
      throw ServiceError(
        message: "Die Datei ist mit \(daten.count / 1024 / 1024) MB zu groß für ein Backup "
          + "(erlaubt sind \(maxImportBytes / 1024 / 1024) MB).")
    }
    return daten
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
