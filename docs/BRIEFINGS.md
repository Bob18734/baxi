# Writing the briefings (students only)

`Baxi/Resources/Content/briefings.json` holds the short notes the Preview screen shows under each
hard spot. You write these by hand from the Indiana Driver's Manual; no AI-written driving advice
(see AI_DISCLOSURE.md). Claude only made the schema and the loader.

## Which entries the app reads

The Preview screen looks up one entry per kind of spot. These five kinds appear on the Carmel routes:

| `kind` (exact spelling) | Shown on |
|---|---|
| `singleLaneRoundabout` | Roundabouts with one circulating lane |
| `multiLaneRoundabout` | Roundabouts with two or more lanes |
| `interchangeRoundabout` | Roundabouts at a highway or parkway ramp |
| `highwayRamp` | Merges, on-ramps and exit ramps |
| `schoolZone` | School zones |

Other kinds in `FeatureKind` (`stopSign`, `trafficSignal`, `road40to45`, `road50`) are accepted
but not shown yet.

## Each entry

```json
{
  "kind": "multiLaneRoundabout",
  "title": "Two-lane roundabouts",
  "howTo": "One or two sentences in your own words.",
  "manualChapter": 7,
  "manualPage": 41,
  "quote": "The exact sentence from the manual, copied word for word."
}
```

- An entry with an empty `title` or `howTo` is skipped, so you can fill them one at a time.
- `manualChapter` and `manualPage` print as "Indiana Driver's Manual, chapter 7, page 41" under the note.
- `quote` is optional; leave it `""` if you paraphrase only.
- The page numbers in the current file are placeholders. Check every one against the PDF.

## Check your work

Run `python3 scripts/check-readiness.py` to validate the required entries and citation fields.
The Swift package excludes the content folder, so `swift test` alone does not validate this file.
Then open Preview on the Roundabout loop. Each
roundabout card should show your note with its citation.
