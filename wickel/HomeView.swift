import SwiftUI

struct HomeView: View {
  @StateObject private var model = HomeViewModel()
  @Environment(\.scenePhase) private var szenenPhase
  @Environment(\.accessibilityReduceMotion) private var wenigerBewegung

  @State private var zeigeEinstellungen = false
  @State private var zeigeUndoNachfrage = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        // Kopf in jedem Zustand, damit die Einstellungen auch bei einem
        // Ladefehler erreichbar bleiben.
        MhKopf("Wickel-Tracker") {
          MhSymbolButton("MhRefresh", beschreibung: "Aktualisieren") {
            model.aktualisieren()
          }
          MhSymbolButton("MhSliders", beschreibung: "Einstellungen") {
            zeigeEinstellungen = true
          }
          .accessibilityIdentifier("einstellungen")
        }
        // Offline-Hinweis gleich unter dem Titel: man kann weiterarbeiten,
        // der Stand ist aber noch nicht beim Server.
        if model.offlineGrund != nil || model.ausstehend > 0 {
          OfflineHinweis(grund: model.offlineGrund, ausstehend: model.ausstehend)
            .padding(.bottom, Mh.abstand4)
        }
        inhalt
      }
      .padding(.horizontal, Mh.rand)
      .padding(.top, Mh.abstand2)
      .padding(.bottom, Mh.abstand12)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .refreshable { model.aktualisieren() }
    .background(Mh.bg.ignoresSafeArea())
    // Grund unter der Statusleiste: gescrollter Inhalt verschwindet darunter.
    .safeAreaInset(edge: .top, spacing: 0) {
      Color.clear.frame(height: 0).background(Mh.bg, ignoresSafeAreaEdges: .top)
    }
    .overlay(alignment: .bottom) {
      if let rueckmeldung = model.rueckmeldung {
        MhToast(text: rueckmeldung.text)
          .id(rueckmeldung.id)
          .transition(
            wenigerBewegung
              ? AnyTransition.opacity
              : AnyTransition.move(edge: .bottom).combined(with: .opacity))
          .onTapGesture { model.rueckmeldung = nil }
      }
    }
    .animation(.easeOut(duration: 0.2), value: model.rueckmeldung)
    .task(id: model.rueckmeldung) {
      guard model.rueckmeldung != nil else { return }
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      if !Task.isCancelled { model.rueckmeldung = nil }
    }
    .sheet(isPresented: $zeigeEinstellungen, onDismiss: model.datenquelleNeuAufbauen) {
      SettingsView()
    }
    .alert("Letzten Eintrag löschen?", isPresented: $zeigeUndoNachfrage) {
      Button("Abbrechen", role: .cancel) {}
      Button("Löschen", role: .destructive) { model.letztenRueckgaengig() }
    } message: {
      Text("Der zuletzt angelegte Wickel-Eintrag wird entfernt.")
    }
    .alert(
      "Hinweis",
      isPresented: .init(get: { model.meldung != nil }, set: { if !$0 { model.meldung = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.meldung ?? "")
    }
    .task { model.aktualisieren() }
    // Rückkehr aus dem Hintergrund: nachladen und dabei die Warteschlange
    // abarbeiten – zwischendurch kann die Verbindung wiedergekommen sein,
    // ohne dass die Wache lief.
    .onChange(of: szenenPhase) { neu in
      if neu == .active { model.aktualisieren() }
    }
  }

  // MARK: - Inhalt

  @ViewBuilder
  private var inhalt: some View {
    if model.laedt && model.stats == nil && model.fehler == nil {
      MhLaden()
    } else if let fehler = model.fehler {
      FehlerAnsicht(meldung: fehler) { model.aktualisieren() }
    } else {
      if model.stoffwindelEnabled {
        stoffwindelSchalter
      }
      VStack(spacing: Mh.abstand2) {
        ForEach(WickelType.anzeigeReihenfolge) { typ in
          WickelEintragZeile(typ: typ) { model.anlegen(typ) }
        }
      }
      rueckgaengig
      if let stats = model.stats {
        LetzterEintrag(last: stats.last, stoffwindelEnabled: model.stoffwindelEnabled)
        statistik(stats)
      }
    }
  }

  /// Nur bei eingeschalteter Stoffwindel-Funktion: gilt für den nächsten Eintrag.
  private var stoffwindelSchalter: some View {
    Toggle(isOn: $model.stoffwindelActive) {
      HStack(spacing: Mh.abstand3) {
        MhSymbol("MhDiaper").foregroundStyle(Mh.textSecondary)
        Text("Stoffwindel").mhText(.label).foregroundStyle(Mh.textStrong)
      }
    }
    .tint(Mh.primary)
    .frame(minHeight: Mh.touch)
    .padding(.bottom, Mh.abstand3)
  }

  private var rueckgaengig: some View {
    HStack(spacing: Mh.abstand3) {
      Text("Letzten Eintrag zurücknehmen")
        .mhText(.small)
        .foregroundStyle(Mh.textSecondary)
      Spacer(minLength: 0)
      Button {
        zeigeUndoNachfrage = true
      } label: {
        MhButtonInhalt("Rückgängig", symbol: "MhUndo", symbolGroesse: Mh.symbolKlein)
      }
      .buttonStyle(.mhLoeschen)
    }
    .padding(.top, Mh.abstand2)
    .padding(.leading, 2)
  }

  private func statistik(_ stats: WickelStats) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      PeriodenBlock(
        titel: "Heute", periode: stats.today, stoffwindelEnabled: model.stoffwindelEnabled)
      PeriodenBlock(
        titel: "Letzte 7 Tage", periode: stats.week,
        stoffwindelEnabled: model.stoffwindelEnabled)
      PeriodenBlock(
        titel: "Letzte 21 Tage", periode: stats.threeWeeks,
        stoffwindelEnabled: model.stoffwindelEnabled)
      PeriodenBlock(
        titel: "Letzte 30 Tage", periode: stats.month,
        stoffwindelEnabled: model.stoffwindelEnabled)
    }
  }
}

