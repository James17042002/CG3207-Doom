// doomgeneric platform layer for the CG3207 RISC-V SoC (doom branch).
//
// Video: Doom renders 320x200 palette indices (CMAP256). DG_DrawFrame scales that down to the
//        96x64 Pmod OLEDrgb (RGB565) through the OLED MMIO registers.
// Input: push buttons and switches on the board, plus keys typed in the PC terminal (UART).
// Time:  TIMER_MS / TIMER_US peripherals.
//
// Board controls
//   BTNU / BTND / BTNL / BTNR   arrow keys (move, turn, menu navigation)
//   BTNC                        fire + Enter (menu select)
//   SW0 flipped (either way)    Escape (open/close the menu)
//   SW1 flipped                 Use (open doors, flip switches)
//   SW2 up                      crop the status bar (game view fills the OLED)
//   SW3 up                      smoother downscaling (2x2 average, slower)
//   SW4 up when Doom starts     skip the title screen and menus: start E1M1 directly
// PC terminal (doom/tools/load.py keeps the terminal open):
//   arrows or WASD move, F or Ctrl fire, Space or E use, Enter, Esc or Q menu, Y/N answers,
//   1-7 weapons, Tab map.
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "doomgeneric.h"
#include "doomkeys.h"
#include "doomtype.h"
#include "i_video.h"                    // struct color, colors[] (CMAP256 palette)
#include "mmio.h"

extern boolean palette_changed;         // i_video.c (CMAP256)

#define OLED_W 96
#define OLED_H 64
static uint16_t pal565[256];
static uint8_t  palR[256], palG[256], palB[256];

// ---------------- video ----------------
void DG_Init(void) {
    OLED_CTRL = 0x14;                   // 16-bit colour, auto-advance column (row major)
    LEDS = 0x00FF;
}

