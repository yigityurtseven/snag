"""Snag extraction bridge.

Turns a post URL (Instagram, TikTok, X) into direct media URLs using
gallery-dl and yt-dlp, without downloading anything. The app downloads the
files itself so that iOS can finish them in the background.

Used two ways:
  * macOS:  python3 snag_bridge.py <url> [--cookies cookies.txt]
  * iOS:    the embedded interpreter imports this module and calls
            extract_json(url, cookies_path)

Output is always a single JSON object:
  {"ok": true, "site": "...", "extractor": "...", "title": ..., "uploader": ...,
   "media": [{"url": ..., "kind": "image"|"video", "ext": ..., "headers": {...}}]}
  {"ok": false, "error": "..."}
"""

import io
import json
import re
import ssl
import sys
import urllib.request
from urllib.parse import unquote, urlparse

SITES = {
    "instagram": ("instagram.com",),
    "tiktok": ("tiktok.com",),
    "x": ("x.com", "twitter.com"),
}

VIDEO_EXTS = {"mp4", "mov", "m4v", "webm"}

# yt-dlp format: one progressive file, preferring H.264 mp4 so it can be
# saved to Photos without remuxing or transcoding.
YTDLP_FORMAT = "b[ext=mp4][vcodec^=avc]/b[ext=mp4][vcodec^=h264]/b[ext=mp4]/b"

USER_AGENT = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36")


def site_of(url):
    host = (urlparse(url).hostname or "").lower()
    for name, domains in SITES.items():
        if any(host == d or host.endswith("." + d) for d in domains):
            return name
    return "other"


def media_entry(url, ext, headers=None, width=None, height=None):
    ext = (ext or "").lower().lstrip(".")
    return {
        "url": url,
        "kind": "video" if ext in VIDEO_EXTS else "image",
        "ext": ext or "bin",
        "headers": headers or {},
        "width": width,
        "height": height,
    }


def guess_ext(url, default):
    path = urlparse(url).path.lower()
    for ext in ("jpg", "jpeg", "png", "webp", "heic", "mp4", "mov"):
        if path.endswith("." + ext) or f".{ext}~" in path or f":{ext}" in path:
            return "jpg" if ext == "jpeg" else ext
    return default


def ssl_context():
    # Embedded Python on iOS has no system CA bundle; certifi ships one.
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


def http_get(url, headers=None):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(request, timeout=20, context=ssl_context()) as response:
        return response.geturl(), response.read()


def best_instagram_image(thumbnails):
    """Instagram lists many renditions; the uncropped one without a size in
    its `stp` parameter is the original upload."""
    def score(thumb):
        match = re.search(r"[?&]stp=([^&]*)", thumb.get("url") or "")
        stp = match.group(1) if match else ""
        cropped = bool(re.match(r"c\d", stp))
        size = re.search(r"_[sp](\d+)x(\d+)", stp)
        area = int(size.group(1)) * int(size.group(2)) if size else float("inf")
        return (not cropped, area)
    return max(thumbnails, key=score)


def via_gallery_dl(url, cookies):
    from gallery_dl import config, job
    from gallery_dl.job import Message

    config.clear()
    if cookies:
        config.set(("extractor",), "cookies", cookies)

    data_job = job.DataJob(url, file=io.StringIO())
    data_job.run()

    media, meta = [], {}
    for msg in data_job.data:
        if not msg:
            continue
        kind = msg[0]
        if kind == Message.Directory and len(msg) > 1 and isinstance(msg[1], dict):
            meta = msg[1]
        elif kind == Message.Url and len(msg) > 2:
            file_url, kw = msg[1], msg[2]
            # "ytdl:" URLs mean gallery-dl wants yt-dlp to handle the video.
            if file_url.startswith("ytdl:"):
                continue
            media.append(media_entry(file_url, kw.get("extension"),
                                     width=kw.get("width"), height=kw.get("height")))
        elif isinstance(msg[-1], dict) and "error" in msg[-1]:
            raise RuntimeError(msg[-1].get("message") or msg[-1]["error"])

    title = meta.get("description") or meta.get("content") or meta.get("title")
    author = meta.get("author") or meta.get("user") or {}
    uploader = (author.get("name") or author.get("nick") or author.get("username")
                if isinstance(author, dict) else author) or meta.get("username")
    return {"title": title, "uploader": uploader, "media": media}


