import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var mode = AppSettings.mode
  @State private var apiUrl = AppSettings.apiBaseUrl
  @State private var apiKeyUrl = AppSettings.apiKeyBaseUrl
  @State private var apiKey = AppSettings.apiKey
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

  var body: some View {
    NavigationStack {
      ZStack {
        Mh.grund.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            datenquelle
            if mode == .apiKey { apiKeySektion }
            if mode == .api { mtlsSektion }
            if mode == .demo { backupSektion }
            optionen
            erklaerung
          }
          .padding(16)
        }
      }
      .navigationTitle("Einstellungen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Fertig") { dismiss() }
            .font(.nunitoBold(16))
            .foregroundStyle(Mh.gruenText)
        }
      }
    }
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
    VStack(alignment: .leading, spacing: 4) {
      Sektion("Datenquelle")
      ModusZeile(
        gewaehlt: mode == .api, titel: "Server (mTLS-API)",
        untertitel: "Client-Zertifikat + API-Key"
      ) { setzeModus(.api) }
      ModusZeile(
        gewaehlt: mode == .apiKey, titel: "Server (API-Key)",
        untertitel: "API-Key ohne Client-Zertifikat"
      ) { setzeModus(.apiKey) }
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
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Group {
          if apiKeySichtbar {
            TextField("API-Key", text: $apiKey)
          } else {
            SecureField("API-Key", text: $apiKey)
          }
        }
        .font(.nunito(16))
        .focused($keyFokus)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: apiKey) { neu in AppSettings.apiKey = neu }
        Button {
          apiKeySichtbar.toggle()
        } label: {
          Image(systemName: apiKeySichtbar ? "eye.slash" : "eye")
            .foregroundStyle(Mh.textSekundaer)
        }
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .background(Mh.feldFlaeche)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(keyFokus ? Mh.minze500 : Mh.rand, lineWidth: 1.5))
      if let hilfe {
        Text(hilfe).font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
      }
    }
  }

  private var apiKeySektion: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Server (API-Key)")
      UrlFeld(wert: $apiKeyUrl, fokus: $urlFokus) { AppSettings.apiKeyBaseUrl = $0 }
      apiKeyFeld(hilfe: "Erforderlich – die api.php verlangt den Key in jedem Fall.")
    }
  }

  private var mtlsSektion: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Server (mTLS-API)")
      UrlFeld(wert: $apiUrl, fokus: $urlFokus) { AppSettings.apiBaseUrl = $0 }
      zertifikatsBlock
      apiKeyFeld(hilfe: "Erforderlich – die api.php verlangt den Key in jedem Fall.")
    }
  }

  /// Status der Client-Zertifikate samt Ordnerwahl. Standard bleibt der
  /// App-Ordner in der Dateien-App; alternativ lässt sich ein beliebiger
  /// Ordner auswählen, auf den die App per security-scoped Bookmark
  /// zugreift – dieselbe Bedienung wie in „Hello Baby“.
  private var zertifikatsBlock: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: certsOk ? "checkmark.circle.fill" : "xmark.circle.fill")
          .foregroundStyle(certsOk ? Mh.gruenText : Mh.fehlerText)
        VStack(alignment: .leading, spacing: 2) {
          Text(certsOk ? "Zertifikate gefunden" : "Keine Zertifikate gefunden")
            .font(.nunito(16)).foregroundStyle(Mh.text)
          Text("\(CertSource.certFileName) & \(CertSource.keyFileName) – \(certOrt)")
            .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
          if !eigenerCertOrdner {
            Text(
              "Per Dateien-App in den Ordner der App „Wickeln“ kopieren – oder "
                + "unten einen eigenen Ordner wählen.")
              .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
          }
        }
      }
      zertifikatsButton("Zertifikats-Ordner wählen", "folder") { zeigeOrdnerwahl = true }
      if eigenerCertOrdner {
        zertifikatsButton("Standard: App-Ordner (Dateien-App)", "folder.badge.gearshape") {
          certSource.nutzeStandardOrdner()
          pruefeZertifikate()
        }
      }
      zertifikatsButton("Erneut prüfen", "arrow.clockwise") {
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
      Label(titel, systemImage: symbol)
        .font(.nunitoBold(15))
        .foregroundStyle(Mh.gruenText)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Mh.rand, lineWidth: 1.5))
    }
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
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Backup")
      Button {
        exportieren()
      } label: {
        Label("In iCloud speichern", systemImage: "icloud.and.arrow.up")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MhButtonStil(flaeche: Mh.honig300, text: Mh.honig900))
      Button {
        restoreBestaetigen = true
      } label: {
        Label("Backup wiederherstellen", systemImage: "arrow.counterclockwise")
          .font(.nunitoBold(16))
          .foregroundStyle(Mh.gruenText)
          .frame(maxWidth: .infinity, minHeight: 44)
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Mh.rand, lineWidth: 1.5))
      }
      Text("Im Dateidialog iCloud Drive als Ziel wählen.")
        .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
    }
  }

  private var optionen: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Optionen")
      Toggle(isOn: $stoffwindelEnabled) {
        HStack(spacing: 12) {
          Image(systemName: "washer")
            .foregroundStyle(stoffwindelEnabled ? Mh.stoffwindelAkzent : Mh.textSekundaer)
          VStack(alignment: .leading, spacing: 2) {
            Text("Stoffwindel-Funktion").font(.nunito(16)).foregroundStyle(Mh.text)
            Text("Zeigt beim Eintragen eine Umschaltfläche für Stoffwindeln")
              .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
          }
        }
      }
      .tint(Mh.minze500)
      .onChange(of: stoffwindelEnabled) { neu in AppSettings.stoffwindelEnabled = neu }
    }
  }

  private var erklaerung: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Erklärung")
      HStack(spacing: 8) {
        InfoButton(titel: "Aufbau API", symbol: "cloud") {
          infoTitel = "Aufbau API"
          infoText = SettingsView.apiInfoText
        }
        InfoButton(titel: "Aufbau Datenbank", symbol: "cylinder.split.1x2") {
          infoTitel = "Aufbau Datenbank"
          infoText = SettingsView.dbInfoText
        }
      }
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

