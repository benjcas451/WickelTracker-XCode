import SwiftUI

/// Spiegel von `WickelType` der iPhone-App.
///
/// `rawValue` entspricht exakt `apiValue` — er geht so über WatchConnectivity
/// ans iPhone. Farben nach Minze & Honig 2.0 (dunkle Rollen, siehe MhUhr.swift):
/// neutrale Flächen, Farbe nur als Signal am Symbol – Urin = data2 (Honig),
/// Beides = data1 (Minze), Stuhlgang = data3 (Flieder), wie im Web.
enum WickelType: String, CaseIterable, Identifiable {
  case urin
  case stuhlgang
  case beides

  /// Kennfarbe der Stoffwindel-Funktion (Rolle link bzw. onTint, Minze 300).
  static let stoffwindelColor = Mh.link

  /// Akzent für Status/Verbindung (Rolle link).
  static let minze = Mh.link

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

  /// Fläche der Eingabe-Buttons: neutral (surfaceRaised), keine Pastellfläche.
  var color: Color { Mh.surfaceRaised }

  /// Text auf der Button-Fläche.
  var buttonText: Color { Mh.textStrong }

  /// Datenfarbe des Typs (Symbol, letzter Eintrag).
  var akzent: Color {
    switch self {
    case .urin: return Mh.data2
    case .stuhlgang: return Mh.data3
    case .beides: return Mh.data1
    }
  }
}
