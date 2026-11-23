import XCTest

/// Bildschirmfotos für Pull Requests (Minze & Honig 2.0).
///
/// Läuft im Workflow „Bildschirmfotos“; hell/dunkel und Schriftgröße stellt
/// der Workflow am Simulator ein und reicht den Namen der Variante als
/// MH_VARIANTE durch (TEST_RUNNER_MH_VARIANTE). Die App startet im Modus
/// „Lokal (SQLite)“ mit erfundenen Einträgen (`-MhBildschirmfotos`, nur im
/// Debug-Build), es geht nichts an einen Server.
final class ScreenshotTests: XCTestCase {

  override func setUp() {
    continueAfterFailure = true
  }

  @MainActor
  func testAnsichten() throws {
    let app = starte(stoffwindel: false)
    foto(app, "01-start")
    app.swipeUp()
    foto(app, "02-start-statistik")

    let einstellungen = app.buttons["einstellungen"]
    if einstellungen.waitForExistence(timeout: 5) {
      einstellungen.tap()
      foto(app, "03-einstellungen")
      app.swipeUp()
      foto(app, "04-einstellungen-unten")
    }
    app.terminate()

    // Mit eingeschalteter Stoffwindel-Funktion, dann ein Eintrag mit
    // Rückmeldung.
    let mitStoffwindel = starte(stoffwindel: true)
    foto(mitStoffwindel, "05-stoffwindel")
    let urin = mitStoffwindel.buttons["eintrag-urin"]
    if urin.waitForExistence(timeout: 5) {
      urin.tap()
      foto(mitStoffwindel, "06-eintrag-gespeichert", warte: 1)
    }
    mitStoffwindel.terminate()
  }

  @MainActor
  private func starte(stoffwindel: Bool) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-MhBildschirmfotos", "1",
      // Systemtexte und Uhrzeiten auf Deutsch, wie auf Lucas' Geräten.
      "-AppleLanguages", "(de)",
      "-AppleLocale", "de_DE",
      "-data_source_mode", "demo",
      "-stoffwindel_enabled", stoffwindel ? "YES" : "NO",
    ]
    app.launch()
    return app
  }

  @MainActor
  private func foto(_ app: XCUIApplication, _ name: String, warte: UInt32 = 2) {
    sleep(warte)
    let variante = ProcessInfo.processInfo.environment["MH_VARIANTE"] ?? "standard"
    let anhang = XCTAttachment(screenshot: app.screenshot())
    anhang.name = "\(variante)-\(name)"
    anhang.lifetime = .keepAlways
    add(anhang)
  }
}
