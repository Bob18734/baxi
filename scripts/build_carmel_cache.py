#!/usr/bin/env python3
"""Build the bundled Carmel road cache from OpenStreetMap via the Overpass API.

Output: Baxi/Resources/Data/carmel_osm.json
Run:    python3 scripts/build_carmel_cache.py

The app never calls Overpass during the Carmel demo; it reads this file.
Bounding box covers Carmel, IN (south 39.92, west -86.20, north 40.00, east -86.05).
"""
import json, sys, time, urllib.request, urllib.parse, pathlib

BBOX = "39.92,-86.20,40.00,-86.05"
UA = "baxi-cac-2026/0.1 (student project; contact via GitHub)"
OUT = pathlib.Path(__file__).resolve().parents[1] / "Baxi/Resources/Data/carmel_osm.json"

QUERY = f"""
[out:json][timeout:120];
way["junction"="roundabout"]({BBOX})->.rb;
node(w.rb)->.rbn;
way(bn.rbn)["highway"]->.legs;
way["turn:lanes"]({BBOX})->.tl;
way["highway"~"^(motorway_link|trunk_link)$"]({BBOX})->.ramps;
way["highway"~"^(motorway|trunk|primary|secondary|tertiary)$"]["maxspeed"]({BBOX})->.fast;
node["highway"="traffic_signals"]({BBOX})->.sig;
node["highway"="stop"]({BBOX})->.stops;
node["railway"="level_crossing"]({BBOX})->.rail;
(node["amenity"="school"]({BBOX}); way["amenity"="school"]({BBOX}););
out center tags;
(.rb; .legs; .tl; .ramps; .fast;);
out body geom;
(.sig; .stops; .rail;);
out;
"""

KEEP_TAGS = {"highway", "junction", "lanes", "turn:lanes", "turn:lanes:forward", "turn:lanes:backward",
             "lanes:forward", "lanes:backward", "oneway", "maxspeed", "name", "ref", "amenity", "stop", "railway"}

MIRRORS = ["https://overpass-api.de/api/interpreter", "https://lz4.overpass-api.de/api/interpreter",
           "https://z.overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter"]

def fetch():
    # curl instead of urllib: the python.org build on macOS ships without root certificates.
    # GET, not POST: overpass-api.de answered POST with an HTML error page on Oct 13, 2026.
    import subprocess
    last = ""
    for attempt in range(6):
        url = MIRRORS[attempt % len(MIRRORS)]
        t0 = time.time()
        proc = subprocess.run(["curl", "-sS", "-m", "180", "-A", UA, "-G", url,
                               "--data-urlencode", "data=" + QUERY], capture_output=True, text=True)
        try:
            body = json.loads(proc.stdout)
            print(f"overpass ({url}): {len(body['elements'])} elements in {time.time()-t0:.1f}s", file=sys.stderr)
            return body
        except json.JSONDecodeError:
            last = proc.stdout[:300] or proc.stderr[:300]
            print(f"attempt {attempt+1} at {url} failed: {last!r}", file=sys.stderr)
            time.sleep(10)
    sys.exit("overpass failed on every mirror; last response: " + last)

def compact(el):
    tags = {k: v for k, v in el.get("tags", {}).items() if k in KEEP_TAGS}
    out = {"id": el["id"], "type": el["type"], "tags": tags}
    if el["type"] == "node":
        out["lat"] = round(el["lat"], 6); out["lon"] = round(el["lon"], 6)
    else:
        if "nodes" in el:
            out["nodes"] = el["nodes"]
        if "geometry" in el:
            out["geometry"] = [[round(p["lat"], 6), round(p["lon"], 6)] for p in el["geometry"]]
        elif "center" in el:
            out["lat"] = round(el["center"]["lat"], 6); out["lon"] = round(el["center"]["lon"], 6)
    return out

def main():
    body = fetch()
    seen, ways, nodes = {}, [], []
    for el in body["elements"]:
        key = (el["type"], el["id"])
        c = compact(el)
        if key in seen:
            # a later 'out geom' pass may add geometry to an element first seen with 'out center'
            if "geometry" in c: seen[key].update(c)
            continue
        seen[key] = c
        (nodes if el["type"] == "node" else ways).append(c)
    rb = sum(1 for w in ways if w["tags"].get("junction") == "roundabout")
    tl = sum(1 for w in ways if "turn:lanes" in w["tags"])
    print(f"ways={len(ways)} nodes={len(nodes)} roundabout_ways={rb} turn_lanes_ways={tl}", file=sys.stderr)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = {"source": "OpenStreetMap contributors, ODbL, via Overpass API", "bbox": BBOX,
           "fetched": time.strftime("%Y-%m-%d"), "ways": ways, "nodes": nodes}
    OUT.write_text(json.dumps(doc, separators=(",", ":")))
    print(f"wrote {OUT} ({OUT.stat().st_size/1e6:.1f} MB)", file=sys.stderr)

if __name__ == "__main__":
    main()
