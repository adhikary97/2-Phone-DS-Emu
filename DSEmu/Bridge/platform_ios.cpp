// iOS implementation of melonDS::Platform namespace
// Provides file I/O, threading, and other platform services

#include "Platform.h"
#include "types.h"

#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <string>
#include <functional>
#include <pthread.h>
#include <dispatch/dispatch.h>
#include <unistd.h>
#include <sys/time.h>
#include <os/log.h>

// The data directory is set by the Swift layer before initialization
static std::string s_dataDir;

extern "C" void platform_set_data_dir(const char* dir)
{
    s_dataDir = dir ? dir : "";
}

namespace melonDS::Platform
{

// --- Stop Signal ---

void SignalStop(StopReason reason, void* userdata)
{
    Log(LogLevel::Info, "melonDS: SignalStop reason=%d\n", (int)reason);
}

// --- File I/O ---

struct FileHandle
{
    FILE* file;
    FileHandle(FILE* f) : file(f) {}
};

static const char* FileModeString(FileMode mode)
{
    bool read  = mode & FileMode::Read;
    bool write = mode & FileMode::Write;
    bool preserve = mode & FileMode::Preserve;
    bool text  = mode & FileMode::Text;
    bool append = mode & FileMode::Append;

    if (append) return text ? "a" : "ab";
    if (read && write) return text ? (preserve ? "r+" : "w+") : (preserve ? "r+b" : "w+b");
    if (write) return text ? "w" : "wb";
    return text ? "r" : "rb";
}

std::string GetLocalFilePath(const std::string& filename)
{
    return s_dataDir + "/" + filename;
}

FileHandle* OpenFile(const std::string& path, FileMode mode)
{
    if (path.empty()) return nullptr;

    bool noCreate = mode & FileMode::NoCreate;
    if (noCreate && (mode & FileMode::Write)) {
        FILE* test = fopen(path.c_str(), "rb");
        if (!test) return nullptr;
        fclose(test);
    }

    FILE* f = fopen(path.c_str(), FileModeString(mode));
    if (!f) return nullptr;
    return new FileHandle(f);
}

FileHandle* OpenLocalFile(const std::string& path, FileMode mode)
{
    std::string fullPath = s_dataDir + "/" + path;
    return OpenFile(fullPath, mode);
}

bool FileExists(const std::string& name)
{
    FILE* f = fopen(name.c_str(), "rb");
    if (f) { fclose(f); return true; }
    return false;
}

bool LocalFileExists(const std::string& name)
{
    return FileExists(s_dataDir + "/" + name);
}

bool CheckFileWritable(const std::string& filepath)
{
    FILE* f = fopen(filepath.c_str(), "a");
    if (f) { fclose(f); return true; }
    return false;
}

bool CheckLocalFileWritable(const std::string& filepath)
{
    return CheckFileWritable(s_dataDir + "/" + filepath);
}

bool CloseFile(FileHandle* file)
{
    if (!file) return false;
    int ret = fclose(file->file);
    delete file;
    return ret == 0;
}

bool IsEndOfFile(FileHandle* file)
{
    return file && feof(file->file);
}

bool FileReadLine(char* str, int count, FileHandle* file)
{
    if (!file) return false;
    return fgets(str, count, file->file) != nullptr;
}

bool FileSeek(FileHandle* file, s64 offset, FileSeekOrigin origin)
{
    if (!file) return false;
    int whence;
    switch (origin) {
        case FileSeekOrigin::Start:   whence = SEEK_SET; break;
        case FileSeekOrigin::Current: whence = SEEK_CUR; break;
        case FileSeekOrigin::End:     whence = SEEK_END; break;
        default: return false;
    }
    return fseeko(file->file, offset, whence) == 0;
}

void FileRewind(FileHandle* file)
{
    if (file) rewind(file->file);
}

u64 FileRead(void* data, u64 size, u64 count, FileHandle* file)
{
    if (!file) return 0;
    return fread(data, size, count, file->file);
}

bool FileFlush(FileHandle* file)
{
    if (!file) return false;
    return fflush(file->file) == 0;
}

u64 FileWrite(const void* data, u64 size, u64 count, FileHandle* file)
{
    if (!file) return 0;
    return fwrite(data, size, count, file->file);
}

u64 FileWriteFormatted(FileHandle* file, const char* fmt, ...)
{
    if (!file) return 0;
    va_list args;
    va_start(args, fmt);
    u64 ret = vfprintf(file->file, fmt, args);
    va_end(args);
    return ret;
}

u64 FileLength(FileHandle* file)
{
    if (!file) return 0;
    long pos = ftell(file->file);
    fseek(file->file, 0, SEEK_END);
    long len = ftell(file->file);
    fseek(file->file, pos, SEEK_SET);
    return (u64)len;
}

// --- Logging ---

void Log(LogLevel level, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    os_log_type_t type;
    switch (level) {
        case LogLevel::Debug: type = OS_LOG_TYPE_DEBUG; break;
        case LogLevel::Info:  type = OS_LOG_TYPE_INFO; break;
        case LogLevel::Warn:  type = OS_LOG_TYPE_DEFAULT; break;
        case LogLevel::Error: type = OS_LOG_TYPE_ERROR; break;
        default: type = OS_LOG_TYPE_DEFAULT; break;
    }
    os_log_with_type(OS_LOG_DEFAULT, type, "%{public}s", buf);
}

// --- Threading ---

struct Thread
{
    pthread_t handle;
    std::function<void()> func;
};

static void* thread_entry(void* arg)
{
    Thread* t = static_cast<Thread*>(arg);
    t->func();
    return nullptr;
}

Thread* Thread_Create(std::function<void()> func)
{
    Thread* t = new Thread();
    t->func = std::move(func);
    pthread_create(&t->handle, nullptr, thread_entry, t);
    return t;
}

void Thread_Free(Thread* thread)
{
    if (!thread) return;
    delete thread;
}

void Thread_Wait(Thread* thread)
{
    if (!thread) return;
    pthread_join(thread->handle, nullptr);
}

// --- Semaphore ---

struct Semaphore
{
    dispatch_semaphore_t sema;
};

Semaphore* Semaphore_Create()
{
    Semaphore* s = new Semaphore();
    s->sema = dispatch_semaphore_create(0);
    return s;
}

void Semaphore_Free(Semaphore* sema)
{
    if (!sema) return;
    delete sema;
}

void Semaphore_Reset(Semaphore* sema)
{
    if (!sema) return;
    // Drain any pending signals
    while (dispatch_semaphore_wait(sema->sema, DISPATCH_TIME_NOW) == 0) {}
}

void Semaphore_Wait(Semaphore* sema)
{
    if (!sema) return;
    dispatch_semaphore_wait(sema->sema, DISPATCH_TIME_FOREVER);
}

bool Semaphore_TryWait(Semaphore* sema, int timeout_ms)
{
    if (!sema) return false;
    dispatch_time_t timeout = timeout_ms > 0
        ? dispatch_time(DISPATCH_TIME_NOW, (int64_t)timeout_ms * NSEC_PER_MSEC)
        : DISPATCH_TIME_NOW;
    return dispatch_semaphore_wait(sema->sema, timeout) == 0;
}

void Semaphore_Post(Semaphore* sema, int count)
{
    if (!sema) return;
    for (int i = 0; i < count; i++)
        dispatch_semaphore_signal(sema->sema);
}

// --- Mutex ---

struct Mutex
{
    pthread_mutex_t handle;
};

Mutex* Mutex_Create()
{
    Mutex* m = new Mutex();
    pthread_mutex_init(&m->handle, nullptr);
    return m;
}

void Mutex_Free(Mutex* mutex)
{
    if (!mutex) return;
    pthread_mutex_destroy(&mutex->handle);
    delete mutex;
}

void Mutex_Lock(Mutex* mutex)
{
    if (mutex) pthread_mutex_lock(&mutex->handle);
}

void Mutex_Unlock(Mutex* mutex)
{
    if (mutex) pthread_mutex_unlock(&mutex->handle);
}

bool Mutex_TryLock(Mutex* mutex)
{
    if (!mutex) return false;
    return pthread_mutex_trylock(&mutex->handle) == 0;
}

// --- Timing ---

void Sleep(u64 usecs)
{
    usleep((useconds_t)usecs);
}

u64 GetMSCount()
{
    struct timeval tv;
    gettimeofday(&tv, nullptr);
    return (u64)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

u64 GetUSCount()
{
    struct timeval tv;
    gettimeofday(&tv, nullptr);
    return (u64)tv.tv_sec * 1000000 + tv.tv_usec;
}

// --- Save callbacks ---

void WriteNDSSave(const u8* savedata, u32 savelen, u32 writeoffset, u32 writelen, void* userdata)
{
    // Save to Documents/save.sav
    std::string path = s_dataDir + "/save.sav";
    FILE* f = fopen(path.c_str(), "wb");
    if (f) {
        fwrite(savedata, 1, savelen, f);
        fclose(f);
    }
}

void WriteGBASave(const u8* savedata, u32 savelen, u32 writeoffset, u32 writelen, void* userdata)
{
    // Not needed for DS emulation
}

void WriteFirmware(const Firmware& firmware, u32 writeoffset, u32 writelen, void* userdata)
{
    // Using generated firmware, no need to persist
}

void WriteDateTime(int year, int month, int day, int hour, int minute, int second, void* userdata)
{
    // No-op
}

// --- Multiplayer (stubs) ---

void MP_Begin(void* userdata) {}
void MP_End(void* userdata) {}
int MP_SendPacket(u8* data, int len, u64 timestamp, void* userdata) { return 0; }
int MP_RecvPacket(u8* data, u64* timestamp, void* userdata) { return 0; }
int MP_SendCmd(u8* data, int len, u64 timestamp, void* userdata) { return 0; }
int MP_SendReply(u8* data, int len, u64 timestamp, u16 aid, void* userdata) { return 0; }
int MP_SendAck(u8* data, int len, u64 timestamp, void* userdata) { return 0; }
int MP_RecvHostPacket(u8* data, u64* timestamp, void* userdata) { return 0; }
u16 MP_RecvReplies(u8* data, u64 timestamp, u16 aidmask, void* userdata) { return 0; }

// --- Networking (stubs) ---

int Net_SendPacket(u8* data, int len, void* userdata) { return 0; }
int Net_RecvPacket(u8* data, void* userdata) { return 0; }

// --- Camera (stubs) ---

void Camera_Start(int num, void* userdata) {}
void Camera_Stop(int num, void* userdata) {}
void Camera_CaptureFrame(int num, u32* frame, int width, int height, bool yuv, void* userdata) {}

// --- Addon (stubs) ---

bool Addon_KeyDown(KeyType type, void* userdata) { return false; }
void Addon_RumbleStart(u32 len, void* userdata) {}
void Addon_RumbleStop(void* userdata) {}
float Addon_MotionQuery(MotionQueryType type, void* userdata) { return 0.0f; }

// --- Dynamic Library (stubs) ---

DynamicLibrary* DynamicLibrary_Load(const char* lib) { return nullptr; }
void DynamicLibrary_Unload(DynamicLibrary* lib) {}
void* DynamicLibrary_LoadFunction(DynamicLibrary* lib, const char* name) { return nullptr; }

} // namespace melonDS::Platform
