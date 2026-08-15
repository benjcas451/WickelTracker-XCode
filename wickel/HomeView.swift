import SwiftUI

struct HomeView: View {
  @StateObject private var model = HomeViewModel()

  @State private var zeigeEinstellungen = false
  @State private var zeigeUndoNachfrage = false

  var body: some View {
    NavigationStack {
      ZStack {
        Mh.grund.ignoresSafeArea()
        inhalt
      }
      .navigationTitle("")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.aktualisieren()
          } label: {
            Image(systemName: "arrow.clockwise").foregroundStyle(Mh.gruenText)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            zeigeEinstellungen = true
          } label: {
            Image(systemName: "gearshape").foregroundStyle(Mh.gruenText)
          }
        }
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
    }
  }

  // MARK: - Inhalt

  @ViewBuilder
  private var inhalt: some View {
    if model.laedt && model.stats == nil && model.fehler == nil {
      ProgressView().tint(Mh.minze500)
    } else if let fehler = model.fehler {
      FehlerAnsicht(meldung: fehler) { model.aktualisieren() }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // App-Titel im Inhalt statt in der Toolbar: iOS faltet Text-Items
          // dort in ein Überlauf-Menü.
          Text("🧷 Wickel-Tracker")
            .font(.nunitoExtraBold(26))
            .foregroundStyle(Mh.text)
          if let stats = model.stats {
            LetzterEintragKarte(
              last: stats.last, stoffwindelEnabled: model.stoffwindelEnabled)
          }
          Text("Neuer Eintrag").font(.nunitoBold(16)).foregroundStyle(Mh.text)
          if model.stoffwindelEnabled {
            stoffwindelSchalter
          }
          schnellEingabe
          Button {
            zeigeUndoNachfrage = true
          } label: {
            Label("Letzten rückgängig", systemImage: "arrow.uturn.backward")
              .font(.nunitoSemiBold(15))
          }
          .buttonStyle(MhRandButtonStil())
          if let stats = model.stats { statistik(stats) }
        }
        .padding(16)
      }
      .refreshable { model.aktualisieren() }
    }
  }

  private var stoffwindelSchalter: some View {
    MhKarte {
      Toggle(isOn: $model.stoffwindelActive) {
        HStack(spacing: 12) {
          Image(systemName: "washer")
            .foregroundStyle(model.stoffwindelActive ? Mh.stoffwindelAkzent : Mh.textSekundaer)
          Text("Stoffwindel").font(.nunito(16)).foregroundStyle(Mh.text)
        }
      }
      .tint(Mh.minze500)
    }
  }

  private var schnellEingabe: some View {
    // Kategorie-Buttons nach dem Chip-Muster: Pastellfläche (300) mit
    // 900er-Text derselben Farbe, Radius 12, Höhe 44 (Touch-Minimum).
    let spalten = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    return LazyVGrid(columns: spalten, alignment: .leading, spacing: 10) {
      ForEach(WickelType.allCases) { type in
        Button {
          model.anlegen(type)
        } label: {
          HStack(spacing: 6) {
            Image(systemName: type.symbol).font(.system(size: 15, weight: .bold))
            Text(type.label).lineLimit(1)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(MhButtonStil(flaeche: type.buttonFlaeche, text: type.buttonText))
      }
    }
  }

  private func statistik(_ stats: WickelStats) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Statistik").font(.nunitoBold(16)).foregroundStyle(Mh.text)
      PeriodenKarte(
        titel: "Heute", periode: stats.today,
        stoffwindelEnabled: model.stoffwindelEnabled, hervorgehoben: true)
      PeriodenKarte(
        titel: "Letzte 7 Tage", periode: stats.week,
        stoffwindelEnabled: model.stoffwindelEnabled)
      PeriodenKarte(
        titel: "Letzte 3 Wochen", periode: stats.threeWeeks,
        stoffwindelEnabled: model.stoffwindelEnabled)
      PeriodenKarte(
        titel: "Letzte 30 Tage", periode: stats.month,
        stoffwindelEnabled: model.stoffwindelEnabled)
    }
  }
}

// MARK: - Letzter Eintrag

private struct LetzterEintragKarte: View {
  let last: LastEntry
  let stoffwindelEnabled: Bool

