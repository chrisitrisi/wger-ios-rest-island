import AppIntents
import Flutter
import UIKit

private struct WorkoutActionError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

@available(iOS 16.0, *)
@MainActor
enum WorkoutShortcutBridge {
  private static var channel: FlutterMethodChannel?
  private static var ready = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let bridge = FlutterMethodChannel(name: "de.wger.flutter/workout-shortcuts",
                                      binaryMessenger: registrar.messenger())
    ready = false
    channel = bridge
    bridge.setMethodCallHandler { call, reply in
      guard call.method == "ready" else { reply(FlutterMethodNotImplemented); return }
      ready = true
      reply(nil)
    }
  }

  /// [background] is for actions with openAppWhenRun = false: iOS may start
  /// wger without drawing frames, so it gives up sooner with a clear message.
  static func run(_ method: String, arguments: [String: Any] = [:],
                  background: Bool = false) async throws -> String {
    // Cold launches create the Flutter engine and install the Dart handler asynchronously.
    for _ in 0..<(background ? 60 : 150) {
      if ready { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    guard ready, let channel = channel else {
      throw WorkoutActionError(message: background
        ? "wger läuft nicht im Hintergrund. Öffne wger einmal und versuche es erneut."
        : "wger ist noch nicht bereit. Öffne die App und versuche es erneut.")
    }
    return try await withCheckedThrowingContinuation { continuation in
      channel.invokeMethod(method, arguments: arguments) { result in
        if let value = result as? String {
          continuation.resume(returning: value)
        } else {
          let error = result as? FlutterError
          continuation.resume(throwing: WorkoutActionError(message: error?.message ?? "Aktion fehlgeschlagen."))
        }
      }
    }
  }
}

@available(iOS 16.0, *)
struct StartWorkoutAction: AppIntent {
  static var title: LocalizedStringResource = "Workout starten"
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Trainingstag (leer für heute)")
  var day: String?

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("start", arguments: ["day": day ?? ""])
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct StartWithNoopAction: AppIntent {
  static var title: LocalizedStringResource = "Workout mit NOOP starten"
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Trainingstag (leer für heute)")
  var day: String?

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("start", arguments: ["day": day ?? ""])
    if !((await UIApplication.shared.open(URL(string: "noop://")!))) {
      throw WorkoutActionError(message: "Dein wger-Workout läuft. NOOP konnte nicht geöffnet werden.")
    }
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct LogSetAction: AppIntent {
  static var title: LocalizedStringResource = "Aktuellen Satz speichern"
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("log", background: true)
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct SkipRestAction: AppIntent {
  static var title: LocalizedStringResource = "Satzpause überspringen"
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("skip", background: true)
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct ExtendRestAction: AppIntent {
  static var title: LocalizedStringResource = "Satzpause verlängern"
  static var openAppWhenRun: Bool = false

  @Parameter(title: "Sekunden", default: 30)
  var seconds: Int

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("extend", arguments: ["seconds": seconds],
                                                 background: true)
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct WorkoutStatusAction: AppIntent {
  static var title: LocalizedStringResource = "Workoutstatus abrufen"
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("status", background: true)
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct FinishWorkoutAction: AppIntent {
  static var title: LocalizedStringResource = "Workoutabschluss öffnen"
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("finish")
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct SaveWorkoutAction: AppIntent {
  static var title: LocalizedStringResource = "Workout beenden und speichern"
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("saveFinish")
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct OpenRoutinesAction: AppIntent {
  static var title: LocalizedStringResource = "Trainingspläne öffnen"
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("plans")
    return .result(value: value)
  }
}

// Further actions for automations in the Shortcuts app. Without Siri phrases:
// AppShortcutsProvider takes at most 10, they appear under "Add Action".

@available(iOS 16.0, *)
struct RestEndAction: AppIntent {
  static var title: LocalizedStringResource = "Pausenende abrufen"
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Date> {
    let value = try await WorkoutShortcutBridge.run("restEnd", background: true)
    guard let milliseconds = Double(value) else {
      throw WorkoutActionError(message: "Kein Pausen-Countdown aktiv.")
    }
    return .result(value: Date(timeIntervalSince1970: milliseconds / 1000))
  }
}

@available(iOS 16.0, *)
struct RestRemainingAction: AppIntent {
  static var title: LocalizedStringResource = "Verbleibende Pause (Sekunden)"
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> {
    let value = try await WorkoutShortcutBridge.run("restRemaining", background: true)
    return .result(value: Int(value) ?? 0)
  }
}

@available(iOS 16.0, *)
struct LogSetWithValuesAction: AppIntent {
  static var title: LocalizedStringResource = "Satz mit Werten speichern"
  static var openAppWhenRun: Bool = false

  @Parameter(title: "Wiederholungen (leer = geplant)")
  var repetitions: Double?

  @Parameter(title: "Gewicht (leer = geplant)")
  var weight: Double?

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    var arguments: [String: Any] = [:]
    if let repetitions = repetitions { arguments["repetitions"] = repetitions }
    if let weight = weight { arguments["weight"] = weight }
    let value = try await WorkoutShortcutBridge.run("logValues", arguments: arguments,
                                                    background: true)
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct NextSetAction: AppIntent {
  static var title: LocalizedStringResource = "Nächsten Satz abrufen"
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("next", background: true)
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct WgerWorkoutShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: StartWorkoutAction(), phrases: ["Starte mein Workout in \(.applicationName)"],
                shortTitle: "Workout starten", systemImageName: "figure.strengthtraining.traditional")
    AppShortcut(intent: StartWithNoopAction(), phrases: ["Starte mein Training mit NOOP und \(.applicationName)"],
                shortTitle: "Workout mit NOOP starten", systemImageName: "waveform.path.ecg")
    AppShortcut(intent: LogSetAction(), phrases: ["Speichere meinen Satz in \(.applicationName)"],
                shortTitle: "Aktuellen Satz speichern", systemImageName: "checkmark.circle")
    AppShortcut(intent: SkipRestAction(), phrases: ["Überspringe meine Satzpause in \(.applicationName)"],
                shortTitle: "Satzpause überspringen", systemImageName: "forward.end")
    AppShortcut(intent: ExtendRestAction(), phrases: ["Verlängere meine Satzpause in \(.applicationName)"],
                shortTitle: "Satzpause verlängern", systemImageName: "timer")
    AppShortcut(intent: WorkoutStatusAction(), phrases: ["Zeige meinen Workoutstatus in \(.applicationName)"],
                shortTitle: "Workoutstatus abrufen", systemImageName: "list.bullet")
    AppShortcut(intent: SaveWorkoutAction(), phrases: ["Beende mein Workout in \(.applicationName)"],
                shortTitle: "Workout beenden", systemImageName: "checkmark.flag")
    AppShortcut(intent: FinishWorkoutAction(), phrases: ["Öffne meinen Workoutabschluss in \(.applicationName)"],
                shortTitle: "Workoutabschluss öffnen", systemImageName: "flag.checkered")
    AppShortcut(intent: OpenRoutinesAction(), phrases: ["Öffne meine Trainingspläne in \(.applicationName)"],
                shortTitle: "Trainingspläne öffnen", systemImageName: "list.clipboard")
  }
}
