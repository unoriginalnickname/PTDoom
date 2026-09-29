/* PTDoom: Nuked OPL3 as a tiny standalone wasm module for the DOS app.
 *
 * v86 has no FM synthesis; web/v86-dos.js catches the guest's writes to the
 * OPL ports and plays them through this. One chip, one output buffer, no
 * Emscripten JavaScript: build with tools/build_opl.py. */
#include <stdint.h>
#include "../music/opl3.h"

#define MAX_FRAMES 8192

static opl3_chip chip;
static int16_t out[2 * MAX_FRAMES];

void opl_reset(uint32_t rate) { OPL3_Reset(&chip, rate); }

void opl_write(uint32_t reg, uint32_t value) { OPL3_WriteReg(&chip, (uint16_t)reg, (uint8_t)value); }

/* Renders frames (at most MAX_FRAMES) of interleaved stereo; returns the buffer. */
int16_t *opl_render(uint32_t frames)
{
    if (frames > MAX_FRAMES) frames = MAX_FRAMES;
    OPL3_GenerateStream(&chip, out, frames);
    return out;
}
