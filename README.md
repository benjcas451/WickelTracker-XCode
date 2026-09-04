# Wickel-Tracker (iOS + watchOS)

Native iOS-App zur Erfassung von Wickel-Vorgängen (Urin / Stuhlgang /
Beides, optional Stoffwindel), mit eingebetteter watchOS-App. Swift,
SwiftUI, keine externen Abhängigkeiten (kein SPM, keine Pods). Portiert
von einer Flutter-App — Bestandsdaten, Einstellungen und sogar noch
unbestätigte Watch-Einträge werden beim App-Store-Update nahtlos
übernommen (Details unten).

Schwester-Repos: **WickelTracker-Android** (Android + Wear OS, gleicher
Funktionsumfang, gleiches Design) sowie **StillzeitTracker-** und
**MedikamentenTracker-XCode/-Android** (gleiche Architektur- und
Design-Familie).

---

## Targets

| Target | Was | Bundle-ID |
|---|---|---|
| `wickel` | iPhone-App (SwiftUI, iOS 16+) | `org.dwarftsch.wickel` |
| `WickelWatch` | watchOS-App (SwiftUI, watchOS 10+), im App-Bundle eingebettet | `org.dwarftsch.wickel.watchkitapp` |
| `wickelTests` / `wickelUITests` | Test-Templates | — |

Alle Targets sind bewusst **auf iOS/watchOS beschränkt**
(`SUPPORTED_PLATFORMS`) — macOS/visionOS wieder zu aktivieren bricht
Xcode-Cloud-Workflows und den WatchConnectivity-Code. Ebenso bleibt
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`; der Code ist unter
`SWIFT_STRICT_CONCURRENCY=complete` warnungsfrei.

## Einrichtung auf einem neuen Gerät

1. Repo klonen, `wickel.xcodeproj` in **Xcode 16 oder neuer** öffnen
   (Projektformat `objectVersion 77` mit synchronisierten Ordner-Gruppen:
   Dateien im Ordner erscheinen automatisch im Target).
2. **Signing:** Automatic Signing; in den Target-Einstellungen das eigene
   Team wählen, falls abweichend. Für Simulator-Builds ist kein
   Zertifikat nötig.
3. Bauen/Starten: Scheme `wickel` (iPhone) bzw. `WickelWatch` (Uhr) auf
   einem Simulator. Das war's — keine weiteren Setup-Schritte.

Watch-Test im Simulator: gekoppeltes Paar booten (`xcrun simctl list
pairs`), iPhone-App starten — sie schiebt den aktuellen Stand per
`updateApplicationContext` auf die Uhr.

## Versionierung & Build-Nummern

- `MARKETING_VERSION`: im Projekt gepflegt, **auf App- und Watch-Target
  identisch halten** (Apple verlangt übereinstimmende
  `CFBundleShortVersionString`). **Konvention:** Major/Minor über alle
  Plattformen identisch; die Patch-Stelle darf pro Plattform divergieren.
- **Xcode Cloud überschreibt die Build-Nummer mit seiner eigenen
  Zählung** — ASC verlangt steigende Nummern nur *innerhalb desselben
  Versions-Strings*. Bei Kollision: Patch-Version anheben oder in ASC →
  Xcode Cloud → „Next Build Number“ setzen.
- **Generischer TestFlight-Installationsfehler?** Erst Geräte-Logs ziehen
  (`sudo log collect --device-name … --last 5m`) statt raten. Bekannter
  Fall in dieser App-Familie: ein DNS-Filter (NextDNS) blockte
  Apple-Endpunkte (`xp.apple.com`), die TestFlight-ServiceExtension
  crashte daran — Fix ist eine Allowlist-Freigabe, kein Build-Problem.
- Die Flutter-App war zuletzt als 1.3.0 (Build ≤ 10) im Store; die
  native App startet als **2.0.0**.

## CI / Releases (`.github/workflows/build-ipa.yml`)

Manuell per *workflow_dispatch*: baut eine **unsignierte IPA**
(inkl. eingebetteter Watch-App) und hängt sie an ein GitHub-Release
(`v<version>-<run_number>`). Unsignierte IPAs sind **nicht**
Transporter-tauglich — App-Store-Uploads laufen über Xcode
(Archive/Organizer) oder Xcode Cloud (beim Anlegen des Workflows nur
iOS-Archive-Aktionen behalten).

## Herkunft & Datenmigration (Flutter → nativ)

Die App ersetzt eine Flutter-App unter derselben Bundle-ID. Beim Update
bleiben alle Nutzerdaten erhalten (im Simulator verifiziert):

- **SQLite:** identische Datei `wickel_demo.db` im Documents-Ordner,
  identisches Schema, `PRAGMA user_version = 2` inkl. Upgrade-Pfad von v1
  (`stoffwindel`-Spalte). Der `IsoZeit`-Parser toleriert auch die
  Mikrosekunden-Präzision alter Dart-Einträge. `last`/`undo` sortieren
  nach `time`, nicht `id` — Watch-Einträge können nachträglich mit
  älterem Zeitpunkt eintreffen.
- **Einstellungen:** Flutters shared_preferences landet in denselben
  UserDefaults, nur mit Präfix `flutter.`. Einmalige Migration inklusive
  der **Bool**-Einstellung `stoffwindel_enabled`
  (`AppSettings.migrationAusfuehren()`).
- **Watch-Warteschlange:** Die native `WatchBridge` verwendet dieselben
  UserDefaults-Schlüssel (`watch.pendingEntries`, `watch.appliedIds`)
  wie die Flutter-App — beim Update noch unbestätigte Uhr-Einträge gehen
  nicht verloren. Auch das Snapshot-Format an die Uhr ist identisch, die
  installierte Watch-App läuft nahtlos weiter.

## Architektur

```
wickel/                          iPhone-App
  Models.swift                   WickelType/PeriodStats(%)/LastEntry/WickelStats, IsoZeit
  WickelService.swift            Protokoll der Datenquellen + Factory
  DemoService.swift              lokale SQLite (sqflite-kompatibel, v2, C-API)
  ApiService.swift               REST-Client (URLSession; api.php + mTLS via Delegate)
  ClientIdentity.swift           PEM (crt/key) -> SecIdentity (Keychain)
  CertSource.swift               client.crt/client.key: App-Ordner oder frei
                                 gewählter Ordner (security-scoped Bookmark)
  AppOrdner.swift                hält den App-Ordner in der Dateien-App sichtbar
  AppSettings.swift              UserDefaults + Flutter-Migration (inkl. Bool)
  LocalBackupService.swift       JSON-Backup (Format kompatibel zu Android/Flutter)
  WatchBridge.swift              Warteschlange+Ack der Uhr, Snapshot-Push, getConnection
  Theme.swift                    Minze-&-Honig-Tokens, Nunito, Bausteine
  HomeView/HomeViewModel/SettingsView.swift   UI
