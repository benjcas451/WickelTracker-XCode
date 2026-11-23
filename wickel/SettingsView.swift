import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var mode = AppSettings.mode
  @State private var apiUrl = AppSettings.apiBaseUrl
  @State private var apiKeyUrl = AppSettings.apiKeyBaseUrl
  @State private var cloudflareUrl = AppSettings.cloudflareBaseUrl
  @State private var apiKey = AppSettings.apiKey
  @State private var cfClientId = AppSettings.cfAccessClientId
  @State private var cfClientSecret = AppSettings.cfAccessClientSecret
  @State private var apiKeySichtbar = false
  @State private var certsOk = CertSource().sindVorhanden
  @State private var certOrt = CertSource().locationLabel
  @State private var eigenerCertOrdner = CertSource().eigenerOrdner
  @State private var zeigeOrdnerwahl = false
  @State private var meldung: String?
  @State private var infoTitel: String?
  @State private var infoText: String?
  @State private var restoreBestaetigen = false
  @State private var stoffwindelEnabled = AppSettings.stoffwindelEnabled
  @State private var exportDokument: BackupDokument?
  @State private var zeigeImport = false
  private let certSource = CertSource()

  @FocusState private var urlFokus: Bool
  @FocusState private var keyFokus: Bool
  @FocusState private var cfIdFokus: Bool
  @FocusState private var cfSecretFokus: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        // Die eine Hauptaktion dieser Ansicht: „Fertig“ schließt den Bogen.
        MhKopf("Einstellungen") {
          EmptyView()
        } hauptaktion: {
          // Volle Höhe (44 pt): die kleine Variante hätte nur 36 pt Tippfläche.
          Button("Fertig") { dismiss() }
            .buttonStyle(.mhHaupt)
        }
        datenquelle
        if mode == .apiKey { apiKeySektion }
        if mode == .api { mtlsSektion }
        if mode == .cloudflare { cloudflareSektion }
        if mode == .demo { backupSektion }
        optionen
        erklaerung
      }
      .padding(.horizontal, Mh.rand)
      .padding(.top, Mh.abstand5)
      .padding(.bottom, Mh.abstand12)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(Mh.bg.ignoresSafeArea())
    .alert(
      "Hinweis", isPresented: .init(get: { meldung != nil }, set: { if !$0 { meldung = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(meldung ?? "")
    }
    .alert("Backup wiederherstellen?", isPresented: $restoreBestaetigen) {
      Button("Abbrechen", role: .cancel) {}
      Button("Backup auswählen") { zeigeImport = true }
    } message: {
      Text(
        "Alle aktuell lokal gespeicherten Einträge werden durch den Inhalt des "
          + "Backups ersetzt. Dieser Vorgang kann nicht rückgängig gemacht werden.")
    }
    .sheet(
      isPresented: .init(get: { infoText != nil }, set: { if !$0 { infoText = nil } })
    ) {
      InfoSheet(titel: infoTitel ?? "", text: infoText ?? "")
    }
    .fileExporter(
      isPresented: .init(get: { exportDokument != nil }, set: { if !$0 { exportDokument = nil } }),
      document: exportDokument,
      contentType: .json,
      defaultFilename: LocalBackupService.dateiname()
    ) { ergebnis in
      switch ergebnis {
      case .success: meldung = "Backup gespeichert."
      case .failure(let fehler): meldung = "Backup fehlgeschlagen: \(fehler.localizedDescription)"
      }
    }
    .fileImporter(isPresented: $zeigeImport, allowedContentTypes: [.json]) { ergebnis in
      wiederherstellen(ergebnis)
    }
  }

  // MARK: - Sektionen

  private var datenquelle: some View {
    VStack(alignment: .leading, spacing: 0) {
      MhGruppenLabel("Datenquelle")
      ModusZeile(
        gewaehlt: mode == .api, titel: "Server (mTLS-API)",
        untertitel: "Client-Zertifikat + API-Key"
      ) { setzeModus(.api) }
      MhTrennlinie()
      ModusZeile(
        gewaehlt: mode == .apiKey, titel: "Server (API-Key)",
        untertitel: "API-Key ohne Client-Zertifikat"
      ) { setzeModus(.apiKey) }
      MhTrennlinie()
      ModusZeile(
        gewaehlt: mode == .cloudflare, titel: "Server (Cloudflare Access)",
        untertitel: "Service Token + API-Key"
      ) { setzeModus(.cloudflare) }
      MhTrennlinie()
      ModusZeile(
        gewaehlt: mode == .demo, titel: "Lokal (SQLite)",
        untertitel: "Einträge bleiben nur auf diesem Gerät"
      ) { setzeModus(.demo) }
    }
  }

  private func setzeModus(_ neu: DataSourceMode) {
    mode = neu
    AppSettings.mode = neu
  }

  /// Der API-Key wird in beiden Server-Modi mitgesendet – die api.php
  /// verlangt ihn in jedem Fall, auch hinter mTLS.
  private func apiKeyFeld(hilfe: String?) -> some View {
    MhFeld("API-Key", hinweis: hilfe) {
      HStack(spacing: 0) {
        Group {
          if apiKeySichtbar {
            TextField("", text: $apiKey)
          } else {
            SecureField("", text: $apiKey)
          }
        }
        .focused($keyFokus)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .accessibilityLabel("API-Key")
        .onChange(of: apiKey) { neu in AppSettings.apiKey = neu }
        SichtbarKnopf(sichtbar: $apiKeySichtbar)
      }
      .mhEingabe(fokus: keyFokus, mitKnopf: true)
    }
  }

  private var apiKeySektion: some View {
    VStack(alignment: .leading, spacing: Mh.abstand4) {
      MhGruppenLabel("Server (API-Key)")
      UrlFeld(wert: $apiKeyUrl, fokus: $urlFokus) { AppSettings.apiKeyBaseUrl = $0 }
      apiKeyFeld(hilfe: "Erforderlich – die api.php verlangt den Key in jedem Fall.")
    }
  }

  private var mtlsSektion: some View {
    VStack(alignment: .leading, spacing: Mh.abstand4) {
      MhGruppenLabel("Server (mTLS-API)")
      UrlFeld(wert: $apiUrl, fokus: $urlFokus) { AppSettings.apiBaseUrl = $0 }
      zertifikatsBlock
      apiKeyFeld(hilfe: "Erforderlich – die api.php verlangt den Key in jedem Fall.")
    }
  }

  /// Cloudflare Access prüft das Service Token am Rand und reicht die
  /// Anfrage erst danach an den Server weiter. Der API-Key bleibt trotzdem
  /// nötig – die api.php verlangt ihn in jedem Fall.
  private var cloudflareSektion: some View {
    VStack(alignment: .leading, spacing: Mh.abstand4) {
      MhGruppenLabel("Server (Cloudflare Access)")
      UrlFeld(wert: $cloudflareUrl, fokus: $urlFokus) { AppSettings.cloudflareBaseUrl = $0 }
      GeheimFeld(
        wert: $cfClientId, fokus: $cfIdFokus, titel: "Client-ID",
        hinweis: "Client-ID des Service Tokens, endet üblicherweise auf „.access“."
      ) { AppSettings.cfAccessClientId = $0 }
      GeheimFeld(
        wert: $cfClientSecret, fokus: $cfSecretFokus, titel: "Client-Secret",
        hinweis: "Beide Teile nötig. Service Tokens laufen ab, standardmäßig "
          + "nach einem Jahr."
      ) { AppSettings.cfAccessClientSecret = $0 }
      apiKeyFeld(hilfe: "Erforderlich – die api.php verlangt den Key in jedem Fall.")
    }
  }

  /// Status der Client-Zertifikate samt Ordnerwahl. Standard bleibt der
  /// App-Ordner in der Dateien-App; alternativ lässt sich ein beliebiger
  /// Ordner auswählen, auf den die App per security-scoped Bookmark
  /// zugreift – dieselbe Bedienung wie in „Hello Baby“.
  private var zertifikatsBlock: some View {
    VStack(alignment: .leading, spacing: Mh.abstand3) {
      HStack(alignment: .top, spacing: Mh.abstand3) {
        MhSymbol(certsOk ? "MhCheck" : "MhAlert")
          .foregroundStyle(certsOk ? Mh.successFg : Mh.errorFg)
          .padding(.top, 1)
        VStack(alignment: .leading, spacing: 2) {
          Text(certsOk ? "Zertifikate gefunden" : "Keine Zertifikate gefunden")
            .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
            .foregroundStyle(Mh.textStrong)
          Text("\(CertSource.certFileName) & \(CertSource.keyFileName) – \(certOrt)")
            .mhText(.small).foregroundStyle(Mh.textSecondary)
          if !eigenerCertOrdner {
            Text(
              "Per Dateien-App in den Ordner der App „Windel-Tracker“ kopieren – oder "
                + "unten einen eigenen Ordner wählen.")
              .mhText(.small).foregroundStyle(Mh.textSecondary)
          }
        }
        .accessibilityElement(children: .combine)
      }
      zertifikatsButton("Zertifikats-Ordner wählen", "MhFolder") { zeigeOrdnerwahl = true }
      if eigenerCertOrdner {
        zertifikatsButton("Standard: App-Ordner (Dateien-App)", "MhHome") {
          certSource.nutzeStandardOrdner()
          pruefeZertifikate()
        }
      }
      zertifikatsButton("Erneut prüfen", "MhRefresh") {
        pruefeZertifikate()
        meldung = certsOk ? "Zertifikate gefunden." : "Keine Zertifikate gefunden."
      }
    }
    // Bewusst hier und nicht am Wurzel-View: dort hängt bereits der Importer
    // für Backups, und zwei fileImporter am selben View vertragen sich nicht.
    .fileImporter(isPresented: $zeigeOrdnerwahl, allowedContentTypes: [.folder]) { ergebnis in
      if case .success(let url) = ergebnis {
        do {
          try certSource.uebernehmeOrdner(url: url)
        } catch {
          meldung = "Ordner konnte nicht übernommen werden: \(error.localizedDescription)"
        }
        pruefeZertifikate()
      }
    }
  }

  private func zertifikatsButton(
    _ titel: String, _ symbol: String, _ aktion: @escaping () -> Void
  ) -> some View {
    Button(action: aktion) {
      MhButtonInhalt(titel, symbol: symbol)
    }
    .buttonStyle(.mhZweit)
  }

  private func pruefeZertifikate() {
    // Nebenbei: legt die Hinweisdatei an, falls sie fehlt. Damit laesst sich
    // der App-Ordner in der Dateien-App auch ohne Neustart hervorholen.
    AppOrdner.sichtbarMachen()
    certsOk = certSource.sindVorhanden
    certOrt = certSource.locationLabel
    eigenerCertOrdner = certSource.eigenerOrdner
  }

  private var backupSektion: some View {
    VStack(alignment: .leading, spacing: Mh.abstand2) {
      MhGruppenLabel("Backup")
      Button {
        exportieren()
      } label: {
        MhButtonInhalt("In iCloud speichern", symbol: "MhUpload")
      }
      .buttonStyle(MhZweitButtonStil(breit: true))
      Button {
        restoreBestaetigen = true
      } label: {
        MhButtonInhalt("Backup wiederherstellen", symbol: "MhDownload")
      }
      .buttonStyle(MhZweitButtonStil(breit: true))
      Text("Im Dateidialog iCloud Drive als Ziel wählen.")
        .mhText(.small).foregroundStyle(Mh.textSecondary)
    }
  }

  private var optionen: some View {
    VStack(alignment: .leading, spacing: 0) {
      MhGruppenLabel("Optionen")
      Toggle(isOn: $stoffwindelEnabled) {
        HStack(alignment: .top, spacing: Mh.abstand3) {
          MhSymbol("MhDiaper").foregroundStyle(Mh.textSecondary).padding(.top, 1)
          VStack(alignment: .leading, spacing: 2) {
            Text("Stoffwindel-Funktion")
              .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
              .foregroundStyle(Mh.textStrong)
            Text("Zeigt beim Eintragen eine Umschaltfläche für Stoffwindeln")
              .mhText(.small).foregroundStyle(Mh.textSecondary)
          }
        }
      }
      .tint(Mh.primary)
      .padding(.vertical, Mh.abstand2)
      .onChange(of: stoffwindelEnabled) { neu in AppSettings.stoffwindelEnabled = neu }
    }
  }

  private var erklaerung: some View {
    VStack(alignment: .leading, spacing: 0) {
      MhGruppenLabel("Erklärung")
      Button {
        infoTitel = "Aufbau API"
        infoText = SettingsView.apiInfoText
      } label: {
        MhListenZeile("Aufbau API", symbol: "MhCloud", pfeil: true)
      }
      .buttonStyle(.plain)
      MhTrennlinie()
      Button {
        infoTitel = "Aufbau Datenbank"
        infoText = SettingsView.dbInfoText
      } label: {
        MhListenZeile("Aufbau Datenbank", symbol: "MhList", pfeil: true)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Backup-Logik

  private func exportieren() {
    Task {
      do {
        let rows = try await DemoService.shared.exportRows()
        exportDokument = BackupDokument(daten: try LocalBackupService.exportJson(rows))
      } catch {
        meldung = "Backup fehlgeschlagen: \(error.localizedDescription)"
      }
    }
  }

  private func wiederherstellen(_ ergebnis: Result<URL, Error>) {
    Task {
      do {
        let url = try ergebnis.get()
        guard url.startAccessingSecurityScopedResource() else {
          throw ServiceError(message: "Datei ließ sich nicht öffnen.")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let rows = try LocalBackupService.parseUndValidiere(
          try LocalBackupService.leseBegrenzt(url))
        try await DemoService.shared.replaceAll(rows)
        meldung = "Wiederherstellung erfolgreich: \(rows.count) Einträge."
      } catch {
        meldung = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"
      }
    }
  }
}

// MARK: - Bausteine

/// Eine Datenquelle: Titel und Untertitel, gewählt mit Haken in Linkfarbe.
private struct ModusZeile: View {
  let gewaehlt: Bool
  let titel: String
  let untertitel: String
  let onWahl: () -> Void

  var body: some View {
    Button(action: onWahl) {
      MhListenZeile(titel, untertitel: untertitel) {
        MhSymbol("MhCheck")
          .foregroundStyle(Mh.link)
          .opacity(gewaehlt ? 1 : 0)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(gewaehlt ? [.isSelected] : [])
  }
}

/// Auge zum Auf- und Zudecken eines verdeckten Feldes.
private struct SichtbarKnopf: View {
  @Binding var sichtbar: Bool

  var body: some View {
    MhSymbolButton(
      sichtbar ? "MhEyeOff" : "MhEye",
      beschreibung: sichtbar ? "Verbergen" : "Anzeigen"
    ) {
      sichtbar.toggle()
    }
  }
}

private extension View {
  /// Eingabefeld nach Guide: 44 pt, Radius 10, Haarlinie `borderStrong`,
  /// Grund `fieldBg`; im Fokus Rand in `focusRing`.
  func mhEingabe(fokus: Bool, mitKnopf: Bool = false) -> some View {
    self
      .mhText(.body)
      .foregroundStyle(Mh.textStrong)
      .tint(Mh.primary)
      .padding(.leading, Mh.abstand3)
      .padding(.trailing, mitKnopf ? 0 : Mh.abstand3)
      .frame(minHeight: Mh.touch)
      .background(RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous).fill(Mh.fieldBg))
      .overlay(
        RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
          .stroke(fokus ? Mh.focusRing : Mh.borderStrong, lineWidth: 1))
  }
}

/// Verdecktes Eingabefeld mit Auge zum Aufdecken – für die beiden Hälften
/// des Cloudflare Service Tokens.
private struct GeheimFeld: View {
  @Binding var wert: String
  var fokus: FocusState<Bool>.Binding
  let titel: String
  let hinweis: String
  let onAenderung: (String) -> Void

  @State private var sichtbar = false

  var body: some View {
    MhFeld(titel, hinweis: hinweis) {
      HStack(spacing: 0) {
        Group {
          if sichtbar {
            TextField("", text: $wert)
          } else {
            SecureField("", text: $wert)
          }
        }
        .focused(fokus)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .accessibilityLabel(titel)
        .onChange(of: wert) { neu in onAenderung(neu) }
        SichtbarKnopf(sichtbar: $sichtbar)
      }
      .mhEingabe(fokus: fokus.wrappedValue, mitKnopf: true)
    }
  }
}

private struct UrlFeld: View {
  @Binding var wert: String
  var fokus: FocusState<Bool>.Binding
  let onAenderung: (String) -> Void

  var body: some View {
    MhFeld("API-URL", hinweis: "Basis-URL der API inkl. abschließendem /") {
      TextField("", text: $wert)
        .keyboardType(.URL)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .focused(fokus)
        .accessibilityLabel("API-URL")
        .onChange(of: wert) { neu in onAenderung(neu) }
        .mhEingabe(fokus: fokus.wrappedValue)
    }
  }
}

private struct InfoSheet: View {
  let titel: String
  let text: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        MhKopf(titel) {
          Button("Schließen") { dismiss() }
            .buttonStyle(.mhText)
        }
        Text(text)
          .mhText(.body)
          .foregroundStyle(Mh.text)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, Mh.rand)
      .padding(.top, Mh.abstand5)
      .padding(.bottom, Mh.abstand12)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .background(Mh.bg.ignoresSafeArea())
  }
}

/// FileDocument-Hülle für den Export-Dialog.
struct BackupDokument: FileDocument {
  static let readableContentTypes: [UTType] = [.json]
  let daten: Data

  init(daten: Data) { self.daten = daten }

  init(configuration: ReadConfiguration) throws {
    daten = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: daten)
  }
}

// MARK: - Info-Texte (identisch zur Flutter-/Android-App)

extension SettingsView {
  static let apiInfoText = """
    Die App spricht die Wickel-Tracker-API unter <Basis-URL>api.php an. Alle Antworten sind JSON.

    Endpunkte:

    • POST <Basis-URL>api.php?action=wickeln
      Neuen Eintrag anlegen, Body: {"typ": "urin", "stoffwindel": false}
      Erlaubte Typen: urin, stuhlgang, beides
      Antwort: {"ok": true, "id": 42, "typ": "urin", "zeit": "14:30"}

    • GET <Basis-URL>api.php?action=last
      Letzter Eintrag: {"typ": "...", "zeitstempel": "...", "zeit_kurz": "HH:MM"}

    • GET <Basis-URL>api.php?action=heute
      Anzahl heute: {"anzahl": 7}

    • GET <Basis-URL>api.php?action=stats
      Statistik je Zeitraum (today, week, threeWeeks, month) mit total und
      Prozentanteilen je Typ, plus "last": {"type": "...", "time": ISO8601}

    • POST <Basis-URL>api.php?action=undo_last
      Letzten Eintrag löschen: {"ok": true, "removed": 42}

    • POST <Basis-URL>api.php?action=undo
      Eintrag nach ID löschen, Body: {"id": 42}

    Authentifizierung:
    • Header "X-API-Key: <Key>" ist in jedem Fall erforderlich – auch hinter mTLS.
    • Im Modus "Server (mTLS-API)" zusätzlich ein Client-Zertifikat \
    (client.crt + client.key) auf Transport-Ebene.
    • Im Modus "Server (Cloudflare Access)" zusätzlich die Header \
    "CF-Access-Client-Id: <ID>" und "CF-Access-Client-Secret: <Secret>".

    Fehler kommen als {"error": "..."} mit passendem HTTP-Statuscode.
    """

  static let dbInfoText = """
    Im Modus "Lokal (SQLite)" speichert die App alle Einträge in der Datenbank \
    wickel_demo.db im app-privaten Speicher. Andere Apps haben keinen Zugriff, \
    es findet keine Synchronisation statt.

    Tabelle "entries":

    • id
      INTEGER, Primärschlüssel (Auto-Increment)

    • type
      TEXT: urin, stuhlgang oder beides

    • time
      TEXT, Zeitpunkt als ISO 8601 in UTC gespeichert (dadurch chronologisch \
    sortierbar), Anzeige in lokaler Zeit

    • stoffwindel
      INTEGER (0/1): Eintrag war eine Stoffwindel

    Die Statistik (heute / 7 Tage / 3 Wochen / 30 Tage) wird lokal aus diesen \
    Einträgen berechnet – mit denselben Prozentwerten wie die Server-API.

    Sicherung & Gerätewechsel

    Die Einträge liegen in der SQLite-Datei im app-privaten Speicher und werden \
    vom iCloud-Backup mitgesichert – nach einer Wiederherstellung sind sie also wieder da.

    Der API-Key liegt dagegen nicht in den Einstellungen, sondern in der Keychain. \
    Er wandert beim Direkttransfer auf ein neues Gerät (Schnellstart) und im \
    verschlüsselten Backup über den Computer mit, lässt sich aus einem \
    iCloud-Backup aber nicht wiederherstellen. Das ist Absicht: der Schlüssel \
    soll nicht auf fremden Servern liegen. Nach einer Wiederherstellung aus \
    iCloud muss er einmal neu eingetragen werden.

    Client-Zertifikate (client.crt / client.key) liegen im App-Ordner der \
    Dateien-App und sind nach einem Gerätewechsel gegebenenfalls neu abzulegen. \
    Alternativ lässt sich oben ein beliebiger anderer Ordner auswählen; der \
    Zugriff darauf wird als Lesezeichen gespeichert. Nach einer \
    Wiederherstellung auf einem neuen Gerät zeigt das Lesezeichen ins Leere – \
    die App meldet das und bittet darum, den Ordner erneut auszuwählen.

    Unabhängig davon lässt sich hier jederzeit ein eigenes Backup als \
    JSON-Datei sichern und wieder einspielen.
    """
}
