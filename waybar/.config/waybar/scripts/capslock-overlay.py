#!/usr/bin/env python3
"""
Caps lock indicator: a 3px red strip at the very top of the screen.
Slides in when caps lock is on, slides out when off.
Uses gtk-layer-shell so it floats above everything at y=0.
"""

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, GtkLayerShell, GLib

CAPS_LED  = "/sys/class/leds/input3::capslock/brightness"
HEIGHT    = 3      # px
COLOR_ON  = "#f7768e"  # Tokyo Night red
POLL_MS   = 300

CSS = f"""
window {{
  background-color: transparent;
  transition: background-color 300ms ease;
}}
window.caps-active {{
  background-color: {COLOR_ON};
}}
""".encode()


def read_caps() -> bool:
    try:
        with open(CAPS_LED) as f:
            return f.read().strip() == "1"
    except OSError:
        return False


def poll(window: Gtk.Window) -> bool:
    active = read_caps()
    ctx = window.get_style_context()
    if active:
        ctx.add_class("caps-active")
    else:
        ctx.remove_class("caps-active")
    return True  # keep polling


def build_window() -> Gtk.Window:
    win = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)

    # Layer shell setup — overlay layer, anchored to top+left+right, no exclusive zone
    GtkLayerShell.init_for_window(win)
    GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP,   True)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT,  True)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, True)
    GtkLayerShell.set_exclusive_zone(win, -1)  # ignore other layers' exclusive zones
    GtkLayerShell.set_margin(win, GtkLayerShell.Edge.TOP, 0)

    win.set_size_request(-1, HEIGHT)

    # CSS
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        win.get_screen(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_USER
    )

    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    return win


def main():
    win = build_window()
    poll(win)  # immediate first check
    GLib.timeout_add(POLL_MS, poll, win)
    Gtk.main()


if __name__ == "__main__":
    main()