static void update_palette(void) {
    for (int i = 0; i < 256; i++) {
        uint8_t r = colors[i].r, g = colors[i].g, b = colors[i].b;
        palR[i] = r; palG[i] = g; palB[i] = b;
        pal565[i] = (uint16_t)(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
    }
}

void DG_DrawFrame(void) {
    static int first = 1;
    if (palette_changed || first) { update_palette(); palette_changed = 0; first = 0; }
    const uint8_t *src = (const uint8_t *)DG_ScreenBuffer;
    uint32_t sw = DIPS;
    int src_h = (sw & 0x4) ? 168 : 200;   // 168 = view without the 32-pixel status bar
    int smooth = sw & 0x8;

    OLED_CTRL = 0x14;
    OLED_ROW = 0;
    OLED_COL = 0;
    for (int y = 0; y < OLED_H; y++) {
        int sy = (y * src_h) / OLED_H;
        const uint8_t *row = src + sy * 320;
        const uint8_t *row2 = src + (sy + 1 < src_h ? sy + 1 : sy) * 320;
        for (int x = 0; x < OLED_W; x++) {
            int sx = (x * 320) / OLED_W;
            uint32_t px;
            if (smooth) {
                uint8_t a = row[sx], b = row[sx + 1], c = row2[sx], d = row2[sx + 1];
                uint32_t r = (palR[a] + palR[b] + palR[c] + palR[d]) >> 2;
                uint32_t g = (palG[a] + palG[b] + palG[c] + palG[d]) >> 2;
                uint32_t bl = (palB[a] + palB[b] + palB[c] + palB[d]) >> 2;
                px = ((r >> 3) << 11) | ((g >> 2) << 5) | (bl >> 3);
            } else {
                px = pal565[row[sx]];
            }
            OLED_DATA = px;
        }
    }
    static uint32_t frames = 0, t0 = 0;
    frames++;
    uint32_t now = TIMER_MS;
    if (now - t0 >= 1000) {                 // frames per second on the 7-segment display
        SEVENSEG = ((frames * 1000 / (now - t0)) % 100) | (frames << 16);
        frames = 0; t0 = now;
    }
}

void DG_SleepMs(uint32_t ms) {
    uint32_t t = TIMER_MS;
    while (TIMER_MS - t < ms) ;
}

uint32_t DG_GetTicksMs(void) { return TIMER_MS; }

void DG_SetWindowTitle(const char *title) { (void)title; }

// ---------------- input ----------------
#define QLEN 32
static struct { uint8_t pressed, key; } q[QLEN];
static unsigned qh, qt;
static void push(int pressed, uint8_t key) {
    if (((qt + 1) % QLEN) == qh) return;
    q[qt].pressed = pressed; q[qt].key = key; qt = (qt + 1) % QLEN;
}

// keys typed in a terminal have no "release": release them after a short time
#define NREL 8
static struct { uint8_t key; uint32_t t; } rel[NREL];
static void tap(uint8_t key) {
    push(1, key);
    for (int i = 0; i < NREL; i++)
        if (rel[i].key == 0 || rel[i].key == key) { rel[i].key = key; rel[i].t = TIMER_MS + 150; return; }
    push(0, key);
}

static uint8_t map_char(int c) {
    switch (c) {
        case 'w': case 'W': return KEY_UPARROW;
        case 's': case 'S': return KEY_DOWNARROW;
        case 'a': case 'A': return KEY_LEFTARROW;
        case 'd': case 'D': return KEY_RIGHTARROW;
        case 'f': case 'F': case 'j': case 'J': return KEY_FIRE;
        case ' ': case 'e': case 'E': return KEY_USE;
        case '\r': case '\n': return KEY_ENTER;
        case 'q': case 'Q': return KEY_ESCAPE;
        case '\t': return KEY_TAB;
        case 'y': case 'Y': return 'y';
        case 'n': case 'N': return 'n';
        default: return (c >= '1' && c <= '7') ? (uint8_t)c : 0;
    }
}

static void poll_uart(void) {
    static int esc = 0;                     // 0 none, 1 got ESC, 2 got ESC [
    static uint32_t esc_t;
    int c;
    while ((c = uart_getc_nb()) >= 0) {
        if (esc == 1) { if (c == '[' || c == 'O') { esc = 2; continue; } tap(KEY_ESCAPE); esc = 0; }
        if (esc == 2) {
            esc = 0;
            if (c == 'A') tap(KEY_UPARROW); else if (c == 'B') tap(KEY_DOWNARROW);
            else if (c == 'C') tap(KEY_RIGHTARROW); else if (c == 'D') tap(KEY_LEFTARROW);
            continue;
        }
        if (c == 27) { esc = 1; esc_t = TIMER_MS; continue; }
        if (c == 3 || c == 0) { tap(KEY_FIRE); continue; }   // Ctrl+C / Ctrl (from load.py)
        uint8_t k = map_char(c);
        if (k) tap(k);
    }
    if (esc == 1 && TIMER_MS - esc_t > 50) { tap(KEY_ESCAPE); esc = 0; }   // a lone Escape
}

static void poll_board(void) {
    static uint32_t prev_pb = 0, prev_sw = 0xFFFFFFFF;
    uint32_t pb = PBS, sw = DIPS;
    if (prev_sw == 0xFFFFFFFF) prev_sw = sw;
    uint32_t ch = pb ^ prev_pb;
    if (ch & PB_UP)    push(!!(pb & PB_UP), KEY_UPARROW);
    if (ch & PB_DOWN)  push(!!(pb & PB_DOWN), KEY_DOWNARROW);
    if (ch & PB_LEFT)  push(!!(pb & PB_LEFT), KEY_LEFTARROW);
    if (ch & PB_RIGHT) push(!!(pb & PB_RIGHT), KEY_RIGHTARROW);
    if (ch & PB_CENTER) { push(!!(pb & PB_CENTER), KEY_FIRE); push(!!(pb & PB_CENTER), KEY_ENTER); }
    if ((sw ^ prev_sw) & 1) tap(KEY_ESCAPE);
    if ((sw ^ prev_sw) & 2) tap(KEY_USE);
    prev_pb = pb; prev_sw = sw;
}

int DG_GetKey(int *pressed, unsigned char *key) {
    if (qh == qt) {
        poll_board();
        poll_uart();
        uint32_t now = TIMER_MS;
        for (int i = 0; i < NREL; i++)
            if (rel[i].key && (int32_t)(now - rel[i].t) >= 0) { push(0, rel[i].key); rel[i].key = 0; }
    }
    if (qh == qt) return 0;
    *pressed = q[qh].pressed; *key = q[qh].key; qh = (qh + 1) % QLEN;
    return 1;
}

// ---------------- main ----------------
int main(void) {
    static char *argv[] = { "doom", "-iwad", "doom.wad", "-warp", "1", "1", NULL };
    int argc = (DIPS & 0x10) ? 6 : 3;      // SW4 up at start: go straight into E1M1
    printf("\nDoom on the CG3207 RISC-V processor\n");
    doomgeneric_Create(argc, argv);
    for (;;) doomgeneric_Tick();
}
