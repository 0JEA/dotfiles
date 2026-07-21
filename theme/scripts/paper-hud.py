#!/usr/bin/env python3
"""Live tuning HUD for the paper screen shader.

    theme/scripts/paper-hud.py

Hyprland screen shaders take NO custom uniforms, so a slider cannot push a value
into a running shader. The only mechanism is: rewrite the .frag and re-apply it
with `hyprctl keyword decoration:screen_shader`. That is ~100ms, which is fine to
drag against, but it means every change writes a file and pokes the compositor --
hence the debounce below. Without it, a single drag queues dozens of recompiles
and the compositor visibly stutters.

Drag a slider -> shader updates on your real screen, at your real resolution.
"Copy values" puts the current settings on the clipboard, ready to be pasted back
as a variant in toggle-paper-shader.sh (or ported into the zathura tile).
"""
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Gdk  # noqa: E402

SCRIPT = os.path.expanduser("~/dotfiles/theme/scripts/toggle-paper-shader.sh")
DEBOUNCE_MS = 90

# name, label, lo, hi, default, step, tooltip
KNOBS = [
    ("STRENGTH", "strength", 0.0, 3.0, 1.8, 0.05,
     "Master amplitude. Scales every layer. calm=1.0, bold=2.2, worn=1.8"),
    ("SCRATCH_THRESH", "scratch density", 0.60, 0.999, 0.85, 0.005,
     "BASELINE scratch probability, INVERTED: 0.985 = 1.5% of cells = ~3 scratches "
     "on the whole screen (the old default, why they looked missing). "
     "Lower = more scratches."),
    ("SCRATCH_GAIN", "scratch depth", 0.0, 4.0, 1.8, 0.05,
     "How dark/deep each scratch cuts."),
    ("FOLD_GAIN", "fold depth", 0.0, 5.0, 2.4, 0.05,
     "Page-scale crease depth. Folds are cm-scale: the only layer paper's own "
     "0.33mm optical blur does not touch."),
    ("FOLD_COUNT", "fold count", 0.0, 8.0, 8.0, 1.0,
     "Number of crease centres (max 8 -- the GLSL loop is bounded)."),
    ("ROUGH_GAIN", "roughness", 0.0, 3.0, 1.0, 0.05,
     "Pixel-scale grain. MEASURED as the dominant layer: sd 1.17% of a 1.15% total."),
    ("FIBER_GAIN", "fibre", 0.0, 3.0, 1.0, 0.05,
     "|grad fbm| filaments. Paper physics says this should matter least -- the "
     "bulk MTF at fibre scale is 0.055."),
    ("AO_GAIN", "crease shadow", 0.0, 3.0, 1.0, 0.05,
     "Ambient occlusion in the fold valleys."),
    ("FADE_AMT", "patchiness", 0.0, 1.0, 0.70, 0.01,
     "Non-stationarity: how unevenly distressed the sheet is. The shader's own "
     "comment calls a stationary result 'the single biggest this-is-procedural "
     "tell'. Feeds an 8*x^3 curve -- above ~0.72 it saturates and switches folds "
     "and scratches OFF."),
    ("RELIEF_Z", "relief flatness", 0.3, 6.0, 1.8, 0.05,
     "Normal's z. LOWER = more dramatic relief. Not strength-scaled."),
    ("SEED", "seed", 0.0, 40.0, 3.0, 1.0,
     "Reroll the pattern: different folds, different scratches."),
]
# the script's env var names differ for two of them
ENV = {"RELIEF_Z": "PAPER_RELIEF_Z_VAL", "SEED": "PAPER_SEED_VAL"}


