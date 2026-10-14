"""Routes the three preset Carmel practice drives through the public OSRM server and saves the raw
responses into the app bundle. The app parses them with the same code it uses for live routes.
Run: python3 scripts/build_preset_routes.py   (uses curl; python.org builds on macOS may lack TLS roots)"""
import json, subprocess, sys, pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "Baxi" / "Resources" / "Routes"
UA = "baxi-cac-2026/0.1"
HOME = (39.9765, -86.1281)  # Carmel City Center

PRESETS = {
    "preset_roundabouts": ("Roundabout loop", [HOME, (39.9594, -86.0605), (39.9547, -86.1180), HOME]),
    "preset_parkway": ("Parkway loop", [HOME, (39.9540, -86.0935), (39.9270, -86.0990), HOME]),
    "preset_highway": ("Highway ramp loop", [HOME, (39.9479, -86.1579), HOME]),
}

def route(points):
    coords = ";".join(f"{lon},{lat}" for lat, lon in points)
    url = (f"https://router.project-osrm.org/route/v1/driving/{coords}"
           "?overview=full&geometries=geojson&steps=true&annotations=false&continue_straight=true")
    out = subprocess.run(["curl", "-sS", "--max-time", "60", "-A", UA, url], capture_output=True, text=True, check=True)
    body = json.loads(out.stdout)
    if body.get("code") != "Ok":
        raise SystemExit(f"OSRM error: {body.get('code')} {body.get('message')}")
    return body

def summary(name, body):
    r = body["routes"][0]
    steps = [s for leg in r["legs"] for s in leg["steps"]]
    kinds = {}
    for s in steps:
        t = s["maneuver"]["type"]; kinds[t] = kinds.get(t, 0) + 1
    lanes = sum(1 for s in steps for i in s["intersections"] if i.get("lanes"))
    print(f"{name}: {r['distance']/1609:.1f} mi, {r['duration']/60:.0f} min, {len(steps)} steps, "
          f"lane-tagged intersections {lanes}, {kinds}")

if __name__ == "__main__":
    only = sys.argv[1:]
    for key, (title, pts) in PRESETS.items():
        if only and key not in only: continue
        body = route(pts)
        body["baxi"] = {"id": key, "name": title, "waypoints": pts}
        (OUT / f"{key}.json").write_text(json.dumps(body, separators=(",", ":")))
        summary(title, body)