private struct Sektion: View {
  let titel: String
  init(_ titel: String) { self.titel = titel }

  var body: some View {
    Text(titel).font(.nunitoBold(14)).foregroundStyle(Mh.gruenText)
  }
}

private struct ModusZeile: View {
  let gewaehlt: Bool
  let titel: String
  let untertitel: String
  let onWahl: () -> Void

  var body: some View {
    Button(action: onWahl) {
      HStack(spacing: 12) {
        Image(systemName: gewaehlt ? "largecircle.fill.circle" : "circle")
          .font(.system(size: 20))
          .foregroundStyle(gewaehlt ? Mh.gruenText : Mh.textSekundaer)
        VStack(alignment: .leading, spacing: 2) {
          Text(titel).font(.nunito(16)).foregroundStyle(Mh.text)
          Text(untertitel).font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
        }
        Spacer()
      }
      .padding(.vertical, 8)
    }
  }
}

private struct UrlFeld: View {
  @Binding var wert: String
  var fokus: FocusState<Bool>.Binding
  let onAenderung: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField("API-URL", text: $wert)
        .font(.nunito(16))
        .keyboardType(.URL)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .focused(fokus)
        .onChange(of: wert) { neu in onAenderung(neu) }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Mh.feldFlaeche)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(fokus.wrappedValue ? Mh.minze500 : Mh.rand, lineWidth: 1.5))
      Text("Basis-URL der API inkl. abschließendem /")
        .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
    }
  }
}

private struct InfoButton: View {
  let titel: String
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(titel, systemImage: symbol)
        .font(.nunitoBold(15))
        .foregroundStyle(Mh.gruenText)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Mh.rand, lineWidth: 1.5))
    }
  }
}

private struct InfoSheet: View {
  let titel: String
  let text: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(text)
          .font(.nunito(15))
          .foregroundStyle(Mh.text)
          .textSelection(.enabled)
          .padding(16)
      }
      .background(Mh.grund)
      .navigationTitle(titel)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Schließen") { dismiss() }
            .font(.nunitoBold(16)).foregroundStyle(Mh.gruenText)
        }
      }
    }
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
