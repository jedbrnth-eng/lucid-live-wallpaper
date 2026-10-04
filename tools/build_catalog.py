#!/usr/bin/env python3
"""Build Lucid' curated 4K LIVE-wallpaper catalog.

Sources (all keyless, all license-checked; see SOURCES.md / live-wallpaper-sources.md):
  - ESA/Webb + ESA/Hubble  (CC BY 4.0)        esawebb.org / esahubble.org
  - ESO                    (CC BY 4.0)        eso.org/public/videos
  - NASA SVS               (public domain)    svs.gsfc.nasa.gov/api
  - NASA Image & Video Lib (public domain)    images-api.nasa.gov

Every item is verified by ffprobe over HTTP: video stream >= 3840x2160, H.264/HEVC
(plays natively in AVFoundation), sane duration. Nothing is fully downloaded.

Usage: build_catalog.py [out.json] [--quick]
"""
import concurrent.futures as cf
import html as htmllib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

UA = "Lucid/1.0 (macOS live wallpaper app; +https://github.com/jedbrnth-eng/lucid-live-wallpaper; catalog builder)"
OUT = next((a for a in sys.argv[1:] if not a.startswith("--")),
           os.path.expanduser("~/Library/Application Support/Lucid/catalog.json"))
QUICK = "--quick" in sys.argv
FFPROBE = shutil.which("ffprobe") or "/opt/homebrew/bin/ffprobe"
LOG = []


def log(*a):
    s = " ".join(str(x) for x in a)
    LOG.append(s)
    print(s, flush=True)


def fetch(url, timeout=90, binary=False, method="GET", tries=2):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA}, method=method)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                if method == "HEAD":
                    return r.status, dict(r.headers)
                b = r.read()
                return b if binary else b.decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            last = e
            if getattr(e, "code", None) in (403, 404, 410):
                break
            time.sleep(1.5 * (i + 1))
    raise last


def head_size(url):
    try:
        _, h = fetch(url, timeout=30, method="HEAD")
        return int(h.get("Content-Length") or 0) or None
    except Exception:  # noqa: BLE001
        return None


def probe(url):
    """ffprobe over HTTP -> dict or None. Only reads headers/moov via range requests."""
    try:
        p = subprocess.run([FFPROBE, "-v", "error", "-rw_timeout", "30000000", "-user_agent", UA,
                            "-select_streams", "v:0", "-show_entries",
                            "stream=codec_name,width,height,avg_frame_rate:format=duration",
                            "-of", "json", url], capture_output=True, text=True, timeout=120)
        j = json.loads(p.stdout or "{}")
        st = (j.get("streams") or [{}])[0]
        num, _, den = (st.get("avg_frame_rate") or "0/1").partition("/")
        fps = round(float(num) / float(den or 1), 2) if float(den or 1) else 0
        return {"codec": st.get("codec_name"), "width": int(st.get("width") or 0), "height": int(st.get("height") or 0),
                "fps": fps, "duration": round(float((j.get("format") or {}).get("duration") or 0), 1)}
    except Exception:  # noqa: BLE001
        return None


def ok_video(p, min_d=8, max_d=900):
    return (p and p["codec"] in ("h264", "hevc") and p["width"] >= 3840 and p["height"] >= 2160
            and p["width"] <= 4096 and 1.6 <= p["width"] / p["height"] <= 2.0 and min_d <= p["duration"] <= max_d)


def clean(s):
    s = re.sub(r"<[^>]+>", " ", s or "")
    return re.sub(r"\s+", " ", htmllib.unescape(s)).strip()


GOOD = re.compile(r"\b(pan|panning|zoom|zooming|fly|flying|flight|fly-?through|journey|animation|artist|impression|"
                  r"time-?lapse|timelapse|3d|visuali[sz]ation|exploring|sky|milky way|night|sunset|sunrise|aurora|"
                  r"panorama|galaxy|nebula|cluster|planet|moon|sun|earth|stars?|comet|black hole|supernova|telescope|"
                  r"observatory|alma|paranal|cosmic|universe)\b", re.I)
