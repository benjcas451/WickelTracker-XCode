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

  private var service: WickelService = createConfiguredWickelService()
  private var beobachter: AnyCancellable?

  init() {
    // Übernommene Watch-Einträge lösen ein Neuladen aus.
    beobachter = NotificationCenter.default
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
  }

  /// Baut die Datenquelle anhand der Einstellung neu auf (z. B. nach dem
  /// Verlassen der Einstellungen) und lädt anschließend neu.
  func datenquelleNeuAufbauen() {
    service = createConfiguredWickelService()
    stoffwindelEnabled = AppSettings.stoffwindelEnabled
    aktualisieren()
    // Liegengebliebene Watch-Einträge mit der (neuen) Quelle verarbeiten.
    WatchBridge.shared.verarbeitePending()
  }

  func aktualisieren() {
    laedt = true
    fehler = nil
    Task {
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
