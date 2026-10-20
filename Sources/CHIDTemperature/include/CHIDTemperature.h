#ifndef FANKIT_HID_TEMP_H
#define FANKIT_HID_TEMP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One temperature sensor published by the system.
typedef struct {
    char name[128];
    double celsius;
} fankit_temperature;

/// Reads every temperature sensor exposed over HID.
///
/// Writes at most `capacity` entries into `out` and returns the number written,
/// or -1 when the HID event system is unavailable.
int fankit_read_temperatures(fankit_temperature *out, int capacity);

#ifdef __cplusplus
}
#endif

#endif /* FANKIT_HID_TEMP_H */