BAD = re.compile(r"(cast\b|hubblecast|webbcast|esocast|episode|chasing starlight|interview|trailer|q&a|press conference|"
                 r"briefing|behind the scenes|lecture|talk\b|podcast|coverage|broadcast|live\b|replay|panel|remarks|"
                 r"ceremony|webinar|chapter|subtitle|captions|explained|music video|reel\b|update\b|news\b|"
                 r"vertical|portrait|instagram|tiktok|shorts\b|countdown|announcement|teaser|intro\b|outro\b|logo|"
                 r"hyperwall|science on a sphere|fulldome|dome\b|equirectangular|360|vr\b|b-roll|soundbite|graphic)", re.I)


def tag_for(title):
    t = title.lower()
    for k, v in [("waterfall", "Nature"), ("forest", "Nature"), ("river", "Nature"), ("mountain", "Nature"),
                 ("cloud", "Sky"), ("aurora", "Sky"), ("sunset", "Sky"), ("sunrise", "Sky"), ("milky way", "Sky"),
                 ("city", "City"), ("wave", "Ocean"), ("beach", "Ocean"), ("sea", "Ocean"),
                 ("time-lapse", "Time-lapse"), ("timelapse", "Time-lapse"), ("zoom", "Zoom"), ("pan", "Pan"),
                 ("fly", "Fly-through"), ("flight", "Fly-through"), ("journey", "Fly-through"),
                 ("artist", "Animation"), ("animation", "Animation"), ("3d", "3D"), ("earth", "Earth"),
                 ("sun", "Sun"), ("moon", "Moon"), ("ocean", "Earth")]:
        if k in t:
            return v
    return "Space"


# ---------------- djangoplicity sites (ESA/Webb, ESA/Hubble, ESO) ----------------

DJ = {
    "esawebb": {"name": "ESA/Webb", "base": "https://esawebb.org", "videos": "/videos/", "license": "CC BY 4.0",
                "licenseURL": "https://esawebb.org/copyright/",
                "searches": ["pan", "zoom", "fly", "flight", "animation", "artist", "3D", "visualisation"]},
    "esahubble": {"name": "ESA/Hubble", "base": "https://esahubble.org", "videos": "/videos/", "license": "CC BY 4.0",
                  "licenseURL": "https://esahubble.org/copyright/",
                  "searches": ["pan", "zoom", "fly", "flight", "animation", "artist", "3D", "visualisation"]},
    "eso": {"name": "ESO", "base": "https://www.eso.org", "videos": "/public/videos/", "license": "CC BY 4.0",
            "licenseURL": "https://www.eso.org/public/copyright/",
            "searches": ["time-lapse", "timelapse", "pan", "zoom", "fly", "animation", "artist", "night sky",
                         "milky way", "alma", "paranal", "panorama", "aurora", "sunset"]},
}


def dj_ids(key):
    cfg = DJ[key]
    ids = {}
    pages = 1 if QUICK else 3
    for q in cfg["searches"]:
        for page in range(1, pages + 1):
            url = f"{cfg['base']}{cfg['videos']}" + (f"page/{page}/" if page > 1 else "") + "?" + urllib.parse.urlencode({"search": q})
            try:
                h = fetch(url, timeout=40)
            except Exception as e:  # noqa: BLE001
                if page == 1:
                    log(f"  {key} search {q!r} failed: {e}")
                break
            found = re.findall(re.escape(cfg["videos"]) + r"([a-z]+[0-9]+[a-z]?)/", h)
            new = [f for f in found if f not in ids]
            for f in found:
                ids.setdefault(f, q)
            if not new:
                break
    return list(ids)


