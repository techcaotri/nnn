/*
 * nnn-dnd -- a tiny, dependency-light drag-and-drop helper for nnn.
 *
 * A terminal program (a TUI) owns no windowing-system surface: the terminal
 * emulator owns the X11 window, so nnn itself cannot be an XDND drag source or
 * drop target.  This helper is the small window-owning process that nnn drives
 * to perform real drag-and-drop on X11 (and, via XWayland, on most Wayland
 * desktops too).  It implements the XDND protocol (version 5) directly on
 * libX11 -- no GTK/Qt -- so the only link dependency is -lX11.
 *
 * Two modes (a deliberate, CLI-compatible subset of the `dragon` tool, so it is
 * a drop-in replacement and nnn's plugins keep working):
 *
 *   nnn-dnd FILE...        source mode: a small window you can drag OUT of into
 *                          any XDND-aware GUI app (browser, file manager, GIMP).
 *   nnn-dnd --target       target mode: a window you can drag files INTO from a
 *                          GUI app; received paths/URIs are printed to stdout.
 *
 * See docs/Brainstorm_nnn_Support_Drag_and_Drop.md for the full design.
 *
 * Design: docs/Brainstorm_nnn_Support_Drag_and_Drop.md (Approach B).
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#define _GNU_SOURCE /* strdup, getopt_long */

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/cursorfont.h>

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <time.h>
#include <unistd.h>

#define NNN_DND_VERSION "1.0"
#define XDND_VERSION    5
#define DND_TIMEOUT_SEC 10

static int dbg_on; /* enabled by $NNN_DND_DEBUG */
#define DBG(...) do { if (dbg_on) { \
		fprintf(stderr, "nnn-dnd[dbg]: "); \
		fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); \
		fflush(stderr); } } while (0)

/* All XDND / selection atoms we need, interned once. */
struct atoms {
	Atom XdndAware;
	Atom XdndSelection;
	Atom XdndEnter;
	Atom XdndPosition;
	Atom XdndStatus;
	Atom XdndLeave;
	Atom XdndDrop;
	Atom XdndFinished;
	Atom XdndTypeList;
	Atom XdndActionCopy;
	Atom XdndProxy;
	Atom text_uri_list;
	Atom TARGETS;
	Atom INCR;
	Atom prop;       /* property used to transfer the selection data */
	Atom wm_delete;
	Atom wm_protocols;
	Atom net_wm_state;
	Atom net_wm_state_above;
};

/* Parsed command-line options. */
struct options {
	int target;        /* -t: act as a drop target instead of a drag source */
	int and_exit;      /* -x: exit after the first completed drag/drop */
	int print_path;    /* -p: with --target, print plain paths, not URIs */
	int on_top;        /* -T: keep the window always on top */
	int from_stdin;    /* -I: read the file list from stdin */
	int read_nnn_sel;  /* --nnn-sel: read the file list from $NNN_SEL */
	/* accepted-for-compat, mostly no-ops in this minimal helper */
	int all;           /* -a/-A: drag all as one (this is our default anyway) */
	int icon_only;     /* -i */
};

/* Whole-program runtime aggregate. */
struct app {
	Display *dpy;
	int screen;
	Window root;
	Window win;          /* our helper window */
	GC gc;
	XFontStruct *font;
	Cursor drag_cursor;
	struct atoms a;
	struct options o;
	char **files;        /* source mode: absolute paths to offer */
	int nfiles;
	char *uri_list;      /* source mode: prebuilt text/uri-list payload */
	size_t uri_len;
	const char *label;   /* text drawn in the window */
};

/* ------------------------------------------------------------------ utils */

static void die(const char *msg)
{
	fprintf(stderr, "nnn-dnd: %s\n", msg);
	exit(1);
}

static void *xmalloc(size_t n)
{
	void *p = malloc(n);

	if (!p)
		die("out of memory");
	return p;
}

