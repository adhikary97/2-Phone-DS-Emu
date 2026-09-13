#include "melonds_bridge.h"

#include <memory>
#include <string>
#include <cstring>
#include <fstream>

#include "NDS.h"
#include "NDSCart.h"
#include "GPU.h"
#include "SPU.h"
#include "Args.h"
#include "Savestate.h"
#include "GPU3D_Soft.h"
#include "FreeBIOS.h"
#include "SPI_Firmware.h"

static std::unique_ptr<melonDS::NDS> nds = nullptr;
static std::string dataDirectory;
static bool running = false;
static bool paused = false;

static uint64_t fnv1a64(const void* bytes, size_t length)
{
    constexpr uint64_t offsetBasis = 14695981039346656037ULL;
    constexpr uint64_t prime = 1099511628211ULL;
    const auto* cursor = static_cast<const uint8_t*>(bytes);
    uint64_t hash = offsetBasis;
    for (size_t i = 0; i < length; i++) {
        hash ^= cursor[i];
        hash *= prime;
    }
    return hash;
}

extern "C" {

bool melonds_init(const char* dataDir)
{
    if (nds) return false;

    dataDirectory = dataDir ? dataDir : "";

    melonDS::NDSArgs args {};
    // FreeBIOS is already the default
    // SoftRenderer is the default Renderer3D

    // Disable JIT on iOS — shm_open for executable memory is blocked.
    // The interpreter is slower but works without special entitlements.
    // JIT can be re-enabled later with a custom mmap-based allocator.
    args.JIT = std::nullopt;

    nds = std::make_unique<melonDS::NDS>(std::move(args));
    nds->SPU.SetInterpolation(melonDS::AudioInterpolation::None);

    return true;
}

void melonds_deinit(void)
{
    running = false;
    paused = false;
    nds.reset();
}

bool melonds_load_rom(const uint8_t* romData, uint32_t romSize,
                      const uint8_t* sramData, uint32_t sramSize)
{
    if (!nds || !romData || romSize == 0) return false;

    // Copy ROM data into a unique_ptr buffer for melonDS
    auto romBuf = std::make_unique<melonDS::u8[]>(romSize);
    std::memcpy(romBuf.get(), romData, romSize);

    // Parse the ROM
    std::optional<melonDS::NDSCart::NDSCartArgs> cartArgs = std::nullopt;
    if (sramData && sramSize > 0) {
        melonDS::NDSCart::NDSCartArgs ca {};
        ca.SRAM = std::make_unique<melonDS::u8[]>(sramSize);
        std::memcpy(ca.SRAM.get(), sramData, sramSize);
        ca.SRAMLength = sramSize;
        cartArgs = std::move(ca);
    }

    auto cart = melonDS::NDSCart::ParseROM(
        std::move(romBuf), romSize, nds->UserData, std::move(cartArgs));

    if (!cart) return false;

    nds->SetNDSCart(std::move(cart));
    nds->Reset();
    nds->SetupDirectBoot("game.nds");
    nds->Start();

    running = true;
    paused = false;

    return true;
}

void melonds_unload_rom(void)
{
    if (!nds) return;
    running = false;
    paused = false;
    nds->EjectCart();
    nds->Reset();
}

void melonds_run_frame(void)
{
    if (!nds || !running || paused) return;
    nds->RunFrame();
}

void melonds_pause(void)
{
    paused = true;
}

void melonds_resume(void)
{
    paused = false;
}

void melonds_reset(void)
{
    if (!nds) return;
    nds->Reset();
    nds->Start();
}

bool melonds_is_running(void)
{
    return nds && running && !paused;
}

static int frameCount = 0;

void melonds_get_framebuffers(const uint32_t** topBuffer,
                              const uint32_t** bottomBuffer)
{
    if (!nds || !topBuffer || !bottomBuffer) {
        if (topBuffer) *topBuffer = nullptr;
        if (bottomBuffer) *bottomBuffer = nullptr;
        return;
    }

    int frontBuf = nds->GPU.FrontBuffer;
    *topBuffer = nds->GPU.Framebuffer[frontBuf][0].get();
    *bottomBuffer = nds->GPU.Framebuffer[frontBuf][1].get();

    // Debug: log every 60 frames
    frameCount++;
    if (frameCount % 60 == 1) {
        uint32_t topSample = *topBuffer ? (*topBuffer)[128 + 96*256] : 0xDEAD;
        uint32_t botSample = *bottomBuffer ? (*bottomBuffer)[128 + 96*256] : 0xDEAD;
        // Check if any non-white pixel exists in top screen
        int nonWhite = 0;
        if (*topBuffer) {
            for (int i = 0; i < 256*192; i++) {
                if ((*topBuffer)[i] != 0xFFFFFFFF) { nonWhite++; break; }
            }
        }
        printf("Frame %d: frontBuf=%d topPx=0x%08X botPx=0x%08X nonWhite=%d "
               "ARM9pc=0x%08X NumFrames=%u\n",
               frameCount, frontBuf, topSample, botSample, nonWhite,
               nds->ARM9.R[15], nds->NumFrames);
    }
}

void melonds_set_key_mask(uint32_t mask)
{
    if (!nds) return;
    nds->SetKeyMask(mask);
}

void melonds_touch_screen(uint16_t x, uint16_t y)
{
    if (!nds) return;
    nds->TouchScreen(x, y);
}

void melonds_release_screen(void)
{
    if (!nds) return;
    nds->ReleaseScreen();
}

int melonds_audio_read(int16_t* buffer, int maxSamples)
{
    if (!nds || !buffer || maxSamples <= 0) return 0;
    return nds->SPU.ReadOutput(buffer, maxSamples);
}

bool melonds_save_state(const char* path)
{
    if (!nds || !path) return false;

    melonDS::Savestate state;
    nds->DoSavestate(&state);

    if (state.Length() == 0) return false;

    std::ofstream file(path, std::ios::binary);
    if (!file.is_open()) return false;

    file.write(reinterpret_cast<const char*>(state.Buffer()), state.Length());
    return file.good();
}

bool melonds_load_state(const char* path)
{
    if (!nds || !path) return false;

    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) return false;

    auto size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> data(size);
    file.read(reinterpret_cast<char*>(data.data()), size);
    if (!file.good()) return false;

    return melonds_load_state_from_buffer(data.data(), static_cast<uint32_t>(data.size()));
}