def dj_item(key, vid):
    cfg = DJ[key]
    page = f"{cfg['base']}{cfg['videos']}{vid}/"
    try:
        h = fetch(page, timeout=40)
    except Exception:  # noqa: BLE001
        return None
    m = re.search(r"<h1[^>]*>(.*?)</h1>", h, re.S)
    title = clean(m.group(1)) if m else vid
    if BAD.search(title) or not GOOD.search(title):
        return None
    cm = re.search(r"Credit:</strong>\s*(?:<br\s*/?>)?\s*<div class=\"credit\">(.*?)</div>", h, re.S)
    credit_lines = [clean(x) for x in re.findall(r"<p[^>]*>(.*?)</p>", cm.group(1), re.S)] if cm else []
    credit = next((c for c in credit_lines if c), cfg["name"])
    credit_full = clean(cm.group(1)) if cm else credit
    links = re.findall(r"https?://[^\"'\s]+?\.(?:mp4|jpg)", h)
    cands = [l.replace("http://", "https://") for l in links if "/ultra_hd_h265/" in l] + \
            [l.replace("http://", "https://") for l in links if "/ultra_hd/" in l]
    cands = list(dict.fromkeys(c for c in cands if c.endswith(".mp4")))
    thumb = next((l.replace("http://", "https://") for l in links if "/videoframe/" in l), None) or \
        next((l.replace("http://", "https://") for l in links if "/thumb" in l and l.endswith(".jpg")), None)
    for url in cands:
        p = probe(url)
        if ok_video(p, max_d=600):
            return {"id": f"{key}:{vid}", "source": key, "collection": cfg["name"], "title": title,
                    "url": url, "thumb": thumb, "page": page, "credit": credit, "creditFull": credit_full,
                    "license": cfg["license"], "licenseURL": cfg["licenseURL"], "tag": tag_for(title),
                    "bytes": head_size(url), **p}
    return None


# ---------------- Wikimedia Commons (Earth & nature; WebM -> app transcodes to HEVC) ----------------

COMMONS_TERMS = ["timelapse", "time-lapse", "waterfall", "clouds", "aerial", "drone", "ocean waves", "sunset", "sunrise",
                 "aurora", "night sky", "milky way", "mountains", "forest", "river", "lake", "snow", "city night",
                 "fog", "storm", "lightning", "beach", "desert", "volcano", "glacier", "long exposure"]
COMMONS_OK_LICENSE = re.compile(r"^(CC0|Public domain|PD|CC BY(-SA)? [0-9.]+)$", re.I)
COMMONS_BAD = re.compile(r"(google|nesdis|noaa|look back|monitor|hubblecast|esocast|webbcast|\bcast\b|navy|army|"
                         r"air force|marine corps|teatro|escuela|school|church|museum|parade|concert|festival|protest|"
                         r"ice mass|sea level|co2|carbon|temperature|anomal|text|ceremony|training|sere\b|"
                         r"map\b|chart|graph|lecture|interview|slides?|screencast|tutorial|animation of|"
                         r"diagram|simulation|subtitles|news|logo|trailer|\bvr\b|360|equirect|fulldome|stereo)", re.I)


COMMONS_SCENIC = re.compile(r"(waterfall|водоспад|cascade|falls\b|aurora|northern lights|sunset|sunrise|milky way|night sky|"
                            r"star trail|eclipse|clouds?\b|nuages|fog|mist|ocean|sea\b|beach|waves?\b|coast|shore|harbou?r|"
                            r"lake|river|stream|creek|glacier|mountain|valley|canyon|forest|woods|snow|winter|desert|dunes?|"
                            r"volcano|lava|lightning|storm|rain\b|timelapse|time-lapse|time lapse|aerial|drone|fpv|skyline|"
                            r"at night|twilight|long exposure|reef|underwater|meadow|grassland)", re.I)
COMMONS_JUNK = re.compile(r"(test\b|isis|strike|military|f-35|a-10|flyby|memorial|ariketa|lecture|sublimation|weaver|"
                          r"acanthodactylus|railway station|team racing|grb|noirlab|host galaxy|horse|unicorn|zero-project|"
                          r"demolition|music video|singing|airport|gorilla|fox in|\b\d{6,}\b|C06\d\d|IMG\d+|video\d+$)", re.I)
