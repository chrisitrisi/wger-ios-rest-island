# wger-Kurzbefehle und Live Activity für iOS

Installiere die IPA mit SideStore, öffne wger und melde dich bei deinem gewohnten Server an. Die Aktionen sind für **Automationen und eigene Abläufe** in Apples Kurzbefehle-App gedacht, nicht für Siri. Du findest sie unter **Aktion hinzufügen → Apps → wger**. Die ersten neun stehen zusätzlich unter **App-Kurzbefehle → wger** (Apple erlaubt dort höchstens zehn).

## Aktionen

| Aktion | Öffnet wger | Ergebnis |
| --- | --- | --- |
| Workout starten | ja | Startet den heutigen Trainingstag im aktuellen Plan. Optional einen Trainingstag mit seinem Namen angeben. Ein laufendes Training wird fortgesetzt. Liefert den Namen des Trainingstags. |
| Workout mit NOOP starten | ja | Wie „Workout starten“, öffnet danach die NOOP-App. |
| Aktuellen Satz speichern | nein | Speichert den geöffneten, ungespeicherten Satz mit seinen Werten. Danach startet die Satzpause. |
| Satz mit Werten speichern | nein | Wie oben, mit **Wiederholungen** und **Gewicht** aus dem Kurzbefehl. Leere Felder übernehmen die geplanten Werte. Einheiten und RiR bleiben die geplanten. |
| Satzpause verlängern | nein | Verlängert den laufenden Countdown um 1 bis 1800 Sekunden, standardmäßig 30. |
| Satzpause überspringen | nein | Wechselt von der laufenden Pause zum nächsten Satz. |
| Pausenende abrufen | nein | **Datum** des Countdown-Endes. Fehler, wenn keine Pause läuft. |
| Verbleibende Pause (Sekunden) | nein | **Zahl**, aufgerundet. 0, wenn keine Pause läuft. |
| Nächsten Satz abrufen | nein | **Text**, z. B. „Bankdrücken · Satz 2 von 3 · 10 × 60 kg“. Während der Pause der Satz danach, sonst der aktuelle. |
| Workoutstatus abrufen | nein | JSON-Text, siehe unten. |
| Workout beenden und speichern | ja | Speichert die wger-Sitzung direkt und gibt die Endzeit in UTC zurück. |
| Workoutabschluss öffnen | ja | Öffnet das vorausgefüllte Abschlussformular. Zeiten und Notizen prüfen und auf **Speichern** tippen. |
| Trainingspläne öffnen | ja | Öffnet die Planliste. |

Die Aktionen ohne „Öffnet wger“ laufen im Hintergrund, iOS startet wger dafür bei Bedarf unsichtbar. Klappt das nicht rechtzeitig, bricht die Aktion ab mit „wger läuft nicht im Hintergrund. Öffne wger einmal und versuche es erneut.“

### Workoutstatus

Über **Wörterbuch aus Eingabe abrufen** lassen sich diese Werte auslesen. Zeiten sind UTC.

| Schlüssel | Inhalt |
| --- | --- |
| `active` | `false`, wenn kein Workout läuft. Dann fehlen die übrigen Werte. |
| `routine`, `day` | Plan und Trainingstag |
| `startedAt` | Start des Workouts |
| `exercise`, `detail` | Nächster Satz wie bei „Nächsten Satz abrufen“, z. B. `Bankdrücken` und `Satz 2 von 3 · 10 × 60 kg` |
| `resting` | `true` während einer Satzpause |
| `restEndsAt` | Ende des Pausen-Countdowns, sonst leer |
| `restRemaining` | Verbleibende Pause in Sekunden, sonst 0 |
| `completedSets` | Anzahl gespeicherter Sätze |

## Beispiel: Satz speichern → Pausenende abrufen

Ein Kurzbefehl, der den Satz speichert und dich am Ende der Pause erinnert, ohne wger zu öffnen. Zum Beispiel als Button auf dem Home-Bildschirm, über die Aktionstaste oder als Automation per NFC-Tag an der Hantelbank:

1. **Aktuellen Satz speichern** (wger). Alternativ **Satz mit Werten speichern** mit **Nach Eingabe fragen** bei den Wiederholungen.
2. **Pausenende abrufen** (wger). Ergebnis: ein Datum.
3. **Warten bis** → *Pausenende*. Alternativ **Verbleibende Pause (Sekunden)** und **Warten** mit dieser Zahl.
4. **Nächsten Satz abrufen** (wger).
5. **Mitteilung anzeigen** mit dem Text aus Schritt 4.

Läuft keine Pause (z. B. letzter Satz oder Pause ohne Countdown), bricht der Kurzbefehl bei Schritt 2 mit einer Meldung ab. Soll er still weiterlaufen, nimm in Schritt 2 und 3 **Verbleibende Pause (Sekunden)**: Sie liefert dann 0. Für das Armband (NOOP) folgt später eine eigene Aktion an Stelle von Schritt 5.

## Live Activity und Dynamic Island

Sobald du im Trainingsmodus das Workout startest, zeigt wger eine Live Activity auf dem Sperrbildschirm und in der Dynamic Island. Sie bleibt bis zum Verlassen des Trainingsmodus oder bis zum Speichern des Workouts bestehen.

- **Zwischen den Pausen:** Übung, „Satz X von Y · Wiederholungen × Gewicht“ und die laufende Workoutzeit.
- **In der Pause:** Countdown und „Als Nächstes …“. Am Pausenende wechselt die Anzeige auch ohne laufende App auf „Pause vorbei“ und den nächsten Satz.
- **Buttons (ab iOS 17):** Satz speichern, Pause überspringen und +30 s, wie in der Benachrichtigung.

iOS erlaubt das Starten einer Live Activity nur, solange wger im Vordergrund ist. Aktualisieren klappt auch im Hintergrund, z. B. nach einem Kurzbefehl. Live Activities lassen sich unter **Einstellungen → wger** ein- und ausschalten.