WickelWatch/                     watchOS-App (aus der Flutter-Ära 1:1 übernommen,
                                 in Minze & Honig restylt)
  WatchStore.swift               Outbox (UUID-dedupliziert), Snapshot-Spiegel, Direktbetrieb
  DirectApi.swift                REST-Client der Uhr (inkl. mTLS)
  ServerConnection.swift         übernommene Verbindung + Persistenz
  ClientIdentity.swift           PEM -> SecIdentity (watchOS)
  WickelType.swift               Typen + Minze-&-Honig-Farben
  ContentView.swift              UI
```

**Datenquellen (vom Nutzer wählbar):** Server per mTLS-Client-Zertifikat,
Server per API-Key oder lokale SQLite ohne Sync. Die `api.php` verlangt
den **API-Key in jedem Fall** — auch hinter mTLS.

## Watch-Protokoll (WatchConnectivity)

Drei Strecken, alle byte-kompatibel zur abgelösten Flutter-App:

1. **Uhr → iPhone (Einträge):** `{"v":1, "action":"add", "id":<UUID>,
   "type", "time", "stoffwindel"}` — parallel per `transferUserInfo`
   (garantiert) und `sendMessage` (schnell). Das iPhone dedupliziert über
   die UUID, legt den Eintrag in der gewählten Datenquelle an und
   bestätigt erst dann (persistente Warteschlange, nichts geht verloren).
2. **iPhone → Uhr (Snapshot):** `updateApplicationContext` mit
   `{lastType, lastTime, lastStoffwindel, stoffwindelEnabled,
   todayTotal, updatedAt}`.
3. **Direktbetrieb:** Mit `getConnection` übernimmt die Uhr die
   Server-Verbindung des iPhones (bei mTLS inkl. PEMs, base64) und
   spricht danach selbst mit der API; ist der Server nicht erreichbar,
   fällt der Eintrag automatisch auf den Weg über das iPhone zurück.

## REST-API & Datenmodell

Alle Endpunkte unter `<Basis-URL>api.php`, Antworten JSON.

| Endpunkt | Zweck |
|---|---|
| `POST api.php?action=wickeln` | Eintrag anlegen: `{"typ": "urin", "stoffwindel": false}` (Server stempelt die Zeit selbst) |
| `GET api.php?action=stats` | Statistik je Zeitraum mit total + Prozentanteilen je Typ, plus `last` |
| `GET api.php?action=last` | letzter Eintrag |
| `GET api.php?action=heute` | Anzahl heute |
| `POST api.php?action=undo_last` | letzten Eintrag löschen (404 = keiner vorhanden) |
| `POST api.php?action=undo` | Eintrag nach ID löschen: `{"id": 42}` |

Lokale Tabelle: `entries(id, type, time, stoffwindel)`.

## Sicherung & Gerätewechsel

Auf iOS gibt es kein Gegenstück zu Androids `backup_rules.xml` /
`data_extraction_rules.xml`. Gesteuert wird über die Dateiablage
(`Documents` wird gesichert, `Library/Caches` und `tmp` nicht),
`isExcludedFromBackup` und die Keychain-Attribute.

| | iCloud-Backup | Direkttransfer (Schnellstart) |
|---|---|---|
| Einträge (SQLite) | ✅ | ✅ |
| API-Key (Keychain) | ❌ | ✅ |
| Client-Zertifikat | ❌ | ❌ |

Der API-Key liegt in der Keychain, mit `kSecAttrAccessibleAfterFirstUnlock`
und **ohne** `kSecAttrSynchronizable`. Damit ist er beim Direkttransfer und
im verschlüsselten Finder-Backup dabei, aus einem iCloud-Backup dagegen nicht
wiederherstellbar — die iOS-Entsprechung der Android-Entscheidung
„`<device-transfer>` ja, `<cloud-backup>` nein“. Nach einer Wiederherstellung
aus iCloud ist er einmal neu einzutragen. Die Uhr legt ihre übernommene
Verbindung in `ServerConnectionStore` mit demselben Attribut ab.

Client-Zertifikate (`client.crt` / `client.key`) liegen im App-Ordner der
Dateien-App und sind nach einem Gerätewechsel gegebenenfalls neu abzulegen.
Damit dieser Ordner dort überhaupt auftaucht, hält `AppOrdner` beim Start
eine Hinweisdatei (`README.txt`) darin vor – iOS blendet App-Ordner ohne
sichtbare Datei aus. Die Datei wird angelegt, sobald sie fehlt, und
bewusst **ohne** vorherige Leer-Prüfung: `contentsOfDirectory` zählt auch
unsichtbare Punkt-Dateien mit, für iOS gilt der Ordner damit trotzdem als
leer. Genau daran scheiterte der erste Anlauf.

Der Build-Check prüft am gebauten Bundle, dass `UIFileSharingEnabled` und
`LSSupportsOpeningDocumentsInPlace` wirklich als Boolean in der generierten
Info.plist stehen, und schlägt sonst fehl.

Alternativ lässt sich unter *Einstellungen → Server (mTLS-API)* ein
beliebiger anderer Ordner auswählen. Er wird als security-scoped Bookmark
gespeichert. Nach einer Wiederherstellung auf einem neuen Gerät zeigt das
Bookmark ins Leere; die App meldet das und bittet darum, den Ordner erneut
auszuwählen.

Unabhängig davon gibt es das manuelle Backup unter *Einstellungen → Backup*.

## Design-System „Minze & Honig“ (v1.0)

Quelle der Wahrheit im Code: `wickel/Theme.swift` (iPhone) und
`WickelWatch/WickelType.swift` (Uhr). Kernregeln wie in den
Schwester-Repos (Weiß dominiert, Skalen 50–900, Pastell 300 nie als Text
auf Weiß, Nunito eingebettet, Radien 8/12/16/24/Pill).

**Wickel-Typen (Chip-Muster, plattformübergreifend identisch):**
Urin = Honig, Stuhlgang = Grau, Beides = Flieder; die
**Stoffwindel-Funktion trägt Minze**.

## Sicherheit / was nie ins Repo darf

API-Keys, Server-URLs von Nutzern, Zertifikate/private Schlüssel,
Provisioning-Profile. Die App liest Client-Zertifikate ausschließlich zur
Laufzeit aus ihrem Documents-Ordner.
