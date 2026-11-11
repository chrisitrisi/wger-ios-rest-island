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

  static func run(_ method: String, arguments: [String: Any] = [:]) async throws -> String {
    // Cold launches create the Flutter engine and install the Dart handler asynchronously.
    for _ in 0..<150 {
      if ready { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    guard ready, let channel = channel else {
      throw WorkoutActionError(message: "wger ist noch nicht bereit. Öffne die App und versuche es erneut.")
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
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("log")
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct SkipRestAction: AppIntent {
  static var title: LocalizedStringResource = "Satzpause überspringen"
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("skip")
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct ExtendRestAction: AppIntent {
  static var title: LocalizedStringResource = "Satzpause verlängern"
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Sekunden", default: 30)
  var seconds: Int

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("extend", arguments: ["seconds": seconds])
    return .result(value: value)
  }
}

@available(iOS 16.0, *)
struct WorkoutStatusAction: AppIntent {
  static var title: LocalizedStringResource = "Workoutstatus abrufen"
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("status")
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
struct OpenRoutinesAction: AppIntent {
  static var title: LocalizedStringResource = "Trainingspläne öffnen"
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let value = try await WorkoutShortcutBridge.run("plans")
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
    AppShortcut(intent: FinishWorkoutAction(), phrases: ["Öffne meinen Workoutabschluss in \(.applicationName)"],
                shortTitle: "Workoutabschluss öffnen", systemImageName: "flag.checkered")
    AppShortcut(intent: OpenRoutinesAction(), phrases: ["Öffne meine Trainingspläne in \(.applicationName)"],
                shortTitle: "Trainingspläne öffnen", systemImageName: "list.clipboard")
  }
}
