# Snag

Save photos and videos from **Instagram, TikTok and X** to your iPhone or Mac.
Share a post to Snag from the share sheet and it lands in your library, ready
to keep in the app or save to Photos, or have it go straight to Photos.

Snag is a native SwiftUI front end for [yt-dlp](https://github.com/yt-dlp/yt-dlp)
and [gallery-dl](https://github.com/mikf/gallery-dl). Everything runs on your
device: no server, no account, no tracking.

> **Status:** early, but working on both platforms. iOS runs yt-dlp and
> gallery-dl in an embedded Python; macOS installs them on first launch.

## How it works

```
Share sheet ──▶ ShareExtension ──▶ app group inbox (Pending/)
                                         │
                       app becomes active ▼
                LinkProcessor ──▶ MediaExtractor ──▶ snag_bridge.py
                                         │            (gallery-dl / yt-dlp)
                       direct media URLs ▼
                DownloadManager (background URLSession) ──▶ Media/ + library.json
                                         │
                                         ▼
                       LibraryView ──▶ Save to Photos / Share
```

- **`snag_bridge.py`** is the only extraction logic. It returns direct media
  URLs as JSON and downloads nothing itself. It tries several methods in order,
  so most public posts work without logging in:
  - **Instagram:** yt-dlp (works logged out, including photo carousels), then gallery-dl.
  - **TikTok:** yt-dlp, then TikTok's embed player API (also serves posts the
    website puts behind a login wall, like age-restricted ones), then gallery-dl.
  - **X:** gallery-dl, then yt-dlp.
- **`MediaExtractor`** runs the bridge: `ProcessExtractor` (macOS, subprocess)
  or `EmbeddedPythonExtractor` (iOS, in-process CPython, since iOS can't spawn
  processes).
- **`DownloadManager`** uses a background `URLSession`, so iOS finishes
  downloads even after you leave the app.
- **`ShareExtension`** only stores the link. Share extensions get very little
  memory and time, so the app does the real work.

## Project layout

| Path | What's there |
|---|---|
| `Snag/` | The multiplatform app (iOS + macOS) |
| `Snag/Engine/` | `snag_bridge.py` and the Swift extractors that run it |
| `Snag/Services/` | Library storage, link processing, downloads, Photos |
| `ShareExtension/` | iOS share extension |
| `SnagWidgets/` | iOS Live Activity (Dynamic Island, Lock Screen) for downloads |
| `Shared/` | Code used by both the app and the extension (app group, inbox) |
| `scripts/` | Engine setup for macOS and iOS |

## Running it

Requires Xcode 26 or later. iOS 26 / macOS 26.

### macOS

Open `Snag.xcodeproj`, pick the **Snag** scheme with **My Mac** as the
destination, and run it. On first launch, click **Install** in the banner. Snag
downloads a self-contained Python
([python-build-standalone](https://github.com/astral-sh/python-build-standalone))
and installs yt-dlp and gallery-dl into
`~/Library/Application Support/Snag/engine/python`. After that it updates them
once a day, and you can update or reinstall from **Snag › Settings**.

Developers can use `scripts/setup-macos-engine.sh` to build the same engine
from their own `python3`.

You can test extraction without the app:

```bash
~/Library/Application\ Support/Snag/engine/python/bin/python3 Snag/Engine/snag_bridge.py "https://x.com/…/status/…"
```

### iOS

iOS apps can't run other programs, so Snag embeds CPython
([BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support))
and calls `snag_bridge.py` in-process through a small C shim
(`Snag/Engine/SnagPython.c`). Fetch Python and the tools once (about 40 MB,
into the git-ignored `Vendor/`):

```bash
scripts/fetch-python-ios.sh
```

Then set your own team and bundle IDs (`com.yigityurtseven.Snag`, the share
extension and the app group `group.com.yigityurtseven.Snag`) under Signing &
Capabilities and run on a device or an iOS 26+ simulator. The **Install Python**
build phase copies the standard library and packages into the app and turns
Python's extension modules into frameworks, as iOS requires.

Snag isn't on the App Store. Install it from Xcode, or with AltStore/SideStore.

## Installing

The App Store doesn't allow apps that download from other services
(guideline 5.2.3), so Snag for iPhone is sideloaded with
[AltStore](https://altstore.io) or [SideStore](https://sidestore.io). They
install it with your own Apple ID and refresh it every 7 days.

1. Set up AltStore or SideStore on your iPhone.
2. Add the Snag source: `https://yigithanyurtseven.com/snag/altstore.json`,
   or download `Snag.ipa` from [Releases](https://github.com/yigityurtseven/Snag/releases)
   and open it in AltStore or SideStore.
3. Install Snag. Requires iOS 26.

The install page is at [yigithanyurtseven.com/snag/install](https://yigithanyurtseven.com/snag/install).

### Making a release

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the Snag target.
2. Run `scripts/build-ipa.sh`. It builds `build/ipa/Snag.ipa` and prints the
   version, build, size and date.
3. Attach `Snag.ipa` to a GitHub release tagged `v<version>`.
4. Add a version entry with those values (newest first) to the website's
   `public/snag/altstore.json`, and deploy the site.

## Roadmap

- [x] Library, background downloads, Save to Photos
- [x] Save to Photos automatically, and remove posts from Snag once they're saved
- [x] iOS share extension
- [x] macOS engine (subprocess)
- [x] iOS engine: embedded CPython
- [x] Log in to Instagram, TikTok and X in a web view and pass cookies to the extractors
- [x] macOS: install and update the engine from inside the app
- [ ] iOS: update yt-dlp and gallery-dl at runtime, without an app update
- [x] Download progress (Live Activity)
- [x] Extract inside the share extension, so downloads start without opening the app
- [ ] macOS share extension
- [ ] Web version (server-side `snag_bridge.py`)

## Legal

Only download content you have the right to save. Snag is a tool; respect the
terms of the platforms you use and the rights of the people who post there.
Snag isn't affiliated with or endorsed by Instagram, TikTok or X.

## License

Snag is free software under the [GNU General Public License, version 2](LICENSE),
the same license as gallery-dl, which it bundles and runs in the same process.
It also bundles [yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense),
[gallery-dl](https://github.com/mikf/gallery-dl) (GPL-2.0-only) and
[CPython](https://github.com/python/cpython) (PSF License).
