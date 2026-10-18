# PANO

Native macOS (SwiftUI, macOS 14+) implementation of the `Ruzname.dc.html` design: main window (Bugün, Haberler, Ekonomi, Maçlar, Spor, Teknoloji, Radyo, Hava Durumu, Defter, Arşiv), menu-bar popover, settings window and app icon.

    ./scripts/build_app.sh        # → build/PANO.app  (release, ad-hoc signed)
    open build/PANO.app

## Live data (all keyless)
- **News** – RSS from 24 sources, toggle any in Settings:
  - Gündem/genel: AA, Cumhuriyet, Hürriyet, NTV, TRT Haber, Sözcü, Habertürk, Oda TV
  - Dünya: BBC Türkçe
  - Ekonomi: Bloomberg HT, Dünya, Ekonomim, Habertürk Ekonomi
  - Spor/Futbol: TRT Spor, Fotomaç, A Spor, Sabah Spor
  - Teknoloji: Webtekno, ShiftDelete.Net, Donanımhaber, Webrazzi, Hürriyet Teknoloji, LOG, CNN Türk Teknoloji
- **Technology** – its own tab (Teknoloji), the same reading experience as Haberler scoped to tech news, drawing on the Teknoloji sources above plus any general source's story that classifies as tech.
- **Economy** – Yahoo Finance chart API. Gram/çeyrek altın and Bitcoin-TL are derived (ons × USD/TRY).
- **Radio** – Turkish stations from the community directory radio-browser.info (TRT, Power, Kral, Metro, NTV Radyo …), streamed with AVPlayer. Favourites, category filter, search, now-playing bar with song titles (ICY metadata), media keys. Some stations are offline or slow; the app retries and then shows an error.
- **Weather** – Open-Meteo, for the city set in Ayarlar › Genel. The Bugün header shows current condition and temperature (tap it to open the detail screen); Hava Durumu adds feels-like, humidity, wind, pressure, UV, sunrise/sunset, a 24-hour strip and a 7-day outlook.
- **Football** – ESPN's public scoreboard API (no key) for scores/fixtures: Süper Lig, Şampiyonlar Ligi, Avrupa Ligi, Premier Lig, LaLiga, Serie A, plus Türkiye's national-team fixtures. Unofficial, so it can change without notice. Football *news* (Fotomaç, A Spor, Sabah Spor, TRT Spor) is separate, via the RSS sources above.

Todos and journal pages are JSON files in `~/Library/Application Support/PANO/`, along with an offline cache.
Petrona and JetBrains Mono (OFL) are bundled in `Resources/Fonts`.

Refresh: news, economy and weather every 1 minute by default; football scores every 15 seconds while Bugün/Futbol is open or a match is live. Both are adjustable in Ayarlar › Yenileme.

Sidebar: drag a tab to reorder it; the order is saved. Ayarlar stays pinned at the bottom and isn't part of the reorder.

Theme: Ayarlar › Genel › Renk teması picks the colour theme (Lacivert, Zümrüt, Bordo, Amber, Mor). Each sets the accent and tints every surface — page, cards, sidebar, rules and text — with its hue, in both light and dark mode. Lacivert is the original Platinum/Charcoal design. The semantic up/down colours stay the same across all five.

