import SwiftUI

/// Spiegel von `WickelType` der iPhone-App.
///
/// `rawValue` entspricht exakt `apiValue` — er geht so über WatchConnectivity
/// ans iPhone. Farben nach Design-System „Minze & Honig“ (Dark-Regeln aus
/// Guide 2.8): Pastellflächen 300 mit 900er-Text; Urin = Honig,
/// Stuhlgang = Grau, Beides = Flieder, Stoffwindel = Minze.
enum WickelType: String, CaseIterable, Identifiable {
  case urin
  case stuhlgang
  case beides

  /// Kennfarbe der Stoffwindel-Funktion (Minze 300).
  static let stoffwindelColor = Color(red: 0xA8 / 255, green: 0xD5 / 255, blue: 0xBA / 255)

  /// Minze 300 — Akzent für Status/Import (ersetzt das frühere Lila).
  static let minze = stoffwindelColor

  var id: String { rawValue }

  var label: String {
    switch self {
    case .urin: return "Urin"
    case .stuhlgang: return "Stuhlgang"
    case .beides: return "Beides"
    }
  }

  var symbol: String {
    switch self {
    case .urin: return "drop.fill"
    case .stuhlgang: return "tornado"
    case .beides: return "circle.lefthalf.filled"
    }
  }

  /// Kräftige Fläche (300) für die Eingabe-Buttons; Grau für Stuhlgang.
  var color: Color {
    switch self {
    case .urin: return Color(red: 0xF7 / 255, green: 0xE8 / 255, blue: 0xA4 / 255)
    case .stuhlgang: return Color(red: 0x3A / 255, green: 0x40 / 255, blue: 0x3C / 255)
    case .beides: return Color(red: 0xCD / 255, green: 0xB4 / 255, blue: 0xDB / 255)
    }
  }

  /// Text/Icon auf der Button-Fläche (900er bzw. helles Grau).
  var buttonText: Color {
    switch self {
    case .urin: return Color(red: 0x47 / 255, green: 0x3A / 255, blue: 0x17 / 255)
    case .stuhlgang: return Color(red: 0xEC / 255, green: 0xEF / 255, blue: 0xED / 255)
    case .beides: return Color(red: 0x37 / 255, green: 0x26 / 255, blue: 0x3F / 255)
    }
  }

  /// Akzent auf dunklem Grund (Text/Icons): die 300er-Stufe, für Stuhlgang
  /// das helle Grau 300.
  var akzent: Color {
    switch self {
    case .urin: return Color(red: 0xF7 / 255, green: 0xE8 / 255, blue: 0xA4 / 255)
    case .stuhlgang: return Color(red: 0xC6 / 255, green: 0xCD / 255, blue: 0xC9 / 255)
    case .beides: return Color(red: 0xCD / 255, green: 0xB4 / 255, blue: 0xDB / 255)
    }
  }
}