COMMONS_PER_AUTHOR = 6


def commons_scenic(rows):
    """Commons is amateur-heavy: keep scenic titles only, drop junk, cap near-duplicate series per author."""
    keep = [x for x in rows if COMMONS_SCENIC.search(x["title"]) and not COMMONS_JUNK.search(x["title"])
            and 8 <= x["duration"] <= 420]
    by = {}
    for x in keep:
        by.setdefault(x["credit"], []).append(x)
    out = []
    for v in by.values():
        out += sorted(v, key=lambda x: -x["duration"])[:COMMONS_PER_AUTHOR]
    return out


def commons_items():
    seen = {}
    terms = COMMONS_TERMS[:3] if QUICK else COMMONS_TERMS
    for term in terms:
        params = {"action": "query", "format": "json", "generator": "search", "gsrnamespace": 6,
                  "gsrsearch": f"{term} filetype:video filew:>3839 fileh:>2159", "gsrlimit": 50, "prop": "imageinfo",
                  "iiprop": "url|size|mime|extmetadata", "iiurlwidth": 640,
                  "iiextmetadatafilter": "LicenseShortName|LicenseUrl|Artist|ObjectName|Credit"}
        try:
            j = None
            for wait in (0, 10, 30, 60):
                time.sleep(wait)
                try:
                    j = json.loads(fetch("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params), timeout=60, tries=1))
                    break
                except Exception as e:  # noqa: BLE001
                    if getattr(e, "code", None) != 429:
                        raise
            if j is None:
                raise RuntimeError("rate-limited (429) after retries")
        except Exception as e:  # noqa: BLE001
            log(f"  commons {term!r} failed: {e}")
            continue
        time.sleep(2)  # be polite; Commons asks for serial, throttled requests
        for pg in (j.get("query", {}).get("pages") or {}).values():
            ii = (pg.get("imageinfo") or [{}])[0]
            w, h, dur = ii.get("width") or 0, ii.get("height") or 0, ii.get("duration") or 0
            meta = ii.get("extmetadata") or {}

            def m(k):
                return clean((meta.get(k) or {}).get("value") or "")
            lic = m("LicenseShortName")
            title = m("ObjectName") or re.sub(r"\.(webm|ogv|mp4)$", "", pg.get("title", "").replace("File:", ""), flags=re.I)
            title = re.sub(r"\s+", " ", title.replace("_", " ")).strip()
            if not (3840 <= w <= 4096 and h >= 2160 and 1.6 <= w / max(h, 1) <= 2.0 and 5 <= dur <= 600):
                continue
            if not COMMONS_OK_LICENSE.match(lic) or COMMONS_BAD.search(title) or ii.get("size", 0) > 1_500_000_000:
                continue
            artist = m("Artist") or "Unknown author"
            if re.search(r"(NOAA|NASA|Google|U\.S\. (Navy|Army|Air Force)|CIRA|ESA|ESO\b)", artist):
                continue  # covered by first-party sources, or institutional news/data footage
            seen.setdefault(pg["pageid"], {
                "id": f"commons:{pg['pageid']}", "source": "commons", "collection": "Wikimedia Commons", "title": title,
                "url": ii["url"], "thumb": ii.get("thumburl"), "page": ii.get("descriptionurl"),
                "credit": f"{artist} / Wikimedia Commons", "creditFull": f"{title} by {artist}, {lic}, via Wikimedia Commons",
                "license": lic, "licenseURL": (meta.get("LicenseUrl") or {}).get("value") or ii.get("descriptionurl"),
                "tag": (lambda t: "Nature" if t == "Space" else t)(tag_for(title)), "codec": "webm", "needsTranscode": True, "width": w, "height": h,
                "fps": 0, "duration": round(dur, 1), "bytes": ii.get("size"), "fileExt": "webm"})
    out = list(seen.values())
    log(f"commons: {len(out)} 4K videos with reusable licences")
    return out


# ---------------- NASA SVS ----------------

SVS_SEARCHES = ["4k", "beauty", "perpetual ocean", "moon", "sun", "earth", "aurora", "black hole", "galaxy",
                "milky way", "solar dynamics observatory", "clouds", "city lights", "hurricane", "jupiter", "saturn"]


def svs_ids():
    ids = {}
    searches = SVS_SEARCHES[:4] if QUICK else SVS_SEARCHES

    def one(q):
        try:
            j = json.loads(fetch("https://svs.gsfc.nasa.gov/api/search/?" + urllib.parse.urlencode({"search": q, "limit": 120}), timeout=150))
            return [(r["id"], r.get("title", ""), r.get("result_type", "")) for r in j.get("results", [])]
        except Exception as e:  # noqa: BLE001
            log(f"  svs search {q!r} failed: {e}")
            return []

    with cf.ThreadPoolExecutor(6) as ex:
        for rows in ex.map(one, searches):
            for i, t, rt in rows:
                if rt in ("Visualization", "Animation") and not BAD.search(t or ""):
                    ids.setdefault(i, t)
    return list(ids.items())


def svs_item(arg):
    sid, _ = arg
    try:
        d = json.loads(fetch(f"https://svs.gsfc.nasa.gov/api/{sid}", timeout=150))
    except Exception:  # noqa: BLE001
        return None
    title = clean(d.get("title"))
    if BAD.search(title):
        return None
    movies = []
    for g in d.get("media_groups") or []:
        for it in g.get("items") or []:
            inst = it.get("instance") or {}
            u, w, h = inst.get("url") or "", inst.get("width") or 0, inst.get("height") or 0
            if inst.get("media_type") == "Movie" and u.lower().endswith(".mp4") and w >= 3840 and h >= 2160 and w <= 4096 \
                    and 1.6 <= w / max(h, 1) <= 2.0:
                movies.append(u)
    for url in movies[:3]:
        p = probe(url)
        if ok_video(p, max_d=900):
            mc = d.get("main_credits") or {}
            credits = [p.get("name") for v in (mc.values() if isinstance(mc, dict) else []) for p in (v or []) if isinstance(p, dict)]
            thumb = (d.get("main_image") or {}).get("url")
            return {"id": f"svs:{sid}", "source": "svs", "collection": "NASA SVS", "title": title, "url": url,
                    "thumb": thumb, "page": d.get("url") or f"https://svs.gsfc.nasa.gov/{sid}/",
                    "credit": "NASA's Scientific Visualization Studio" + (f" ({', '.join(filter(None, credits[:3]))})" if credits else ""),
                    "license": "Public domain (NASA)", "licenseURL": "https://svs.gsfc.nasa.gov/help/",
                    "tag": tag_for(title), "bytes": head_size(url), **p}
    return None


# ---------------- NASA Image & Video Library ----------------

def nasa_lib_items():
    rows = {}
    for q in (["4K"] if QUICK else ["4K", "UHD", "4K animation", "4K timelapse", "4K earth", "4K space"]):
        for page in (1, 2):
            try:
                j = json.loads(fetch("https://images-api.nasa.gov/search?" + urllib.parse.urlencode(
                    {"q": q, "media_type": "video", "page_size": 100, "page": page}), timeout=60))
            except Exception:  # noqa: BLE001
                break
            items = j.get("collection", {}).get("items", [])
            for it in items:
                d = (it.get("data") or [{}])[0]
                nid, title = d.get("nasa_id"), clean(d.get("title"))
                if not nid or BAD.search(title):
                    continue
                prev = next((l.get("href") for l in it.get("links") or [] if l.get("rel") == "preview"), None)
                rows.setdefault(nid, (title, prev, d.get("center")))
            if len(items) < 100:
                break
    return list(rows.items())


NASA_KEEP = re.compile(r"(animation|transit|solar flare|isolated launch|helicopter|drone|aerial|at night|journey)", re.I)
NASA_DROP = re.compile(r"(ISS@25|year \d|inside ksc|101|selfie|prepares|rolls out|arrives|lands|walkout|return|release|"
                       r"test article|engine test|booster test|getting|watching|crystals|letterbox)", re.I)


def nasa_wallpaper_title(title):
    return bool(NASA_KEEP.search(title)) and not NASA_DROP.search(title)


def nasa_lib_item(arg):
    nid, (title, thumb, center) = arg
    if not nasa_wallpaper_title(title):
        return None
    enc = urllib.parse.quote(nid)
    url = f"https://images-assets.nasa.gov/video/{enc}/{enc}~orig.mp4"
    p = probe(url)
    if not ok_video(p, max_d=600):
        return None
    return {"id": f"nasavideo:{nid}", "source": "nasavideo", "collection": "NASA Video", "title": title, "url": url,
            "thumb": thumb, "page": f"https://images.nasa.gov/details/{enc}", "credit": "NASA" + (f" / {center}" if center else ""),
            "license": "Public domain (NASA)", "licenseURL": "https://www.nasa.gov/nasa-brand-center/images-and-media/",
            "tag": tag_for(title), "bytes": head_size(url), **p}


def run(name, args, fn, workers=6):
    out = []
    t0 = time.time()
    with cf.ThreadPoolExecutor(workers) as ex:
        for i, r in enumerate(ex.map(fn, args), 1):
            if r:
                out.append(r)
            if i % 10 == 0:
                log(f"  {name}: {i}/{len(args)} checked, {len(out)} verified ({time.time() - t0:.0f}s)")
    log(f"{name}: {len(out)} verified 4K clips from {len(args)} candidates")
    return out


CK = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".catalog-parts")


def stage(name, make):
    """Run one source, checkpointing its verified items so a crash doesn't lose work."""
    os.makedirs(CK, exist_ok=True)
    f = os.path.join(CK, name + ".json")
    if os.path.exists(f) and "--fresh" not in sys.argv:
        got = json.load(open(f))
        log(f"{name}: reusing {len(got)} checkpointed items")
        return got
    got = make()
    json.dump(got, open(f, "w"))
    return got


def main():
    if not os.path.exists(FFPROBE):
        sys.exit("ffprobe not found (brew install ffmpeg)")
    items = []
    for key in ("esawebb", "esahubble", "eso"):
        def mk(key=key):
            ids = dj_ids(key)
            log(f"{key}: {len(ids)} candidate videos")
            return run(key, ids, lambda v, k=key: dj_item(k, v))
        items += stage(key, mk)

    def mk_lib():
        lib = nasa_lib_items()
        log(f"nasavideo: {len(lib)} candidates")
        return run("nasavideo", lib, nasa_lib_item)
    items += [i for i in stage("nasavideo", mk_lib) if nasa_wallpaper_title(i["title"])]

    items += commons_scenic(stage("commons", commons_items))

    def mk_svs():
        svs = svs_ids()
        log(f"svs: {len(svs)} candidates")
        return run("svs", svs, svs_item, workers=8)
    if "--skip-svs" not in sys.argv:
        items += stage("svs", mk_svs)
    # de-dupe identical URLs/titles
    seen, final = set(), []
    for it in items:
        k = (it["url"], it["title"].lower())
        if it["url"] in seen or k in seen:
            continue
        seen.add(it["url"]); seen.add(k)
        final.append(it)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"version": 1, "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "items": final}, f, indent=1)
    os.replace(tmp, OUT)
    by = {}
    for it in final:
        by[it["collection"]] = by.get(it["collection"], 0) + 1
    log(f"DONE: {len(final)} verified 4K live wallpapers -> {OUT}  {by}")


if __name__ == "__main__":
    main()
