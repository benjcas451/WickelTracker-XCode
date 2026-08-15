import Foundation
import WatchConnectivity

extension Notification.Name {
  /// Übernommene Watch-Einträge — die Oberfläche lädt daraufhin neu.
  static let wickelWatchAenderung = Notification.Name("wickelWatchAenderung")
}

/// Verbindet die Apple-Watch-App mit der Datenquelle des iPhones.
///
/// Die Watch hat keinen Zugriff auf die Datenquelle (lokale SQLite-DB bzw.
/// Server-API), sie schickt neue Einträge deshalb hierher. Eingehende Einträge
/// landen zuerst in einer persistenten Warteschlange in `UserDefaults` — mit
/// denselben Schlüsseln wie in der abgelösten Flutter-App, damit beim Update
/// noch unbestätigte Einträge erhalten bleiben. Verarbeitet (angelegt und erst
/// dann bestätigt) werden sie direkt hier gegen den konfigurierten
/// [WickelService]; schlägt das Anlegen fehl (z. B. Server nicht erreichbar),
/// bleiben sie in der Warteschlange und der nächste Anlauf versucht es erneut.
///
/// Gegenrichtung: `pushSnapshot` spiegelt den letzten Eintrag und die Anzahl
/// von heute per `updateApplicationContext` auf die Watch — Payload-Format
/// identisch zur Flutter-App, die installierte Watch-App läuft nahtlos weiter.
///
/// `getConnection` (Direktbetrieb der Watch) wird direkt aus den Einstellungen
/// beantwortet — anders als früher ist dafür keine laufende UI nötig.
final class WatchBridge: NSObject, @unchecked Sendable {
  static let shared = WatchBridge()

  // Schlüssel identisch zur Flutter-App (WatchBridge.swift im Runner).
  private static let pendingKey = "watch.pendingEntries"
  private static let appliedKey = "watch.appliedIds"

  /// So viele bereits übernommene IDs bleiben gemerkt. Ein Eintrag kann
  /// doppelt ankommen (`sendMessage` für die schnelle Zustellung *und*
  /// `transferUserInfo` als garantierter Weg); die ID entscheidet.
  private static let appliedIdLimit = 200

  private let defaults = UserDefaults.standard

  /// Serialisiert alle Zugriffe auf die Warteschlange: Delegate-Callbacks
  /// kommen auf einem Hintergrund-Thread, UI-Aufrufe vom MainActor.
  /// (`@unchecked Sendable` stützt sich genau darauf.)
  private let store = DispatchQueue(label: "org.dwarftsch.wickel.watch-store")

  /// Verhindert überlappende Verarbeitungsläufe.
  nonisolated(unsafe) private var verarbeitet = false

  private override init() { super.init() }

  // MARK: - Einrichtung

