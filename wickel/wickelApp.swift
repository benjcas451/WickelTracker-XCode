import SwiftUI

@main
struct WickelApp: App {
  @Environment(\.scenePhase) private var scenePhase

  init() {
    NunitoFont.registrieren()
    AppSettings.migrationAusfuehren()
    // Nimmt Einträge der Apple Watch entgegen (WatchConnectivity).
    WatchBridge.shared.activate()
  }

  var body: some Scene {
    WindowGroup {
      HomeView()
    }
    .onChange(of: scenePhase) { phase in
      // Beim Zurückkehren in den Vordergrund können Watch-Einträge angefallen
      // sein, die iOS im Hintergrund zugestellt hat.
      if phase == .active {
        WatchBridge.shared.verarbeitePending()
      }
    }
  }
}
