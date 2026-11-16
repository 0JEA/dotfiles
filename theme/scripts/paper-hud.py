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
import json
import os
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Gdk  # noqa: E402

SCRIPT = os.path.expanduser("~/dotfiles/theme/scripts/toggle-paper-shader.sh")
DEBOUNCE_MS = 90

# name, label, lo, hi, default, step, tooltip
KNOBS = [
    ("STRENGTH", "strength", 0.0, 1.5, 0.45, 0.01,
     "recolor-paper. Master amplitude of the PDF look; 0.45 is zathurarc's."),
    ("TOOTH", "tooth", 0.0, 3.0, 1.0, 0.05,
     "Fine formation grain, as paperlab bakes it into zathura's tile. 1 = as baked."),
    ("DEPTH", "cockle depth", 0.0, 2.0, 0.275, 0.005,
     "recolor-paper-depth: the broad lit undulation."),
    ("DEPTH_SCALE", "cockle size (mm)", 2.0, 80.0, 14.5, 0.5,
     "recolor-paper-depth-scale: cockle wavelength."),
    ("MARKS", "marks", 0.0, 1.0, 0.28, 0.01,
     "recolor-paper-marks: rare large light/dark blotches."),
    ("MARK_DENSITY", "mark density", 0.0, 1.0, 0.15, 0.01,
     "Fraction of mark cells that carry one."),
    ("PITS", "pits", 0.0, 1.5, 0.545, 0.01,
     "recolor-paper-pits: small dark dents."),
    ("PIT_DENSITY", "pit density", 0.0, 0.2, 0.015, 0.001,
     "Fraction of pit cells that carry one."),
    ("SCRATCHES", "scratches", 0.0, 1.0, 0.344, 0.01,
     "recolor-paper-scratches: sparse thin lines, mostly light."),
    ("SCRATCH_DENSITY", "scratch density", 0.0, 0.3, 0.036, 0.001,
     "Fraction of scratch cells that carry one."),
    ("SEED", "seed", 0.0, 40.0, 1.0, 1.0,
     "Reroll the cockle and blemishes (zathura uses page index + 1)."),
]
# every knob's env var is PAPER_<name>
ENV = {}

# Palette. matugen generates ~/.config/theme/colors.json from theme/matugen/
# config.toml, so reading it here means this HUD follows a palette switch instead
# of staying pinned to whichever palette was current when it was written.
# This is a live HUD: any failure (no file, bad JSON, missing key) falls back
# per-key to the Marigold values below, so it never crashes and never renders
# unstyled.
PALETTE = Path("~/.config/theme/colors.json").expanduser()
FALLBACK = {
    "bg": "#1a1614",
    "bg_hl": "#2b2320",
    "fg": "#f5e6d3",
    "blue": "#ff8c42",
    "green": "#a3b565",
    "bright_black": "#75665a",
}


def load_palette():
    colors = dict(FALLBACK)
    try:
        with open(PALETTE) as fh:
            data = json.load(fh)
        for key in FALLBACK:
            val = data.get(key)
            if isinstance(val, str) and val.strip():
                colors[key] = val.strip()
    except Exception:                                  # noqa: BLE001
        pass
    return colors


C = load_palette()


class Hud(Gtk.Window):
    def __init__(self):
        super().__init__(title="paper")
        self.set_default_size(430, 640)
        self.set_keep_above(True)
        self.vals = {k: d for k, _, _, _, d, _, _ in KNOBS}
        self.pending = None
        self.on = True

        css = Gtk.CssProvider()
        css.load_from_data(("""
            window, box { background:%(bg)s; }
            label { color:%(fg)s; font-family:"JetBrainsMono Nerd Font",monospace;
                    font-size:11px; }
            label.hdr { color:%(blue)s; font-weight:bold; }
            label.val { color:%(green)s; }
            scale trough { background:%(bg_hl)s; min-height:5px; }
            scale highlight { background:%(blue)s; }
            scale slider { background:%(fg)s; min-width:14px; min-height:14px; }
            button { background:%(bg_hl)s; color:%(fg)s; border:1px solid %(bright_black)s;
                     font-family:"JetBrainsMono Nerd Font",monospace; font-size:11px; }
            button:hover { background:%(bright_black)s; }
        """ % C).encode())
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
