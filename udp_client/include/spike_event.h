#ifndef SPIKE_EVENT_H
#define SPIKE_EVENT_H

#define WAVEFORM_LENGTH 45

#include <array>
#include <cstdint>
#include <cstring>  // Ensure this is included for memset

#pragma pack(push, 1) // Ensure no padding issues
struct SpikeEvent {
    uint8_t channel_id;                      // Channel ID where the spike was detected
    uint32_t package_id;                     // Associated package ID
    uint16_t cycles;                         // Cycles of package IDs since system start
    float waveform[WAVEFORM_LENGTH];         // Waveform of the spike

    // Default constructor
    SpikeEvent() 
        : channel_id(0), package_id(0), cycles(0) {
        memset(waveform, 0, sizeof(waveform));
        for (uint8_t i = 0; i < WAVEFORM_LENGTH; i++) {
            waveform[i] = 0.;
        }
    }
} __attribute__((packed)); // Ensure no padding for raw transmission
#pragma pack(pop)

#endif // SPIKE_EVENT_H

