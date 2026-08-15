import Foundation
import WatchConnectivity

/// Ein auf der Watch erfasster Eintrag, solange er nicht bestätigt ist.
struct OutboxEntry: Codable, Identifiable, Equatable {
  /// UUID; das iPhone dedupliziert darüber.
  let id: String
  let type: String
  let time: Date
  let stoffwindel: Bool
  /// true, solange der Eintrag direkt an den Server geht. Solche Einträge
  /// dürfen **nicht** zusätzlich ans iPhone gehen — das gäbe Doppel-Einträge.
  let direct: Bool

  /// Einträge aus einer Version ohne Stoffwindel- bzw. Direkt-Feld bleiben
  /// lesbar; ohne `direct` galt immer der Weg über das iPhone.
  init(id: String, type: String, time: Date, stoffwindel: Bool, direct: Bool) {
    self.id = id
    self.type = type
    self.time = time
    self.stoffwindel = stoffwindel
    self.direct = direct
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    type = try c.decode(String.self, forKey: .type)
    time = try c.decode(Date.self, forKey: .time)
    stoffwindel = try c.decodeIfPresent(Bool.self, forKey: .stoffwindel) ?? false
    direct = try c.decodeIfPresent(Bool.self, forKey: .direct) ?? false
  }
}

/// Zustand der Watch-App.
///
/// Die Watch hat keine eigene Datenbank. Woher der Stand kommt und wohin ein
/// neuer Eintrag geht, hängt davon ab, ob die Server-Verbindung des iPhones
/// übernommen wurde:
///
/// - **Über iPhone** (Auslieferungszustand): Der Eintrag wandert in eine
///   Ausgangs-Warteschlange und geht per `transferUserInfo` (garantiert) und
///   `sendMessage` (schnell, wenn erreichbar) hinüber; das iPhone legt ihn in
///   der dort gewählten Datenquelle an und spiegelt den Stand zurück.
/// - **Direkt**: Die Uhr spricht selbst mit der REST-API — auch dann, wenn die
///   iPhone-App gar nicht läuft. Scheitert schon der Verbindungsaufbau, fällt
///   der Eintrag auf den Weg über das iPhone zurück.
///
/// Angezeigt wird stets der jüngere von gespiegeltem Stand und eigener
/// Warteschlange, der eigene Eintrag erscheint also sofort.
@MainActor
final class WatchStore: NSObject, ObservableObject {
  private enum Key {
    static let snapshot = "watch.snapshot"
    static let outbox = "watch.outbox"
  }

  /// Anzuzeigender letzter Eintrag (gespiegelt oder noch nicht übertragen).
  @Published private(set) var lastType: WickelType?
  @Published private(set) var lastTime: Date?
  @Published private(set) var lastStoffwindel = false

  /// Noch nicht bestätigte Einträge.
  @Published private(set) var outbox: [OutboxEntry] = []

  /// Steuert, ob der Stoffwindel-Schalter erscheint. Wird am iPhone
  /// eingestellt und mit dem Stand mitgespiegelt.
  @Published private(set) var stoffwindelEnabled = false

  /// Auswahl für den nächsten Eintrag. Wie am iPhone bewusst nicht
  /// persistiert: nach jedem App-Start wieder aus.
  @Published var stoffwindelActive = false

  /// Übernommene Server-Verbindung; nil = alles läuft über das iPhone.
  @Published private(set) var connection: ServerConnection?

  /// Läuft gerade ein Import der Verbindung?
  @Published private(set) var isImporting = false

  /// Fehler, der eine Aktion verhindert oder unklar zurückgelassen hat.
  @Published var errorMessage: String?

  /// Kurzer Hinweis (z. B. Ausweichen aufs iPhone).
  @Published var notice: String?

  /// Statuszeile: „Direkt · API-Key“, „Direkt · mTLS“ oder „Über iPhone“.
  var statusText: String { connection?.label ?? "Über iPhone" }

  /// Einträge, die auf das iPhone warten. Direkt gesendete zählen nicht mit —
  /// sie sind binnen Sekunden entweder beim Server oder umgeleitet.
  var pendingRelay: [OutboxEntry] { outbox.filter { !$0.direct } }

  private let defaults = UserDefaults.standard

  /// REST-Client der Uhr; nil, solange keine Verbindung übernommen wurde.
  private var direct: DirectApi?

  /// Gespiegelter bzw. direkt vom Server geholter Stand.
  private var snapshotType: WickelType?
  private var snapshotTime: Date?
  private var snapshotStoffwindel = false