  var body: some View {
    MhKarte {
      HStack(spacing: 14) {
        ZStack {
          Circle()
            .fill(last.type?.avatarFlaeche ?? Mh.grauFlaeche)
            .frame(width: 40, height: 40)
          Image(systemName: last.type?.symbol ?? "clock.arrow.circlepath")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(last.type?.akzent ?? Mh.textSekundaer)
        }
        VStack(alignment: .leading, spacing: 2) {
          if let type = last.type {
            Text("Zuletzt: \(type.label)").font(.nunito(16)).foregroundStyle(Mh.text)
            if let zeit = last.time {
              let suffix = stoffwindelEnabled && last.stoffwindel ? " · 🧷 Stoffwindel" : ""
              Text(
                "\(zeit.tagesLabel) um \(zeit.formatted(date: .omitted, time: .shortened)) · \(zeit.relativ)\(suffix)"
              )
              .font(.nunito(14))
              .foregroundStyle(Mh.textSekundaer)
            }
          } else {
            Text("Noch kein Eintrag").font(.nunito(16)).foregroundStyle(Mh.text)
            Text("Lege unten den ersten Wickel-Vorgang an.")
              .font(.nunito(14))
              .foregroundStyle(Mh.textSekundaer)
          }
        }
        Spacer(minLength: 0)
      }
    }
  }
}

// MARK: - Perioden-Karte

private struct PeriodenKarte: View {
  let titel: String
  let periode: PeriodStats
  let stoffwindelEnabled: Bool
  var hervorgehoben = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(titel).font(.nunitoBold(14)).foregroundStyle(Mh.text)
        Spacer()
        Text("\(periode.total) gesamt").font(.nunitoExtraBold(14)).foregroundStyle(Mh.text)
      }
      ForEach(WickelType.allCases) { type in
        ProzentZeile(
          symbol: type.symbol, label: type.label, pct: periode.pctOf(type),
          farbe: type.akzent, grund: type.avatarFlaeche)
      }
      if stoffwindelEnabled {
        ProzentZeile(
          symbol: "washer", label: "Stoffwindel", pct: periode.stoffwindelPct,
          farbe: Mh.stoffwindelAkzent, grund: Mh.stoffwindelFlaeche)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    // "Heute" hervorgehoben als zarte Minze-Fläche (Dark-Äquivalent).
    .background(hervorgehoben ? Mh.minzeFlaeche : Mh.karte)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .shadow(
      color: hervorgehoben ? .clear : Color(UIColor(rgb: 0x22392C)).opacity(0.10),
      radius: 6, y: 2)
  }
}

private struct ProzentZeile: View {
  let symbol: String
  let label: String
  let pct: Int
  let farbe: Color
  let grund: Color

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(farbe)
        .frame(width: 20)
      Text(label).font(.nunito(14)).foregroundStyle(Mh.text)
        .frame(width: 86, alignment: .leading)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(grund)
          Capsule().fill(farbe)
            .frame(width: geo.size.width * CGFloat(pct) / 100)
        }
      }
      .frame(height: 8)
      Text("\(pct)%")
        .font(.nunito(13))
        .foregroundStyle(Mh.text)
        .frame(width: 40, alignment: .trailing)
    }
  }
}

// MARK: - Fehleransicht

private struct FehlerAnsicht: View {
  let meldung: String
  let onErneut: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 52))
        .foregroundStyle(Mh.fehlerText)
      Text(meldung)
        .font(.nunito(16))
        .foregroundStyle(Mh.text)
        .multilineTextAlignment(.center)
      Button {
        onErneut()
      } label: {
        Label("Erneut versuchen", systemImage: "arrow.clockwise")
      }
      .buttonStyle(MhButtonStil())
    }
    .padding(32)
  }
}

// MARK: - Helfer

extension Date {
  var tagesLabel: String {
    if Calendar.current.isDateInToday(self) { return "Heute" }
    if Calendar.current.isDateInYesterday(self) { return "Gestern" }
    return formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
  }

  /// „vor X min/h/d“ – wie in der Flutter-App.
  var relativ: String {
    let differenz = Int(Date().timeIntervalSince(self))
    let minuten = differenz / 60
    if minuten < 1 { return "gerade eben" }
    if minuten < 60 { return "vor \(minuten) min" }
    let stunden = minuten / 60
    if stunden < 24 { return "vor \(stunden) h" }
    return "vor \(stunden / 24) d"
  }
}

/// Sekundär-Button: Rand statt Fläche, grüner Text.
struct MhRandButtonStil: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Mh.gruenText)
      .padding(.horizontal, 16)
      .frame(minHeight: 40)
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Mh.rand, lineWidth: 1.5)
      )
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}
