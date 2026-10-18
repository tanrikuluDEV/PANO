#!/usr/bin/env python3
"""Collect local radio stations for chosen provinces and bundle them with the app.

radio-browser.info (the app's live directory) has few Turkish local stations, so for provinces that need more
this script reads Online Radio Box's city pages once, keeps only stations whose stream actually answers with
audio, and writes Resources/local-stations.json. The app merges that file into Radyo › Yerel.

Usage:  ./scripts/fetch_local_stations.py                  # default provinces
        ./scripts/fetch_local_stations.py Manisa İzmir Aydın
Re-run it now and then: local stations change their stream addresses.
"""
import concurrent.futures, html, json, re, sys, urllib.parse, urllib.request
from pathlib import Path

DEFAULT = ["Manisa", "İzmir"]
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) PANO-local-radio/1.0"}
OUT = Path(__file__).resolve().parent.parent / "Resources" / "local-stations.json"
# national networks show up on every city page; they're already in the app's main list
NATIONAL = re.compile(r"\b(joy|fenomen|kral|power|metro fm|virgin|best fm|radyo d\b|number ?one|pal |süper fm|super fm|trt|slow|"
                      r"show radyo|radyo 7|ntv radyo|cnn|habertürk|bloomberg|a haber|radyo viva|alem fm|kafa radyo|açık radyo|lounge)", re.I)


# Stations whose listing is missing or stale, taken from their own websites. Same name as a listed station
# (letters folded) replaces it. "freq" is shown in the app next to the name.
EXTRAS = {
    "Manisa": [
        {"name": "Radyo Tempo", "url": "https://stream.turkiyeradyolari.com:8170/stream", "freq": "90.2"},   # radyotempo.com.tr
        {"name": "Radyo Seçil", "url": "https://live.radyositesihazir.com:8066/;", "freq": "91.0 · Salihli"},  # radyosecil.com.tr
        {"name": "Alaşehir Damar FM", "url": "http://178.32.4.127:8358/;", "freq": "Alaşehir"},   # radio-browser, filed under TM by mistake
    ],
}
# Listing names without Turkish letters, and frequencies worth showing
NAME_FIX = {"Radyo Hiras": ("Radyo Hiraş", "90.8"), "Radyo Soma FM": ("Radyo Soma FM", None), "Bati Radyo": ("Batı Radyo", None),
            "Radyo Izmir FM": ("Radyo İzmir FM", None), "Radyo Trafik Izmir": ("Radyo Trafik İzmir", None),
            "Radyo Remix Odemis": ("Radyo Remix Ödemiş", None), "Çeşme viking radio": ("Çeşme Viking Radio", None)}
PLAYER_UA = {"User-Agent": "AppleCoreMedia/1.0.0 (Macintosh; U; Intel Mac OS X 14_0)"}   # what AVPlayer sends


def fold(name):
    t = name.replace("İ", "i").replace("I", "ı").lower().replace("ı", "i")
    for a, b in zip("çğöşüâî", "cgosuai"):
        t = t.replace(a, b)
    return re.sub(r"[^a-z0-9]", "", t)


def get(url, limit=None, timeout=15, headers=UA):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.headers.get("Content-Type", ""), (r.read(limit) if limit else r.read())


def city_stations(province):
    slug = urllib.parse.quote(province + "-")
    found, page = {}, 0
    while page < 10:
        _, body = get(f"https://onlineradiobox.com/tr/{slug}/" + (f"?p={page}" if page else ""))
        text = body.decode("utf-8", "replace")
        new = 0
        for tag in re.findall(r"<[^>]*\bstream=\"[^\"]+\"[^>]*>", text):
            a = dict(re.findall(r'(\w+)="([^"]*)"', tag))
            sid, name, stream = a.get("radioId"), html.unescape(a.get("radioName", "")).strip(), html.unescape(a.get("stream", ""))
            if not sid or not name or not stream or sid in found:
                continue
            img = a.get("radioImg", "")
            found[sid] = {"id": "orb-" + sid, "name": name, "url": stream,
                          "logo": ("https:" + img) if img.startswith("//") else (img or None), "province": province}
            new += 1
        if new == 0:
            break
        page += 1
    cands = [s for s in found.values() if not NATIONAL.search(s["name"])]
    # city pages also carry promoted stations from elsewhere; keep one only if its own page names this city
    with concurrent.futures.ThreadPoolExecutor(12) as ex:
        return [s for s, here in zip(cands, ex.map(lambda s: in_city(s, slug), cands)) if here]


def in_city(s, slug):
    try:
        _, body = get("https://onlineradiobox.com/tr/" + s["id"].removeprefix("orb-tr.") + "/")
    except Exception:
        return False
    # station pages spell the city their own way ("Izmir-" vs the listing's "İzmir-"), so compare folded
    want = fold(urllib.parse.unquote(slug))
    return any(fold(urllib.parse.unquote(c)) == want for c in re.findall(r'href="/tr/([^"/]+-)/"', body.decode("utf-8", "replace")))


def alive(s):
    """A stream counts as alive if it answers 200 with audio, an HLS/playlist, or an Icecast/Shoutcast body."""
    try:
        ctype, head = get(s["url"], limit=4096, timeout=8, headers=PLAYER_UA)
    except Exception:
        return False
    ctype = ctype.lower()
    return (ctype.startswith("audio/") or "mpegurl" in ctype or "octet-stream" in ctype or "ogg" in ctype
            or head[:7] == b"#EXTM3U" or head[:10].lower().startswith(b"[playlist]") or head[:3] == b"ID3"
            or (len(head) > 1000 and b"<html" not in head[:200].lower()))


def main():
    provinces = sys.argv[1:] or DEFAULT
    existing = json.loads(OUT.read_text()) if OUT.exists() else []
    keep = [s for s in existing if s["province"] not in provinces]
    for p in provinces:
        cands = city_stations(p)
        for s in cands:
            if s["name"] in NAME_FIX:
                s["name"], freq = NAME_FIX[s["name"]]
                if freq: s["freq"] = freq
        extras = [dict(e, id="extra-" + fold(p) + "-" + fold(e["name"]), logo=None, province=p) for e in EXTRAS.get(p, [])]
        replaced = {fold(e["name"]) for e in extras}
        cands = [s for s in cands if fold(s["name"]) not in replaced] + extras
        with concurrent.futures.ThreadPoolExecutor(16) as ex:
            ok = [s for s, good in zip(cands, ex.map(alive, cands)) if good]
        print(f"{p}: {len(cands)} local stations listed, {len(ok)} streaming now")
        keep += sorted(ok, key=lambda s: s["name"].lower())
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(keep, ensure_ascii=False, indent=1))
    print(f"wrote {len(keep)} stations → {OUT}")


if __name__ == "__main__":
    main()
