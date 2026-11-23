import SwiftUI

// ============================================================================
// Minze & Honig 2.0 – Uhr (watchOS): nur Farben und Schrift.
// Die Uhr ist immer dunkel, deshalb nur die dunklen Rollen aus
// DesignGuide/tokens/design-tokens.json (semantic.dark). Schwarzer
// Uhr-Grund bleibt (watchOS-Konvention). Figtree steht in UIAppFonts der
// Info.plist; nur 400/500/600. Ohne UIKit.
// ============================================================================

enum Mh {

  // MARK: Rollen (dunkel)

  static let surface = farbe(0x262A28)
  static let surfaceRaised = farbe(0x2E3330)
  static let text = farbe(0xE6EAE7)
  static let textStrong = farbe(0xFFFFFF)
  static let textSecondary = farbe(0xA9B0AB)
  static let link = farbe(0xA8D5BA)
  static let primary = farbe(0x82BD9B)
  static let onPrimary = farbe(0x1F2221)
  static let danger = farbe(0xF0B6B1)
  static let data1 = farbe(0xA8D5BA)
  static let data2 = farbe(0xF7E8A4)
  static let data3 = farbe(0xCDB4DB)

  private static func farbe(_ wert: UInt32) -> Color {
    Color(
      red: Double((wert >> 16) & 0xFF) / 255,
      green: Double((wert >> 8) & 0xFF) / 255,
      blue: Double(wert & 0xFF) / 255)
  }

  // MARK: Schrift (Figtree, mit Dynamic Type)

  static func regular(_ groesse: CGFloat, _ bezug: Font.TextStyle) -> Font {
    .custom("Figtree-Regular", size: groesse, relativeTo: bezug)
  }

  static func medium(_ groesse: CGFloat, _ bezug: Font.TextStyle) -> Font {
    .custom("Figtree-Medium", size: groesse, relativeTo: bezug)
  }

  static func semibold(_ groesse: CGFloat, _ bezug: Font.TextStyle) -> Font {
    .custom("Figtree-SemiBold", size: groesse, relativeTo: bezug)
  }

  /// Grundschrift für alles ohne eigene Angabe.
  static let body = regular(16, .body)
  /// Buttons und Schalter.
  static let button = medium(16, .body)
  /// Überschriften („Server-Verbindung“, letzter Eintrag).
  static let headline = semibold(16, .headline)
  static let footnote = regular(14, .footnote)
  static let caption = regular(12, .caption2)
}
