// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// JavaScript injected into Wallpaper Engine web wallpapers so common pages run in Lucid's WebKit window.
// Implements the documented API surface (https://docs.wallpaperengine.io/en/web/audio/visualizer.html and
// .../web/api/propertylistener.html): wallpaperRegisterAudioListener gets 128 floats (64 left, 64 right) ~30×/s,
// wallpaperPropertyListener.applyUserProperties gets the project's default property values on load.
// Written from the public docs; no Wallpaper Engine code is used.
import Foundation

enum WEShim {
    static func bootstrapScript(userPropertiesJSON: String?) -> String {
        var props = "{}"
        if let s = userPropertiesJSON, let d = s.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] != nil {
            props = s.replacingOccurrences(of: "</", with: "<\\/")
        }
        return """
        (function(){
          if (window.__lucidShim) return; window.__lucidShim = true;
          var audioListeners = [];
          window.wallpaperRegisterAudioListener = function(cb){ if (typeof cb === 'function') audioListeners.push(cb); };
          window.__lucidAudio = function(a){ for (var i = 0; i < audioListeners.length; i++) { try { audioListeners[i](a); } catch (e) {} } };
          var noop = function(){};
          ['wallpaperRegisterMediaStatusListener','wallpaperRegisterMediaPropertiesListener','wallpaperRegisterMediaThumbnailListener',
           'wallpaperRegisterMediaPlaybackListener','wallpaperRegisterMediaTimelineListener','wallpaperRequestRandomFileForProperty']
            .forEach(function(n){ if (!window[n]) window[n] = noop; });
          window.wallpaperPropertyListener = window.wallpaperPropertyListener || {};
          var props = \(props);
          function L(){ return window.wallpaperPropertyListener || {}; }
          window.__lucidApplyProperties = function(){
            try { if (L().applyGeneralProperties) L().applyGeneralProperties({ fps: 30 }); } catch (e) {}
            try { if (L().applyUserProperties) L().applyUserProperties(props); } catch (e) {}
          };
          window.__lucidSetPaused = function(p){ try { if (L().setPaused) L().setPaused(!!p); } catch (e) {} };
          // Wallpapers stay silent: mute page media so it never plays sound or feeds back into the analyser.
          try { var play = HTMLMediaElement.prototype.play;
                HTMLMediaElement.prototype.play = function(){ this.muted = true; return play.apply(this, arguments); }; } catch (e) {}
          function muteAll(){ try { document.querySelectorAll('audio,video').forEach(function(m){ m.muted = true; }); } catch (e) {} }
          document.addEventListener('DOMContentLoaded', function(){
            muteAll(); try { new MutationObserver(muteAll).observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}
          });
          window.addEventListener('load', function(){ window.__lucidApplyProperties(); });
        })();
        """
    }

    /// JS call that delivers one audio frame: exactly 128 numbers in 0...1 with 3 decimals.
    static func audioCall(_ a: [Float]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(128)
        for i in 0..<128 {
            let v = i < a.count && a[i].isFinite ? min(1, max(0, a[i])) : 0
            parts.append(String(Double((v * 1000).rounded()) / 1000))
        }
        return "window.__lucidAudio&&window.__lucidAudio([" + parts.joined(separator: ",") + "])"
    }
}
