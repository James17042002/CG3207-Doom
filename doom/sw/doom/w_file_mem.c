// WAD access straight from memory (replaces doomgeneric's w_file_stdc.c, which reads through
// stdio one byte at a time - far too slow here). Keeps the name stdc_wad_file so w_file.c is
// unchanged. The WAD is where load.py put it: header at 0x84000000, data at 0x84000010.
#include <string.h>
#include "m_misc.h"
#include "w_file.h"
#include "z_zone.h"

#define WAD_HDR  ((const volatile unsigned int *)0x84000000u)
#define WAD_DATA ((const unsigned char *)0x84000010u)

extern wad_file_class_t stdc_wad_file;

static wad_file_t *W_Mem_OpenFile(char *path) {
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    if (strcmp(base, "doom.wad") != 0 || WAD_HDR[0] != 0x4C444157u)    // 'WADL'
        return NULL;
    wad_file_t *w = Z_Malloc(sizeof(wad_file_t), PU_STATIC, 0);
    w->file_class = &stdc_wad_file;
    w->mapped = NULL;           // lumps are copied, so they are 4-byte aligned in the zone
    w->length = WAD_HDR[1];
    return w;
}

static void W_Mem_CloseFile(wad_file_t *wad) { Z_Free(wad); }

size_t W_Mem_Read(wad_file_t *wad, unsigned int offset, void *buffer, size_t buffer_len) {
    if (offset >= wad->length) return 0;
    if (buffer_len > wad->length - offset) buffer_len = wad->length - offset;
    memcpy(buffer, WAD_DATA + offset, buffer_len);
    return buffer_len;
}

wad_file_class_t stdc_wad_file = { W_Mem_OpenFile, W_Mem_CloseFile, W_Mem_Read };
