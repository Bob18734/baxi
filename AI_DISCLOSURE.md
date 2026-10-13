# AI usage disclosure

The Congressional App Challenge rules allow AI tools when every use is fully disclosed, when AI supports
specific parts of the project rather than the whole technical development, and when the participants
show significant individual contribution and technical understanding. This file is our running log.
It is updated the same day the work happens, never reconstructed afterward.

## Tools

| Tool | Who used it | What it did | What it did not do |
|---|---|---|---|
| Claude Code (Claude Opus 5.5 for most building, Claude Fable 5.1 for planning and review, Anthropic) | Both students, through Vardaan's account | Research and verification of data sources; the planning document; project scaffold; feature extractor; routing client; map screens; route following and cue pipeline; preview, drive, arrived and log screens; PDF export; tests for the student modules; daily code explanations; this file | The four student-owned modules (see below), the briefing content file, the written answers, the video narration |
| ChatGPT Codex (OpenAI) | Partner | Reviews pull requests and reports findings. Findings and what we changed are logged below | Does not write app code |
| Higgsfield | Partner | Video intro, title cards, transitions, and a short animated explainer of the lane-cue idea for the demo video only | No generated footage of the app; every app shot is a real screen recording |

## Student-owned code (written by hand, no AI generation)

| File | Owner | Notes |
|---|---|---|
| Baxi/Core/LanePicker.swift | Vardaan | Claude wrote the types, doc comments, tests and a stub. Vardaan replaces the stub. |
| Baxi/Core/CueScheduler.swift | Vardaan | Same arrangement. (Replaces RouteScorer after the Oct 13 refocus; file lands Oct 14.) |
| Baxi/Core/RoundaboutClassifier.swift | Partner | Same arrangement. |
| Baxi/Core/ApproachHeading.swift | Partner | Same arrangement. |
| Baxi/Resources/Content/briefings.json | Both | Every entry cites the Indiana Driver's Manual by chapter and page. No AI-written driving advice. |

## Log

### 2026-10-12
- Claude Code: critiqued the idea, verified data sources live (Overpass, Valhalla, OSRM, Indianapolis MPO ArcGIS services, NHTSA FARS CSV, Indiana State Form 54706, the Indiana Driver's Manual PDFs, the 2026 CAC rulebook), wrote the planning document and the day-by-day plan.

### 2026-10-13
- Claude Code: re-planned for native iOS; probed Apple Look Around coverage at four Carmel points with a Swift script; counted OSM turn:lanes coverage in Carmel; tested OSRM lane and roundabout output.
- Claude Code: created the Xcode project spec (project.yml), the data build scripts in scripts/, the models, Geo helpers, FeatureExtractor, BundledData, the Home, Plan and Log screens, the four module interfaces with stubs, and the first tests.
- Claude Code (Fable 5.1), evening: refocused the plan on navigation for new drivers (early lane cues, lights-until-turn, roundabout exit and lane, spoken once through the system speech synthesizer) after Vardaan proposed it; cut skill tiers, scoring and generated loops; rewrote the planning document; updated this file and the README. Module split changed: Vardaan owns LanePicker and CueScheduler, partner owns RoundaboutClassifier and ApproachHeading.
- Claude Code (Fable 5.1), evening: renamed the app, Xcode targets, bundle id and GitHub repo from FirstRoads to Baxi after Vardaan chose the name (the taxi passenger who knows the way). No logic changed; tests re-run after the rename.