static void usage(FILE *f)
{
	fputs(
"Usage: nnn-dnd [OPTIONS] [FILE...]\n"
"A libX11 drag-and-drop helper for nnn (XDND source/target).\n\n"
"  (no -t) FILE...   source mode: offer FILE(s) for dragging out\n"
"  -t, --target      target mode: receive a drop, print the paths/URIs\n"
"  -x, --and-exit    exit after the first completed drag or drop\n"
"  -p, --print-path  with --target, print plain paths instead of file:// URIs\n"
"  -a, --all         drag all files as one (default behaviour)\n"
"  -A, --all-compact accepted for dragon compatibility\n"
"  -T, --on-top      keep the helper window always on top\n"
"  -I, --stdin       read the file list from stdin (NUL or newline separated)\n"
"  -i, --icon-only   accepted for dragon compatibility\n"
"      --nnn-sel     read the file list from the file named by $NNN_SEL\n"
"  -h, --help        show this help\n"
"  -V, --version     show version\n", f);
}

/* Percent-encode a path for a file:// URI (keep unreserved chars and '/'). */
static char *uri_encode(const char *s)
{
	static const char hex[] = "0123456789ABCDEF";
	size_t len = strlen(s);
	char *out = xmalloc(len * 3 + 1);
	char *p = out;

	for (; *s; ++s) {
		unsigned char c = (unsigned char)*s;

		if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~' || c == '/')
			*p++ = (char)c;
		else {
			*p++ = '%';
			*p++ = hex[c >> 4];
			*p++ = hex[c & 0xf];
		}
	}
	*p = '\0';
	return out;
}

/* Percent-decode in place into a freshly allocated buffer. */
static char *uri_decode(const char *s, size_t len)
{
	char *out = xmalloc(len + 1);
	char *p = out;
	size_t i = 0;

	while (i < len) {
		if (s[i] == '%' && i + 2 < len && isxdigit((unsigned char)s[i + 1])
				&& isxdigit((unsigned char)s[i + 2])) {
			int hi = s[i + 1], lo = s[i + 2];

			hi = (hi <= '9') ? hi - '0' : (tolower(hi) - 'a' + 10);
			lo = (lo <= '9') ? lo - '0' : (tolower(lo) - 'a' + 10);
			*p++ = (char)((hi << 4) | lo);
			i += 3;
		} else
			*p++ = s[i++];
	}
	*p = '\0';
	return out;
}

static void add_file(struct app *ap, const char *path)
{
	char abs[PATH_MAX * 2 + 2];

	if (!path || !*path)
		return;

	if (path[0] != '/') { /* make relative paths absolute against CWD */
		char cwd[PATH_MAX];

		if (getcwd(cwd, sizeof cwd)) {
			snprintf(abs, sizeof abs, "%s/%s", cwd, path);
			path = abs;
		}
	}

	ap->files = realloc(ap->files, (size_t)(ap->nfiles + 1) * sizeof(char *));
	if (!ap->files)
		die("out of memory");
	ap->files[ap->nfiles++] = strdup(path);
}

/* Split a buffer on a separator byte (NUL or newline), adding each token. */
static void add_split(struct app *ap, char *buf, ssize_t len, char sep)
{
	ssize_t start = 0;

	for (ssize_t i = 0; i < len; ++i) {
		if (buf[i] == sep || (sep == '\n' && buf[i] == '\r')) {
			buf[i] = '\0';
			if (i > start)
				add_file(ap, buf + start);
			start = i + 1;
		}
	}
	if (start < len) /* trailing token without a final separator */
		add_file(ap, buf + start);
}

static char *read_all(int fd, ssize_t *out_len)
{
	size_t cap = 4096, used = 0;
	char *buf = xmalloc(cap);
	ssize_t n;

	while ((n = read(fd, buf + used, cap - used)) > 0) {
		used += (size_t)n;
		if (used == cap) {
			cap *= 2;
			buf = realloc(buf, cap);
			if (!buf)
				die("out of memory");
		}
	}
	*out_len = (ssize_t)used;
	return buf;
}

static void read_stdin_list(struct app *ap)
{
	ssize_t len;
	char *buf = read_all(STDIN_FILENO, &len);
	char sep = '\n';

	if (memchr(buf, '\0', (size_t)len)) /* auto-detect NUL vs newline */
		sep = '\0';
	add_split(ap, buf, len, sep);
	free(buf);
}

