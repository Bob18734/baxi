# Demo audit, Oct 25 2026

Every maneuver of the five practice routes and the Home demo, checked against the map rather than against
Baxi's own logic. Re-run any time with the two tools below; both run on the Mac in under a minute.

## How it was checked

- `swift run baxi-audit` takes each maneuver and measures what the route line really does there: the turn
  angle over the 30 m before and after it (left/right/slight/sharp), and for each roundabout, the exits counted
  around the OpenStreetMap ring between where the route enters and leaves (one-way roads into the ring are
  not exits). It prints what Baxi says and the lanes it shows next to that. `ok` = they agree; `NOTE` = a
  driveway leaves the ring before the exit (see "Open").
- `swift run baxi-demo-check [speed]` plays each demo the way the phone does: the replay timer on a real-time
  clock, while each line takes as long as its recording really lasts. It lists any instruction still being
  said when the car reaches its turn (`LATE`), finished less than 15 m before it (`TIGHT`), or never said.

## What was wrong, and the fix

1. **At 4x the voice fell behind the car.** The demo drove four times faster but speech can't. 35
   instructions across the demos were still being said when the car reached the turn. Many finished after
   it, up to 115 m late. On the Home demo the exit off US 31 was announced after the car had taken it.
   **Fix:** while Baxi is talking the replay drives at real speed, then speeds back up
   (`DriveSession.advanceReplay`). The car also waits at the start until "Here we go" has been said.
   **Now:** 0 late at 1x, 4x and 8x.
2. **The last turn of every practice route was never said.** Each one ends with a left into the lot 24 m
   before the pin, and "arrived" fired at 30 m. **Fix:** a replay drives through every turn before it
   arrives. Live drives keep the 30 m, because GPS is 10-20 m off.
