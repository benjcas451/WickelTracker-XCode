import CoreText
import SwiftUI
import UIKit

// ============================================================================
// Design-System „Minze & Honig" (v1.0) – Farb-Tokens und Typografie
// Quelle: /DesignGuide/tokens/design-tokens.json
// ============================================================================

enum Mh {

  // Hell/Dunkel-Paar als dynamische Farbe.
  private static func dyn(_ hell: UInt32, _ dunkel: UInt32) -> Color {
    Color(UIColor { trait in
      UIColor(rgb: trait.userInterfaceStyle == .dark ? dunkel : hell)
    })
  }

  private static func fest(_ wert: UInt32) -> Color { Color(UIColor(rgb: wert)) }

  /// Wie `dyn`, für Erweiterungen außerhalb dieser Datei-Sektion nutzbar.
  static func dynErweiterung(_ hell: UInt32, _ dunkel: UInt32) -> Color {
    Color(UIColor { trait in
      UIColor(rgb: trait.userInterfaceStyle == .dark ? dunkel : hell)
    })
  }

  // Grundflächen (Guide 2.1/2.8)
  static let grund = dyn(0xFFFFFF, 0x1F2221)
  static let karte = dyn(0xFFFFFF, 0x292D2B)
  static let feldFlaeche = dyn(0xF6F8F6, 0x2E332F)
  static let rand = dyn(0xDFE4E1, 0x3A403C)
  static let text = dyn(0x2E332F, 0xECEFED)
  static let textSekundaer = dyn(0x5D655F, 0xA9B0AB)

  // Pastellflächen (300) bleiben in beiden Modi identisch, Text darauf 900.
  static let minze300 = fest(0xA8D5BA)
  static let minze500 = fest(0x5FA07C)
  static let minze900 = fest(0x22392C)
  static let honig300 = fest(0xF7E8A4)
  static let honig900 = fest(0x473A17)
  static let flieder300 = fest(0xCDB4DB)
  static let flieder900 = fest(0x37263F)
  static let grau200 = fest(0xDFE4E1)
  static let grau800 = fest(0x2E332F)

  /// Text-/icontaugliches Grün auf dem Grund (Light: 700, Dark: 300).
  static let gruenText = dyn(0x38664C, 0xA8D5BA)
  static let gelbText = dyn(0x8A6F26, 0xF7E8A4)
  static let liladText = dyn(0x634472, 0xCDB4DB)
  static let grauText = dyn(0x454C47, 0xC6CDC9)

  // Zarte Flächen (100 bzw. Dark-Äquivalent) für Avatare/Hinweise.
  static let minzeFlaeche = dyn(0xE1F3E8, 0x263B2F)
  static let honigFlaeche = dyn(0xFBF3D3, 0x3B3524)
  static let fliederFlaeche = dyn(0xF1E9F6, 0x352B3C)
  static let grauFlaeche = dyn(0xEDF0EE, 0x2E332F)

  // Semantisch: Fehler/Löschen (Guide 2.6)
  static let fehlerText = dyn(0xB3453E, 0xF0B6B1)
  static let fehlerFlaeche = dyn(0xFAE3E1, 0x3F2523)
  static let loeschenText = dyn(0x96362F, 0xF0B6B1)
}

extension UIColor {
  convenience init(rgb: UInt32) {
    self.init(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1)
  }
}

// MARK: - Wickel-Typ-Farben (Chip-Muster des Guides)

// Urin = Honig, Beides = Flieder, Stuhlgang = neutrales Grau; die
// Stoffwindel-Funktion trägt Minze. Fläche 300 + 900er-Text; zarte
// 100er-Flächen (Dark-Äquivalente) für Avatare und Balkengrund.
extension WickelType {
  var buttonFlaeche: Color {
    switch self {
    case .urin: Mh.honig300
    case .stuhlgang: Mh.grauButtonFlaeche
    case .beides: Mh.flieder300
    }
  }

  var buttonText: Color {
    switch self {
    case .urin: Mh.honig900
    case .stuhlgang: Mh.grauButtonText
    case .beides: Mh.flieder900
    }
  }

  var avatarFlaeche: Color {
    switch self {
    case .urin: Mh.honigFlaeche
    case .stuhlgang: Mh.grauFlaeche
    case .beides: Mh.fliederFlaeche
    }
  }

  var akzent: Color {
    switch self {
    case .urin: Mh.gelbText
    case .stuhlgang: Mh.grauText
    case .beides: Mh.liladText
    }
  }
}

extension Mh {
  /// Stuhlgang-Button: neutrales Grau, im Dark nicht heller als die Pastelle.
  static let grauButtonFlaeche = dynErweiterung(0xDFE4E1, 0x3A403C)
  static let grauButtonText = dynErweiterung(0x2E332F, 0xECEFED)
  /// Stoffwindel-Funktion: Minze.
  static var stoffwindelAkzent: Color { gruenText }
  static var stoffwindelFlaeche: Color { minzeFlaeche }
}

// MARK: - Typografie: Nunito (zur Laufzeit registriert, kein Info.plist nötig)

enum NunitoFont {
  // Wird nur einmal beim App-Start (wickelApp.init) gesetzt.
  nonisolated(unsafe) private static var registriert = false

  /// Beim App-Start aufrufen. Registriert die eingebetteten TTFs.
  static func registrieren() {
    guard !registriert else { return }
    registriert = true
    for name in ["nunito_regular", "nunito_semibold", "nunito_bold", "nunito_extrabold"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
}

extension Font {
  // PostScript-Namen der eingebetteten Schnitte. Die statischen Instanzen der
  // Google-Fonts-API tragen das kuriose Präfix "NunitoExtraLight-" – es sind
  // trotzdem die regulären Gewichte 400/600/700/800.
  static func nunito(_ groesse: CGFloat) -> Font { .custom("NunitoExtraLight-Regular", size: groesse) }
  static func nunitoSemiBold(_ groesse: CGFloat) -> Font { .custom("NunitoExtraLight-SemiBold", size: groesse) }
  static func nunitoBold(_ groesse: CGFloat) -> Font { .custom("NunitoExtraLight-Bold", size: groesse) }
  static func nunitoExtraBold(_ groesse: CGFloat) -> Font { .custom("NunitoExtraLight-ExtraBold", size: groesse) }
}

// MARK: - Wiederkehrende Bausteine

/// Karte nach Guide: weiß (Dark: Grau-850), Radius 16, weicher Schatten.
struct MhKarte<Inhalt: View>: View {
  @ViewBuilder let inhalt: () -> Inhalt

  var body: some View {
    inhalt()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(Mh.karte)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .shadow(color: Color(UIColor(rgb: 0x22392C)).opacity(0.10), radius: 6, y: 2)
  }
}

/// Primär-/Sekundär-Button nach Guide: Pastellfläche, 900er-Text, Radius 12,
/// Höhe 44, Gewicht Bold.
struct MhButtonStil: ButtonStyle {
  var flaeche: Color = Mh.minze300
  var text: Color = Mh.minze900

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.nunitoBold(16))
      .foregroundStyle(text)
      .padding(.horizontal, 16)
      .frame(minHeight: 44)
      .background(flaeche.opacity(configuration.isPressed ? 0.75 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
