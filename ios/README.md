# PANO for iPhone

iOS version of the PANO Mac app (`~/Desktop/ajanda/PANO`). The Mac project is not touched: its sources were
copied here and adapted.

## Layout

- `PANO/Shared/` — the Mac app's Swift files (models, services, stores, screens, cards), copied. Small `#if os(macOS)`
  guards and `isPhone` layout tweaks were added; everything else is the Mac code.
- `PANO/iOS/` — iPhone-only code:
  - `Platform.swift` — UIKit stand-ins for the AppKit names the shared code uses (`NSColor`, `NSImage`,
    `NSWorkspace.shared.open`, `NSPasteboard`, `VisualEffect`), so most shared files compile unchanged.
  - `PlatformViews.swift` — iOS versions of the Mac's AppKit-backed views (web view, TV player, video layer,
    Defter's lined editor).
  - `MobileRoot.swift` — animated side menu (every screen in the sidebar order with badges, Ayarlar, "Sırayı düzenle");
    ☰ slides the current screen aside as a rounded, scaled, slightly turned card. The shown screen is `store.screen`,
    so the shared cards' links work as on the Mac. Also the radio mini player, TV mini player and in-app browser.
  - `MobileBugun.swift`, `MobileHaberler.swift`, `MobileAyarlar.swift` — phone layouts.
  - `PANOApp.swift` — entry point; playback audio session for background radio.
- `PANO/Resources/` — fonts and bundled JSON (from the Mac project). `PANO/Assets.xcassets` — app icon, made by
  `scripts/make_icon_ios.sh` (full-bleed version of the Mac icon, drawn with alpha and flattened to opaque —
  drawing straight into an alpha-less bitmap gives a black image).
- `BriefView.swift` — the summaries with every line leading on (story, Hava, Ekonomi, to-dos, match): the morning one
  is Haberler › Sabah Özeti (Liste · Sabah Özeti · Günün Özeti · Haftanın Özeti), the evening one a page opened by its
  notification (it closes as the app moves).
- `Notifications.swift` — notification delegate (banners in front, tap routing), the summaries scheduled ahead with
  calendar triggers (so they arrive with the app closed), and background refresh (BGAppRefreshTask).
- `SplashView.swift` — opening screen: the system launch screen (navy `SplashBackground`, `SplashLogo` tile — see
  `UILaunchScreen` in project.yml) hands over to this view with the same image in the same place, which adds
  the slogan "Gündemin panosu", then scales away (~1.6 s). `scripts/make_splash.swift` makes the logo image set.
- Bugün's sections can be reordered and hidden (button top right; stored in `bugunOrder` / `bugunHidden`).

ESPN (Maçlar, Takımım): the phone uses `site.web.api.espn.com`. The Mac's host, `site.api.espn.com`, answers 403 to
every request from an iPhone (checked on the device); the web host serves the same API. Requests go through
`appSession` (system User-Agent). The Mac project keeps its host — it works there.
- `project.yml` — XcodeGen spec. Run `xcodegen generate` after adding or removing files.

Phone helpers in `Shared/Components.swift`: `isPhone`, `AdaptiveStack` (stacks the Mac's side-by-side columns),
`EdgeInsets.screenHeader`, `.phoneScroll()` (pill rows scroll sideways), `NewsFeedPane` (list + story side by side on the
Mac, list → story page on the phone). Maçlar's detail opens as a sheet; Canlı TV / IPTV / Deprem put the player or map
on top; Defter's calendar folds away.

## Build

```sh
xcodegen generate
xcodebuild -project PANO.xcodeproj -scheme PANO -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/dd build
```

`scripts/shot.sh <Tab> <out.png> [seconds]` installs the simulator build, opens a tab and takes a screenshot.
Command-line-only launch arguments for this: `-startTab Haberler`, `-screenshots YES` (no permission prompt),
`-openFirstNews YES`, `-playFirstStation YES`, `-radioVolume 0`, `-menuOpen YES`, `-showYear YES`, `-editBugun YES`, `-brief evening`, `-newsMode morning`, `-splash YES` (show the splash despite `-screenshots`).

## Installing on an iPhone

`scripts/install_all.sh` builds once (Release, new build number = yyMMddHHmm) and installs that build on both phones
at the same time — iPhone 11 Pro Max and iPhone 17 Pro Max (UDIDs in `scripts/devices.local`, one per line, not in git; or `PANO_DEVICES`), waiting for a locked
phone to be unlocked — then prints each phone's build number. Always use it, so both phones stay on the same build.

Manually: 
Open `PANO.xcodeproj` in Xcode → target PANO → Signing & Capabilities → pick your team, connect the iPhone
(Developer Mode on), choose it as the destination and Run. With a paid developer account the app stays installed
for a year; with a free Apple ID it has to be re-installed every 7 days.

## Status

All 15 screens of the Mac app are in (phase 1: Bugün, Haberler, Ekonomi, Hava Durumu, Radyo; phase 2: Maçlar, Spor,
Teknoloji, Canlı TV, IPTV, Deprem, Yol Durumu, Defter, Arşiv, Ayarlar). Mac-only settings (menu bar, launch at login)
are hidden on the phone.
