import SwiftUI
import WatchKit

struct ContentView: View {
  @EnvironmentObject private var store: WatchStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var showsConnection = false

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        LastEntryView(
          type: store.lastType,
          time: store.lastTime,
          stoffwindel: store.stoffwindelEnabled && store.lastStoffwindel
        )

        if store.stoffwindelEnabled {
          Toggle(isOn: $store.stoffwindelActive) {
            Label("Stoffwindel", systemImage: "washer.fill")
              .font(Mh.button)
              .foregroundStyle(Mh.text)
          }
          .tint(Mh.primary)
          .padding(.bottom, 2)
        }

        ForEach(WickelType.allCases) { type in
          Button {
            store.add(type)
            WKInterfaceDevice.current().play(.success)
          } label: {
            Label {
              Text(type.label).foregroundStyle(type.buttonText)
            } icon: {
              Image(systemName: type.symbol).foregroundStyle(type.akzent)
            }
            .font(Mh.button)
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(type.color)
        }

        if !store.pendingRelay.isEmpty {
          Label(
            store.pendingRelay.count == 1
              ? "1 Eintrag wartet auf das iPhone"
              : "\(store.pendingRelay.count) Einträge warten auf das iPhone",
            systemImage: "arrow.triangle.2.circlepath"
          )
          .font(Mh.footnote)
          .foregroundStyle(Mh.textSecondary)
          .multilineTextAlignment(.center)
          .padding(.top, 4)
        }

        if let message = store.errorMessage {
          Text(message)
            .font(Mh.footnote)
            .foregroundStyle(Mh.danger)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
        }

        if let notice = store.notice {
          Text(notice)
            .font(Mh.caption)
            .foregroundStyle(Mh.textSecondary)
            .multilineTextAlignment(.center)
        }

        connectionStatus
      }
    }
    .font(Mh.body)
    .navigationTitle("Wickeln")
    .sheet(isPresented: $showsConnection) {
      ConnectionView(store: store)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { store.refreshFromServer() }
    }
  }

  /// Zeigt, ob die Uhr direkt mit dem Server spricht oder über das iPhone geht
  /// — und führt zum Übernehmen der Verbindung.
  private var connectionStatus: some View {
    Button {
      showsConnection = true
    } label: {
      Label(store.statusText, systemImage: store.connection == nil ? "iphone" : "link")
        .font(Mh.caption)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(store.connection == nil ? Mh.textSecondary : WickelType.minze)
    .padding(.top, 8)
  }
}

/// Übernimmt die auf dem iPhone eingerichtete Server-Verbindung, sodass die
/// Uhr anschließend selbst mit dem Server spricht.
private struct ConnectionView: View {
  @ObservedObject var store: WatchStore
  @Environment(\.dismiss) private var dismiss

  private var connected: Bool { store.connection != nil }

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        Text("Server-Verbindung")
          .font(Mh.headline)
          .foregroundStyle(Mh.textStrong)

        Text(store.statusText)
          .font(Mh.body)
          .foregroundStyle(connected ? WickelType.minze : Mh.textSecondary)

        Text(
          connected
            ? "Einträge gehen direkt an den Server — auch ohne laufende iPhone-App. Ist er nicht erreichbar, springt die Uhr automatisch auf das iPhone um."
            : "Alle Einträge laufen über das iPhone. Ist dort ein Server eingerichtet, kann die Uhr die Verbindung übernehmen."
        )
        .font(Mh.caption)
        .foregroundStyle(Mh.textSecondary)
        .multilineTextAlignment(.center)

        if store.isImporting {
          ProgressView().tint(Mh.primary)
        }

        if let message = store.errorMessage {
          Text(message)
            .font(Mh.caption)
            .foregroundStyle(Mh.danger)
            .multilineTextAlignment(.center)
        }

        Button {
          store.importConnection()
        } label: {
          Label(
            connected ? "Erneut importieren" : "Verbindung importieren",
            systemImage: "square.and.arrow.down"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Mh.primary)
        .foregroundStyle(Mh.onPrimary)
        .disabled(store.isImporting)

        if connected {
          Button(role: .destructive) {
            store.removeConnection()
          } label: {
            Label("Verbindung entfernen", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(Mh.danger)
          .disabled(store.isImporting)
        }

        Button("Fertig") { dismiss() }
          .buttonStyle(.bordered)
      }
      .padding(.horizontal, 4)
    }
    .font(Mh.button)
  }
}

/// Letzter Eintrag mit „vor X“-Angabe, die minütlich weiterläuft.
struct LastEntryView: View {
  let type: WickelType?
  let time: Date?
  let stoffwindel: Bool

  var body: some View {
    VStack(spacing: 2) {
      if let type {
        Label {
          Text(type.label).foregroundStyle(Mh.textStrong)
        } icon: {
          Image(systemName: type.symbol).foregroundStyle(type.akzent)
        }
        .font(Mh.headline)
        if let time {
          TimelineView(.periodic(from: .now, by: 60)) { context in
            Text("\(Self.relative(time, now: context.date)) · \(Self.hhmm(time))")
              .font(Mh.footnote)
              .monospacedDigit()
              .foregroundStyle(Mh.textSecondary)
          }
        }
        if stoffwindel {
          Label("Stoffwindel", systemImage: "washer.fill")
            .font(Mh.caption)
            .foregroundStyle(WickelType.stoffwindelColor)
        }
      } else {
        Text("Noch kein Eintrag")
          .font(Mh.headline)
          .foregroundStyle(Mh.textSecondary)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
  }

  /// Gleiche Formulierungen wie `relative()` in `lib/screens/home_screen.dart`.
  static func relative(_ time: Date, now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(time))
    let minutes = seconds / 60
    if minutes < 1 { return "gerade eben" }
    if minutes < 60 { return "vor \(minutes) min" }
    let hours = minutes / 60
    if hours < 24 { return "vor \(hours) h" }
    return "vor \(hours / 24) d"
  }

  static func hhmm(_ time: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
  }
}
