/*
 * hsin-fpsd: daemon kecil pengambil waktu frame untuk HSIN.
 *
 * Membaca `SurfaceFlinger --latency <layer>` langsung lewat binder (AIBinder_dump), tanpa fork `dumpsys`
 * dan tanpa parsing shell. Hasil tiap detik ditulis ke <dir>/fpsd.out dalam format yang sama dengan
 * baris `lat=` milik hud_sample.sh, jadi aplikasi (Kotlin) tidak perlu diubah untuk membacanya.
 *
 *   hsin-fpsd <dir>         jalan terus (daemon). Game yang dipantau = isi <dir>/fpsd.pkg
 *                           (ditulis hud_sample.sh tiap detik). Berkas pkg lebih tua dari 8 dtk = tidur.
 *   hsin-fpsd --selftest    uji sekali: cetak OK/GAGAL dan alasannya, lalu keluar.
 *
 * Berkas di <dir>: fpsd.pkg (masuk), fpsd.out (keluar), fpsd.status (ok | binder-fail | dump-fail), fpsd.pid
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define MAXTS 70
#define OUTBUF (256 * 1024)

/* Header binder_manager.h tidak ada di semua NDK, jadi libbinder_ndk.so dimuat saat jalan (dlopen) dan
 * hanya dua fungsi yang dipakai. Tipe dideklarasikan sendiri (cocok dengan NDK: AIBinder opak, status int32). */
typedef struct AIBinder AIBinder;
typedef int32_t binder_status_t;
#define STATUS_OK 0
typedef AIBinder *(*check_service_fn)(const char *);
typedef binder_status_t (*dump_fn)(AIBinder *, int, const char **, uint32_t);
static check_service_fn p_check = NULL;
static dump_fn p_dump = NULL;

static int bind_lib(void) {
    if (p_check && p_dump) return 0;
    void *h = dlopen("libbinder_ndk.so", RTLD_NOW);
    if (!h) return -1;
    p_check = (check_service_fn)dlsym(h, "AServiceManager_checkService");
    p_dump = (dump_fn)dlsym(h, "AIBinder_dump");
    return (p_check && p_dump) ? 0 : -1;
}

static volatile sig_atomic_t g_stop = 0;
static void on_sig(int s) { (void)s; g_stop = 1; }

static AIBinder *g_sf = NULL;

static int sf_connect(void) {
    if (g_sf) return 0;
    if (bind_lib() != 0) return -1;
    g_sf = p_check("SurfaceFlinger");
    return g_sf ? 0 : -1;
}

/* Jalankan dump SurfaceFlinger dengan argumen, hasil teks di buf. Return panjang, atau -1. */
static ssize_t sf_dump(const char *a0, const char *a1, char *buf, size_t cap) {
    if (sf_connect() != 0) return -1;
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) return -1;
#ifdef F_SETPIPE_SZ
    fcntl(fds[1], F_SETPIPE_SZ, 1024 * 1024);
#endif
    const char *args[2];
    uint32_t n = 0;
    args[n++] = a0;
    if (a1) args[n++] = a1;
    binder_status_t st = p_dump(g_sf, fds[1], args, n);
    close(fds[1]);
    if (st != STATUS_OK) { close(fds[0]); return -2; }
    fcntl(fds[0], F_SETFL, O_NONBLOCK);
    size_t len = 0;
    for (;;) {
        ssize_t r = read(fds[0], buf + len, cap - 1 - len);
        if (r <= 0) break;
        len += (size_t)r;
        if (len >= cap - 1) break;
    }
    close(fds[0]);
    buf[len] = 0;
    return (ssize_t)len;
}

/* Isi `ts` dengan kolom 2 (actualPresentTime) dari keluaran --latency; return jumlah, last = terbaru. */
static int parse_latency(const char *txt, long long *ts, long long *last) {
    int n = 0;
    *last = 0;
    const char *p = txt;
    int line = 0;
    while (*p) {
        const char *e = strchr(p, '\n');
        size_t ll = e ? (size_t)(e - p) : strlen(p);
        if (line++ > 0 && ll > 0) {
            long long a, b, c;
            if (sscanf(p, "%lld %lld %lld", &a, &b, &c) == 3) {
                if (b > 0 && b != 9223372036854775807LL) {
                    if (n == MAXTS) { memmove(ts, ts + 1, sizeof(long long) * (MAXTS - 1)); n--; }
                    ts[n++] = b;
                    *last = b;
                }
            }
        }
        if (!e) break;
        p = e + 1;
    }
    return n;
}

static int has(const char *line, const char *needle) { return strstr(line, needle) != NULL; }

