/* Caps lock indicator: a 3px strip across the top of the focused
 * output, drawn with raw Wayland + wlr-layer-shell (no GTK, no Python).
 * Replaces capslock-overlay.py (~45 MB RSS) with ~1 MB.
 * Colour: "red" from ~/.config/theme/colors.json (matugen), else Marigold. */
#define _GNU_SOURCE
#include <glob.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "layer-shell.h"

#define HEIGHT  3
#define POLL_MS 300

static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct wl_surface *surf;
static struct wl_buffer *buf_on, *buf_off;
static uint32_t width;
static int configured, running = 1;

static uint32_t load_red(void) {
    uint32_t rgb = 0xf2543d; /* Marigold fallback */
    char path[512], data[8192];
    snprintf(path, sizeof path, "%s/.config/theme/colors.json", getenv("HOME"));
    FILE *f = fopen(path, "r");
    if (!f) return rgb;
    size_t n = fread(data, 1, sizeof data - 1, f);
    fclose(f);
    data[n] = 0;
    char *p = strstr(data, "\"red\"");
    if (p && (p = strchr(p + 5, '#'))) {
        unsigned v;
        if (sscanf(p + 1, "%6x", &v) == 1) rgb = v;
    }
    return rgb;
}

static struct wl_buffer *make_buf(uint32_t argb) {
    size_t stride = width * 4, size = stride * HEIGHT;
    int fd = memfd_create("capslock", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, size) < 0) exit(1);
    uint32_t *px = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    for (size_t i = 0; i < size / 4; i++) px[i] = argb;
    munmap(px, size);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *b = wl_shm_pool_create_buffer(pool, 0, width, HEIGHT,
                                                    stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return b;
}

static int read_caps(void) {
    glob_t g;
    int on = 0;
    if (glob("/sys/class/leds/*capslock/brightness", 0, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc && !on; i++) {
            FILE *f = fopen(g.gl_pathv[i], "r");
            if (f) { on = fgetc(f) == '1'; fclose(f); }
        }
        globfree(&g);
    }
    return on;
}

static void show(int on) {
    wl_surface_attach(surf, on ? buf_on : buf_off, 0, 0);
    wl_surface_damage(surf, 0, 0, width, HEIGHT);
    wl_surface_commit(surf);
}

static void ls_configure(void *d, struct zwlr_layer_surface_v1 *ls,
                         uint32_t serial, uint32_t w, uint32_t h) {
    zwlr_layer_surface_v1_ack_configure(ls, serial);
    if (w && w != width) {
        if (buf_on) { wl_buffer_destroy(buf_on); wl_buffer_destroy(buf_off); }
        width = w;
        buf_on = make_buf(0xff000000 | load_red());
        buf_off = make_buf(0x00000000);
    }
    configured = 1;
    show(read_caps());
}
static void ls_closed(void *d, struct zwlr_layer_surface_v1 *ls) { running = 0; }
static const struct zwlr_layer_surface_v1_listener ls_lis = { ls_configure, ls_closed };

static void reg_global(void *d, struct wl_registry *r, uint32_t name,
                       const char *iface, uint32_t ver) {
    if (!strcmp(iface, wl_compositor_interface.name))
        comp = wl_registry_bind(r, name, &wl_compositor_interface, 4);
    else if (!strcmp(iface, wl_shm_interface.name))
        shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
    else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name))
        layer_shell = wl_registry_bind(r, name, &zwlr_layer_shell_v1_interface, 1);
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener reg_lis = { reg_global, reg_remove };

int main(void) {
    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) { fprintf(stderr, "no wayland display\n"); return 1; }
    wl_registry_add_listener(wl_display_get_registry(dpy), &reg_lis, NULL);
    wl_display_roundtrip(dpy);
    if (!comp || !shm || !layer_shell) { fprintf(stderr, "missing globals\n"); return 1; }

    surf = wl_compositor_create_surface(comp);
    /* empty input region: clicks on the top 3px go through to the app below */
    struct wl_region *empty = wl_compositor_create_region(comp);
    wl_surface_set_input_region(surf, empty);
    wl_region_destroy(empty);

    struct zwlr_layer_surface_v1 *ls = zwlr_layer_shell_v1_get_layer_surface(
        layer_shell, surf, NULL, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "capslock-strip");
    zwlr_layer_surface_v1_set_anchor(ls, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_size(ls, 0, HEIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(ls, -1);
    zwlr_layer_surface_v1_add_listener(ls, &ls_lis, NULL);
    wl_surface_commit(surf);

    int last = -1;
    struct pollfd pfd = { wl_display_get_fd(dpy), POLLIN, 0 };
    while (running) {
        wl_display_flush(dpy);
        if (poll(&pfd, 1, POLL_MS) > 0) {
            if (wl_display_dispatch(dpy) < 0) break;
        }
        if (configured) {
            int on = read_caps();
            if (on != last) { show(on); last = on; }
        }
    }
    return 0;
}
