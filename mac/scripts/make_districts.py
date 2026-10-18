#!/usr/bin/env python3
"""Build Resources/districts.json: the 81 provinces and their 973 districts, with Turkish spellings, for the Yerel tab.

Source: turkiyeapi.dev (open data). Districts are sorted in Turkish alphabetical order. Re-run if districts change.
"""
import json, locale, urllib.request
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Resources" / "districts.json"
ORDER = "abcçdefgğhıijklmnoöprsştuüvyz"


def key(s):
    t = s.replace("İ", "i").replace("I", "ı").lower()
    return [ORDER.index(c) if c in ORDER else 100 + ord(c) for c in t]


def main():
    req = urllib.request.Request("https://api.turkiyeapi.dev/v1/provinces", headers={"User-Agent": "PANO/1.0"})
    data = json.load(urllib.request.urlopen(req, timeout=30))["data"]
    out = {p["name"]: sorted((d["name"] for d in p["districts"]), key=key) for p in sorted(data, key=lambda p: key(p["name"]))}
    assert len(out) == 81, len(out)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f"{OUT.name}: {len(out)} il, {sum(map(len, out.values()))} ilçe")


if __name__ == "__main__":
    main()
