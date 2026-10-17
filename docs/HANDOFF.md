# Latest handoff: Oct 17 Preview context

Synced main through ed867b2; the decision modules and initial crash matching are now implemented upstream.
Built Preview source details, study/FARS card types, lane strips and unverified lane-count labels on
`codex/preview-context`. Eight focused tests were added. Manual briefing content and official PDF form
filling are the next unfinished deliverables. See IMPLEMENTATION-STATUS.md for details.
Validation: 107 active tests pass, three live-network tests skipped; design lint, unsigned iPhone build
and Mac Catalyst build pass. Screenshots are under build/screens/preview*.png. This work was prepared
on codex/preview-context; the GitHub pull request records its merge status.

## Previous handoff: Oct 14 implementation audit

See [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) for the repo-backed feature inventory,
reliability fixes, verification and ordered next steps. Student modules and manual briefings are
still incomplete; `python3 scripts/check-readiness.py` reports these separately from passing logic
tests. The official-form export is also still pending. Codex changes are local and await student review.

## Earlier handoff (Oct 14, 12:15 pm)

Committed and pushed: the full redesign (Baxi/Design, every screen), the Mac screenshot harness,
design lint, DESIGN.md, SHIP-CHECKLIST.md, the DriveSession distance fix, explicit SwiftData saves,
friendly route errors. Tests green, lint clean, iPhone build compiles.

Next, in order:
1. Done: the review came back and its findings are fixed (commit after 0269a1e), plus an
   out-and-back route-following bug it led to.
2. Done: real window captures of the Routes map (`screencapture -l <window id>`; find the id with
   CGWindowListCopyWindowInfo using `.optionAll`, since the window may not count as on screen). Fixed
   the cards filling the panel and the route overview camera. Not yet seen: the refit when switching
   routes by tapping a card (needs a click), and pins stacking on out-and-back roads (roundabout loop
   pins 1-7 sit under 15-21).
3. Done: plan doc's Oct 14 row updated. Now waiting on signing to test on the iPhone.
