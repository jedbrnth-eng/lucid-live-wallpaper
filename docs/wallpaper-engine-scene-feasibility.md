# Can Lucid render Wallpaper Engine *scenes* on a Mac?

Status: feasibility note only. Nothing in this pass renders scenes. Written 2026-10-26.

## What a scene is

A Wallpaper Engine scene is a `scene.pkg` archive (with `project.json` saying `"type": "scene"`). Inside are a `scene.json` graph, textures in Wallpaper Engine's own `.tex` format, models, materials, particle systems, image effects, puppet/skeletal animation, and optional SceneScript (a JavaScript dialect). Wallpaper Engine's Windows renderer draws all of this with DirectX, and many items also depend on the shared `assets` folder that ships with Wallpaper Engine itself.

So a scene is a small game scene for a proprietary engine, not a media file. AVFoundation or WebKit can't play it.

## Prior art (read only, nothing copied)

| Project | Licence | Approach | Notes |
|---|---|---|---|
| [Almamu/linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) | GPL-3.0 (per GitHub API, checked 2026-10-26) | C++, OpenGL 3.3, GLFW/GLEW/SDL2, FFmpeg, MPV, PulseAudio, FFTW, X11 or Wayland | About 4.7k stars, pushed 2026-08. Its README says you must own Wallpaper Engine and supply its `assets` folder, and to "expect some limitations and quirks". |
| [wqLouis/linux-wallpaperengine](https://github.com/wqLouis/linux-wallpaperengine) | GPL-3.0 | Rust, Vulkan and Metal, claims Mac support | Very new and small (16 stars). Not assessed further. |

## Licence check

- Lucid is GPL-3.0-only. GPL-3.0 code (either "only" or "or later") can be combined with it, so studying or reusing linux-wallpaperengine is allowed, as long as we keep its copyright notices, credit it and publish the full source. It is credited in the README.
- Wallpaper Engine's `assets` folder and Workshop items are **not** free software. They can never go in the repo or the app bundle. Any scene support would have to read them from the user's own copy, like the importer already does.

## Options

1. **Port linux-wallpaperengine as a separate helper process.** macOS still ships OpenGL 4.1 (deprecated since 10.14), which covers the 3.3 it needs. The work: replace its X11/Wayland output with a desktop-level `NSWindow` + `CAOpenGLLayer` (or render offscreen and hand frames to Lucid), replace PulseAudio with Lucid's analyser, and build its dependencies on macOS. A separate GPL binary keeps crashes out of Lucid. **Estimate: about 1 to 2 weeks to a rough first render, unknown time to good fidelity.** Risk: Apple can remove OpenGL, and fidelity is only as good as upstream's.
2. **Write a Metal scene renderer.** It would be the cleanest result, but it means re-implementing the `.tex` decoder, the scene graph, the material/shader translation (Wallpaper Engine's HLSL-style shaders to Metal), particles and effects. **Months**, not a feature.
3. **Adopt the Rust/Metal project.** Too immature to judge today; worth re-checking in six months.

## What it needs from Jed

- A few real scene samples and the Wallpaper Engine `assets` folder, copied from his own Windows install. This Mac has Steam and Wallpaper Engine in the library, but no Workshop content (`~/Library/Application Support/Steam/steamapps/workshop/content/431960` does not exist), and the Windows app can't install here.
- A decision on whether a GPL helper binary bundled inside Lucid is acceptable. The licence allows it; it adds size and a second build system (CMake).

## Recommendation

Don't build it into Lucid now. If scenes matter, do a **2–3 day spike** on option 1: build linux-wallpaperengine on macOS, render 5 of Jed's scenes into a test window, and measure what renders correctly, plus CPU, GPU and battery use. Go or no-go after that. Until then Lucid lists scenes as *Unsupported on Mac*. It can show the scene's animated preview as a clearly labelled stand-in, if the user turns that on.

## Not verified here

Upstream build success on macOS, which features it renders correctly, and how well it performs. All of it is from its README and repo metadata, not from running it.
