// Minimal "operating system" for doomgeneric on the doom SoC, on top of picolibc:
//  * stdin/stdout/stderr go to the UART
//  * a read-only file system with one file, "doom.wad", which is the WAD that load.py placed in
//    DDR2 (header 'WADL' + size at 0x84000000, data at 0x84000010). Opening anything else fails,
//    so config files and savegames are simply not saved.
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include "mmio.h"

#define WAD_HDR  ((volatile uint32_t *)0x84000000u)
#define WAD_DATA ((const uint8_t *)0x84000010u)

// ---------------- console ----------------
static int con_put(char c, FILE *f) {
    (void)f;
    if (c == '\n') uart_putc('\r');
    uart_putc(c);
    return (unsigned char)c;
}
static int con_get(FILE *f) { (void)f; return uart_getc(); }
static FILE __stdio = FDEV_SETUP_STREAM(con_put, con_get, NULL, _FDEV_SETUP_RW);
FILE *const stdin = &__stdio;
__strong_reference(stdin, stdout);
__strong_reference(stdin, stderr);

// ---------------- one-file file system ----------------
#define WAD_FD 3
static uint32_t wad_pos;
static int wad_open;

static uint32_t wad_size(void) { return (WAD_HDR[0] == 0x4C444157u) ? WAD_HDR[1] : 0; }   // 'WADL'

int open(const char *path, int flags, ...) {
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    if (strcmp(base, "doom.wad") == 0 && (flags & O_ACCMODE) == O_RDONLY && wad_size() && !wad_open) {
        wad_open = 1; wad_pos = 0;
        return WAD_FD;
    }
    errno = ENOENT;
    return -1;
}

int close(int fd) { if (fd == WAD_FD) { wad_open = 0; return 0; } return (fd >= 0 && fd <= 2) ? 0 : -1; }

ssize_t read(int fd, void *buf, size_t n) {
    if (fd == 0) { if (!n) return 0; ((char *)buf)[0] = (char)uart_getc(); return 1; }
    if (fd != WAD_FD) { errno = EBADF; return -1; }
    uint32_t sz = wad_size();
    if (wad_pos >= sz) return 0;
    if (n > sz - wad_pos) n = sz - wad_pos;
    memcpy(buf, WAD_DATA + wad_pos, n);
    wad_pos += n;
    return (ssize_t)n;
}

ssize_t write(int fd, const void *buf, size_t n) {
    if (fd == 1 || fd == 2) { const char *p = buf; for (size_t i = 0; i < n; i++) con_put(p[i], NULL); return (ssize_t)n; }
    errno = EBADF;
    return -1;
}

off_t lseek(int fd, off_t off, int whence) {
    if (fd != WAD_FD) { errno = ESPIPE; return -1; }
    uint32_t sz = wad_size(), base = whence == SEEK_SET ? 0 : whence == SEEK_CUR ? wad_pos : sz;
    wad_pos = base + (uint32_t)off;
    return (off_t)wad_pos;
}

int fstat(int fd, struct stat *st) {
    memset(st, 0, sizeof *st);
    if (fd == WAD_FD) { st->st_mode = S_IFREG; st->st_size = wad_size(); return 0; }
    st->st_mode = S_IFCHR;
    return 0;
}
int stat(const char *path, struct stat *st) { (void)path; (void)st; errno = ENOENT; return -1; }
int isatty(int fd) { return fd <= 2; }
int mkdir(const char *path, mode_t mode) { (void)path; (void)mode; errno = EROFS; return -1; }
int unlink(const char *path) { (void)path; errno = EROFS; return -1; }
int rename(const char *a, const char *b) { (void)a; (void)b; errno = EROFS; return -1; }
int remove(const char *path) { (void)path; errno = EROFS; return -1; }
int system(const char *cmd) { (void)cmd; return -1; }
int gettimeofday(struct timeval *tv, void *tz) {
    (void)tz; uint32_t us = TIMER_US; tv->tv_sec = us / 1000000; tv->tv_usec = us % 1000000; return 0;
}
