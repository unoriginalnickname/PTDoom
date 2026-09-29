// PTDoom: functions from Chocolate Doom 3.0.1 that the music code needs and
// doomgeneric's older copies of these files don't have.

#include <stdlib.h>

#include "i_system.h"
#include "ptdoom_compat.h"

// From Chocolate Doom's i_system.c.
void *I_Realloc(void *ptr, size_t size)
{
    void *new_ptr;

    new_ptr = realloc(ptr, size);

    if (size != 0 && new_ptr == NULL)
    {
        I_Error ("I_Realloc: failed on reallocation of %i bytes", size);
    }

    return new_ptr;
}