static void read_nnn_sel_list(struct app *ap)
{
	const char *sel = getenv("NNN_SEL");
	int fd;
	ssize_t len;
	char *buf;

	if (!sel || !*sel) {
		fprintf(stderr, "nnn-dnd: --nnn-sel but $NNN_SEL is unset\n");
		return;
	}
	fd = open(sel, O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "nnn-dnd: cannot open $NNN_SEL (%s)\n", strerror(errno));
		return;
	}
	buf = read_all(fd, &len);
	close(fd);
	add_split(ap, buf, len, '\0'); /* nnn selection is NUL-separated */
	free(buf);
}

/* Build the text/uri-list payload from the gathered files. */
static void build_uri_list(struct app *ap)
{
	size_t cap = 1, used = 0;
	char *out = xmalloc(cap);

	for (int i = 0; i < ap->nfiles; ++i) {
		char *enc = uri_encode(ap->files[i]);
		size_t need = strlen("file://") + strlen(enc) + 2 /* CRLF */;

		while (used + need + 1 > cap) {
			cap = (cap * 2) + need + 1;
			out = realloc(out, cap);
			if (!out)
				die("out of memory");
		}
		used += (size_t)snprintf(out + used, cap - used, "file://%s\r\n", enc);
		free(enc);
	}
	out[used] = '\0';
	ap->uri_list = out;
	ap->uri_len = used;
}

/* ------------------------------------------------------------------ X11 */

static void intern_atoms(struct app *ap)
{
	Display *d = ap->dpy;
	struct atoms *a = &ap->a;

	a->XdndAware       = XInternAtom(d, "XdndAware", False);
	a->XdndSelection   = XInternAtom(d, "XdndSelection", False);
	a->XdndEnter       = XInternAtom(d, "XdndEnter", False);
	a->XdndPosition    = XInternAtom(d, "XdndPosition", False);
	a->XdndStatus      = XInternAtom(d, "XdndStatus", False);
	a->XdndLeave       = XInternAtom(d, "XdndLeave", False);
	a->XdndDrop        = XInternAtom(d, "XdndDrop", False);
	a->XdndFinished    = XInternAtom(d, "XdndFinished", False);
	a->XdndTypeList    = XInternAtom(d, "XdndTypeList", False);
	a->XdndActionCopy  = XInternAtom(d, "XdndActionCopy", False);
	a->XdndProxy       = XInternAtom(d, "XdndProxy", False);
	a->text_uri_list   = XInternAtom(d, "text/uri-list", False);
	a->TARGETS         = XInternAtom(d, "TARGETS", False);
	a->INCR            = XInternAtom(d, "INCR", False);
	a->prop            = XInternAtom(d, "NNN_DND_DATA", False);
	a->wm_delete       = XInternAtom(d, "WM_DELETE_WINDOW", False);
	a->wm_protocols    = XInternAtom(d, "WM_PROTOCOLS", False);
	a->net_wm_state    = XInternAtom(d, "_NET_WM_STATE", False);
	a->net_wm_state_above = XInternAtom(d, "_NET_WM_STATE_ABOVE", False);
}

static void create_window(struct app *ap)
{
	Display *d = ap->dpy;
	unsigned long bg = WhitePixel(d, ap->screen);
	unsigned long fg = BlackPixel(d, ap->screen);
	XSizeHints hints;
	XSetWindowAttributes attr;
	const char *title = ap->o.target ? "nnn-dnd: drop here" : "nnn-dnd: drag out";

	attr.background_pixel = bg;
	attr.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask
			| StructureNotifyMask | PropertyChangeMask;

	ap->win = XCreateWindow(d, ap->root, 0, 0, 260, 90, 0,
				CopyFromParent, InputOutput, CopyFromParent,
				CWBackPixel | CWEventMask, &attr);

	XStoreName(d, ap->win, title);
	XSetClassHint(d, ap->win, &(XClassHint){ .res_name = (char *)"nnn-dnd",
						 .res_class = (char *)"nnn-dnd" });

	hints.flags = PMinSize;
	hints.min_width = 160;
	hints.min_height = 60;
	XSetWMNormalHints(d, ap->win, &hints);

	/* Honour the window-close button. */
	XSetWMProtocols(d, ap->win, &ap->a.wm_delete, 1);

	if (ap->o.on_top)
		XChangeProperty(d, ap->win, ap->a.net_wm_state, XA_ATOM, 32,
				PropModeReplace,
				(unsigned char *)&ap->a.net_wm_state_above, 1);

	ap->gc = XCreateGC(d, ap->win, 0, NULL);
	XSetForeground(d, ap->gc, fg);
	XSetBackground(d, ap->gc, bg);

	ap->font = XLoadQueryFont(d, "fixed");
	if (!ap->font)
		ap->font = XLoadQueryFont(d, "9x15");
	if (ap->font)
		XSetFont(d, ap->gc, ap->font->fid);

	ap->drag_cursor = XCreateFontCursor(d, XC_hand2);

	XMapRaised(d, ap->win);
}

