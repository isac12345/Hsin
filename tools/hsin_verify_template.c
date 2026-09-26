/*
 * HSIN integrity verifier.
 *
 * This file is a TEMPLATE. build_release.sh copies it, replaces the
 * /*__ENTRIES__*\/ marker below with the real {path, md5} pairs computed
 * from the exact files being packaged, then compiles the result into
 * bin/hsin-verify. The compiled binary is what ships in the RELEASE zip.
 * The DEV zip never contains this binary at all.
 *
 * Usage: hsin-verify <module_path>
 * Exit 0  = every protected file matches its expected hash.
 * Exit 1  = mismatch, missing file, or unreadable file.
 *
 * Why a binary instead of another shell script: a .sh file is plain text -
 * open it in any editor and the check (and the expected hashes) are right
 * there to read and delete. A compiled ELF isn't readable text; picking the
 * check apart requires actually disassembling it, which is a very different
 * (and much higher) bar than opening a file in a text editor.
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* ---- minimal MD5 (RFC 1321), little-endian only (true for arm64/x86) ---- */

static const uint32_t K[64] = {
    0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,
    0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
    0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,
    0x6b901122,0xfd987193,0xa679438e,0x49b40821,
    0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,
    0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
    0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,
    0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
    0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,
    0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
    0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,
    0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
    0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,
    0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
    0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,
    0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
};
static const uint32_t S[64] = {
    7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
    5, 9,14,20, 5, 9,14,20, 5, 9,14,20, 5, 9,14,20,
    4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
    6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
};

static uint32_t leftrotate(uint32_t x, uint32_t c) {
    return (x << c) | (x >> (32 - c));
}

static void md5_digest(const uint8_t *data, size_t len, uint8_t out[16]) {
    uint32_t a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;

    size_t new_len = ((len + 8) / 64 + 1) * 64 - 8;
    uint8_t *msg = calloc(new_len + 64, 1);
    if (!msg) { fprintf(stderr, "hsin-verify: out of memory\n"); exit(1); }
    memcpy(msg, data, len);
    msg[len] = 0x80;
    uint64_t bits_len = (uint64_t)len * 8;
    memcpy(msg + new_len, &bits_len, 8);

    for (size_t offset = 0; offset < new_len; offset += 64) {
        uint32_t w[16];
        memcpy(w, msg + offset, 64);
        uint32_t a = a0, b = b0, c = c0, d = d0;
        for (int i = 0; i < 64; i++) {
            uint32_t f, g;
            if (i < 16)      { f = (b & c) | (~b & d);         g = i; }
            else if (i < 32) { f = (d & b) | (~d & c);         g = (5*i + 1) % 16; }
            else if (i < 48) { f = b ^ c ^ d;                  g = (3*i + 5) % 16; }
            else             { f = c ^ (b | ~d);               g = (7*i) % 16; }
            uint32_t temp = d;
            d = c;
            c = b;
            b = b + leftrotate(a + f + K[i] + w[g], S[i]);
            a = temp;
        }
        a0 += a; b0 += b; c0 += c; d0 += d;
    }
    free(msg);
    memcpy(out,    &a0, 4);
    memcpy(out+4,  &b0, 4);
    memcpy(out+8,  &c0, 4);
    memcpy(out+12, &d0, 4);
}

static void md5_hex_of_file(const char *path, char out_hex[33]) {
    out_hex[0] = '\0';
    FILE *f = fopen(path, "rb");
    if (!f) return;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return; }
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc((size_t)sz > 0 ? (size_t)sz : 1);
    if (!buf) { fclose(f); return; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if (rd != (size_t)sz) { free(buf); return; }

    uint8_t digest[16];
    md5_digest(buf, (size_t)sz, digest);
    free(buf);

    static const char hexch[] = "0123456789abcdef";
    for (int i = 0; i < 16; i++) {
        out_hex[i*2]   = hexch[(digest[i] >> 4) & 0xF];
        out_hex[i*2+1] = hexch[digest[i] & 0xF];
    }
    out_hex[32] = '\0';
}

/* ---- protected file list, filled in by build_release.sh ---- */

typedef struct { const char *rel_path; const char *expect_md5; } hsin_entry_t;

static const hsin_entry_t HSIN_ENTRIES[] = {
/*__ENTRIES__*/
};
static const int HSIN_ENTRY_COUNT = (int)(sizeof(HSIN_ENTRIES) / sizeof(HSIN_ENTRIES[0]));

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <module_path>\n", argv[0]);
        return 1;
    }
    const char *base = argv[1];

    for (int i = 0; i < HSIN_ENTRY_COUNT; i++) {
        char full[1024];
        snprintf(full, sizeof(full), "%s/%s", base, HSIN_ENTRIES[i].rel_path);

        char actual[33];
        md5_hex_of_file(full, actual);

        if (actual[0] == '\0') return 1;                        /* missing/unreadable */
        if (strcmp(actual, HSIN_ENTRIES[i].expect_md5) != 0) return 1; /* tampered */
    }
    return 0;
}
