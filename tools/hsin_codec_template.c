/*
 * HSIN content codec - XOR stream cipher.
 *
 * This is a TEMPLATE. build_release.sh generates a random key per build,
 * fills in the /*__KEY_BYTES__*\/ marker below, and compiles the result
 * into bin/hsin-unpack. That single binary is used twice:
 *   - during the build, to turn protected .sh source into opaque blobs
 *   - on-device, inside the stub that replaces each protected file, to
 *     decode the blob back into runnable shell text
 * XOR is symmetric, so "encode" and "decode" are the exact same
 * operation - there's no enc/dec mode to get wrong.
 *
 * What this buys you: a protected script can no longer be read by
 * opening the module zip in a file manager, archive tool, or text
 * editor. What it does NOT buy you: real cryptographic secrecy. The
 * key lives inside this compiled binary and can be recovered by anyone
 * willing to disassemble it. Treat this as raising the bar against
 * casual copying, not as defeating a determined reverse engineer.
 *
 * Usage: hsin-unpack <file>   (prints XOR'd bytes to stdout)
 */

#include <stdio.h>
#include <stdlib.h>

static const unsigned char HSIN_KEY[] = {
/*__KEY_BYTES__*/
};
static const long HSIN_KEY_LEN = (long)(sizeof(HSIN_KEY) / sizeof(HSIN_KEY[0]));

static unsigned char *read_all(FILE *f, long *out_len) {
    if (fseek(f, 0, SEEK_END) != 0) return NULL;
    long sz = ftell(f);
    if (sz < 0) return NULL;
    rewind(f);
    unsigned char *buf = malloc((size_t)sz > 0 ? (size_t)sz : 1);
    if (!buf) return NULL;
    size_t rd = fread(buf, 1, (size_t)sz, f);
    if (rd != (size_t)sz) { free(buf); return NULL; }
    *out_len = sz;
    return buf;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <file>\n", argv[0]);
        return 1;
    }
    if (HSIN_KEY_LEN <= 0) {
        fprintf(stderr, "hsin-unpack: no key compiled in\n");
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { fprintf(stderr, "hsin-unpack: cannot open %s\n", argv[1]); return 1; }
    long len = 0;
    unsigned char *buf = read_all(f, &len);
    fclose(f);
    if (!buf) { fprintf(stderr, "hsin-unpack: read failed\n"); return 1; }

    for (long i = 0; i < len; i++) {
        buf[i] ^= HSIN_KEY[i % HSIN_KEY_LEN];
    }

    fwrite(buf, 1, (size_t)len, stdout);
    free(buf);
    return 0;
}
