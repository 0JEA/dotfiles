# Tiny caps-lock strip: raw Wayland + wlr-layer-shell, no GTK.
# Needs: wayland, wayland-protocols, wlr-protocols. Build: make
PROTO = /usr/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml
# layer-shell's get_popup references xdg_popup, so its interface must be linked
XDG = /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml

capslock-strip: main.c layer-shell.h layer-shell.c xdg-shell.c
	$(CC) -O2 -Wall -o $@ main.c layer-shell.c xdg-shell.c -lwayland-client

layer-shell.h: ; wayland-scanner client-header $(PROTO) $@
layer-shell.c: ; wayland-scanner private-code $(PROTO) $@
xdg-shell.c:   ; wayland-scanner private-code $(XDG) $@

clean: ; rm -f capslock-strip layer-shell.* xdg-shell.*