def via_yt_dlp(url, cookies):
    import yt_dlp

    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "format": YTDLP_FORMAT,
        # Photo posts have no video formats; keep going so we can use the images.
        "ignore_no_formats_error": True,
    }
    if cookies:
        opts["cookiefile"] = cookies

    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.sanitize_info(ydl.extract_info(url, download=False))

    media = []
    for entry in info.get("entries") or [info]:
        if not entry:
            continue
        if entry.get("url"):
            headers = dict(entry.get("http_headers") or {})
            if entry.get("cookies"):
                headers["Cookie"] = entry["cookies"]
            media.append(media_entry(entry["url"], entry.get("ext"), headers,
                                     entry.get("width"), entry.get("height")))
        elif entry.get("extractor_key") == "Instagram" and entry.get("thumbnails"):
            # yt-dlp keeps Instagram photos as thumbnails, including the original.
            image = best_instagram_image(entry["thumbnails"])
            media.append(media_entry(image["url"], guess_ext(image["url"], "jpg")))

    return {
        "title": info.get("description") or info.get("title"),
        "uploader": info.get("uploader") or info.get("channel"),
        "media": media,
    }


def tiktok_id(url):
    pattern = r"/(?:video|photo)/(\d+)"
    match = re.search(pattern, url)
    if not match:
        # Short links (vm.tiktok.com/…) redirect to the full URL, sometimes via
        # the login page with the post URL in `redirect_url`.
        final_url, _ = http_get(url)
        match = re.search(pattern, unquote(final_url))
    if not match:
        raise RuntimeError("couldn't find the post ID in this link")
    return match.group(1)


def via_tiktok_embed(url, cookies):
    """TikTok's embed player API. Embeds are watched logged out on other
    websites, so it serves posts the TikTok site hides behind a login wall."""
    post_id = tiktok_id(url)
    _, body = http_get(f"https://www.tiktok.com/player/api/v1/items?item_ids={post_id}",
                       {"Referer": f"https://www.tiktok.com/player/v1/{post_id}"})
    items = json.loads(body).get("items") or []
    if not items:
        raise RuntimeError("the post is private, deleted or can't be embedded")
    item = items[0]

    # The CDN rejects requests without a browser user agent and referer.
    headers = {"User-Agent": USER_AGENT, "Referer": "https://www.tiktok.com/"}
    media = []

    # Photo slideshows.
    for image in (item.get("image_post_info") or {}).get("images") or []:
        urls = (image.get("display_image") or {}).get("url_list") or []
        if urls:
            media.append(media_entry(urls[0], guess_ext(urls[0], "jpg"), headers))

    if not media:
        video = item.get("video_info") or {}
        # Prefer H.264 (saves to Photos as-is), then the highest bitrate.
        profiles = sorted(video.get("profiles") or [],
                          key=lambda p: (p.get("codec_type") == "h264", p.get("bitrate") or 0),
                          reverse=True)
        best = profiles[0].get("play_addr") or {} if profiles else {}
        urls = best.get("url_list") or video.get("url_list") or []
        if urls:
            media.append(media_entry(urls[0], "mp4", headers, best.get("width"), best.get("height")))

    author = item.get("author_info") or {}
    return {
        "title": item.get("desc"),
        "uploader": author.get("nickname") or author.get("unique_id"),
        "media": media,
    }


def extract(url, cookies=None):
    site = site_of(url)
    # Tried in order until one finds media. yt-dlp handles logged-out
    # Instagram (including carousels); gallery-dl mostly needs a login there.
    if site == "tiktok":
        order = [("yt-dlp", via_yt_dlp), ("tiktok-embed", via_tiktok_embed), ("gallery-dl", via_gallery_dl)]
    elif site == "instagram":
        order = [("yt-dlp", via_yt_dlp), ("gallery-dl", via_gallery_dl)]
    else:
        order = [("gallery-dl", via_gallery_dl), ("yt-dlp", via_yt_dlp)]

    errors = []
    for name, fn in order:
        try:
            result = fn(url, cookies)
        except ImportError as exc:
            errors.append(f"{name} is not installed ({exc})")
            continue
        except Exception as exc:  # extractors raise many different types
            errors.append(f"{name}: {exc}")
            continue
        if result["media"]:
            return {"ok": True, "site": site, "extractor": name, **result}
        errors.append(f"{name}: no media found")

    if site == "instagram" and "/stories/" in urlparse(url).path and not cookies:
        return {"ok": False, "site": site,
                "error": "Instagram only shows stories to logged-in users. "
                         "Log in to Instagram in Snag to download them."}
    return {"ok": False, "site": site, "error": "; ".join(errors)}


def extract_json(url, cookies=None):
    return json.dumps(extract(url, cookies), ensure_ascii=False)


def main(argv):
    if not argv:
        print(json.dumps({"ok": False, "error": "usage: snag_bridge.py <url> [--cookies FILE]"}))
        return 2
    cookies = None
    if "--cookies" in argv:
        i = argv.index("--cookies")
        cookies = argv[i + 1] if i + 1 < len(argv) else None
        argv = argv[:i] + argv[i + 2:]
    result = extract(argv[0], cookies)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