static void draw_label(struct app *ap)
{
	const char *s = ap->label ? ap->label : "";

	XClearWindow(ap->dpy, ap->win);
	XDrawString(ap->dpy, ap->win, ap->gc, 14, 34, s, (int)strlen(s));
	if (!ap->o.target) {
		const char *hint = "press + drag to a GUI app";

		XDrawString(ap->dpy, ap->win, ap->gc, 14, 58, hint, (int)strlen(hint));
	}
}

static void send_xdnd(struct app *ap, Window to, Atom message,
		      long l0, long l1, long l2, long l3, long l4)
{
	XClientMessageEvent ev;

	memset(&ev, 0, sizeof ev);
	ev.type = ClientMessage;
	ev.display = ap->dpy;
	ev.window = to;
	ev.message_type = message;
	ev.format = 32;
	ev.data.l[0] = l0;
	ev.data.l[1] = l1;
	ev.data.l[2] = l2;
	ev.data.l[3] = l3;
	ev.data.l[4] = l4;
	XSendEvent(ap->dpy, to, False, NoEventMask, (XEvent *)&ev);
}

/* Read a window's XdndAware version (0 if not aware). */
static int xdnd_version(struct app *ap, Window w)
{
	Atom type;
	int fmt;
	unsigned long n, after;
	unsigned char *data = NULL;
	int ver = 0;

	if (XGetWindowProperty(ap->dpy, w, ap->a.XdndAware, 0, 1, False,
			       AnyPropertyType, &type, &fmt, &n, &after, &data) == Success) {
		if (data && type != None && n >= 1)
			ver = (int)data[0];
		if (data)
			XFree(data);
	}
	return ver;
}

/* Descend to the deepest window under the given root coordinates. */
static Window window_under_pointer(struct app *ap)
{
	Window w = ap->root, child = ap->root, r;
	int rx, ry, wx, wy;
	unsigned int mask;

	while (child != None) {
		w = child;
		if (!XQueryPointer(ap->dpy, w, &r, &child, &rx, &ry, &wx, &wy, &mask))
			break;
	}
	return w;
}

/*
 * Find the XDND target for the window under the pointer: walk up the ancestor
 * chain looking for XdndAware, honour XdndProxy, and never target ourselves.
 * Returns the window to send messages to (via *msg_win) and its version.
 */
static Window find_target(struct app *ap, Window *msg_win, int *version)
{
	Window w = window_under_pointer(ap);

	*msg_win = None;
	*version = 0;

	while (w != None && w != ap->root) {
		if (w == ap->win)
			return None; /* under our own window: no target */

		int ver = xdnd_version(ap, w);

		if (ver) {
			Window proxy = None;
			Atom type;
			int fmt;
			unsigned long n, after;
			unsigned char *data = NULL;

			/* XdndProxy redirects where messages must be sent. */
			if (XGetWindowProperty(ap->dpy, w, ap->a.XdndProxy, 0, 1, False,
					       XA_WINDOW, &type, &fmt, &n, &after,
					       &data) == Success) {
				if (data && type == XA_WINDOW && n >= 1)
					proxy = *(Window *)data;
				if (data)
					XFree(data);
			}
			*msg_win = proxy ? proxy : w;
			*version = ver < XDND_VERSION ? ver : XDND_VERSION;
			return w;
		}

		Window root_r, parent, *children = NULL;
		unsigned int nch;

		if (!XQueryTree(ap->dpy, w, &root_r, &parent, &children, &nch))
			break;
		if (children)
			XFree(children);
		w = parent;
	}
	return None;
}

