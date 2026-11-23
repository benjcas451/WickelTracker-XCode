#if DEBUG
  import Foundation

  /// Nur für die Bildschirmfotos der UI-Tests (Workflow „Bildschirmfotos“).
  ///
  /// Startet die App mit dem Argument `-MhBildschirmfotos 1`, ersetzt sie den
  /// Inhalt der lokalen Datenbank (Modus „Lokal (SQLite)“) durch erfundene
  /// Einträge der letzten 30 Tage. Ohne das Argument passiert nichts; in
  /// Release-Builds ist der Code gar nicht enthalten.
  enum Bildschirmfotos {

    static var aktiv: Bool {
      ProcessInfo.processInfo.arguments.contains("-MhBildschirmfotos")
    }

    /// Beim Start aufrufen, bevor die Oberfläche lädt. Wartet, bis die
    /// Testdaten geschrieben sind, damit das erste Bild sie schon zeigt.
    static func testdatenEinspielen() {
      guard aktiv else { return }
      let zeilen = erfundeneEintraege(jetzt: Date())
      let fertig = DispatchSemaphore(value: 0)
      Task.detached {
        try? await DemoService.shared.replaceAll(zeilen)
        fertig.signal()
      }
      _ = fertig.wait(timeout: .now() + 10)
    }

    /// Etwa sieben Einträge am Tag, rückwärts ab „vor 42 Minuten“, nach
    /// festem Muster – jeder Lauf ergibt dieselbe Verteilung.
    static func erfundeneEintraege(jetzt: Date) -> [EntryRow] {
      let muster = [
        "beides", "urin", "urin", "urin", "beides", "urin",
        "urin", "stuhlgang", "urin", "urin", "beides", "urin",
      ]
      let grenze = jetzt.addingTimeInterval(-30 * 86_400)
      var zeit = jetzt.addingTimeInterval(-42 * 60)
      var zeilen: [EntryRow] = []
      var nummer = 0
      while zeit > grenze {
        zeilen.append(
          EntryRow(
            id: Int64(nummer + 1),
            type: muster[nummer % muster.count],
            time: IsoZeit.dbString(from: zeit),
            stoffwindel: nummer % 3 == 0 ? 1 : 0))
        zeit = zeit.addingTimeInterval(-(3 * 3_600 + 10 * 60 + Double(nummer % 5) * 600))
        nummer += 1
      }
      return zeilen
    }
  }
#endif