3. **Roundabout lanes were picked from the exit number, not from where the exit is.** Exit 1 was always
   "use the right lane", and exit N was judged against a leg count that leaves out driveways. On 96th Street
   (Parkway route) two first exits sit straight ahead, past a driveway on the right, and were "use the right
   lane". Two left exits on the Highway route (third and fourth exits) were "either lane". **Fix:** the lane
   side comes from where the route leaves the circle, measured around it from the entry
   (`LanePicker.side(exitAngle:)`, the same angle the sign's diagram draws). Within 45° of straight ahead
   either lane works and both are lit; the right side asks for the right lane; the left side for the left
   lane. Where the exit sits is what matters for lanes: leaving from the inner lane at an exit on the right
   cuts across the outer lane. So a first exit at 61° (Old Meridian, Highway route) still asks for the right
   lane, even though the road beyond it carries on straight.
4. **Lanes only showed for a moment.** They appeared only once an instruction had been said, and only where
   a lane change was asked for. **Fix:** `DriveSession.upcomingLanes` shows the lanes at the top of the sign
   from 800 m before any maneuver with lane data, with the lane(s) to use lit. Where the map has no lane data,
   nothing is shown rather than a guess. The phone's GPS can't tell which lane the car is in, so no lane is
   ever marked as "you".

5. **Found by the code review of these fixes:**
   - A line the system cuts off (a phone call, Siri) left the speaker "busy" forever. Before, that meant
     silence for the rest of a real drive; with the new pacing it would also have frozen a demo.
   - **Fix:** the speaker now treats an interruption or an unrequested cancel as the end of that line, and
     ignores a second callback for a line already finished.
   - A demo also never waits on the voice for more than 25 s.
   - Muted, the demo still slows for as long as each line would have taken, so the sign keeps the same pace.

The 20 changed spoken lines were recorded with the same Kokoro voice, so the demos stay in the natural voice.
Tests: `BaxiTests/DemoTimingTests.swift`. Each fix was undone on purpose and its test failed.

## Open

- **Driveways on a roundabout.** At four roundabouts a driveway or school road leaves the ring before
  the exit Baxi calls "first". The router doesn't count it, and neither does the line, but a nervous driver
  might. These are 96th Street twice on the Parkway route, the 3rd Avenue SW circle on the Highway route, and
  the Carmel High School trail on the Roundabout loop. The sign already shows the road name ("onto East 96th
  Street"). Saying it too ("take the first exit, onto 96th Street") would remove the doubt, but every
  roundabout line would need re-recording.
- The only real check is riding each route as a passenger with the app running. This audit is
  against OpenStreetMap, which can be out of date.

## The Home demo (Oct 25 afternoon)

The Home demo is now `preset_downtown` from its start, the route the video shows: 193 s at 4x, 18 lines, 0 late,
0 never said at 1x, 2x and 4x; every maneuver `ok` in the audit. (It was the highway loop from 4,400 m.)

## The Drive screen at every Palladium maneuver (Oct 25 afternoon)

`build/screens/palladium/` holds 26 frames (not committed): the Drive screen about 300 ft before each of the 13
maneuvers, day and night, from the Mac copy (`scripts/screens.sh --no-build palladium/<name> --demo-drive
preset_downtown --replay-speed 1 --replay-start <maneuver − 150> --snap-delay 6 --drive-time day|night`). Checked by
eye, every frame: the arrow and the roundabout diagram match the audit's exit and side; the exit number and road name
are right; at the two-lane roundabouts (Guilford/City Center, Range Line/City Center) the left lane is lit amber with
"Move to the left lane", and at the 3rd Avenue circle both lanes are lit; the distance counts down and the bar
empties; the "Then" line shows the next maneuver; the speed-limit sign and the car's speed show; nothing is clipped
at either time of day. Nothing looked wrong.

## Results after the fixes

Demo timing at 4x:
```
== preset_highway from 4400 m (Home demo) at 4.0x: 21 lines, 238 s
== preset_firstdrive at 4.0x: 16 lines, 208 s
== preset_downtown at 4.0x: 18 lines, 193 s
== preset_roundabouts at 4.0x: 31 lines, 523 s
== preset_parkway at 4.0x: 36 lines, 543 s
== preset_highway at 4.0x: 32 lines, 411 s
TOTAL late (finished after the maneuver) 0, never said 0
```

Every maneuver (`swift run baxi-audit`; "sign angle" is where the exit sits around the circle, clockwise from straight ahead):
```

== preset_firstdrive: 15 maneuvers, 3878 m, polyline ends 3878
ok         0 m  depart left  | (nothing)
ok        23 m  turn right angle +110° | turn right, then an immediate right
ok        57 m  turn right angle +89° | (nothing)
ok       193 m  turn left angle -91° | turn left onto 1st Street Southwest
ok      1317 m  turn right angle +90° | turn right onto West Main Street
ok      1787 m  roundabout slightRight sign angle 5° (through), router exit 2, ring exits 2 (roads 2) [4th Avenue Southwest, West Main Street], net turn -28° | at the roundabout, take the second exit
ok      2087 m  turn left angle -89° | turn left onto 1st Avenue Northwest
ok      2184 m  turn right angle +90° | turn right onto 1st Street Northwest
ok      2424 m  turn left angle -90° | turn left onto 1st Avenue Northeast
ok      2916 m  turn left angle -89° | turn left onto North Range Line Road
ok      3670 m  turn right angle +88° | turn right onto West Phelps Way
ok      3784 m  turn right angle +90° | turn right onto Veterans Way, then an immediate right
ok      3834 m  turn right angle +68° | (nothing)
ok      3855 m  turn left angle -49° | turn left
ok      3879 m  arrive left  | Your destination is just ahead

== preset_downtown: 16 maneuvers, 4720 m, polyline ends 4720
ok         0 m  depart left  | (nothing)
ok        23 m  turn right angle +110° | turn right, then an immediate right
ok        57 m  turn right angle +89° | (nothing)
ok       292 m  turn left angle -92° | turn left onto West Main Street
ok       570 m  roundabout slightRight sign angle 356° (through), router exit 2, ring exits 2 (roads 2) [Harlin Boulevard, West Main Street], net turn -30° | at the roundabout, take the second exit
ok      1360 m  roundabout slightRight sign angle 278° (left), router exit 3, ring exits 3 (roads 3) [North Guilford Road, West Main Street, South Guilford Road], net turn -110° | at the roundabout, take the third exit
ok      2523 m  roundabout straight sign angle 284° (left), router exit 3, ring exits 3 (roads 3) [City Center Drive, South Guilford Road, City Center Drive], net turn -110° | at the roundabout, take the third exit. Use the left lane lanes [←↑] ↑→
ok      3514 m  roundabout right sign angle 13° (through), router exit 2, ring exits 2 (roads 2) [3rd Avenue Southwest, City Center Drive], net turn -25° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      3743 m  roundabout straight sign angle 22° (through), router exit 2, ring exits 2 (roads 2) [unnamed, City Center Drive], net turn -17° | at the roundabout, take the second exit
ok      3883 m  roundabout right sign angle 276° (left), router exit 3, ring exits 3 (roads 3) [South Range Line Road, East City Center Drive, South Range Line Road], net turn -111° | at the roundabout, take the third exit. Use the left lane lanes [←↑] ↑→
ok      4128 m  roundabout straight sign angle 15° (through), router exit 2, ring exits 2 (roads 2) [East Walnut Street, South Range Line Road], net turn -23° | at the roundabout, take the second exit
ok      4437 m  roundabout slightRight sign angle 284° (left), router exit 3, ring exits 3 (roads 3) [East Elm Street, South Range Line Road, West Elm Street], net turn -96° | at the roundabout, take the third exit
ok      4588 m  turn right angle +86° | turn right onto Veterans Way
ok      4676 m  turn right angle +68° | turn right, then an immediate left
ok      4697 m  turn left angle -49° | (nothing)
ok      4720 m  arrive left  | Your destination is just ahead

== preset_roundabouts: 28 maneuvers, 17779 m, polyline ends 17779
ok         0 m  depart left  | (nothing)
ok        23 m  turn right angle +110° | turn right, then an immediate left
ok        57 m  turn left angle -90° | (nothing)
ok       145 m  turn left angle -86° | turn left onto West Elm Street
ok       255 m  roundabout slightRight sign angle 99° (right), router exit 1, ring exits 1 (roads 1) [South Range Line Road], net turn +62° | at the roundabout, take the first exit
ok       544 m  roundabout right sign angle 9° (through), router exit 2, ring exits 2 (roads 2) [West Walnut Street, South Range Line Road], net turn -25° | at the roundabout, take the second exit
ok       747 m  roundabout straight sign angle 28° (through), router exit 2, ring exits 2 (roads 2) [City Center Drive, South Range Line Road], net turn -21° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      1573 m  roundabout straight sign angle 16° (through), router exit 2, ring exits 2 (roads 2) [West Executive Drive, South Range Line Road], net turn -29° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      1782 m  roundabout slightRight sign angle 353° (through), router exit 2, ring exits 2 (roads 2) [West Carmel Drive, South Range Line Road], net turn -53° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      2142 m  roundabout slightRight sign angle 7° (through), router exit 2, ring exits 2 (roads 2) [unnamed, South Range Line Road], net turn -25° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      2347 m  roundabout right sign angle 278° (left), router exit 3, ring exits 3 (roads 3) [East 116th Street, Westfield Boulevard, East 116th Street], net turn -108° | at the roundabout, take the third exit. Use the left lane lanes [?] ↑→
ok      3452 m  roundabout straight sign angle 11° (through), router exit 2, ring exits 2 (roads 2) [unnamed, East 116th Street], net turn -6° | at the roundabout, take the second exit. Either lane works lanes [↑] [↑→] →
ok      5590 m  roundabout straight sign angle 13° (through), router exit 2, ring exits 2 (roads 2) [North Gray Road, East 116th Street], net turn -42° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      6896 m  roundabout slightRight sign angle 24° (through), router exit 2, ring exits 2 (roads 2) [Hazel Dell Parkway, East 116th Street], net turn -40° | at the roundabout, take the second exit. Either lane works lanes [?] [↑→]
ok      7622 m  turn left angle -59° | turn left onto River Road
ok     10092 m  turn left angle -90° | turn left onto East 126th Street
ok     11701 m  roundabout slightRight sign angle 108° (right), router exit 1, ring exits 1 (roads 1) [Hazel Dell Parkway], net turn +65° | at the roundabout, take the first exit. Use the right lane lanes ←↑ [↑→]
ok     12488 m  roundabout slightRight sign angle 283° (left), router exit 3, ring exits 3 (roads 3) [East Main Street, Hazel Dell Parkway, East Main Street], net turn -108° | at the roundabout, take the third exit. Use the left lane lanes [←↑] ↑→
ok     14145 m  roundabout slightRight sign angle 14° (through), router exit 2, ring exits 2 (roads 2) [North Gray Road, East Main Street], net turn -30° | at the roundabout, take the second exit
ok     16104 m  roundabout straight sign angle 13° (through), router exit 2, ring exits 2 (roads 2) [unnamed, East Main Street], net turn -5° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑] [↑→]
NOTE   16634 m  roundabout right sign angle 24° (through), router exit 1, ring exits 2 (roads 1) [CHS Trail, East Main Street], net turn -15° — a driveway is counted or not | at the roundabout, take the first exit
ok     16990 m  roundabout right sign angle 24° (through), router exit 2, ring exits 2 (roads 2) [unnamed, East Main Street], net turn -14° | at the roundabout, take the second exit
ok     17275 m  turn left angle -89° | turn left onto 1st Avenue Southeast
ok     17373 m  turn right angle +92° | turn right onto 1st Street Southeast
ok     17599 m  turn left angle -89° | turn left onto Veterans Way
ok     17735 m  turn left angle -111° | turn left, then an immediate left
ok     17756 m  turn left angle -92° | (nothing)
ok     17780 m  arrive left  | Your destination is just ahead

== preset_parkway: 32 maneuvers, 20423 m, polyline ends 20423
ok         0 m  depart left  | (nothing)
ok        23 m  turn right angle +110° | turn right, then an immediate left
ok        57 m  turn left angle -90° | (nothing)
ok       145 m  turn left angle -86° | turn left onto West Elm Street
ok       255 m  roundabout slightRight sign angle 99° (right), router exit 1, ring exits 1 (roads 1) [South Range Line Road], net turn +62° | at the roundabout, take the first exit
ok       544 m  roundabout right sign angle 9° (through), router exit 2, ring exits 2 (roads 2) [West Walnut Street, South Range Line Road], net turn -25° | at the roundabout, take the second exit
ok       747 m  roundabout straight sign angle 28° (through), router exit 2, ring exits 2 (roads 2) [City Center Drive, South Range Line Road], net turn -21° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      1573 m  roundabout straight sign angle 16° (through), router exit 2, ring exits 2 (roads 2) [West Executive Drive, South Range Line Road], net turn -29° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      1782 m  roundabout slightRight sign angle 353° (through), router exit 2, ring exits 2 (roads 2) [West Carmel Drive, South Range Line Road], net turn -53° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      2142 m  roundabout slightRight sign angle 7° (through), router exit 2, ring exits 2 (roads 2) [unnamed, South Range Line Road], net turn -25° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      2347 m  roundabout right sign angle 278° (left), router exit 3, ring exits 3 (roads 3) [East 116th Street, Westfield Boulevard, East 116th Street], net turn -108° | at the roundabout, take the third exit. Use the left lane lanes [?] ↑→
ok      3452 m  roundabout straight sign angle 11° (through), router exit 2, ring exits 2 (roads 2) [unnamed, East 116th Street], net turn -6° | at the roundabout, take the second exit. Either lane works lanes [↑] [↑→] →
ok      5590 m  roundabout straight sign angle 13° (through), router exit 2, ring exits 2 (roads 2) [North Gray Road, East 116th Street], net turn -42° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      6896 m  roundabout slightRight sign angle 101° (right), router exit 1, ring exits 1 (roads 1) [Hazel Dell Parkway], net turn +37° | at the roundabout, take the first exit. Use the right lane lanes · [↑→]
ok      8620 m  roundabout right sign angle 99° (right), router exit 1, ring exits 1 (roads 1) [East 106th Street], net turn +57° | at the roundabout, take the first exit. Use the right lane lanes · · [→]
ok      9784 m  roundabout straight sign angle 268° (left), router exit 3, ring exits 3 (roads 3) [North Gray Road, East 106th Street, North Gray Road], net turn -119° | at the roundabout, take the third exit
ok     11442 m  roundabout right sign angle 108° (right), router exit 1, ring exits 1 (roads 1) [East 96th Street], net turn +55° | at the roundabout, take the first exit. Use the right lane lanes ←↑ [↑→]
NOTE   12339 m  roundabout straight sign angle 22° (through), router exit 1, ring exits 2 (roads 1) [driveway, East 96th Street], net turn -33° — a driveway is counted or not | at the roundabout, take the first exit. Either lane works lanes [←↑] [↑→]
NOTE   12967 m  roundabout slightRight sign angle 28° (through), router exit 1, ring exits 2 (roads 1) [driveway, East 96th Street], net turn -28° — a driveway is counted or not | at the roundabout, take the first exit. Either lane works lanes [←↑] [↑→]
ok     13400 m  roundabout slightRight sign angle 113° (right), router exit 1, ring exits 1 (roads 1) [unnamed], net turn +42° | at the roundabout, take the first exit. Use the right lane lanes ←↑ [↑→]
ok     13767 m  fork slightLeft angle -1° | keep left
ok     13900 m  merge slightLeft  | merge. Match the speed of traffic, then find a gap
ok     17938 m  offRamp slightRight angle +4° | take the exit on the right. Slow down once you're on the ramp lanes · · [↗]
ok     18335 m  roundabout slightRight sign angle 317° (through), router exit 3, ring exits 3 (roads 3) [East 126th Street, unnamed, East City Center Drive], net turn -78° | at the roundabout, take the third exit. Either lane works lanes [↑] [↑]
ok     18910 m  roundabout straight sign angle 33° (through), router exit 2, ring exits 2 (roads 2) [Kinzer Avenue, East City Center Drive], net turn -9° | at the roundabout, take the second exit
ok     19649 m  roundabout straight sign angle 97° (right), router exit 1, ring exits 1 (roads 1) [South Range Line Road], net turn +52° | at the roundabout, take the first exit. Use the right lane lanes ←↑ [↑→]
ok     19831 m  roundabout straight sign angle 15° (through), router exit 2, ring exits 2 (roads 2) [East Walnut Street, South Range Line Road], net turn -23° | at the roundabout, take the second exit
ok     20140 m  roundabout slightRight sign angle 284° (left), router exit 3, ring exits 3 (roads 3) [East Elm Street, South Range Line Road, West Elm Street], net turn -96° | at the roundabout, take the third exit
ok     20291 m  turn right angle +86° | turn right onto Veterans Way
ok     20379 m  turn right angle +68° | turn right, then an immediate left
ok     20400 m  turn left angle -49° | (nothing)
ok     20423 m  arrive left  | Your destination is just ahead

== preset_highway: 29 maneuvers, 12218 m, polyline ends 12218
ok         0 m  depart left  | (nothing)
ok        23 m  turn right angle +110° | turn right, then an immediate left
ok        57 m  turn left angle -90° | (nothing)
ok       145 m  turn right angle +90° | turn right onto West Elm Street
ok       396 m  turn left angle -91° | turn left onto 3rd Avenue Southwest
NOTE     669 m  roundabout right sign angle 21° (through), router exit 1, ring exits 2 (roads 1) [driveway, 3rd Avenue Southwest], net turn -17° — a driveway is counted or not | at the roundabout, take the first exit
ok       928 m  roundabout right sign angle 107° (right), router exit 1, ring exits 1 (roads 1) [City Center Drive], net turn +71° | at the roundabout, take the first exit. Use the right lane lanes ←↑ [↑→]
ok      1856 m  roundabout slightRight sign angle 5° (through), router exit 2, ring exits 2 (roads 2) [South Guilford Road, City Center Drive], net turn -43° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      2258 m  roundabout right sign angle 23° (through), router exit 2, ring exits 2 (roads 2) [West Carmel Drive, City Center Drive], net turn -24° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      2497 m  turn left angle -83° | turn left onto Congressional Boulevard. Use the left lane lanes [←] · ·
ok      3733 m  turn left angle -57° | turn left onto Pennsylvania Street
ok      3959 m  roundabout slightRight sign angle 102° (right), router exit 1, ring exits 1 (roads 1) [East 116th Street], net turn +62° | at the roundabout, take the first exit. Use the right lane lanes ←↑ [↑→]
ok      4119 m  roundabout slightRight sign angle 305° (left), router exit 3, ring exits 3 (roads 3) [unnamed, West 116th Street, unnamed], net turn -68° | at the roundabout, take the third exit. Use the left lane lanes [←↑] ↑→
ok      4972 m  merge slightLeft  | merge. Match the speed of traffic, then find a gap
ok      5194 m  offRamp slightRight angle +5° | take the exit on the right. Slow down once you're on the ramp lanes · · · [↗]
ok      5876 m  roundabout slightRight sign angle 259° (left), router exit 4, ring exits 4 (roads 4) [West 106th Street, unnamed, East 106th Street, unnamed], net turn -104° | at the roundabout, take the fourth exit. Use the left lane lanes [←↑] ↑→
ok      6707 m  merge slightLeft  | merge. Match the speed of traffic, then find a gap
ok      8390 m  offRamp slightRight angle +4° | take the exit on the right. Slow down once you're on the ramp lanes · · · [↗]
ok      8868 m  continueStraight straight angle -2° | (nothing)
ok      9017 m  roundabout right sign angle 12° (through), router exit 2, ring exits 2 (roads 2) [Pennsylvania Street, Old Meridian Street], net turn -40° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      9434 m  roundabout straight sign angle 41° (through), router exit 2, ring exits 2 (roads 2) [West Carmel Drive, Old Meridian Street], net turn -10° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok      9836 m  roundabout straight sign angle 12° (through), router exit 2, ring exits 2 (roads 2) [Grand Boulevard, Old Meridian Street], net turn -37° | at the roundabout, take the second exit. Either lane works lanes [←↑] [↑→]
ok     10442 m  roundabout straight sign angle 61° (right), router exit 1, ring exits 1 (roads 1) [West Main Street], net turn +3° | at the roundabout, take the first exit. Use the right lane lanes ←↑ [↑→]
ok     10835 m  roundabout slightRight sign angle 7° (through), router exit 2, ring exits 2 (roads 2) [South Guilford Road, West Main Street], net turn -40° | at the roundabout, take the second exit
ok     11640 m  roundabout slightRight sign angle 5° (through), router exit 2, ring exits 2 (roads 2) [4th Avenue Southwest, West Main Street], net turn -28° | at the roundabout, take the second exit
ok     11940 m  turn right angle +92° | turn right onto Veterans Way
ok     12174 m  turn left angle -111° | turn left, then an immediate left
ok     12195 m  turn left angle -92° | (nothing)
ok     12219 m  arrive left  | Your destination is just ahead
```
