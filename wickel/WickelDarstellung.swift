import SwiftUI
import UIKit

// ============================================================================
// Wickel-Tracker in Minze & Honig 2.0 – app-eigene Darstellung.
// Wie auf der Webseite: Urin = data2 (Honig), Urin + Stuhlgang = halber
// Punkt data2/data1, Nur Stuhlgang = data3 (Flieder). Farbe nur als Punkt
// oder 4-pt-Balken, immer mit Text daneben.
// ============================================================================

extension WickelType {
  /// Reihenfolge in der Oberfläche (wie im Web).
  static let anzeigeReihenfolge: [WickelType] = [.urin, .beides, .stuhlgang]

  /// Füllung des Statistik-Balkens.
  var balkenFarbe: Color {
    switch self {
    case .urin: Mh.data2
    case .beides: Mh.data1
    case .stuhlgang: Mh.data3
    }
  }
}

/// Kennpunkt eines Wickel-Typs (10 pt); „Urin + Stuhlgang“ halb Honig, halb Minze.
struct WickelPunkt: View {
  let typ: WickelType

  var body: some View {
    switch typ {
    case .urin: MhPunkt(farbe: Mh.data2)
    case .stuhlgang: MhPunkt(farbe: Mh.data3)
    case .beides:
      HStack(spacing: 0) {
        Rectangle().fill(Mh.data2)
        Rectangle().fill(Mh.data1)
      }
      .frame(width: 10, height: 10)
      .clipShape(Circle())
      .accessibilityHidden(true)
    }
  }
}

/// „Eintrag mit einem Tipp“ (`.action-row`): Fläche + Haarlinie, Punkt
/// links, „+“ in primary rechts, 60 pt hoch.
struct WickelEintragZeile: View {
  let typ: WickelType
  let aktion: () -> Void

  var body: some View {
    Button(action: aktion) {
      HStack(spacing: Mh.abstand3) {
        WickelPunkt(typ: typ)
        Text(typ.label)
          .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
          .foregroundStyle(Mh.textStrong)
          .multilineTextAlignment(.leading)
        Spacer(minLength: Mh.abstand2)
        MhSymbol("MhPlus").foregroundStyle(Mh.primary)
      }
      .padding(.horizontal, Mh.abstand4)
      .padding(.vertical, Mh.abstand2)
      .frame(maxWidth: .infinity, minHeight: 60)
    }
    .buttonStyle(WickelEintragStil())
    .accessibilityLabel("\(typ.label) eintragen")
    .accessibilityIdentifier("eintrag-\(typ.rawValue)")
  }
}

private struct WickelEintragStil: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
          .fill(configuration.isPressed ? Mh.surfaceSubtle : Mh.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
          .stroke(Mh.border, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous))
  }
}

/// Eine Zeile der Statistik: Punkt + Bezeichnung, 4-pt-Balken, Prozentzahl.
/// Bei sehr großer Schrift steht der Balken unter der Bezeichnung.
struct WickelStatZeile: View {
  let typ: WickelType?
  let label: String
  let prozent: Int
  let farbe: Color

  @Environment(\.dynamicTypeSize) private var typoGroesse
  @ScaledMetric(relativeTo: .subheadline) private var labelBreite: CGFloat = 168
  @ScaledMetric(relativeTo: .subheadline) private var zahlBreite: CGFloat = 44

  var body: some View {
    Group {
      if typoGroesse.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 10) {
            bezeichnung
            Spacer(minLength: Mh.abstand2)
            zahl
          }
          MhBalken(anteil: Double(prozent) / 100, farbe: farbe)
        }
      } else {
        HStack(spacing: 10) {
          bezeichnung.frame(width: labelBreite, alignment: .leading)
          MhBalken(anteil: Double(prozent) / 100, farbe: farbe)
          zahl.frame(width: zahlBreite, alignment: .trailing)
        }
      }
    }
    .padding(.vertical, 7)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label): \(prozent) Prozent")
  }

  private var bezeichnung: some View {
    HStack(spacing: 10) {
      if let typ {
        WickelPunkt(typ: typ)
      } else {
        Color.clear.frame(width: 10, height: 10)
      }
      Text(label)
        .mhText(.small)
        .foregroundStyle(Mh.text)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
  }

  private var zahl: some View {
    Text("\(prozent)%")
      .mhText(.small)
      .monospacedDigit()
      .foregroundStyle(Mh.textSecondary)
  }
}

/// Kurze Rückmeldung (`.toast`): unten mittig, dunkel auf hell bzw. hell auf
/// dunkel, verschwindet von selbst.
struct MhToast: View {
  let text: String

  var body: some View {
    Text(text)
      .mhText(.label)
      .foregroundStyle(Mh.bg)
      .multilineTextAlignment(.center)
      .padding(.horizontal, Mh.abstand4)
      .padding(.vertical, Mh.abstand3)
      .background(
        RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous).fill(Mh.textStrong)
      )
      .shadow(color: Color.black.opacity(0.14), radius: 12, y: 4)
      .padding(.horizontal, Mh.rand)
      .padding(.bottom, Mh.abstand6)
      .onAppear { UIAccessibility.post(notification: .announcement, argument: text) }
  }
}

// MARK: - Zeitangaben (wie auf der Webseite)

extension Date {
  /// „gerade eben“, „vor 12 Min.“, „vor 3 Std.“, „vor 2 Tagen“.
  func relativ(bis jetzt: Date = Date()) -> String {
    let sekunden = Int(jetzt.timeIntervalSince(self))
    if sekunden < 60 { return "gerade eben" }
    if sekunden < 3_600 { return "vor \(sekunden / 60) Min." }
    if sekunden < 86_400 { return "vor \(sekunden / 3_600) Std." }
    let tage = sekunden / 86_400
    return tage == 1 ? "vor 1 Tag" : "vor \(tage) Tagen"
  }

  /// Heute „08:24 Uhr“, sonst „22.11., 08:24“.
  var zeitpunktLabel: String {
    if Calendar.current.isDateInToday(self) {
      return ZeitFormat.uhrzeit.string(from: self) + " Uhr"
    }
    return ZeitFormat.tagUndUhrzeit.string(from: self)
  }
}

// DateFormatter ist laut Apple-Doku thread-sicher.
private enum ZeitFormat {
  nonisolated(unsafe) static let uhrzeit: DateFormatter = {
    let format = DateFormatter()
    format.locale = Locale(identifier: "de_DE")
    format.dateFormat = "HH:mm"
    return format
  }()

  nonisolated(unsafe) static let tagUndUhrzeit: DateFormatter = {
    let format = DateFormatter()
    format.locale = Locale(identifier: "de_DE")
    format.dateFormat = "dd.MM., HH:mm"
    return format
  }()
}
