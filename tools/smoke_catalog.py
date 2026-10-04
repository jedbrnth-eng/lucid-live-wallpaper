import json, time, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_catalog as b

def t(label, fn):
    t0 = time.time()
    try:
        r = fn()
    except Exception as e:  # noqa: BLE001
        r = f"ERROR {e}"
    print(label, round(time.time() - t0, 1), "s ->", json.dumps(r)[:420], flush=True)

t("webb", lambda: b.dj_item("esawebb", "potm2609a"))
t("hubble", lambda: b.dj_item("esahubble", "potm2609b"))
t("eso", lambda: b.dj_item("eso", "eso2402a"))
t("nasa", lambda: b.nasa_lib_item(("GSFC_20160601_Mercury_m12268_Transit_4K", ("Mercury Transit 4K", None, "GSFC"))))
t("svs", lambda: b.svs_item((5529, "")))
b.QUICK = True
t("webb ids", lambda: (lambda x: [len(x), x[:10]])(b.dj_ids("esawebb")))
