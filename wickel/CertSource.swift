import Foundation

/// Quelle für client.crt / client.key: der Documents-Ordner der App, sichtbar
/// in der „Dateien"-App (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace).
/// Gleicher Ort wie bei der Flutter-App – vorhandene Zertifikate werden beim
/// Umstieg automatisch weiter genutzt (gleiche Bundle-ID = gleicher Container).
struct CertSource {

  static let certFileName = "client.crt"
  static let keyFileName = "client.key"

  private var ordner: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  /// Für die UI lesbarer Ort der Zertifikate.
  var locationLabel: String { ordner.path }

  var sindVorhanden: Bool {
    FileManager.default.fileExists(atPath: ordner.appendingPathComponent(Self.certFileName).path)
      && FileManager.default.fileExists(atPath: ordner.appendingPathComponent(Self.keyFileName).path)
  }

  /// Liest die Bytes von Zertifikat und privatem Schlüssel.
  func readCredentials() throws -> (cert: Data, key: Data) {
    let certURL = ordner.appendingPathComponent(Self.certFileName)
    let keyURL = ordner.appendingPathComponent(Self.keyFileName)
    guard
      let cert = try? Data(contentsOf: certURL),
      let key = try? Data(contentsOf: keyURL)
    else {
      throw ServiceError(
        message: "\(Self.certFileName) oder \(Self.keyFileName) nicht im App-Ordner gefunden.")
    }
    return (cert, key)
  }
}