/* Wait up to DND_TIMEOUT_SEC for an X event; return 0 on timeout. */
static int wait_event(struct app *ap)
{
	int fd = ConnectionNumber(ap->dpy);
	fd_set rfds;
	struct timeval tv = { DND_TIMEOUT_SEC, 0 };

	if (XPending(ap->dpy))
		return 1;
	FD_ZERO(&rfds);
	FD_SET(fd, &rfds);
	return select(fd + 1, &rfds, NULL, NULL, &tv) > 0;
}

/* ------------------------------------------------------------- target mode */

static void emit_uri_list(struct app *ap, const char *data, size_t len)
{
	size_t start = 0;

	for (size_t i = 0; i <= len; ++i) {
		if (i == len || data[i] == '\n') {
			size_t end = i;

			if (end > start && data[end - 1] == '\r')
				--end;
			if (end > start && data[start] != '#') { /* skip comments */
				if (ap->o.print_path
						&& strncmp(data + start, "file://", 7) == 0) {
					/* file://HOST/path -> decode the local path */
					const char *p = data + start + 7;
					const char *slash = memchr(p, '/', end - (size_t)(p - data));

					if (slash) {
						char *dec = uri_decode(slash, end - (size_t)(slash - data));

						printf("%s\n", dec);
						free(dec);
					}
				} else {
					fwrite(data + start, 1, end - start, stdout);
					putchar('\n');
				}
			}
			start = i + 1;
		}
	}
	fflush(stdout);
}

/* Read our transfer property, transparently handling the INCR protocol. */
static char *recv_property(struct app *ap, size_t *out_len)
{
	Atom type;
	int fmt;
	unsigned long n, after;
	unsigned char *data = NULL;

	if (XGetWindowProperty(ap->dpy, ap->win, ap->a.prop, 0, 0x1FFFFFFF, True,
			       AnyPropertyType, &type, &fmt, &n, &after, &data) != Success)
		return NULL;

	if (type != ap->a.INCR) { /* the common, single-shot case */
		char *buf = xmalloc(n + 1);

		if (n && data)
			memcpy(buf, data, n);
		buf[n] = '\0';
		*out_len = n;
		if (data)
			XFree(data);
		return buf;
	}

	/* INCR: delete the property to start, then accumulate each chunk. */
	if (data)
		XFree(data);
	XDeleteProperty(ap->dpy, ap->win, ap->a.prop);
	XFlush(ap->dpy);

	size_t cap = 4096, used = 0;
	char *buf = xmalloc(cap);

	for (;;) {
		XEvent ev;

		if (!wait_event(ap)) {
			free(buf);
			return NULL; /* timed out */
		}
		XNextEvent(ap->dpy, &ev);
		if (ev.type != PropertyNotify || ev.xproperty.atom != ap->a.prop
				|| ev.xproperty.state != PropertyNewValue)
			continue;

		data = NULL;
		if (XGetWindowProperty(ap->dpy, ap->win, ap->a.prop, 0, 0x1FFFFFFF, True,
				       AnyPropertyType, &type, &fmt, &n, &after,
				       &data) != Success)
			break;
		if (n == 0) { /* zero-length chunk terminates the transfer */
			if (data)
				XFree(data);
			break;
		}
		while (used + n + 1 > cap) {
			cap = (cap * 2) + n + 1;
			buf = realloc(buf, cap);
			if (!buf)
				die("out of memory");
		}
		memcpy(buf + used, data, n);
		used += n;
		if (data)
			XFree(data);
	}
	buf[used] = '\0';
	*out_len = used;
	return buf;
}

