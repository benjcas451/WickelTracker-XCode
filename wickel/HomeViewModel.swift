import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {

  @Published var laedt = true
  @Published var fehler: String?
  @Published var stats: WickelStats?

  /// Stoffwindel-Funktion in den Einstellungen aktiviert?
  @Published var stoffwindelEnabled = AppSettings.stoffwindelEnabled

  /// Umschaltfläche: nächster Eintrag ist eine Stoffwindel.
  @Published var stoffwindelActive = false

  /// Kurzmeldungen (Fehler bei Aktionen, Backup-Ergebnisse).
  @Published var meldung: String?

  /// Grund der abgebrochenen Verbindung; nil heisst „online“.
  @Published var offlineGrund: String?
  /// Anzahl der Einträge, die noch auf Übertragung warten.
  @Published var ausstehend = 0

  private var service: WickelService = createConfiguredWickelService(offlineFaehig: true)
  private var beobachter: Set<AnyCancellable> = []

  init() {
    // Übernommene Watch-Einträge lösen ein Neuladen aus.
    NotificationCenter.default
      .publisher(for: .wickelWatchAenderung)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] mitteilung in
        if let anzahl = mitteilung.userInfo?["anzahl"] as? Int {
          self?.meldung =
            anzahl == 1
            ? "1 Eintrag von der Apple Watch übernommen"
            : "\(anzahl) Einträge von der Apple Watch übernommen"
        }
        self?.aktualisieren()
      }
      .store(in: &beobachter)

    // Den Offline-Zustand übernehmen, statt ihn doppelt zu führen.
    let status = OfflineStatus.shared
    status.$grund.assign(to: &$offlineGrund)
    status.$ausstehend.assign(to: &$ausstehend)

    // Sobald wieder ein Netzwerkpfad da ist, die Warteschlange abarbeiten –
    // ohne dass der Nutzer etwas antippen muss.
    Verbindungswache.shared.wiederVerbunden
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.aktualisieren() }
      .store(in: &beobachter)
  }

  /// Baut die Datenquelle anhand der Einstellung neu auf (z. B. nach dem
  /// Verlassen der Einstellungen) und lädt anschließend neu.
  func datenquelleNeuAufbauen() {
    // Der Hinweis des alten Zugangs darf nicht über dem neuen stehen bleiben;
    // die neue Datenquelle meldet ihren eigenen Stand sofort nach.
    OfflineStatus.shared.zuruecksetzen()
    service = createConfiguredWickelService(offlineFaehig: true)
    stoffwindelEnabled = AppSettings.stoffwindelEnabled
    aktualisieren()
    // Liegengebliebene Watch-Einträge mit der (neuen) Quelle verarbeiten.
    WatchBridge.shared.verarbeitePending()
  }

  func aktualisieren() {
    laedt = true
    fehler = nil
    Task {
      // Erst das Liegengebliebene loswerden, dann laden: sonst zeigte die
      // Statistik einen Serverstand ohne die eigenen Einträge.
      await warteschlangeAbarbeiten()
      do {
        let neu = try await service.getStats()
        stats = neu
        laedt = false
        // Watch mit dem frischen Stand versorgen (fehlertolerant).
        WatchBridge.shared.pushSnapshot(stats: neu, stoffwindelEnabled: stoffwindelEnabled)
      } catch {
        fehler = error.localizedDescription
        laedt = false
      }
    }
  }

  func anlegen(_ type: WickelType) {
    let sw = stoffwindelEnabled && stoffwindelActive
    fuehreAus { [self] in
      try await service.addEntry(type: type, stoffwindel: sw, time: nil)
      meldung = "\(type.label) gespeichert\(sw ? " · 🧷 Stoffwindel" : "")"
    }
  }

  func letztenRueckgaengig() {
    fuehreAus { [self] in
      let entfernt = try await service.undoLast()
      meldung = entfernt ? "Letzter Eintrag gelöscht" : "Kein Eintrag vorhanden"
    }
  }

  /// Schickt die offenen Einträge zum Server. Verworfene (vom Server
  /// inhaltlich zurückgewiesene) meldet sie einmal gesammelt.
  private func warteschlangeAbarbeiten() async {
    guard let offline = service as? OfflineService else { return }
    let verworfen = await offline.nachholen()
    guard !verworfen.isEmpty else { return }
    meldung = verworfen.count == 1
      ? "Ein wartender Eintrag wurde vom Server abgelehnt: \(verworfen[0])"
      : "\(verworfen.count) wartende Einträge wurden vom Server abgelehnt."
  }

  /// Führt eine schreibende Aktion aus und lädt danach neu.
  private func fuehreAus(_ aktion: @escaping () async throws -> Void) {
    Task {
      do {
        try await aktion()
        aktualisieren()
      } catch {
        meldung = "Fehler: \(error.localizedDescription)"
      }
    }
  }
}
