import Combine
import Foundation
import Network

// MARK: - Warteschlange

/// Ein offline erfasster Eintrag, der noch zum Server muss.
struct Warteeintrag: Codable, Equatable {
  let type: WickelType
  let stoffwindel: Bool
  /// Zeitpunkt der Erfassung, nicht des Hochladens – sonst bekäme der Eintrag
  /// beim Nachholen die falsche Uhrzeit.
  let time: Date
}

/// Die geordnete Liste der offenen Einträge eines Zugangs.
///
/// Anders als beim Stillzeit-Tracker gibt es hier nur eine Schreibaktion:
/// Anlegen. `undoLast` lässt sich nicht sinnvoll vormerken, weil die API dafür
/// keine ID kennt — beim Nachholen träfe es womöglich einen Eintrag, den
/// jemand anders inzwischen angelegt hat. Offline nimmt `undoLast` deshalb nur
/// den zuletzt **vorgemerkten** Eintrag zurück; ist keiner da, meldet es wie
/// bisher einen Fehler.
struct Warteschlange: Codable, Equatable {

  private(set) var eintraege: [Warteeintrag] = []

  var istLeer: Bool { eintraege.isEmpty }
  var anzahl: Int { eintraege.count }

  mutating func lege(_ eintrag: Warteeintrag) {
    eintraege.append(eintrag)
  }

  /// Nimmt den zuletzt vorgemerkten Eintrag zurück; false, wenn keiner wartet.
  mutating func nimmLetztenZurueck() -> Bool {
    guard !eintraege.isEmpty else { return false }
    eintraege.removeLast()
    return true
  }

  mutating func entferneErsten() {
    if !eintraege.isEmpty { eintraege.removeFirst() }
  }

  /// Rechnet die wartenden Einträge in die Statistik ein.
  ///
  /// Die Prozentanteile bleiben, wie der Server sie gemeldet hat: Sie aus den
  /// wartenden Einträgen neu zu berechnen ginge nur mit den Rohdaten, die die
  /// API nicht liefert. Gesamtzahlen und der letzte Eintrag stimmen dagegen —
  /// und genau die stehen in der App im Vordergrund.
  func anwenden(auf stats: WickelStats, jetzt: Date = Date()) -> WickelStats {
    guard !eintraege.isEmpty else { return stats }
    var werte = stats
    let kalender = Calendar.current
    for eintrag in eintraege {
      if kalender.isDate(eintrag.time, inSameDayAs: jetzt) { werte.today.total += 1 }
      if eintrag.time > jetzt.vorTagen(7) { werte.week.total += 1 }
      if eintrag.time > jetzt.vorTagen(21) { werte.threeWeeks.total += 1 }
      if eintrag.time > jetzt.vorTagen(30) { werte.month.total += 1 }
    }
    // Der jüngste wartende Eintrag ist der letzte – sofern er nicht älter ist
    // als der, den der Server kennt.
    if let neuester = eintraege.max(by: { $0.time < $1.time }),
      werte.last.time.map({ neuester.time > $0 }) ?? true
    {
      werte.last = LastEntry(
        type: neuester.type, time: neuester.time, stoffwindel: neuester.stoffwindel)
    }
    return werte
  }
}

extension Date {
  fileprivate func vorTagen(_ tage: Int) -> Date {
    addingTimeInterval(-Double(tage) * 24 * 60 * 60)
  }
}

// MARK: - Ablage

/// Legt Warteschlange und Lesestand je Zugang im App-Verzeichnis ab.
///
/// Der Schlüssel ist Modus plus Basis-URL: Wer zwischen zwei Servern wechselt,
/// bekommt nicht den Stand des anderen zu sehen und lädt auch keine
/// Warteschlange dorthin hoch, wo sie nicht hingehört. Die Ablage liegt in
/// `Application Support` und damit ausserhalb von `Caches` — der Lesestand
/// darf verschwinden, die Warteschlange nicht.
struct OfflineSpeicher {

  private let ordner: URL
  private let schluessel: String

  init(zugang: String) {
    schluessel = zugang.map { $0.isLetter || $0.isNumber ? $0 : "_" }.map(String.init).joined()
    let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ordner = basis.appendingPathComponent("Offline", isDirectory: true)
    try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
  }

  private var warteschlangeUrl: URL {
    ordner.appendingPathComponent("warteschlange_\(schluessel).json")
  }

