#!/usr/bin/env python3
"""Build the bundled crash-context layers.

Inputs (data/raw/): hin_2026.geojson, intersection_studies.geojson, fars_2023_hamilton.json
Outputs (Baxi/Resources/Data/): hin_2026.json, intersection_studies.json, fars_2023_hamilton.json

Sources:
  Indianapolis MPO High Injury Network 2026 (public ArcGIS feature service)
  Indianapolis MPO 24 Completed Intersection Safety Studies (public ArcGIS feature service)
  NHTSA FARS 2023 national CSV, filtered to Indiana (STATE=18), Hamilton County (COUNTY=57)
"""
import json, pathlib, shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
RAW, OUT = ROOT / "data/raw", ROOT / "Baxi/Resources/Data"

def num(v):
    try: return float(v) if v not in (None, "") else None
    except (TypeError, ValueError): return None

def hin():
    g = json.load(open(RAW / "hin_2026.geojson"))
    segs = []
    for f in g["features"]:
        p, geom = f["properties"], f["geometry"]
        coords = geom["coordinates"] if geom["type"] == "MultiLineString" else [geom["coordinates"]]
        segs.append({
            "id": p.get("FID"), "route": p.get("ROUTE_NAME"), "jurisdiction": p.get("JURISDICTI"),
            "community": p.get("Community"), "county": p.get("County"),
            "fatalCrashes": num(p.get("Fatal_Cras")), "seriousInjuryCrashes": num(p.get("SSI_Crashe")),
            "ksiPerMile": num(p.get("KSI_per_Mi")),
            "lines": [[[round(c[1], 6), round(c[0], 6)] for c in line] for line in coords],
        })
    json.dump({"source": "Indianapolis MPO High Injury Network 2026", "segments": segs},
              open(OUT / "hin_2026.json", "w"), separators=(",", ":"))
    print("hin segments", len(segs))

def studies():
    g = json.load(open(RAW / "intersection_studies.geojson"))
    pts = []
    for f in g["features"]:
        p = f["properties"]
        pts.append({"id": p.get("FID"), "name": p.get("Name"), "jurisdiction": p.get("Jurisdicti"),
                    "lat": num(p.get("Latitude")), "lon": num(p.get("Longitude")),
                    "aadt": num(p.get("TotalAADT")), "fatal": num(p.get("Fatal")),
                    "incapacitating": num(p.get("INC")), "nonIncapacitating": num(p.get("NonINC")),
                    "propertyDamageOnly": num(p.get("PDO")), "total": num(p.get("Total")),
                    "studyURL": p.get("Link")})
    json.dump({"source": "Indianapolis MPO Intersection Safety Studies", "intersections": pts},
              open(OUT / "intersection_studies.json", "w"), separators=(",", ":"))
    print("study intersections", len(pts))

def fars():
    rows = json.load(open(RAW / "fars_2023_hamilton.json"))
    out = [{"case": r["ST_CASE"], "city": r["CITYNAME"].title(), "lat": float(r["LATITUDE"]), "lon": float(r["LONGITUD"]),
            "road": r["TWAY_ID"], "crossRoad": r["TWAY_ID2"], "intersectionType": r["TYP_INTNAME"],
            "light": r["LGT_CONDNAME"], "month": int(r["MONTH"]), "hour": int(r["HOUR"]), "fatals": int(r["FATALS"])}
           for r in rows]
    json.dump({"source": "NHTSA FARS 2023, Hamilton County IN", "crashes": out},
              open(OUT / "fars_2023_hamilton.json", "w"), separators=(",", ":"))
    print("fars rows", len(out))

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    hin(); studies(); fars()