/* Pilih layer game: prioritas SurfaceView+BLAST, SurfaceView, BLAST biasa, lainnya; yang frame terbarunya menang. */
static int pick_layer(const char *pkg, char *layer, size_t lsz, char *buf, size_t cap) {
    ssize_t len = sf_dump("--list", NULL, buf, cap);
    if (len <= 0) return -1;
    char *list = strdup(buf);
    if (!list) return -1;
    long long bestlast = -1;
    int found = 0;
    for (int prio = 0; prio < 4; prio++) {
        char *save = NULL;
        char *copy = strdup(list);
        for (char *ln = strtok_r(copy, "\n", &save); ln; ln = strtok_r(NULL, "\n", &save)) {
            if (!has(ln, pkg)) continue;
            int sv = has(ln, "SurfaceView"), bl = has(ln, "BLAST");
            int pr = (sv && bl) ? 0 : sv ? 1 : bl ? 2 : 3;
            if (pr != prio) continue;
            char name[512];
            snprintf(name, sizeof name, "%s", ln);
            size_t nl = strlen(name);
            while (nl && (name[nl - 1] == '\r' || name[nl - 1] == ' ')) name[--nl] = 0;
            ssize_t l2 = sf_dump("--latency", name, buf, cap);
            if (l2 <= 0) continue;
            long long ts[MAXTS], last;
            int n = parse_latency(buf, ts, &last);
            if (n >= 3 && last > bestlast) {
                bestlast = last;
                snprintf(layer, lsz, "%s", name);
                found = 1;
            }
        }
        free(copy);
        if (found) break;
    }
    free(list);
    return found ? 0 : -1;
}

static void write_file(const char *dir, const char *name, const char *content) {
    char path[512], tmp[520];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "w");
    if (!f) return;
    fputs(content, f);
    fclose(f);
    chmod(tmp, 0644);
    rename(tmp, path);
}

static int read_pkg(const char *dir, char *pkg, size_t sz) {
    char path[512];
    snprintf(path, sizeof path, "%s/fpsd.pkg", dir);
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    if (time(NULL) - st.st_mtime > 8) return 0;
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    if (!fgets(pkg, (int)sz, f)) { fclose(f); return 0; }
    fclose(f);
    size_t n = strlen(pkg);
    while (n && isspace((unsigned char)pkg[n - 1])) pkg[--n] = 0;
    for (size_t i = 0; i < n; i++)
        if (!(isalnum((unsigned char)pkg[i]) || pkg[i] == '.' || pkg[i] == '_')) return 0;
    return n > 2;
}

static int selftest(void) {
    char *buf = malloc(OUTBUF);
    if (!buf) { puts("GAGAL: memori"); return 2; }
    if (sf_connect() != 0) { puts("GAGAL: binder SurfaceFlinger tidak terjangkau (SELinux/ROM)"); return 3; }
    ssize_t n = sf_dump("--list", NULL, buf, OUTBUF);
    if (n <= 0) { printf("GAGAL: dump ditolak (kode %zd)\n", n); return 4; }
    int lines = 0;
    for (ssize_t i = 0; i < n; i++) if (buf[i] == '\n') lines++;
    printf("OK: binder jalan, %d layer terdaftar\n", lines);
    free(buf);
    return 0;
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "--selftest") == 0) return selftest();
    const char *dir = argc >= 2 ? argv[1] : "/data/adb/hsin";
    signal(SIGTERM, on_sig);
    signal(SIGINT, on_sig);
    signal(SIGHUP, SIG_IGN);

    char pidbuf[32];
    snprintf(pidbuf, sizeof pidbuf, "%d\n", (int)getpid());
    write_file(dir, "fpsd.pid", pidbuf);

    char *buf = malloc(OUTBUF);
    char *out = malloc(MAXTS * 24 + 256);
    if (!buf || !out) return 1;
    char pkg[256] = "", cur_pkg[256] = "", layer[512] = "";
    int stale = 0, fail_run = 0;
    long long prevlast = 0;

    while (!g_stop) {
        if (!read_pkg(dir, pkg, sizeof pkg)) {
            cur_pkg[0] = 0; layer[0] = 0;
            sleep(2);
            continue;
        }
        if (strcmp(pkg, cur_pkg) != 0) {
            snprintf(cur_pkg, sizeof cur_pkg, "%s", pkg);
            layer[0] = 0; stale = 0; prevlast = 0;
        }
        if (sf_connect() != 0) {
            write_file(dir, "fpsd.status", "binder-fail\n");
            sleep(5);
            continue;
        }
        long long ts[MAXTS], last = 0;
        int n = 0;
        if (layer[0]) {
            ssize_t l = sf_dump("--latency", layer, buf, OUTBUF);
            if (l > 0) n = parse_latency(buf, ts, &last);
            if (n < 3) layer[0] = 0;
            else if (last == prevlast) { if (++stale >= 3) { layer[0] = 0; stale = 0; } }
            else stale = 0;
        }
        if (!layer[0]) {
            if (pick_layer(pkg, layer, sizeof layer, buf, OUTBUF) == 0) {
                ssize_t l = sf_dump("--latency", layer, buf, OUTBUF);
                if (l > 0) n = parse_latency(buf, ts, &last);
            }
        }
        if (n >= 3) {
            fail_run = 0;
            prevlast = last;
            int o = snprintf(out, 128, "pkg=%s\nstatus=ok\nlat=", cur_pkg);
            for (int i = 0; i < n; i++) o += snprintf(out + o, 32, " %lld", ts[i]);
            out[o++] = '\n'; out[o] = 0;
            write_file(dir, "fpsd.out", out);
            write_file(dir, "fpsd.status", "ok\n");
        } else if (++fail_run == 5) {
            write_file(dir, "fpsd.status", "dump-fail\n");
        }
        usleep(1000 * 1000);
    }
    return 0;
}