  /// Aktiviert die WatchConnectivity-Sitzung. Muss so früh wie möglich im
  /// App-Start passieren, damit iOS zwischengespeicherte Übertragungen
  /// zustellt.
  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    if session.activationState != .activated {
      session.activate()
    }
  }

  // MARK: - Snapshot an die Watch

  /// Schickt den aktuellen Stand an die Watch. `updateApplicationContext`
  /// überschreibt den vorherigen Stand — es zählt immer nur der neueste.
  func pushSnapshot(stats: WickelStats, stoffwindelEnabled: Bool) {
    let session = WCSession.default
    guard WCSession.isSupported(), session.activationState == .activated,
      session.isPaired, session.isWatchAppInstalled
    else { return }

    var context: [String: Any] = [
      "v": 1,
      "todayTotal": stats.today.total,
      "stoffwindelEnabled": stoffwindelEnabled,
      "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
    ]
    if let type = stats.last.type {
      context["lastType"] = type.apiValue
      context["lastStoffwindel"] = stats.last.stoffwindel
      if let time = stats.last.time {
        context["lastTime"] = IsoZeit.fractional.string(from: time)
      }
    }
    do {
      try session.updateApplicationContext(context)
    } catch {
      NSLog("WatchBridge: Stand konnte nicht übertragen werden: \(error)")
    }
  }

  // MARK: - Warteschlange verarbeiten

  /// Legt alle offenen Watch-Einträge über die konfigurierte Datenquelle an
  /// und bestätigt sie einzeln. Wird beim App-Start, bei Rückkehr in den
  /// Vordergrund und nach jeder Zustellung angestoßen.
  func verarbeitePending() {
    let offen = store.sync { self.pendingEntries() }
    guard !offen.isEmpty else { return }
    let schonAktiv = store.sync { () -> Bool in
      if self.verarbeitet { return true }
      self.verarbeitet = true
      return false
    }
    guard !schonAktiv else { return }

    Task {
      defer { self.store.sync { self.verarbeitet = false } }
      let service = createConfiguredWickelService()
      var uebernommen = 0
      for eintrag in offen {
        guard let id = eintrag["id"] as? String,
          let typ = eintrag["type"] as? String,
          let zeitText = eintrag["time"] as? String
        else {
          // Unlesbarer Datensatz: verwerfen, damit er die Schlange nicht blockiert.
          self.store.sync { self.removePending(ids: [(eintrag["id"] as? String) ?? ""]) }
          continue
        }
        do {
          try await service.addEntry(
            type: WickelType.fromApi(typ),
            stoffwindel: eintrag["stoffwindel"] as? Bool ?? false,
            time: IsoZeit.parse(zeitText))
          self.store.sync { self.removePending(ids: [id]) }
          uebernommen += 1
        } catch {
          // Anlegen fehlgeschlagen (z. B. Server nicht erreichbar): Eintrag
          // bleibt in der Warteschlange, Abbruch bis zum nächsten Anlauf.
          NSLog("WatchBridge: Übernahme fehlgeschlagen: \(error)")
          break
        }
      }
      if uebernommen > 0 {
        let anzahl = uebernommen
        Task { @MainActor in
          NotificationCenter.default.post(
            name: .wickelWatchAenderung, object: nil, userInfo: ["anzahl": anzahl])
        }
      }
    }
  }

  // MARK: - Warteschlange (immer auf `store` aufrufen)

  private func pendingEntries() -> [[String: Any]] {
    (defaults.array(forKey: Self.pendingKey) as? [[String: Any]]) ?? []
  }

  private func appliedIds() -> [String] {
    (defaults.array(forKey: Self.appliedKey) as? [String]) ?? []
  }

  private func removePending(ids: [String]) {
    guard !ids.isEmpty else { return }
    let acked = Set(ids)
    defaults.set(
      pendingEntries().filter { !acked.contains($0["id"] as? String ?? "") },
      forKey: Self.pendingKey)
    // Ältestes zuerst abschneiden, damit die jüngsten IDs erhalten bleiben.
    let applied = (appliedIds() + ids).suffix(Self.appliedIdLimit)
    defaults.set(Array(applied), forKey: Self.appliedKey)
  }

  /// Nimmt eine eingehende Nachricht entgegen. Rückgabe: true, wenn daraus ein
  /// neuer Eintrag entstanden ist.
  private func enqueue(_ payload: [String: Any]) -> Bool {
    guard payload["action"] as? String == "add",
      let id = payload["id"] as? String, !id.isEmpty,
      let type = payload["type"] as? String, WickelType(rawValue: type) != nil,
      let time = payload["time"] as? String, !time.isEmpty
    else {
      NSLog("WatchBridge: unbrauchbare Nachricht verworfen.")
      return false
    }

    // Ältere Watch-Versionen kennen das Feld nicht — dann gilt "keine
    // Stoffwindel", wie bisher.
    let stoffwindel = payload["stoffwindel"] as? Bool ?? false

    return store.sync {
      let pending = pendingEntries()
      // Doppelte Zustellung desselben Eintrags ignorieren.
      guard !pending.contains(where: { $0["id"] as? String == id }),
        !appliedIds().contains(id)
      else { return false }
      let entry: [String: Any] = [
        "id": id, "type": type, "time": time, "stoffwindel": stoffwindel,
      ]
      defaults.set(pending + [entry], forKey: Self.pendingKey)
      return true
    }
  }

  // MARK: - getConnection

  /// Überträgt die eingerichtete Server-Verbindung an die Watch, damit diese
  /// anschließend direkt mit dem Server sprechen kann. Bei der lokalen
  /// SQLite-Quelle gibt es nichts zu übernehmen. Der API-Key geht in beiden
  /// Server-Modi mit, weil die api.php ihn stets verlangt; bei mTLS kommen
  /// Zertifikat und privater Schlüssel als PEM (base64-kodiert) dazu.
  private func verbindung() throws -> [String: Any] {
    switch AppSettings.mode {
    case .demo:
      return ["mode": "demo"]

    case .apiKey:
      let baseUrl = AppSettings.apiKeyBaseUrl
      guard !baseUrl.isEmpty else {
        throw ServiceError(message: "Auf dem iPhone ist keine API-URL hinterlegt.")
      }
      return ["mode": "apiKey", "base_url": baseUrl, "api_key": AppSettings.apiKey]

    case .api:
      let baseUrl = AppSettings.apiBaseUrl
      guard !baseUrl.isEmpty else {
        throw ServiceError(message: "Auf dem iPhone ist keine API-URL hinterlegt.")
      }
      let (cert, key) = try CertSource().readCredentials()
      return [
        "mode": "api",
        "base_url": baseUrl,
        "api_key": AppSettings.apiKey,
        "client_cert": cert.base64EncodedString(),
        "client_key": key.base64EncodedString(),
      ]
    }
  }
}

// MARK: - WCSessionDelegate

extension WatchBridge: WCSessionDelegate {
  func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      NSLog("WatchBridge: Aktivierung fehlgeschlagen: \(error)")
      return
    }
    if state == .activated { verarbeitePending() }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  /// Nach einem Wechsel der gekoppelten Watch muss neu aktiviert werden.
  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  /// Garantierter Weg: wird auch zugestellt, wenn die App nicht lief.
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    if enqueue(userInfo) { verarbeitePending() }
  }

  /// Schneller Weg, solange das iPhone erreichbar ist.
  func session(
    _ session: WCSession, didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    if message["action"] as? String == "getConnection" {
      do {
        replyHandler(["ok": true, "data": try verbindung()])
      } catch {
        replyHandler(["ok": false, "error": error.localizedDescription])
      }
      return
    }
    let accepted = enqueue(message)
    replyHandler(["ok": true])
    if accepted { verarbeitePending() }
  }
}