  private var statsUrl: URL {
    ordner.appendingPathComponent("stats_\(schluessel).json")
  }

  func ladeWarteschlange() -> Warteschlange {
    guard let daten = try? Data(contentsOf: warteschlangeUrl),
      let warteschlange = try? JSONDecoder().decode(Warteschlange.self, from: daten)
    else { return Warteschlange() }
    return warteschlange
  }

  func speichere(_ warteschlange: Warteschlange) {
    guard let daten = try? JSONEncoder().encode(warteschlange) else { return }
    try? daten.write(to: warteschlangeUrl, options: .atomic)
  }

  func ladeStats() -> WickelStats? {
    guard let daten = try? Data(contentsOf: statsUrl) else { return nil }
    return try? JSONDecoder().decode(WickelStats.self, from: daten)
  }

  func speichere(stats: WickelStats) {
    guard let daten = try? JSONEncoder().encode(stats) else { return }
    try? daten.write(to: statsUrl, options: .atomic)
  }
}

// MARK: - Zustand

/// Der Offline-Zustand, den die Oberfläche anzeigt.
@MainActor
final class OfflineStatus: ObservableObject {

  static let shared = OfflineStatus()

  /// Grund der letzten gescheiterten Verbindung; nil heisst „online“.
  @Published private(set) var grund: String?
  /// Anzahl der Einträge, die noch auf Übertragung warten.
  @Published private(set) var ausstehend = 0

  var istOffline: Bool { grund != nil }

  fileprivate func melde(grund: String?) { self.grund = grund }
  fileprivate func melde(ausstehend: Int) { self.ausstehend = ausstehend }

  /// Setzt alles zurück – beim Wechsel der Datenquelle, damit der Hinweis des
  /// alten Zugangs nicht über dem neuen stehen bleibt.
  func zuruecksetzen() {
    grund = nil
    ausstehend = 0
  }
}

// MARK: - Dienst

/// Legt sich über die Server-Quelle und hält die App bei einem
/// Verbindungsabbruch benutzbar.
///
/// Lesen: Bei jedem Netzwerkfehler wird der zuletzt erfolgreiche Stand
/// gezeigt — dabei ist gleich, ob die Anfrage ankam, denn ein Lesevorgang
/// verändert nichts.
///
/// Schreiben: In die Warteschlange darf ein Eintrag **nur**, wenn er den
/// Server nachweislich nie erreicht hat (`Netzfehler.nieGesendet`). Bei einer
/// Zeitüberschreitung oder einem Abbruch mitten in der Übertragung könnte der
/// Server ihn bereits angelegt haben; ein zweiter Versuch legte dann einen
/// zweiten an.
///
/// Die Uhr benutzt diesen Umweg bewusst nicht: sie führt eine eigene Outbox
/// und würde denselben Eintrag sonst zweimal einreihen.
final class OfflineService: WickelService {

  private let innen: WickelService
  private let speicher: OfflineSpeicher

  private let sperre = NSLock()
  nonisolated(unsafe) private var warteschlange: Warteschlange

  init(innen: WickelService, zugang: String) {
    self.innen = innen
    self.speicher = OfflineSpeicher(zugang: zugang)
    self.warteschlange = speicher.ladeWarteschlange()
    meldeStand()
  }

  func getStats() async throws -> WickelStats {
    do {
      let vomServer = try await innen.getStats()
      speicher.speichere(stats: vomServer)
      await online()
      return aktuelleWarteschlange.anwenden(auf: vomServer)
    } catch let fehler as ServiceError where fehler.netzfehler != nil {
      guard let stand = speicher.ladeStats() else { throw fehler }
      await offline(fehler.message)
      return aktuelleWarteschlange.anwenden(auf: stand)
    }
  }

  func addEntry(type: WickelType, stoffwindel: Bool, time: Date?) async throws {
    let zeit = time ?? Date()
    // Reihenfolge wahren: Steht schon etwas an, gehört auch das Neue hinten
    // dran, statt es am Stau vorbeizuschicken.
    guard aktuelleWarteschlange.istLeer else {
      reiheEin(type: type, stoffwindel: stoffwindel, time: zeit)
      return
    }
    do {
      try await innen.addEntry(type: type, stoffwindel: stoffwindel, time: time)
      await online()
    } catch let fehler as ServiceError where fehler.netzfehler == .nieGesendet {
      await offline(fehler.message)
      reiheEin(type: type, stoffwindel: stoffwindel, time: zeit)
    }
  }

