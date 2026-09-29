// PTDoom: declarations i_oplmusic.c expects from Chocolate Doom 3.0.1's
// i_sound.h that doomgeneric's older copy doesn't have.

#ifndef PTDOOM_COMPAT_H
#define PTDOOM_COMPAT_H

// DMX version to emulate for OPL emulation:
typedef enum {
    opl_doom1_1_666,    // Doom 1 v1.666
    opl_doom2_1_666,    // Doom 2 v1.666, Hexen, Heretic
    opl_doom_1_9        // Doom v1.9, Strife
} opl_driver_ver_t;

void I_SetOPLDriverVer(opl_driver_ver_t ver);

// From Chocolate Doom's i_system.c; midifile.c uses it.
#include <stddef.h>
void *I_Realloc(void *ptr, size_t size);

#endif
