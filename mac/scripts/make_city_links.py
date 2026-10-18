#!/usr/bin/env python3
"""Build Resources/city-links.json: per-province links for the Bugün › Şehrim card.

For each of the 81 provinces it checks, and keeps only what answers:
  - eczane:  eczaneler.gen.tr duty-pharmacy pages (province and district slugs, read from the site's sitemap)
  - water:   sukesintisi.com.tr/<il>/        (page must carry a real title; it only covers the bigger cities,
             the app falls back to the site's all-Türkiye list)
  - power:   elektrikkesintiler.com.tr/<il>/
  - belediye: www.<il>.bel.tr or <il>.bel.tr, with a few exceptions. Only DNS is checked: several municipal sites
             don't answer requests from abroad or from scripts, but open fine for people in Türkiye.
The app opens these in its in-app browser. Re-run it now and then: sites move.
"""
import concurrent.futures, json, re, socket, ssl, urllib.parse, urllib.request
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Resources" / "city-links.json"
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"}
PROVINCES = ("Adana Adıyaman Afyonkarahisar Ağrı Aksaray Amasya Ankara Antalya Ardahan Artvin Aydın Balıkesir Bartın Batman Bayburt "
             "Bilecik Bingöl Bitlis Bolu Burdur Bursa Çanakkale Çankırı Çorum Denizli Diyarbakır Düzce Edirne Elazığ Erzincan Erzurum "
             "Eskişehir Gaziantep Giresun Gümüşhane Hakkari Hatay Iğdır Isparta İstanbul İzmir Kahramanmaraş Karabük Karaman Kars "
             "Kastamonu Kayseri Kilis Kırıkkale Kırklareli Kırşehir Kocaeli Konya Kütahya Malatya Manisa Mardin Mersin Muğla Muş "
             "Nevşehir Niğde Ordu Osmaniye Rize Sakarya Samsun Siirt Sinop Sivas Şanlıurfa Şırnak Tekirdağ Tokat Trabzon Tunceli Uşak "
             "Van Yalova Yozgat Zonguldak").split()
BELEDIYE_OVERRIDE = {"İstanbul": "https://www.ibb.istanbul", "Afyonkarahisar": "https://www.afyon.bel.tr"}


def resolves(url):
    try:
        socket.gethostbyname(urllib.parse.urlparse(url).hostname)
        return True
    except OSError:
        return False


def slug(name):
    t = name.replace("İ", "i").replace("I", "ı").lower().replace("ı", "i")
    for a, b in zip("çğöşüâî", "cgosuai"):
        t = t.replace(a, b)
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")


def fetch(url, timeout=15):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout, context=ssl.create_default_context()) as r:
            return r.status, r.read(60000).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception:
        return 0, ""


def titled(url):
    code, body = fetch(url)
    m = re.search(r"<title>\s*([^<]{8,})", body)
    return url if code == 200 and m else None


def province_links(p):
    s = slug(p)
    water = titled(f"https://sukesintisi.com.tr/{s}/")
    power = titled(f"https://elektrikkesintiler.com.tr/{s}/")
    candidates = [BELEDIYE_OVERRIDE[p]] if p in BELEDIYE_OVERRIDE else [f"https://www.{s}.bel.tr", f"https://{s}.bel.tr"]
    bel = next((u for u in candidates if resolves(u)), None)
    return p, {"water": water, "power": power, "belediye": bel}


def main():
    with urllib.request.urlopen(urllib.request.Request("https://www.eczaneler.gen.tr/sitemap.xml", headers=UA), timeout=30) as r:
        full = r.read().decode("utf-8", "replace")
    slugs = set(re.findall(r"https://www\.eczaneler\.gen\.tr/nobetci-([a-z0-9-]+)</loc>", full))
    with concurrent.futures.ThreadPoolExecutor(16) as ex:
        links = dict(ex.map(province_links, PROVINCES))
    out = {}
    for p in PROVINCES:
        s = slug(p)
        districts = sorted(d[len(s) + 1:] for d in slugs if d.startswith(s + "-"))
        out[p] = dict(links[p], eczane=s if s in slugs else None, districts=districts)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    miss = {k: [p for p in PROVINCES if not out[p][k]] for k in ("eczane", "water", "power", "belediye")}
    for k, v in miss.items():
        print(f"{k:9} {81 - len(v)}/81" + (f"  missing: {', '.join(v)}" if v else ""))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