  /// Anzahl der Einträge von heute. Wird bewusst nicht angezeigt (die
  /// Watch-App bleibt auf Schnell-Eingabe beschränkt), ist aber die Grundlage
  /// für eine spätere Zifferblatt-Komplikation.
  private(set) var todayTotal = 0

  // ISO8601DateFormatter ist laut Apple-Doku thread-sicher.
  nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  /// Dart schreibt Zeitstempel mit Millisekunden, tolerant bleiben wir
  /// trotzdem gegenüber der Variante ohne.
  nonisolated private static func parseDate(_ text: String) -> Date? {
    if let date = isoFormatter.date(from: text) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: text)
  }

  override init() {
    super.init()
    loadSnapshot()
    loadOutbox()
    restoreConnection()
    discardUnconfirmedDirect()
    recompute()
  }

  // MARK: - Sitzung

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  // MARK: - Eingabe

  func add(_ type: WickelType) {
    let entry = OutboxEntry(
      id: UUID().uuidString,
      type: type.rawValue,
      time: Date(),
      // Der Schalter zählt nur, solange das iPhone die Funktion anbietet.
      stoffwindel: stoffwindelEnabled && stoffwindelActive,
      direct: direct != nil
    )
    outbox.append(entry)
    saveOutbox()
    recompute()
    errorMessage = nil
    notice = nil

    if let api = direct {
      sendDirect(entry, type: type, using: api)
    } else {
      transmit(entry)
    }
  }

  private func transmit(_ entry: OutboxEntry) {
    let session = WCSession.default
    // Vor der Aktivierung geht nichts raus — der Eintrag bleibt in der
    // Warteschlange und wird nach der Aktivierung nachgereicht.
    guard session.activationState == .activated else { return }

    let payload: [String: Any] = [
      "v": 1,
      "action": "add",
      "id": entry.id,
      "type": entry.type,
      "time": Self.isoFormatter.string(from: entry.time),
      "stoffwindel": entry.stoffwindel,
    ]
    session.transferUserInfo(payload)
    if session.isReachable {
      session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }
  }

  /// Schickt alles Offene erneut ans iPhone. Bereits zugestellte Einträge
  /// erkennt es an der ID und verwirft sie.
  private func retransmitOutbox() {
    for entry in outbox where !entry.direct { transmit(entry) }
  }

  // MARK: - Direktbetrieb

  /// Legt den Eintrag über die REST-API an und holt anschließend den Stand.
  private func sendDirect(_ entry: OutboxEntry, type: WickelType, using api: DirectApi) {
    Task {
      do {
        try await api.addEntry(type: type, stoffwindel: entry.stoffwindel)
        // Bewusst als eigener Vorgang: schlägt das Nachladen fehl, darf
        // keinesfalls der Eintrag erneut entstehen.
        let snapshot = try? await api.stats()
        self.confirmDirect(entry, type: type, snapshot: snapshot)
      } catch DirectApiError.unreachable {
        // Der Server war gar nicht erreichbar — nichts wurde gesendet, also
        // ist der Umweg über das iPhone gefahrlos.
        self.redirectToPhone(entry)
      } catch {
        self.abandonDirect(entry, message: error.localizedDescription)
      }
    }
  }

  private func confirmDirect(_ entry: OutboxEntry, type: WickelType, snapshot: DirectSnapshot?) {
    outbox.removeAll { $0.id == entry.id }
    saveOutbox()
    // Der Server kennt den Eintrag jetzt; bis der Stand geladen ist, gilt der
    // eigene Eintrag als aktueller Stand.
    snapshotType = type
    snapshotTime = entry.time
    snapshotStoffwindel = entry.stoffwindel
    todayTotal += 1
    if let snapshot { apply(snapshot) }
    persistSnapshot()
    recompute()
    errorMessage = nil
  }

  private func redirectToPhone(_ entry: OutboxEntry) {
    guard let index = outbox.firstIndex(where: { $0.id == entry.id }) else { return }
    let relayed = OutboxEntry(
      id: entry.id, type: entry.type, time: entry.time,
      stoffwindel: entry.stoffwindel, direct: false)
    outbox[index] = relayed
    saveOutbox()
    transmit(relayed)
    notice = "Server nicht direkt erreichbar — über das iPhone gemeldet."
  }

  /// Der Server hat geantwortet (oder die Übertragung brach mittendrin ab):
  /// Der Eintrag könnte angelegt sein. Erneut senden würde ihn womöglich
  /// verdoppeln, also melden statt wiederholen.
  private func abandonDirect(_ entry: OutboxEntry, message: String) {
    outbox.removeAll { $0.id == entry.id }
    saveOutbox()
    recompute()
    errorMessage = message
  }

  /// Holt den Stand direkt vom Server. Ohne übernommene Verbindung wirkungslos
  /// — dann spiegelt ihn das iPhone.
  func refreshFromServer() {
    guard let api = direct else { return }
    Task {
      guard let snapshot = try? await api.stats() else { return }
      self.apply(snapshot)
      self.persistSnapshot()
      self.recompute()
    }
  }

  private func apply(_ snapshot: DirectSnapshot) {
    snapshotType = snapshot.lastType
    snapshotTime = snapshot.lastTime
    snapshotStoffwindel = snapshot.lastStoffwindel
    todayTotal = snapshot.todayTotal
  }

  /// Direkt gesendete Einträge, deren Antwort die App nicht mehr erlebt hat
  /// (Prozess beendet), sind in unklarem Zustand — der Server könnte sie
  /// angelegt haben. Erneut senden hieße Doppel-Eintrag riskieren, also
  /// verwerfen und darauf hinweisen.
  private func discardUnconfirmedDirect() {
    let unconfirmed = outbox.filter { $0.direct }
    guard !unconfirmed.isEmpty else { return }
    outbox.removeAll { $0.direct }
    saveOutbox()
    notice = unconfirmed.count == 1
      ? "1 Eintrag blieb unbestätigt — bitte am iPhone prüfen."
      : "\(unconfirmed.count) Einträge blieben unbestätigt — bitte am iPhone prüfen."
  }

  // MARK: - Server-Verbindung übernehmen

  /// Holt die auf dem iPhone eingerichtete Server-Verbindung und legt sie auf
  /// der Uhr ab. Danach laufen alle Anfragen direkt.
  func importConnection() {
    guard WCSession.isSupported() else {
      errorMessage = "Diese Uhr kann sich nicht mit dem iPhone verbinden."
      return
    }
    let session = WCSession.default
    guard session.activationState == .activated else {
      errorMessage = "Verbindung zum iPhone wird aufgebaut …"
      session.activate()
      return
    }
    guard session.isReachable else {
      errorMessage = "iPhone nicht erreichbar. Bitte Wickel-Tracker dort kurz öffnen."
      return
    }

    isImporting = true
    errorMessage = nil
    notice = nil
    session.sendMessage(
      ["action": "getConnection"],
      replyHandler: { [weak self] reply in
        // [String: Any] ist nicht Sendable; die Antwort wird bewusst
        // unstrukturiert auf den MainActor gereicht.
        nonisolated(unsafe) let uebergabe = reply
        Task { @MainActor in self?.adopt(uebergabe) }
      },
      errorHandler: { [weak self] error in
        let text = error.localizedDescription
        Task { @MainActor in self?.failImport(text) }
      })
  }

  /// Verwirft die übernommene Verbindung; alles läuft wieder über das iPhone.
  func removeConnection() {
    direct?.close()
    direct = nil
    connection = nil
    ServerConnectionStore.delete()
    errorMessage = nil
    notice = nil
  }

  private func adopt(_ reply: [String: Any]) {
    guard reply["ok"] as? Bool == true else {
      failImport(reply["error"] as? String ?? "Unbekannter Fehler")
      return
    }
    guard let candidate = ServerConnection(reply: reply["data"] as? [String: Any] ?? [:]) else {
      failImport("Auf dem iPhone ist keine Server-Verbindung eingerichtet.")
      return
    }
    do {
      // Baut bei mTLS gleich die Identity — ein unbrauchbares Zertifikat soll
      // beim Import auffallen, nicht erst beim Speichern eines Eintrags.
      let api = try DirectApi(connection: candidate)
      direct?.close()
      direct = api
      connection = candidate
      ServerConnectionStore.save(candidate)
      isImporting = false
      errorMessage = nil
      // Eine Erfolgsmeldung erübrigt sich: die Statuszeile zeigt ab jetzt
      // „Direkt · …“ statt „Über iPhone“.
      refreshFromServer()
    } catch {
      failImport(error.localizedDescription)
    }
  }

  private func failImport(_ message: String) {
    isImporting = false
    errorMessage = message
  }

  private func restoreConnection() {
    guard let stored = ServerConnectionStore.load() else { return }
    do {
      direct = try DirectApi(connection: stored)
      connection = stored
    } catch {
      ServerConnectionStore.delete()
      errorMessage =
        "Gespeichertes Client-Zertifikat ist unbrauchbar: \(error.localizedDescription)"
    }
  }

  // MARK: - Zustand

  /// Angezeigt wird der jüngere von gespiegeltem Stand und eigener
  /// Warteschlange.
  private func recompute() {
    var type = snapshotType
    var time = snapshotTime
    var stoffwindel = snapshotStoffwindel
    if let newest = outbox.max(by: { $0.time < $1.time }),
       time == nil || newest.time > time! {
      type = WickelType(rawValue: newest.type)
      time = newest.time
      stoffwindel = newest.stoffwindel
    }
    lastType = type
    lastTime = time
    lastStoffwindel = stoffwindel
  }

  /// Übernimmt den vom iPhone gespiegelten Stand. Im Direktbetrieb kann er
  /// älter sein als das, was die Uhr selbst beim Server gesehen hat — er wird
  /// trotzdem übernommen und beim nächsten `refreshFromServer` korrigiert.
  private func applySnapshot(_ context: [String: Any]) {
    snapshotType = (context["lastType"] as? String).flatMap(WickelType.init(rawValue:))
    snapshotTime = (context["lastTime"] as? String).flatMap(Self.parseDate)
    snapshotStoffwindel = context["lastStoffwindel"] as? Bool ?? false
    stoffwindelEnabled = context["stoffwindelEnabled"] as? Bool ?? false
    todayTotal = context["todayTotal"] as? Int ?? 0
    persistSnapshot()
    recompute()
  }

  // MARK: - Persistenz

  private func persistSnapshot() {
    var stored: [String: Any] = [
      "lastStoffwindel": snapshotStoffwindel,
      "stoffwindelEnabled": stoffwindelEnabled,
      "todayTotal": todayTotal,
    ]
    if let snapshotType { stored["lastType"] = snapshotType.rawValue }
    if let snapshotTime { stored["lastTime"] = Self.isoFormatter.string(from: snapshotTime) }
    defaults.set(stored, forKey: Key.snapshot)
  }

  private func loadSnapshot() {
    guard let stored = defaults.dictionary(forKey: Key.snapshot) else { return }
    snapshotType = (stored["lastType"] as? String).flatMap(WickelType.init(rawValue:))
    snapshotTime = (stored["lastTime"] as? String).flatMap(Self.parseDate)
    snapshotStoffwindel = stored["lastStoffwindel"] as? Bool ?? false
    stoffwindelEnabled = stored["stoffwindelEnabled"] as? Bool ?? false
    todayTotal = stored["todayTotal"] as? Int ?? 0
  }

  private func saveOutbox() {
    guard let data = try? JSONEncoder().encode(outbox) else { return }
    defaults.set(data, forKey: Key.outbox)
  }

  private func loadOutbox() {
    guard let data = defaults.data(forKey: Key.outbox),
          let stored = try? JSONDecoder().decode([OutboxEntry].self, from: data)
    else { return }
    outbox = stored
  }
}

// MARK: - WCSessionDelegate

extension WatchStore: WCSessionDelegate {
  // Die Delegate-Callbacks kommen von beliebigen Threads; die Verarbeitung
  // springt auf den MainActor ([String: Any] ist nicht Sendable und wird
  // bewusst unstrukturiert übergeben).
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
    error: Error?
  ) {
    guard error == nil, state == .activated else { return }
    nonisolated(unsafe) let context = session.receivedApplicationContext
    Task { @MainActor in
      if !context.isEmpty { self.applySnapshot(context) }
      self.retransmitOutbox()
      self.refreshFromServer()
    }
  }

  nonisolated func session(
    _ session: WCSession, didReceiveApplicationContext context: [String: Any]
  ) {
    nonisolated(unsafe) let uebergabe = context
    Task { @MainActor in self.applySnapshot(uebergabe) }
  }

  /// Zustellung bestätigt — der Eintrag darf aus der Warteschlange.
  nonisolated func session(
    _ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
    error: Error?
  ) {
    guard error == nil, let id = userInfoTransfer.userInfo["id"] as? String else { return }
    Task { @MainActor in
      self.outbox.removeAll { $0.id == id }
      self.saveOutbox()
      self.recompute()
    }
  }
}
