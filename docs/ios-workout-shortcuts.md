# wger-Kurzbefehle für iOS

Installiere die IPA mit SideStore, öffne wger und melde dich bei deinem gewohnten Server an. In Apples Kurzbefehle-App findest du die Aktionen unter **App-Kurzbefehle → wger**. Du kannst sie auch mit **Aktion hinzufügen** in eigene Abläufe einsetzen.

| Aktion | Verhalten |
| --- | --- |
| Workout starten | Startet den heutigen Trainingstag im aktuellen Plan. Optional einen Trainingstag mit seinem Namen angeben. Ein laufendes Training wird fortgesetzt. |
| Workout mit NOOP starten | Startet dasselbe wger-Workout und öffnet die installierte NOOP-App. Dort die Aufzeichnung am Gurt starten. |
| Aktuellen Satz speichern | Speichert die Werte des aktuell geöffneten, vollständigen und noch ungespeicherten Satzes. |
| Satzpause verlängern | Verlängert den laufenden Countdown um 1 bis 1800 Sekunden, standardmäßig 30. |
| Satzpause überspringen | Wechselt von der laufenden Pause zur nächsten Trainingsseite. |
| Workoutstatus abrufen | Liefert JSON-Text. Über „Wörterbuch aus Eingabe abrufen“ lassen sich `active`, `routine`, `day`, `startedAt`, `restEndsAt` und `completedSets` auslesen. Bei inaktivem Training enthält die Antwort nur `active: false`. Zeiten sind UTC. |
| Workout beenden und speichern | Speichert die wger-Sitzung direkt und gibt die Endzeit in UTC zurück. Die NOOP-Aufzeichnung separat stoppen. |
| Workoutabschluss öffnen | Öffnet das vorausgefüllte Abschlussformular. Zeiten und Notizen prüfen und auf **Speichern** tippen. |
| Trainingspläne öffnen | Öffnet die Planliste zur manuellen Auswahl. |

Die Aktionen öffnen wger im Vordergrund. NOOP 12.0.0 registriert das URL-Schema `noop`. Seine iOS-App-Intents bieten unter anderem **Sync Strap** und **Mark a Moment**. Für einen gemeinsamen Start lege „Workout mit NOOP starten“ auf den Home-Bildschirm. Aufnahme und Abschluss in NOOP erfolgen in NOOP selbst. „Workoutstatus abrufen“ liefert den wger-Startzeitpunkt für eigene zeitbasierte Abläufe.

[NOOP-Aktionen in Version 12.0.0](https://github.com/ryanbr/noop/blob/v12.0.0/StrandiOS/System/NOOPAppIntents.swift)
