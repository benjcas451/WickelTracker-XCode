import SwiftUI

@main
struct WickelWatchApp: App {
  @StateObject private var store = WatchStore()

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        ContentView()
      }
      .environmentObject(store)
      // Beim Erscheinen aktivieren: erst danach stellt watchOS gespiegelte
      // Stände zu und nimmt Übertragungen ans iPhone an.
      .onAppear { store.activate() }
    }
  }
}
