#include "CHIDTemperature.h"

#include <CoreFoundation/CoreFoundation.h>
#include <string.h>

// The SDK that ships with Xcode 27 no longer exposes IOHIDEvent.h, so the
// handful of entry points needed here are declared locally. The signatures are
// stable across the IOHID event API.
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service,
                                                 int64_t type,
                                                 int32_t matching,
                                                 int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);

static const int32_t kTemperatureEventType = 15;
static const int32_t kTemperatureLevelField = 15 << 16;
static const int32_t kAppleVendorPage = 0xff00;
static const int32_t kTemperatureUsage = 5;

static int32_t integer_property(IOHIDServiceClientRef service, CFStringRef key) {
    CFTypeRef value = IOHIDServiceClientCopyProperty(service, key);
    if (value == NULL) {
        return -1;
    }
    int32_t result = -1;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &result);
    }
    CFRelease(value);
    return result;
}

static void copy_name(IOHIDServiceClientRef service, char *buffer, size_t capacity) {
    buffer[0] = '\0';
    CFTypeRef value = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
    if (value == NULL) {
        return;
    }
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)value, buffer, (CFIndex)capacity, kCFStringEncodingUTF8);
    }
    CFRelease(value);
}

int fankit_read_temperatures(fankit_temperature *out, int capacity) {
    if (out == NULL || capacity <= 0) {
        return 0;
    }

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        return -1;
    }

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        CFRelease(client);
        return -1;
    }

    int written = 0;
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count && written < capacity; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        if (service == NULL) {
            continue;
        }
        if (integer_property(service, CFSTR("PrimaryUsagePage")) != kAppleVendorPage) {
            continue;
        }
        if (integer_property(service, CFSTR("PrimaryUsage")) != kTemperatureUsage) {
            continue;
        }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kTemperatureEventType, 0, 0);
        if (event == NULL) {
            continue;
        }
        double celsius = IOHIDEventGetFloatValue(event, kTemperatureLevelField);
        CFRelease(event);

        // Calibration channels report values far outside any real die temperature.
        if (!(celsius > -20.0 && celsius < 150.0)) {
            continue;
        }

        copy_name(service, out[written].name, sizeof(out[written].name));
        out[written].celsius = celsius;
        written++;
    }

    CFRelease(services);
    CFRelease(client);
    return written;
}