  @discardableResult
  func undoLast() async throws -> Bool {
    // Wartet noch etwas, ist das der zuletzt erfasste Eintrag – den nimmt die
    // App direkt zurück, ohne den Server zu behelligen.
    var zurueckgenommen = false
    schreibeWarteschlange { zurueckgenommen = $0.nimmLetztenZurueck() }
    if zurueckgenommen { return true }
    // Sonst muss der Server ran. Offline lässt sich das **nicht** vormerken:
    // Die API kennt für `undoLast` keine ID, beim Nachholen träfe es
    // womöglich einen Eintrag, den jemand anders inzwischen angelegt hat.
    return try await innen.undoLast()
  }

  // MARK: - Nachholen

  /// Arbeitet die Warteschlange von vorn ab.
  ///
  /// Bricht beim ersten Verbindungsfehler ab — der Rest bleibt in der
  /// Reihenfolge stehen. Weist der Server einen Eintrag inhaltlich zurück,
  /// fliegt er raus und wird gemeldet; sonst blockierte er die Warteschlange
  /// für immer.
  ///
  /// Liefert die Meldungen zu verworfenen Einträgen.
  @discardableResult
  func nachholen() async -> [String] {
    var verworfen: [String] = []
    while let naechster = aktuelleWarteschlange.eintraege.first {
      do {
        try await innen.addEntry(
          type: naechster.type, stoffwindel: naechster.stoffwindel, time: naechster.time)
        schreibeWarteschlange { $0.entferneErsten() }
      } catch let fehler as ServiceError where fehler.netzfehler != nil {
        await offline(fehler.message)
        return verworfen
      } catch {
        schreibeWarteschlange { $0.entferneErsten() }
        verworfen.append(error.localizedDescription)
      }
    }
    await online()
    return verworfen
  }

  // MARK: - Innere Hilfen

  private var aktuelleWarteschlange: Warteschlange {
    sperre.withLock { warteschlange }
  }

  private func reiheEin(type: WickelType, stoffwindel: Bool, time: Date) {
    schreibeWarteschlange {
      $0.lege(Warteeintrag(type: type, stoffwindel: stoffwindel, time: time))
    }
  }

  private func schreibeWarteschlange(_ aenderung: (inout Warteschlange) -> Void) {
    let stand: Warteschlange = sperre.withLock {
      aenderung(&warteschlange)
      return warteschlange
    }
    speicher.speichere(stand)
    meldeStand()
  }

  private func meldeStand() {
    let anzahl = aktuelleWarteschlange.anzahl
    Task { @MainActor in OfflineStatus.shared.melde(ausstehend: anzahl) }
  }

  @MainActor private func offline(_ grund: String) {
    OfflineStatus.shared.melde(grund: grund)
  }

  @MainActor private func online() {
    OfflineStatus.shared.melde(grund: nil)
  }
}

// MARK: - Verbindungswache

/// Meldet, sobald wieder ein Netzwerkpfad da ist — damit die Warteschlange
/// nicht erst beim nächsten Antippen abgearbeitet wird.
@MainActor
final class Verbindungswache: ObservableObject {

  static let shared = Verbindungswache()

  /// Feuert bei jedem Wechsel von „kein Pfad“ zu „Pfad da“.
  let wiederVerbunden = PassthroughSubject<Void, Never>()

  private let wache = NWPathMonitor()
  private var warOffline = false

  private init() {
    wache.pathUpdateHandler = { [weak self] pfad in
      // Erst auspacken, dann in den Task: `self?` im Task griffe auf die
      // schwache Bindung der äußeren Closure zu, und ein solcher Zugriff aus
      // nebenläufigem Code ist in Swift 6 ein Fehler.
      guard let self else { return }
      let verbunden = pfad.status == .satisfied
      Task { @MainActor in self.pfadGeaendert(verbunden) }
    }
    wache.start(queue: DispatchQueue(label: "wickel.verbindungswache"))
  }

  private func pfadGeaendert(_ verbunden: Bool) {
    if verbunden, warOffline { wiederVerbunden.send(()) }
    warOffline = !verbunden
  }
}