static int run_target(struct app *ap)
{
	long version = XDND_VERSION;
	Window source = None;
	int accept = 0;
	Time drop_time = CurrentTime;

	/* Advertise ourselves as an XDND-aware drop target. */
	XChangeProperty(ap->dpy, ap->win, ap->a.XdndAware, XA_ATOM, 32,
			PropModeReplace, (unsigned char *)&version, 1);
	ap->label = "Drop files here";

	DBG("target: win=0x%lx, XdndAware set, entering event loop",
	    (unsigned long)ap->win);

	for (;;) {
		XEvent ev;

		if (!wait_event(ap)) {
			if (source)
				continue; /* mid-interaction: keep waiting */
			continue;     /* idle: keep the window open */
		}
		XNextEvent(ap->dpy, &ev);

		if (ev.type == Expose) {
			draw_label(ap);
		} else if (ev.type == ClientMessage) {
			Atom mt = ev.xclient.message_type;

			if (mt == ap->a.wm_protocols
					&& (Atom)ev.xclient.data.l[0] == ap->a.wm_delete)
				return 0;

			if (mt == ap->a.XdndEnter) {
				source = (Window)ev.xclient.data.l[0];
				accept = 0;
				/* types in data.l[2..4]; or XdndTypeList if bit0 set */
				if (ev.xclient.data.l[1] & 1) {
					Atom type;
					int fmt;
					unsigned long n, after;
					unsigned char *data = NULL;

					if (XGetWindowProperty(ap->dpy, source, ap->a.XdndTypeList,
							       0, 64, False, XA_ATOM, &type, &fmt,
							       &n, &after, &data) == Success && data) {
						Atom *list = (Atom *)data;

						for (unsigned long i = 0; i < n; ++i)
							if (list[i] == ap->a.text_uri_list)
								accept = 1;
						XFree(data);
					}
				} else {
					for (int i = 2; i <= 4; ++i)
						if ((Atom)ev.xclient.data.l[i] == ap->a.text_uri_list)
							accept = 1;
				}
				DBG("target: XdndEnter from 0x%lx accept=%d",
				    (unsigned long)source, accept);
			} else if (mt == ap->a.XdndPosition) {
				source = (Window)ev.xclient.data.l[0];
				/* Reply with our status: accept uri-list, action copy.
				 * Empty rectangle (w=h=0) asks for a Position per move. */
				send_xdnd(ap, source, ap->a.XdndStatus, (long)ap->win,
					  accept ? 1 : 0, 0, 0,
					  accept ? (long)ap->a.XdndActionCopy : None);
				DBG("target: XdndPosition, sent status accept=%d", accept);
			} else if (mt == ap->a.XdndLeave) {
				source = None;
				accept = 0;
			} else if (mt == ap->a.XdndDrop) {
				source = (Window)ev.xclient.data.l[0];
				drop_time = (Time)ev.xclient.data.l[2];
				if (!accept) {
					send_xdnd(ap, source, ap->a.XdndFinished,
						  (long)ap->win, 0, None, 0, 0);
					continue;
				}
				/* Ask the X server to hand us the dragged data. */
				DBG("target: XdndDrop, converting selection");
				XConvertSelection(ap->dpy, ap->a.XdndSelection,
						  ap->a.text_uri_list, ap->a.prop,
						  ap->win, drop_time);
			}
		} else if (ev.type == SelectionNotify) {
			size_t len = 0;
			char *data;

			DBG("target: SelectionNotify prop=%ld",
			    (long)ev.xselection.property);
			if (ev.xselection.property == None) {
				if (source)
					send_xdnd(ap, source, ap->a.XdndFinished,
						  (long)ap->win, 0, None, 0, 0);
				continue;
			}
			data = recv_property(ap, &len);
			if (data) {
				emit_uri_list(ap, data, len);
				free(data);
			}
			if (source)
				send_xdnd(ap, source, ap->a.XdndFinished, (long)ap->win,
					  1, (long)ap->a.XdndActionCopy, 0, 0);
			source = None;
			accept = 0;
			if (ap->o.and_exit)
				return 0;
		}
	}
}

/* ------------------------------------------------------------- source mode */

static void serve_selection(struct app *ap, XSelectionRequestEvent *req)
{
	XSelectionEvent notify;

	memset(&notify, 0, sizeof notify);
	notify.type = SelectionNotify;
	notify.display = ap->dpy;
	notify.requestor = req->requestor;
	notify.selection = req->selection;
	notify.target = req->target;
	notify.time = req->time;
	notify.property = None;

	if (req->property != None) {
		if (req->target == ap->a.TARGETS) {
			Atom offered[] = { ap->a.text_uri_list, ap->a.TARGETS };

			XChangeProperty(ap->dpy, req->requestor, req->property, XA_ATOM, 32,
					PropModeReplace, (unsigned char *)offered,
					(int)(sizeof offered / sizeof offered[0]));
			notify.property = req->property;
		} else if (req->target == ap->a.text_uri_list) {
			XChangeProperty(ap->dpy, req->requestor, req->property,
					req->target, 8, PropModeReplace,
					(unsigned char *)ap->uri_list, (int)ap->uri_len);
			notify.property = req->property;
		}
	}
	XSendEvent(ap->dpy, req->requestor, False, NoEventMask, (XEvent *)&notify);
}

