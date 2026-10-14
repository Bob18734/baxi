#!/usr/bin/env python3
"""Check student integration prerequisites. This does not certify driving or legal accuracy."""
import json
from pathlib import Path
import re
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    failures = []
    for module in ("LanePicker", "CueScheduler", "RoundaboutClassifier", "ApproachHeading"):
        source = (root / "Baxi/Core" / f"{module}.swift").read_text()
        if not re.search(r"^\s*static let isImplemented = true\s*$", source, re.MULTILINE):
            failures.append(f"{module}: student implementation still pending")

    try:
        entries = json.loads((root / "Baxi/Resources/Content/briefings.json").read_text())["entries"]
        if not isinstance(entries, list) or any(not isinstance(e, dict) for e in entries):
            raise ValueError("entries must be a list of objects")
        required = ("singleLaneRoundabout", "multiLaneRoundabout", "interchangeRoundabout",
                    "highwayRamp", "schoolZone")
        for kind in required:
            matches = [e for e in entries if e.get("kind") == kind]
            if len(matches) != 1:
                failures.append(f"{kind}: expected one briefing, found {len(matches)}")
                continue
            entry = matches[0]
            for field in ("title", "howTo"):
                if not isinstance(entry.get(field), str) or not entry[field].strip():
                    failures.append(f"{kind}: missing {field}")
            for field in ("manualChapter", "manualPage"):
                if type(entry.get(field)) is not int or entry[field] <= 0:
                    failures.append(f"{kind}: missing positive {field}")
            if not isinstance(entry.get("quote"), str):
                failures.append(f"{kind}: quote must be a string (empty is allowed)")
    except (OSError, ValueError, KeyError, TypeError) as error:
        failures.append(f"briefings.json: {error}")

    if failures:
        print("Integration prerequisites incomplete:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("Integration prerequisites present. Run swift test, verify manual citations, and test on an iPhone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
