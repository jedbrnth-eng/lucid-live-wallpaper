"""Offline unit tests for build_catalog.py (no network). Run: python3 -m unittest tools/test_build_catalog.py"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_catalog as b  # noqa: E402

PAGE = """<html><h1>Pan video: Test Nebula</h1>
<strong>Credit:</strong><br><div class="credit"><p>ESA/Webb, NASA &amp; CSA, A. Very Long Author List, B. Another Person, C. Third Person, D. Fourth Person, E. Fifth Person, F. Sixth Person, G. Seventh Person with a deliberately long institutional affiliation (Space Telescope Science Institute)</p>
<p>Music: Stellardrone - Twilight</p></div>
<a href="https://cdn.esawebb.org/archives/videos/ultra_hd_h265/x1.mp4">4K</a>
<img src="https://cdn.esawebb.org/archives/videos/videoframe/x1.jpg"></html>"""

GOOD_PROBE = {"codec": "hevc", "width": 3840, "height": 2160, "fps": 25.0, "duration": 30.0}


class CatalogTests(unittest.TestCase):
    def item(self, page=PAGE, probe=GOOD_PROBE):
        with mock.patch.object(b, "fetch", return_value=page), mock.patch.object(b, "probe", return_value=probe), \
                mock.patch.object(b, "head_size", return_value=123):
            return b.dj_item("esawebb", "x1")

    def test_full_credit_never_truncated(self):
        it = self.item()
        self.assertIn("G. Seventh", it["credit"])
        self.assertGreater(len(it["credit"]), 160)
        self.assertIn("Music: Stellardrone", it["creditFull"])  # full block preserved verbatim

    def test_rejects_below_4k(self):
        self.assertIsNone(self.item(probe={**GOOD_PROBE, "width": 1920, "height": 1080}))

    def test_rejects_unplayable_codec(self):
        self.assertIsNone(self.item(probe={**GOOD_PROBE, "codec": "av1"}))

    def test_rejects_talk_episodes(self):
        self.assertIsNone(self.item(page=PAGE.replace("Pan video: Test Nebula", "Hubblecast 99: interview")))

    def test_rejects_portrait_and_dome(self):
        self.assertFalse(b.ok_video({**GOOD_PROBE, "width": 2160, "height": 3840}))
        self.assertFalse(b.ok_video({**GOOD_PROBE, "width": 4096, "height": 4096}))

    def test_license_and_terms_recorded(self):
        it = self.item()
        self.assertEqual(it["license"], "CC BY 4.0")
        self.assertTrue(it["licenseURL"].startswith("https://esawebb.org/"))
        self.assertTrue(it["page"].endswith("/x1/"))

    def test_commons_scenic_filter(self):
        base = {"credit": "A / Wikimedia Commons", "duration": 30}
        rows = [{**base, "title": "Seljalandsfoss waterfall timelapse"}, {**base, "title": "Lecture on chemistry"},
                {**base, "title": "Test Time Lapse of a sunrise"}, {**base, "title": "F-35 memorial flyby over lake"}]
        self.assertEqual([x["title"] for x in b.commons_scenic(rows)], ["Seljalandsfoss waterfall timelapse"])

    def test_commons_caps_series_per_author(self):
        rows = [{"credit": "Same", "duration": 20 + i, "title": f"Beach waves {chr(65 + i)}"} for i in range(10)]
        self.assertEqual(len(b.commons_scenic(rows)), b.COMMONS_PER_AUTHOR)

    def test_nasa_filter_drops_documentaries(self):
        self.assertTrue(b.nasa_wallpaper_title("2016 Mercury Transit in 4K"))
        self.assertFalse(b.nasa_wallpaper_title("ISS@25: Operations"))


if __name__ == "__main__":
    unittest.main()