static int run_source(struct app *ap)
{
	Window cur_target = None, cur_msg = None;
	int cur_ver = 0;
	int dragging = 0, accepted = 0, dropped = 0;
	time_t drop_started = 0;

	build_uri_list(ap);
	if (ap->nfiles == 1) {
		const char *base = strrchr(ap->files[0], '/');

		ap->label = base ? base + 1 : ap->files[0];
	} else {
		static char buf[64];

		snprintf(buf, sizeof buf, "Drag %d file(s)", ap->nfiles);
		ap->label = buf;
	}

	/* Own the XDND selection for the whole drag. */
	XSetSelectionOwner(ap->dpy, ap->a.XdndSelection, ap->win, CurrentTime);
	if (XGetSelectionOwner(ap->dpy, ap->a.XdndSelection) != ap->win)
		die("could not take ownership of XdndSelection");

	DBG("source: win=0x%lx, %d file(s), entering event loop",
	    (unsigned long)ap->win, ap->nfiles);

	for (;;) {
		XEvent ev;

		/* If we dropped, give the target time to fetch data + finish. */
		if (dropped && drop_started && time(NULL) - drop_started > DND_TIMEOUT_SEC)
			return 0;

		if (!wait_event(ap)) {
			if (dropped)
				return 0;
			continue;
		}
		XNextEvent(ap->dpy, &ev);

		DBG("source: event type=%d", ev.type);

		switch (ev.type) {
		case Expose:
			draw_label(ap);
			break;
		case ClientMessage:
			if (ev.xclient.message_type == ap->a.wm_protocols
					&& (Atom)ev.xclient.data.l[0] == ap->a.wm_delete)
				return 0;
			if (ev.xclient.message_type == ap->a.XdndStatus) {
				accepted = (int)(ev.xclient.data.l[1] & 1);
				DBG("source: XdndStatus accepted=%d", accepted);
			} else if (ev.xclient.message_type == ap->a.XdndFinished) {
				if (ap->o.and_exit)
					return 0;
				/* keep the window for another drag */
				dropped = 0;
				drop_started = 0;
				cur_target = cur_msg = None;
				cur_ver = 0;
			}
			break;
		case ButtonPress:
			if (ev.xbutton.button == Button1 && !dragging) {
				int gr = XGrabPointer(ap->dpy, ap->win, False,
					     ButtonReleaseMask | PointerMotionMask,
					     GrabModeAsync, GrabModeAsync, None,
					     ap->drag_cursor, CurrentTime);

				dragging = 1;
				DBG("source: ButtonPress, XGrabPointer=%d (0=ok)", gr);
			}
			break;
		case MotionNotify:
			if (dragging) {
				Window msg = None;
				int ver = 0;
				Window tgt = find_target(ap, &msg, &ver);

				if (tgt != cur_target) {
					if (cur_target && cur_msg) /* left the old target */
						send_xdnd(ap, cur_msg, ap->a.XdndLeave,
							  (long)ap->win, 0, 0, 0, 0);
					cur_target = tgt;
					cur_msg = msg;
					cur_ver = ver;
					accepted = 0;
					if (cur_target) /* entered a new target */
						send_xdnd(ap, cur_msg, ap->a.XdndEnter,
							  (long)ap->win,
							  (long)cur_ver << 24,
							  (long)ap->a.text_uri_list, 0, 0);
					DBG("source: target=0x%lx ver=%d",
					    (unsigned long)tgt, ver);
				}
				if (cur_target)
					send_xdnd(ap, cur_msg, ap->a.XdndPosition,
						  (long)ap->win, 0,
						  ((long)ev.xmotion.x_root << 16)
							  | (ev.xmotion.y_root & 0xffff),
						  CurrentTime, (long)ap->a.XdndActionCopy);
			}
			break;
		case ButtonRelease:
			if (ev.xbutton.button == Button1 && dragging) {
				dragging = 0;
				XUngrabPointer(ap->dpy, CurrentTime);
				DBG("source: ButtonRelease target=0x%lx accepted=%d",
				    (unsigned long)cur_target, accepted);
				if (cur_target && cur_msg && accepted) {
					send_xdnd(ap, cur_msg, ap->a.XdndDrop, (long)ap->win,
						  0, CurrentTime, 0, 0);
					DBG("source: sent XdndDrop");
					dropped = 1;
					drop_started = time(NULL);
				} else {
					if (cur_target && cur_msg)
						send_xdnd(ap, cur_msg, ap->a.XdndLeave,
							  (long)ap->win, 0, 0, 0, 0);
					cur_target = cur_msg = None;
					if (ap->o.and_exit)
						return 0;
				}
			}
			break;
		case SelectionRequest:
			serve_selection(ap, &ev.xselectionrequest);
			break;
		case SelectionClear:
			/* lost ownership; nothing left to serve */
			break;
		default:
			break;
		}
	}
}