Related news: Ekonomi, Futbol and Hava Durumu each show a "… Haberleri" section drawn from the same fetched Haberler pool — Ekonomi/Futbol by category (Ekonomi/Spor), Hava Durumu by a curated weather-phrase match (specific phrases like "hava durumu" / "kar yağışı" rather than bare words, so it doesn't pick up aviation or profit ("kâr") stories), with any story mentioning the selected city surfaced first. No extra source or fetch — it's a client-side filter over `news`.

News window: the last 7 days, grouped under BUGÜN / DÜN / weekday separators. Most feeds only reach back a day or two, so the week is accumulated across refreshes and kept in the cache; WordPress feeds (ShiftDelete, LOG) are paged back through the whole week once per launch.

Kaldığın yer: the newest story seen when you last left Haberler is remembered. Newer stories get a dot, the sidebar shows "N yeni", a banner counts them and a "KALDIĞIN YER" line marks where they end. The popover shows the same count.

Haftanın Özeti (Haberler › Haftanın Özeti): stories per day, the week's topics (names and two-word phrases covered by the most outlets, with their newest headlines), and the category / source mix. Client-side over `news`.

Aynı haberi katlama (Dedup.swift): the same story from several outlets shows as one row (the newest) with a "+N kaynak" chip that expands the others. Headlines match when published within 36 h and sharing most significant words (first five letters, weighted by rarity); each story is compared only with a group's first story, and one outlet's differently-worded stories never fold. Toggle: Ayarlar › Haber kaynakları › Aynı haberleri birleştir. Not applied in Arşiv.

Günün Özeti (Haberler › Günün Özeti): the same topic ranking over today's stories only, plus today's category mix and the latest headlines.

Arşiv: bookmark a story from the detail pane ("Arşive ekle") or a row's context menu. Bookmarks store the whole item in `bookmarks.json`, so they outlive the one-week window.

Keyword alerts: Ayarlar › Haber kaynakları › Anahtar kelime bildirimleri. A new headline containing one of the words sends a notification (up to three, then one summary); clicking it opens the story. Only stories published around or after launch notify, so a backfill never floods.

Style: Ayarlar › Genel › Arayüz stili. **Cam** (default, glassmorphism): the desktop shows through the window, blurred and washed with the colour theme's hue plus three soft light pools; cards, sidebar and popover are frosted panes (material blur, milky tint, light rim, soft shadow). **Klasik**: the original opaque paper surfaces. Both follow the colour theme and light/dark mode.

Maçlar (formerly Futbol) is scores and fixtures; its news section shows football stories only. Spor is the news tab for every branch — Futbol, Basketbol, Voleybol, Tenis, Motor Sporları, Diğer — fed by the general sports desks (Hürriyet, Habertürk, Sözcü, Sabah, A Spor, Fotomaç, TRT Spor) plus single-branch feeds (A Spor Basketbol / Voleybol / Diğer Sporlar, Fotomaç Basketbol / Voleybol / Tenis). A story's branch comes from its feed when the feed covers one branch, otherwise from headline and link keywords; anything naming no other branch counts as football.

Sources: a source added in a new version starts enabled once; after that, switching it off sticks (`Prefs.seenSources`).

Radyo › Yerel: local stations by province. The whole Turkish directory (~800 stations) is fetched the first time Yerel opens and cached in `radio-local.json`; each station is tied to one of the 81 provinces from its directory place field, name or tags (whole-word, Turkish letters folded, plus common district names, e.g. Kadıköy → İstanbul, Bandırma → Balıkesir). The city menu lists only provinces with stations (currently ~44), with counts; it defaults to the weather city when that has stations, else İstanbul.

Bundled local stations: `Resources/local-stations.json`, made by `scripts/fetch_local_stations.py` (default: Manisa, İzmir; pass other province names to add them). It reads Online Radio Box's city pages once, keeps a station only if its own page names that city, adds hand-checked official streams (`EXTRAS`), and keeps only streams that answer with audio to AVPlayer's user agent. The app merges this list into Radyo › Yerel; a bundled station replaces a directory station of the same name. Re-run the script now and then, since local stations change stream addresses.

Canlı TV: Turkish channels from iptv-org's open list of freely available streams (`countries/tr.m3u`), fetched at most once a day and cached in `tv.json`. The player is AppKit's AVPlayerView (full screen, picture-in-picture). "Ulusal" lists the big national channels first. A channel that fails to open is dimmed for the session. Starting a TV channel stops the radio and vice versa. Leaving the tab keeps it playing in a mini player (MiniTVPlayer) that can be dragged and snaps to the nearest corner of the content area (remembered); clicking it returns to the full player. Some channels are Türkiye-only (geo-blocked) or not 24/7, and a few popular ones aren't in the list.

IPTV: the whole iptv-org collection (https://github.com/iptv-org/iptv) — pick a category (`categories/<id>.m3u`, adult excluded) or one of ~250 countries (`countries/<code>.m3u`, country names in Turkish), or ♥ Favoriler. Lists load when picked and are kept for the session; a country list gets category chips. Same player as Canlı TV (`TVPlayerPane`, shared `TVStore`), so the mini player, sleep timer and radio hand-off apply; the mini player returns to whichever TV tab was last open. Favourites store the whole channel (`tv-favorites.json`) so they play without reloading their list.

Şehrim (Bugün): for the weather city's province — duty pharmacies (eczaneler.gen.tr, province or district, opened in the in-app browser; the site blocks scripted access, so the app never fetches it in the background), MHRS, e-Devlet, the municipality, electricity and water outage pages, and emergency numbers (click to copy). Links come from `Resources/city-links.json`, built and checked by `scripts/make_city_links.py`.

Takımım (Bugün): for each followed team (Ayarlar › Maçlar › Takımlarım) — league position, points, the last five results (G/B/M), the next match with a countdown, the last score, a five-row slice of the table and the latest news mentioning the team. ESPN's public API: the team is found in the followed leagues, fixtures and results are gathered from all of them (so European games count toward form), the table comes from its domestic league. Cached for 30 minutes.

Radyo › Çalanlar (RadioSongs.swift): the station's ICY StreamTitle becomes a song when it looks like "A - B" and isn't a slogan/ad/the station's own name. Each song is looked up on the iTunes Search API (no key) for artist, track, 300px cover and an Apple Music link (opened in the Music app via music://, else the browser; an Apple Music search when nothing matched). The now-playing bar shows the cover and a  Music button. History is kept in radio-history.json, newest first, 300 max; the same song on the same station within 3 h isn't added twice.

Akaryakıt (Fuel.swift, Ekonomi): pump prices for every province from Petrol Ofisi's price page (one HTML request, VAT included: V/Max Kurşunsuz 95, Diesel, PO/gaz Otogaz), fetched at most every 30 min with the slow refresh. The card follows the weather city (İstanbul → Avrupa) unless another province is picked. A snapshot per province is stored in fuel-history.json whenever a price changes; the tiles show the latest change and date. With Ayarlar › Akaryakıt › Zam / indirim bildirimi on, a change in the shown province sends a notification (clicking opens Ekonomi).

Yol Durumu (Traffic.swift): Apple Maps (MapKit, no key) — a map with the live traffic layer and the saved routes drawn on it, coloured by congestion. Each route's driving time now is compared with the same drive at 03:00 the next night (free-flowing, cached per day): under 15% slower is Akıcı, under 40% Yoğun, else Çok yoğun; the delay in minutes, distance, main road and a toll flag (MKRoute.hasTolls) are shown. Routes refresh every 5 min while Yol Durumu or Bugün is on screen, one request at a time. Ready-made İzmir and Manisa routes (seeded once for the weather city, also under "Hazır rotalar"); custom routes are looked up with MKLocalSearch near the city; routes.json. Traffic news: stories mentioning trafik/kaza/yol kapandı/otoyol/köprü…, the weather city's first. KGM has no public live road-status or toll data, so neither is included. Bugün shows the first four routes (TrafficGlance).

Takvim (Takvim.swift, Bugün card): public holidays from Nager.Date (free, no key; includes Ramazan/Kurban Bayramı, 2027 dates marked tentative), fetched for this year and next and cached in holidays.json; multi-day bayrams shown as one item; the weekday afternoon before Ramazan/Kurban/Cumhuriyet Bayramı as a half day; well-known days worked out locally (Sevgililer, Kadınlar Günü, Çanakkale, Anneler/Babalar Günü, 10 Kasım, Öğretmenler Günü). Countdown to the next holiday, plus long-weekend hints: the days off around a holiday, and whether one or two days of leave (each adding at least two days off) would join it to a weekend. "Tüm yıl" opens the next twelve months. Optional (Ayarlar › Takvim, off by default): today's events from the Mac's Calendar via EventKit, asking for access when switched on (NSCalendarsFullAccessUsageDescription in Info.plist).

Sabah özeti: one notification each morning at the chosen hour (Ayarlar › Genel › Sabah özeti, 06:00–10:00, default 08:00) — weather with today's range and rain chance, dollar and gram gold, the top three headlines, today's open to-dos, and the followed team's match today/tomorrow (or yesterday's result). Stale data is refreshed first. If PANO wasn't running at that time it's sent when it next runs within four hours. "Şimdi dene" sends one immediately. Clicking it opens Bugün.

Günün özeti: one notification each evening at the chosen time (Ayarlar › Genel › Günün Özeti, any hour and minute, default 19:30) with today's top four topics and a headline for each. Stale news is refreshed first. If PANO wasn't running at that time it's sent when it next runs the same day. "Şimdi dene" sends one immediately. Clicking it opens Haberler › Günün Özeti.

Deprem: AFAD's public event API (keyless; its dates are UTC). Map (circles sized and coloured by magnitude, a pulsing ring for the last hour, the weather city marked) and a list with time, depth and distance to the weather city. Filters: last 24 hours / 7 days (7 days loads M1.5+), minimum magnitude, and "Yakınımdakiler" (300 km). The last 24 hours refresh every 2 minutes whatever tab is open; a new event at or above the alert magnitude within the alert radius (default 4.0+ within 300 km, set from the bell menu) sends a notification, which opens the event on the map. Only events from the last 30 minutes alert, so a launch doesn't replay the day.
