#ifndef MELONDS_BRIDGE_H
#define MELONDS_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Lifecycle
bool melonds_init(const char* dataDir);
void melonds_deinit(void);
bool melonds_load_rom(const uint8_t* romData, uint32_t romSize,
                      const uint8_t* sramData, uint32_t sramSize);
void melonds_unload_rom(void);

// Emulation
void melonds_run_frame(void);
void melonds_pause(void);
void melonds_resume(void);
void melonds_reset(void);
bool melonds_is_running(void);

// Framebuffers - returns pointers to 256*192 BGRA8 pixel arrays
// topBuffer = top DS screen, bottomBuffer = bottom DS screen
void melonds_get_framebuffers(const uint32_t** topBuffer,
                              const uint32_t** bottomBuffer);

// Input
// mask is 12-bit: bits 0-11 = A,B,Select,Start,Right,Left,Up,Down,R,L,X,Y
// bit=1 means NOT pressed (NDS hardware convention)
void melonds_set_key_mask(uint32_t mask);
void melonds_touch_screen(uint16_t x, uint16_t y);
void melonds_release_screen(void);

// Audio - reads interleaved stereo s16 PCM at 32768 Hz
// Returns number of samples actually read
int melonds_audio_read(int16_t* buffer, int maxSamples);

// Save states
bool melonds_save_state(const char* path);
bool melonds_load_state(const char* path);
// Serializes to caller-owned memory. Returns the required byte count; pass a
// null buffer (or a buffer that is too small) to query the size.
uint32_t melonds_save_state_to_buffer(uint8_t* outData, uint32_t bufferSize);
bool melonds_load_state_from_buffer(const uint8_t* data, uint32_t size);

// Determinism diagnostics used by the two-phone lockstep prototype.
uint64_t melonds_state_hash(void);
uint64_t melonds_top_framebuffer_hash(void);
uint64_t melonds_bottom_framebuffer_hash(void);

// Save RAM - returns current SRAM data and size
uint32_t melonds_get_sram_size(void);
bool melonds_get_sram(uint8_t* outData, uint32_t bufferSize);

#ifdef __cplusplus
}
#endif

#endif // MELONDS_BRIDGE_H
