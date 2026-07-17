#!/usr/bin/env python3
"""Live tuning HUD for the patched zathura's paper texture.

    theme/scripts/paper-zathura-hud.py

Sibling of paper-hud.py (which tunes the Hyprland screen shader). This one tunes
the REAL thing: the page-space paper in the patched zathura.

Unlike the screen shader -- which takes no uniforms, so every change rewrites a
.frag and pokes the compositor -- zathura exposes girara settings over D-Bus
(org.pwmt.zathura.ExecuteCommand). So a slider can push a value straight into the
running viewer: drag -> `set recolor-paper-depth 3.2` -> the page re-renders.

Still debounced: each `set` triggers a full page re-render (~100ms), so an
undebounced drag would queue dozens of them.

Which knobs live where:
  - These sliders  -> the PER-PAGE field (cockle depth, marks, pits, scratches),
    generated procedurally in render.c. Runtime, no rebuild.
  - The fine tooth -> baked into paper_tile.h by `paperlab --bake`. Changing that
    needs a rebake + rebuild, so it is NOT here. Tune it in paperlab's own GUI.

"copy zathurarc" puts the current values on the clipboard as `set ...` lines,
ready to paste into ~/.config/zathura/zathurarc to make them permanent.
"""
import os
import subprocess

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Gdk  # noqa: E402

DEBOUNCE_MS = 130

# setting, label, lo, hi, default, step, tooltip
KNOBS = [
    ("recolor-paper", "master strength", 0.0, 1.0, 0.42, 0.01,
     "Scales the WHOLE paper effect (tooth + depth + blemishes). 0 = plain page. "
     "Everything below is multiplied by this."),
    ("recolor-paper-depth", "cockle depth", 0.0, 8.0, 2.0, 0.05,
     "Broad lit undulation -- the sheet reading as a lit OBJECT rather than a flat "
     "tint. The effect the reading research ranks #1 (evidence supports depth over "
     "grain). Isotropic fbm, so no directional streaking."),
    ("recolor-paper-depth-scale", "depth wavelength", 5.0, 120.0, 30.0, 1.0,
     "Size of the depth sweeps, in mm. Real cockle is 16-34mm. Bigger = broader, "
     "lazier undulation."),
    ("recolor-paper-marks", "mark strength", 0.0, 1.0, 0.10, 0.01,
     "Rare large blotches/stains. Each is independently light OR dark."),
    ("recolor-paper-mark-density", "mark count", 0.0, 1.0, 0.15, 0.01,
     "Fraction of mark cells that carry one. Low = rare."),
    ("recolor-paper-mark-scale", "mark spacing", 5.0, 150.0, 40.0, 1.0,
     "Mark cell size in mm -- how far apart marks can be."),
    ("recolor-paper-pits", "pit depth", 0.0, 1.0, 0.35, 0.01,
     "Small dark dents (fibre pull / impressions). Randomised size+depth each."),
    ("recolor-paper-pit-density", "pit count", 0.0, 0.3, 0.015, 0.005,
     "Fraction of pit cells carrying one."),
    ("recolor-paper-pit-scale", "pit spacing", 1.0, 40.0, 9.0, 0.5,
     "Pit cell size in mm."),
    ("recolor-paper-scratches", "scratch strength", 0.0, 1.0, 0.14, 0.01,
     "Sparse scratches. Mostly LIGHT (fibre lift); ~30% read dark (dirt/pressed)."),
    ("recolor-paper-scratch-density", "scratch count", 0.0, 0.2, 0.012, 0.002,
     "Fraction of scratch cells carrying one."),
    ("recolor-paper-scratch-scale", "scratch spacing", 1.0, 20.0, 3.5, 0.25,
     "Scratch cell size in mm."),
]


def zathura_bus():
    """Bus name of the running zathura, or None."""
    try:
        pid = subprocess.check_output(["pgrep", "-x", "zathura"], text=True).split()[0]
        return f"org.pwmt.zathura.PID-{pid}"
    except Exception:
        return None


class Hud(Gtk.Window):
    def __init__(self):
        super().__init__(title="paper: zathura")
        self.set_default_size(430, 700)
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
            label.warn { color:#e0af68; }
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
        self.scales = {}
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
            self.scales[name] = s
            box.pack_start(s, False, False, 0)
            box.pack_start(Gtk.Label(label=""), False, False, 0)

        btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        for text, cb in (("copy zathurarc", self.copy), ("reset", self.reset),
                         ("paper off/on", self.toggle)):
            b = Gtk.Button(label=text)
            b.connect("clicked", cb)
            btns.pack_start(b, True, True, 0)
        outer.pack_start(btns, False, False, 6)

        self.status = Gtk.Label(label="", xalign=0.0)
        outer.pack_start(self.status, False, False, 0)
        self.refresh_status()

        self.connect("destroy", Gtk.main_quit)
        GLib.timeout_add(2000, self.refresh_status)

    # --- plumbing ---------------------------------------------------------
    def send(self, cmd):
        bus = zathura_bus()
        if bus is None:
            return False
        try:
            subprocess.run(
                ["gdbus", "call", "--session", "--dest", bus,
                 "--object-path", "/org/pwmt/zathura",
                 "--method", "org.pwmt.zathura.ExecuteCommand", cmd],
                check=True, capture_output=True, timeout=5)
            return True
        except Exception:
            return False

    def refresh_status(self):
        if zathura_bus():
            self.status.set_text("drag -> zathura re-renders live")
            self.status.get_style_context().remove_class("warn")
        else:
            self.status.set_text("no zathura running -- open one first")
            self.status.get_style_context().add_class("warn")
        return True

    def changed(self, scale, name):
        self.vals[name] = scale.get_value()
        self.value_labels[name].set_text(f"{self.vals[name]:g}")
        # debounce: a drag emits dozens of events; each `set` re-renders the page
        if self.pending:
            GLib.source_remove(self.pending)
        self.pending = GLib.timeout_add(DEBOUNCE_MS, self.apply_one, name)

    def apply_one(self, name):
        self.pending = None
        self.send(f"set {name} {self.vals[name]:g}")
        return False

    # --- buttons ----------------------------------------------------------
    def copy(self, _btn):
        lines = "\n".join(f"set {n} {self.vals[n]:g}" for n, *_ in KNOBS)
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(lines, -1)
        self.status.set_text("zathurarc lines copied to clipboard")

    def reset(self, _btn):
        for name, _, _, _, default, _, _ in KNOBS:
            self.scales[name].set_value(default)
        self.status.set_text("reset to defaults")

    def toggle(self, _btn):
        self.on = not self.on
        self.send(f"set recolor {'true' if self.on else 'false'}")
        self.status.set_text(f"paper {'on' if self.on else 'off'}")


if __name__ == "__main__":
    os.environ.setdefault("GDK_BACKEND", "wayland,x11")
    w = Hud()
    w.show_all()
    Gtk.main()