uint32_t melonds_save_state_to_buffer(uint8_t* outData, uint32_t bufferSize)
{
    if (!nds) return 0;

    melonDS::Savestate state;
    if (!nds->DoSavestate(&state) || state.Error || state.Length() == 0) return 0;

    const uint32_t required = state.Length();
    if (outData && bufferSize >= required) {
        std::memcpy(outData, state.Buffer(), required);
    }
    return required;
}

bool melonds_load_state_from_buffer(const uint8_t* data, uint32_t size)
{
    if (!nds || !data || size == 0) return false;

    melonDS::Savestate state(const_cast<uint8_t*>(data), size, false);
    return nds->DoSavestate(&state) && !state.Error;
}

uint64_t melonds_state_hash(void)
{
    if (!nds) return 0;

    melonDS::Savestate state;
    if (!nds->DoSavestate(&state) || state.Error || state.Length() == 0) return 0;
    return fnv1a64(state.Buffer(), state.Length());
}

static uint64_t framebufferHash(int screen)
{
    if (!nds) return 0;
    const int frontBuffer = nds->GPU.FrontBuffer;
    const auto* pixels = nds->GPU.Framebuffer[frontBuffer][screen].get();
    if (!pixels) return 0;
    return fnv1a64(pixels, 256 * 192 * sizeof(uint32_t));
}

uint64_t melonds_top_framebuffer_hash(void)
{
    return framebufferHash(0);
}

uint64_t melonds_bottom_framebuffer_hash(void)
{
    return framebufferHash(1);
}

uint32_t melonds_get_sram_size(void)
{
    if (!nds) return 0;
    auto* cart = nds->GetNDSCart();
    if (!cart) return 0;
    return cart->GetSaveMemoryLength();
}

bool melonds_get_sram(uint8_t* outData, uint32_t bufferSize)
{
    if (!nds || !outData) return false;
    auto* cart = nds->GetNDSCart();
    if (!cart) return false;

    uint32_t len = cart->GetSaveMemoryLength();
    if (len == 0 || bufferSize < len) return false;

    const uint8_t* sram = cart->GetSaveMemory();
    if (!sram) return false;

    std::memcpy(outData, sram, len);
    return true;
}

} // extern "C"
