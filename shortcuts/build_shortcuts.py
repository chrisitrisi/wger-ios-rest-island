#!/usr/bin/env python3
"""Builds the unsigned .shortcut files for training with wger and NOOP.

Every step is a built-in "Open URL" (plus a short wait), never an app action:
a sideloaded app carries a bundle id rewritten per signing team, and a shortcut
bound to the app actions of the original id would find no app. The links are
wger://workout/... (lib/features/routines/workout_shortcuts.dart) and
noop://workout/... (Strand/Data/WorkoutLink.swift in the NOOP fork).

Usage: build_shortcuts.py OUTPUT_DIR. Sign the results on macOS with
`shortcuts sign --mode anyone`, see .github/workflows/sign-shortcuts.yml.
"""

import plistlib
import sys
import uuid
from pathlib import Path


def _uuid() -> str:
    return str(uuid.uuid4()).upper()


def open_url(url: str) -> list[dict]:
    """A URL action and the Open URLs action consuming it."""
    url_id = _uuid()
    return [
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.url",
            "WFWorkflowActionParameters": {"UUID": url_id, "WFURLActionURL": url},
        },
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
            "WFWorkflowActionParameters": {
                "UUID": _uuid(),
                "WFInput": {
                    "Value": {"OutputName": "URL", "OutputUUID": url_id, "Type": "ActionOutput"},
                    "WFSerializationType": "WFTextTokenAttachment",
                },
            },
        },
    ]


def wait(seconds: int) -> list[dict]:
    return [
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.delay",
            "WFWorkflowActionParameters": {"UUID": _uuid(), "WFDelayTime": seconds},
        }
    ]


def shortcut(actions: list[dict], glyph: int, color: int) -> dict:
    return {
        "WFWorkflowClientVersion": "2605.0.5",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconGlyphNumber": glyph, "WFWorkflowIconStartColor": color},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowTypes": [],
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowActions": actions,
    }


# Icon colours and glyphs from the Shortcuts palette
RED, ORANGE, BLUE, GREEN, GREY = 4282601983, 4271458815, 463140863, 2071128575, 255
DUMBBELL, RUNNER, FLAME, FLAG = 59511, 59783, 59446, 59468

NOOP_STRENGTH = "noop://workout/start?sport=Strength"
NOOP_RUN_ZONE2 = "noop://workout/start?sport=Running&zone=2&warmup=5"
NOOP_SAUNA = "noop://workout/start?sport=Sauna"
NOOP_END = "noop://workout/end"
WGER_START = "wger://workout/start"
WGER_SAVE = "wger://workout/saveFinish"

SHORTCUTS = {
    # Mon/Tue/Thu/Sat: today's day in wger, the strap records strength
    "Training starten": shortcut(
        open_url(NOOP_STRENGTH) + wait(2) + open_url(WGER_START), DUMBBELL, BLUE),
    # Tue/Sat after the last set: save wger, end strength, run holding zone 2
    "Lauf Zone 2": shortcut(
        open_url(WGER_SAVE) + wait(2) + open_url(NOOP_END) + wait(1) + open_url(NOOP_RUN_ZONE2),
        RUNNER, GREEN),
    # After the run: end it, sauna with heart rate
    "Sauna starten": shortcut(open_url(NOOP_END) + wait(1) + open_url(NOOP_SAUNA), FLAME, ORANGE),
    # Mon/Thu: save wger and end strength in NOOP
    "Training beenden": shortcut(open_url(WGER_SAVE) + wait(2) + open_url(NOOP_END), FLAG, RED),
    # After the sauna (or any NOOP workout)
    "NOOP-Workout beenden": shortcut(open_url(NOOP_END), FLAG, GREY),
}


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, data in SHORTCUTS.items():
        path = out / f"{name}.shortcut"
        path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
        print(path)


if __name__ == "__main__":
    main()