// MARK: - Letzter Eintrag

/// Zwischen zwei Haarlinien: oben Bezeichnung und Zeit, darunter der Typ
/// mit Punkt. Reicht die Breite nicht (große Schrift), stapelt sich alles.
private struct LetzterEintrag: View {
  let last: LastEntry
  let stoffwindelEnabled: Bool

  var body: some View {
    VStack(spacing: 0) {
      MhTrennlinie()
      VStack(alignment: .leading, spacing: Mh.abstand1) {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: Mh.abstand3) {
            bezeichnung
            Spacer(minLength: 0)
            zeit
          }
          VStack(alignment: .leading, spacing: 2) {
            bezeichnung
            zeit
          }
        }
        if let typ = last.type {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
              typZeile(typ)
              marke
            }
            VStack(alignment: .leading, spacing: Mh.abstand1) {
              typZeile(typ)
              marke
            }
          }
        } else {
          Text("Noch kein Eintrag").mhText(.body).foregroundStyle(Mh.textSecondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, Mh.abstand4)
      .accessibilityElement(children: .combine)
      MhTrennlinie()
    }
    .padding(.top, Mh.abstand6)
  }

  private var bezeichnung: some View {
    Text("Letzter Eintrag").mhText(.label).foregroundStyle(Mh.textSecondary)
  }

  /// „vor 42 Min. · 11:58 Uhr“; läuft weiter, ohne neu zu laden.
  @ViewBuilder
  private var zeit: some View {
    if last.type != nil, let zeitpunkt = last.time {
      TimelineView(.periodic(from: .now, by: 30)) { kontext in
        Text("\(zeitpunkt.relativ(bis: kontext.date)) · \(zeitpunkt.zeitpunktLabel)")
          .mhText(.small)
          .monospacedDigit()
          .foregroundStyle(Mh.textSecondary)
      }
    }
  }

  private func typZeile(_ typ: WickelType) -> some View {
    HStack(spacing: 10) {
      WickelPunkt(typ: typ)
      Text(typ.label)
        .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
        .foregroundStyle(Mh.textStrong)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var marke: some View {
    if stoffwindelEnabled && last.stoffwindel {
      MhMarke("Stoffwindel").fixedSize()
    }
  }
}

// MARK: - Statistik

private struct PeriodenBlock: View {
  let titel: String
  let periode: PeriodStats
  let stoffwindelEnabled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MhGruppenLabel(titel, rechts: periode.total == 1 ? "1 Eintrag" : "\(periode.total) Einträge")
        .padding(.top, Mh.abstand2)
      ForEach(WickelType.anzeigeReihenfolge) { typ in
        WickelStatZeile(
          typ: typ, label: typ.label, prozent: periode.pctOf(typ), farbe: typ.balkenFarbe)
      }
      if stoffwindelEnabled {
        WickelStatZeile(
          typ: nil, label: "Stoffwindel", prozent: periode.stoffwindelPct,
          farbe: Mh.textTertiary)
      }
    }
  }
}

// MARK: - Fehleransicht

private struct FehlerAnsicht: View {
  let meldung: String
  let onErneut: () -> Void

  var body: some View {
    VStack(spacing: Mh.abstand4) {
      MhSymbol("MhAlert", groesse: 32).foregroundStyle(Mh.danger)
      Text(meldung)
        .mhText(.body)
        .foregroundStyle(Mh.text)
        .multilineTextAlignment(.center)
      Button {
        onErneut()
      } label: {
        MhButtonInhalt("Erneut versuchen", symbol: "MhRefresh")
      }
      .buttonStyle(.mhHaupt)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Mh.abstand8)
  }
}

// MARK: - Offline-Hinweis

/// Hinweis über dem Inhalt: Verbindung weg, App weiter benutzbar.
private struct OfflineHinweis: View {
  /// Grund der abgebrochenen Verbindung; nil heisst „wieder online, aber es
  /// wartet noch etwas auf die Übertragung“.
  let grund: String?
  let ausstehend: Int

  var body: some View {
    MhHinweis(
      untertitel, titel: titel, art: .warnung,
      symbol: grund == nil ? "MhUpload" : "MhCloudOff")
  }

  private var titel: String {
    guard let grund else { return "Übertragung läuft" }
    return "Offline-Modus – \(grund)"
  }

  private var untertitel: String {
    guard ausstehend > 0 else {
      return "Angezeigt wird der zuletzt geladene Stand."
    }
    let was = ausstehend == 1 ? "Ein Eintrag wartet" : "\(ausstehend) Einträge warten"
    return "\(was) auf die Übertragung und geht raus, sobald die Verbindung steht."
  }
}