class Hud(Gtk.Window):
    def __init__(self):
        super().__init__(title="paper")
        self.set_default_size(430, 640)
        self.set_keep_above(True)
        self.vals = {k: d for k, _, _, _, d, _, _ in KNOBS}
        self.pending = None
        self.on = True

        css = Gtk.CssProvider()
        css.load_from_data(b"""
            window, box { background:#1a1b26; }
            label { color:#c0caf5; font-family:"JetBrainsMono Nerd Font",monospace;
                    font-size:11px; }
            label.hdr { color:#7aa2f7; font-weight:bold; }
            label.val { color:#9ece6a; }
            scale trough { background:#292e42; min-height:5px; }
            scale highlight { background:#7aa2f7; }
            scale slider { background:#c0caf5; min-width:14px; min-height:14px; }
            button { background:#292e42; color:#c0caf5; border:1px solid #414868;
                     font-family:"JetBrainsMono Nerd Font",monospace; font-size:11px; }
            button:hover { background:#414868; }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        outer.set_border_width(10)
        self.add(outer)

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_vexpand(True)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        sw.add(box)
        outer.pack_start(sw, True, True, 0)

        self.value_labels = {}
        for name, label, lo, hi, default, step, tip in KNOBS:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
            l = Gtk.Label(label=label, xalign=0.0)
            l.get_style_context().add_class("hdr")
            row.pack_start(l, True, True, 0)
            v = Gtk.Label(label=f"{default:g}", xalign=1.0)
            v.get_style_context().add_class("val")
            self.value_labels[name] = v
            row.pack_end(v, False, False, 0)
            box.pack_start(row, False, False, 0)

            adj = Gtk.Adjustment(value=default, lower=lo, upper=hi,
                                 step_increment=step, page_increment=step * 4)
            s = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
            s.set_draw_value(False)
            s.set_tooltip_text(tip)
            s.connect("value-changed", self.changed, name)
            box.pack_start(s, False, False, 0)
            box.pack_start(Gtk.Label(label=""), False, False, 0)

        btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        for text, cb in (("copy values", self.copy), ("reset", self.reset),
                         ("toggle off/on", self.toggle)):
            b = Gtk.Button(label=text)
            b.connect("clicked", cb)
            btns.pack_start(b, True, True, 0)
        outer.pack_start(btns, False, False, 6)

        self.status = Gtk.Label(label="dragging re-applies the shader live", xalign=0.0)
        outer.pack_start(self.status, False, False, 0)

        self.connect("destroy", Gtk.main_quit)
        self.apply()

    def changed(self, scale, name):
        self.vals[name] = scale.get_value()
        self.value_labels[name].set_text(f"{self.vals[name]:g}")
        # debounce: a drag emits dozens of events; each apply writes a file and
        # pokes the compositor, so firing them all makes Hyprland stutter
        if self.pending:
            GLib.source_remove(self.pending)
        self.pending = GLib.timeout_add(DEBOUNCE_MS, self.apply)

    def env(self):
        e = dict(os.environ)
        for k, v in self.vals.items():
            e[ENV.get(k, f"PAPER_{k}")] = f"{v:.4f}"
        e["PAPER_FORCE_ON"] = "1"      # never toggle OFF on re-apply
        return e

    def apply(self):
        self.pending = None
        try:
            r = subprocess.run([SCRIPT, "live"], env=self.env(), timeout=10,
                               capture_output=True, text=True)
            if r.returncode != 0:
                self.status.set_text(f"error: {r.stderr.strip()[:60]}")
            else:
                self.on = True
                self.status.set_text("live")
        except Exception as exc:                       # noqa: BLE001
            self.status.set_text(f"error: {exc}")
        return False

    def copy(self, _btn):
        var = "    myvariant)  " + "; ".join(
            f"{k}={v:g}" for k, v in self.vals.items()) + " ;;"
        env = " ".join(f"{ENV.get(k, f'PAPER_{k}')}={v:g}" for k, v in self.vals.items())
        text = f"# paste into toggle-paper-shader.sh:\n{var}\n\n# or run directly:\n{env} {SCRIPT} live\n"
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
        self.status.set_text("values copied to clipboard")

    def reset(self, _btn):
        for name, _, _, _, default, _, _ in KNOBS:
            self.vals[name] = default
        self.status.set_text("reset — reopen to move the sliders back")
        self.apply()

    def toggle(self, _btn):
        if self.on:
            subprocess.run(["hyprctl", "keyword", "decoration:screen_shader",
                            "[[EMPTY]]"], capture_output=True)
            self.on = False
            self.status.set_text("off")
        else:
            self.apply()


if __name__ == "__main__":
    if not os.path.exists(SCRIPT):
        sys.exit(f"missing {SCRIPT}")
    w = Hud()
    w.show_all()
    Gtk.main()