/* ------------------------------------------------------------------ main */

int main(int argc, char **argv)
{
	struct app ap;
	int c;
	static const struct option longopts[] = {
		{ "target",      no_argument, NULL, 't' },
		{ "and-exit",    no_argument, NULL, 'x' },
		{ "print-path",  no_argument, NULL, 'p' },
		{ "all",         no_argument, NULL, 'a' },
		{ "all-compact", no_argument, NULL, 'A' },
		{ "on-top",      no_argument, NULL, 'T' },
		{ "stdin",       no_argument, NULL, 'I' },
		{ "icon-only",   no_argument, NULL, 'i' },
		{ "name-only",   no_argument, NULL, 'f' }, /* dragon compat (ignored) */
		{ "keep",        no_argument, NULL, 'k' }, /* dragon compat (ignored) */
		{ "nnn-sel",     no_argument, NULL, 1 },
		{ "help",        no_argument, NULL, 'h' },
		{ "version",     no_argument, NULL, 'V' },
		{ 0, 0, 0, 0 }
	};

	memset(&ap, 0, sizeof ap);
	dbg_on = (getenv("NNN_DND_DEBUG") != NULL);

	while ((c = getopt_long(argc, argv, "txpaATIifkhV", longopts, NULL)) != -1) {
		switch (c) {
		case 't': ap.o.target = 1; break;
		case 'x': ap.o.and_exit = 1; break;
		case 'p': ap.o.print_path = 1; break;
		case 'a': case 'A': ap.o.all = 1; break;
		case 'T': ap.o.on_top = 1; break;
		case 'I': ap.o.from_stdin = 1; break;
		case 'i': ap.o.icon_only = 1; break;
		case 'f': case 'k': break; /* accepted for compatibility */
		case 1:   ap.o.read_nnn_sel = 1; break;
		case 'h': usage(stdout); return 0;
		case 'V': printf("nnn-dnd %s (XDND v%d)\n", NNN_DND_VERSION, XDND_VERSION); return 0;
		case '?': default: break; /* ignore unknown flags for drop-in compat */
		}
	}

	if (!ap.o.target) { /* gather the file list for source mode */
		for (int i = optind; i < argc; ++i)
			add_file(&ap, argv[i]);
		if (ap.o.from_stdin)
			read_stdin_list(&ap);
		if (ap.o.read_nnn_sel)
			read_nnn_sel_list(&ap);
		if (ap.nfiles == 0)
			die("source mode needs at least one file (FILE..., --stdin, or --nnn-sel)");
	}

	ap.dpy = XOpenDisplay(NULL);
	if (!ap.dpy)
		die("cannot open X display (is $DISPLAY set? Wayland needs XWayland)");
	ap.screen = DefaultScreen(ap.dpy);
	ap.root = RootWindow(ap.dpy, ap.screen);

	intern_atoms(&ap);
	create_window(&ap);

	int rc = ap.o.target ? run_target(&ap) : run_source(&ap);

	if (ap.font)
		XFreeFont(ap.dpy, ap.font);
	XCloseDisplay(ap.dpy);
	return rc;
}
