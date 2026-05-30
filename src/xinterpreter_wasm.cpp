/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#include <iostream>
#include <string>
#include <sstream>
#include <unordered_set>
#include <unordered_map>
#include <stdexcept>

#ifdef __EMSCRIPTEN__
#include <emscripten/stack.h>
#include <emscripten/emscripten.h>
#endif

#include "xeus-lean/xinterpreter_wasm.hpp"
#include "xeus/xhelper.hpp"

#include <lean/lean.h>

namespace xeus_lean
{

// ---------------------------------------------------------------------------
// Rich-display marker parsing
//
// Lean cells emit MIME-typed payloads via Display.html/latex/md/svg/json.
// Each payload is encoded as:
//
//     \x1bMIME:<mime-type>\x1e<content>\x1b/MIME\x1e
//
// where \x1b is ESC (0x1B) and \x1e is RS (0x1E). ESC does not appear in
// ordinary Lean output, so it is safe as a sentinel. The content may span
// multiple lines.
//
// `extract_mime_payloads` walks `text` and pulls out every well-formed
// payload, accumulating them into `bundle` (a JSON object keyed by mime
// type). Anything outside payloads is appended to `plain_out` so we don't
// drop ordinary `IO.println` output.
//
// If the same mime type appears more than once in a single cell, later
// payloads overwrite earlier ones — this matches how Jupyter renders a
// single display_data message: one bundle, one entry per mime type.
// ---------------------------------------------------------------------------
static void extract_mime_payloads(const std::string& text,
                                  nl::json& bundle,
                                  std::string& plain_out)
{
    static const std::string OPEN_PREFIX = "\x1b" "MIME:";
    static const std::string CLOSE_MARK  = "\x1b" "/MIME" "\x1e";
    static const char RS = '\x1e';

    std::size_t cursor = 0;
    while (cursor < text.size()) {
        std::size_t open = text.find(OPEN_PREFIX, cursor);
        if (open == std::string::npos) {
            plain_out.append(text, cursor, std::string::npos);
            return;
        }
        // Anything before the opening marker is plain text.
        plain_out.append(text, cursor, open - cursor);

        std::size_t mime_start = open + OPEN_PREFIX.size();
        std::size_t rs_pos = text.find(RS, mime_start);
        if (rs_pos == std::string::npos) {
            // Malformed marker — emit the rest as plain text and stop.
            plain_out.append(text, open, std::string::npos);
            return;
        }
        std::string mime_type = text.substr(mime_start, rs_pos - mime_start);

        std::size_t content_start = rs_pos + 1;
        std::size_t close_pos = text.find(CLOSE_MARK, content_start);
        if (close_pos == std::string::npos) {
            // Missing close marker — bail out as plain text.
            plain_out.append(text, open, std::string::npos);
            return;
        }
        std::string content = text.substr(content_start, close_pos - content_start);

        bundle[mime_type] = content;
        cursor = close_pos + CLOSE_MARK.size();
    }
}

// Trim a single trailing newline (added by IO.println) from a payload.
static void rstrip_one_newline(std::string& s)
{
    if (!s.empty() && s.back() == '\n') s.pop_back();
}


// Diagnostic: test that hash tables work in wasm64
static void test_hash_tables() {
    std::cerr << "[WASM] test_hash_tables: sizeof(size_t)=" << sizeof(size_t)
              << " sizeof(void*)=" << sizeof(void*) << std::endl;
    try {
        // Test 1: basic unordered_set<int>
        std::unordered_set<int> s;
        for (int i = 0; i < 10000; i++) s.insert(i);
        std::cerr << "[WASM] test_hash_tables: unordered_set<int> size=" << s.size()
                  << " buckets=" << s.bucket_count() << std::endl;

        // Test 2: unordered_map<void*, void*> (like lean's m_cache)
        std::unordered_map<void*, void*> m;
        for (int i = 0; i < 10000; i++) {
            m[(void*)(uintptr_t)(i * 8)] = (void*)(uintptr_t)i;
        }
        std::cerr << "[WASM] test_hash_tables: unordered_map<void*,void*> size=" << m.size()
                  << " buckets=" << m.bucket_count() << std::endl;

        // Test 3: unordered_set with custom hash (like lean's sharecommon)
        struct ptr_hash {
            std::size_t operator()(void* p) const { return (std::size_t)p; }
        };
        struct ptr_eq {
            std::size_t operator()(void* a, void* b) const { return a == b; }  // returns size_t like lean
        };
        std::unordered_set<void*, ptr_hash, ptr_eq> cs;
        for (int i = 0; i < 10000; i++) {
            cs.insert((void*)(uintptr_t)(i * 16));
        }
        std::cerr << "[WASM] test_hash_tables: custom set size=" << cs.size()
                  << " buckets=" << cs.bucket_count() << std::endl;

        std::cerr << "[WASM] test_hash_tables: ALL PASSED" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[WASM] test_hash_tables: FAILED: " << e.what() << std::endl;
    }
}

// Forward declarations for Lean-exported functions.
// These symbols are provided by the Lean libraries (Init, REPL, etc.)
// compiled to WASM via: .lean -> .c (lake) -> .wasm.o (emcc)
extern "C" {
    // Lean runtime initialization (not in public lean.h)
    void lean_initialize_runtime_module(void);

    // Full Lean initialization: runtime + C++ util/kernel/library modules +
    // Init/Std/Lean module inits. This is REQUIRED to set up C++ global state
    // (name tables, expression caches, etc.) that hash tables depend on.
    // Without this, processHeader triggers __next_prime overflow in libc++.
    void lean_initialize(void);

    // REPL module initialization (not covered by lean_initialize)
    // Note: Lean 4 compiler erases the IO world token from generated C code.
    // These functions take only `builtin`, not `(builtin, world)`.
    lean_object* initialize_xeus_x2dlean_REPL(uint8_t builtin);
    lean_object* initialize_xeus_x2dlean_REPL_Main(uint8_t builtin);
    lean_object* initialize_xeus_x2dlean_WasmRepl(uint8_t builtin);

    // Exported from src/WasmRepl.lean via @[export]
    // World token is erased — these match the actual signatures in WasmRepl.c
    lean_object* lean_wasm_repl_init();
    lean_object* lean_wasm_repl_create_state();
    lean_object* lean_wasm_repl_execute(lean_object* state_ref,
                                        lean_object* code,
                                        uint32_t env_id,
                                        uint8_t has_env);
    lean_object* lean_wasm_repl_complete(lean_object* state_ref,
                                         lean_object* prefix_str,
                                         uint32_t env_id,
                                         uint8_t has_env);
}

interpreter::interpreter()
    : m_initialized(false)
    , m_current_env(-1)
    , m_repl_state(nullptr)
{
}

interpreter::~interpreter()
{
    if (m_repl_state) {
        lean_dec(static_cast<lean_object*>(m_repl_state));
        m_repl_state = nullptr;
    }
}

bool interpreter::initialize_lean_runtime()
{
    if (m_initialized) return true;

    try {
        // Initialize Lean runtime + task manager (0 workers for single-threaded WASM)
        lean_initialize_runtime_module();
        lean_init_task_manager_using(0);

        // Full Lean initialization: C++ util/kernel/library modules + Init/Std/Lean.
        // This sets up critical C++ global state (name hash tables, expression caches,
        // type checker state) that must be initialized before processHeader runs.
        // Using lean_initialize() instead of bare initialize_Init(1) matches
        // the working test_wasm_node initialization sequence.
        lean_initialize();

        // Initialize REPL modules (not covered by lean_initialize)
        lean_object* res;

        res = initialize_xeus_x2dlean_REPL(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to initialize REPL module" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_dec(res);

        res = initialize_xeus_x2dlean_REPL_Main(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to initialize REPL.Main module" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_dec(res);

        res = initialize_xeus_x2dlean_WasmRepl(1);
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to initialize WasmRepl module" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_dec(res);

        lean_io_mark_end_initialization();

        // Initialize search path
        res = lean_wasm_repl_init();
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to initialize REPL" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_dec(res);

        // Create REPL state (IO.Ref State)
        res = lean_wasm_repl_create_state();
        if (lean_io_result_is_error(res)) {
            std::cerr << "[WASM] Failed to create REPL state" << std::endl;
            lean_dec(res);
            return false;
        }
        lean_object* state_ref = lean_io_result_get_value(res);
        lean_inc(state_ref);
        m_repl_state = state_ref;
        lean_dec(res);

        m_initialized = true;
        std::cerr << "[WASM] Lean runtime initialized successfully" << std::endl;
        return true;

    } catch (const std::exception& e) {
        std::cerr << "[WASM] Exception during initialization: " << e.what() << std::endl;
        return false;
    }
}

std::string interpreter::call_lean_repl(const std::string& code, int env)
{
    std::cerr << "[WASM] call_lean_repl: ENTER code='" << code.substr(0, 50) << "' env=" << env << std::endl;

    if (!m_repl_state) {
        std::cerr << "[WASM] call_lean_repl: REPL not initialized!" << std::endl;
        return "{\"message\": \"REPL not initialized\"}";
    }

    std::cerr << "[WASM] call_lean_repl: creating string object" << std::endl;
    lean_object* code_obj = lean_mk_string(code.c_str());

    std::cerr << "[WASM] call_lean_repl: preparing state_ref" << std::endl;
    lean_object* state_ref = static_cast<lean_object*>(m_repl_state);
    lean_inc(state_ref);

    uint8_t has_env = (env >= 0) ? 1 : 0;
    uint32_t env_id = (env >= 0) ? static_cast<uint32_t>(env) : 0;
    std::cerr << "[WASM] call_lean_repl: calling lean_wasm_repl_execute (has_env=" << (int)has_env << " env_id=" << env_id << ")" << std::endl;

    lean_object* res;
    try {
        res = lean_wasm_repl_execute(state_ref, code_obj, env_id, has_env);
    } catch (const std::exception& e) {
        std::cerr << "[WASM] call_lean_repl: C++ EXCEPTION: " << e.what() << std::endl;
        return "{\"error\": \"C++ exception: " + std::string(e.what()) + "\"}";
    }

    std::cerr << "[WASM] call_lean_repl: lean_wasm_repl_execute returned" << std::endl;

    if (lean_io_result_is_error(res)) {
        std::cerr << "[WASM] call_lean_repl: execution returned error" << std::endl;
        lean_io_result_show_error(res);
        lean_dec(res);
        return "{\"error\": \"Lean REPL execution failed\"}";
    }

    lean_object* result = lean_io_result_get_value(res);
    const char* result_str = lean_string_cstr(result);
    std::string output = result_str ? result_str : "";
    std::cerr << "[WASM] call_lean_repl: result='" << output.substr(0, 200) << "'" << std::endl;
    lean_dec(res);

    return output;
}

void interpreter::configure_impl()
{
    std::cerr << "[WASM] configure_impl: ENTER" << std::endl;
    // Olean loading used to live here as an embedded EM_ASM block
    // that fetched `manifest.json` (v1, one entry per file) over
    // synchronous XMLHttpRequest.  Synchronous XHR fails silently
    // from inside a Web Worker on JupyterLite's service-worker
    // setup, so the loader was already a no-op in production —
    // it just spammed 404s for `manifest.json` at /xeus/wasm-host
    // / extensions/@jupyterlite/xeus-extension/ etc.
    //
    // The real loader is now in src/post.js: async fetch of
    // `manifest-v2.json` + per-module tarballs, with an IndexedDB
    // cache.  That runs in `Module.preRun` and blocks WASM main()
    // via `addRunDependency`, so by the time we get here the VFS
    // already has every Init/Std/Lean/Sparkle/Hesper olean.
    test_hash_tables();
    initialize_lean_runtime();
    std::cerr << "[WASM] configure_impl: EXIT" << std::endl;
}

#ifdef __EMSCRIPTEN__
// Fire-and-forget: kicks Module.loadManifestAsync() and returns
// without waiting.  We can't await — see CMakeLists.txt for why
// ASYNCIFY=1 (binaryen + memory64) and ASYNCIFY=2 (JSPI + xeus
// std::function dispatch) both fail.  The Promise is stored on
// Module.__lastLoadPromise so callers (or future probes) can poll
// settlement state; we just print progress via console.log and
// rely on the user to wait before issuing the next cell.
EM_JS(void, xlean_load_manifest_kick, (const char* name), {
    // -sMEMORY64=1 passes pointers as JS BigInt; UTF8ToString takes a
    // plain number, so we have to narrow first.
    var n = UTF8ToString(typeof name === 'bigint' ? Number(name) : name);
    Module.__loadProgressQueue = Module.__loadProgressQueue || [];
    Module.__loadProgressQueue.length = 0;
    Module.__loadDone = 0;        // 0 = running, 1 = ok, 2 = failed
    Module.__loadFailMsg = "";
    if (typeof Module.loadManifestAsync !== "function") {
        Module.__loadProgressQueue.push('[%load] Module.loadManifestAsync missing\n');
        Module.__loadDone = 2;
        Module.__loadFailMsg = 'loader missing';
        return;
    }
    Module.loadManifestAsync(n, {
        onProgress: function (stage, info) {
            var line = '[%load ' + n + '] ' + stage;
            if (info && info.name) line += ' ' + info.name;
            Module.__loadProgressQueue.push(line + '\n');
        },
    }).then(function (r) {
        Module.__loadProgressQueue.push('[%load ' + n + '] done: ' + r.written + ' files\n');
        Module.__loadDone = 1;
    }, function (e) {
        Module.__loadProgressQueue.push('[%load ' + n + '] failed: ' + String(e) + '\n');
        Module.__loadDone = 2;
        Module.__loadFailMsg = String(e);
    });
});

// Drain one progress line as a malloc'd C string (caller frees), or
// null when the queue is empty.
EM_JS(char*, xlean_load_drain, (void), {
    var q = Module.__loadProgressQueue;
    if (!q || q.length === 0) return 0;
    var line = q.shift();
    var len = lengthBytesUTF8(line) + 1;
    var ptr = _malloc(len);
    stringToUTF8(line, ptr, len);
    return ptr;
});

// 0 = still running, 1 = success, 2 = failed.
EM_JS(int, xlean_load_status, (void), {
    return Module.__loadDone || 0;
});

// Caller frees the returned string; null when no error message.
EM_JS(char*, xlean_load_fail_msg, (void), {
    var s = Module.__loadFailMsg || '';
    if (!s) return 0;
    var len = lengthBytesUTF8(s) + 1;
    var ptr = _malloc(len);
    stringToUTF8(s, ptr, len);
    return ptr;
});
#endif

#ifdef __EMSCRIPTEN__
// Per-`%load` poll state.  Lives on the heap from the moment the
// magic kicks off until the JS-side Promise settles, at which point
// poll_load_progress() deletes it.
struct LoadCtx {
    interpreter* self;
    xeus::xinterpreter::send_reply_callback cb;
    std::string name;
};

static void poll_load_progress(void* arg)
{
    auto* c = static_cast<LoadCtx*>(arg);

    // Drain whatever the JS side has queued since the last tick.
    while (true) {
        char* line = xlean_load_drain();
        if (!line) break;
        c->self->publish_stream("stdout", std::string(line));
        std::free(line);
    }

    int st = xlean_load_status();
    if (st == 0) {
        emscripten_async_call(&poll_load_progress, arg, 100);
        return;
    }
    if (st == 1) {
        c->cb(xeus::create_successful_reply());
    } else {
        char* msg = xlean_load_fail_msg();
        std::string err = msg ? msg : "load failed";
        if (msg) std::free(msg);
        c->self->publish_execution_error("LoadError", err, {err});
        c->cb(xeus::create_error_reply(err, "LoadError", nl::json::array()));
    }
    delete c;
}
#endif

// Detect a single-line `%load <name>` magic.  Returns the bundle
// name if the entire (trimmed) cell body matches, otherwise "".
static std::string detect_load_magic(const std::string& code)
{
    // Trim leading whitespace.
    size_t start = code.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    if (code.compare(start, 6, "%load ") != 0) return "";
    // Take the rest of the first line as the argument.
    size_t arg_start = start + 6;
    size_t nl = code.find('\n', arg_start);
    std::string arg = (nl == std::string::npos)
        ? code.substr(arg_start)
        : code.substr(arg_start, nl - arg_start);
    // Strip trailing whitespace.
    size_t end = arg.find_last_not_of(" \t\r");
    if (end == std::string::npos) return "";
    arg = arg.substr(0, end + 1);
    // The rest of the cell (after the first line) must be blank — we
    // don't support mixing %load and Lean code in the same cell.
    if (nl != std::string::npos) {
        std::string rest = code.substr(nl + 1);
        if (rest.find_first_not_of(" \t\r\n") != std::string::npos) {
            // There is non-blank content after the magic.  Treat the
            // whole cell as Lean code rather than silently dropping it.
            return "";
        }
    }
    return arg;
}

void interpreter::execute_request_impl(send_reply_callback cb,
                                        int execution_counter,
                                        const std::string& code,
                                        xeus::execute_request_config /*config*/,
                                        nl::json /*user_expressions*/)
{
    std::cerr << "[WASM] execute_request_impl: ENTER (code=" << code.substr(0, 50) << ")" << std::endl;
    if (!m_initialized) {
        if (!initialize_lean_runtime()) {
            publish_execution_error("LeanError", "Failed to initialize Lean runtime", {});
            cb(xeus::create_error_reply("Failed to initialize Lean runtime", "LeanError", nl::json::array()));
            return;
        }
    }

    // Intercept `%load <bundle>` before handing off to the Lean REPL.
    // This kicks an async JS download+unpack of an on-demand olean
    // bundle (e.g. Mathlib) into /lib/lean/ so a subsequent cell can
    // `import` from it.
    //
    // The kick itself is fire-and-forget (we can't suspend the kernel
    // here — see CMakeLists.txt for the ASYNCIFY=1/JSPI failure modes),
    // but we still want the cell to *look* live: per-chunk progress in
    // its stdout, and a single `cb()` call only after the whole bundle
    // finishes (so the notebook keeps showing "running" until then).
    // We achieve that by setting up an emscripten_async_call poll that
    // drains the JS-side progress queue every ~100 ms, forwarding lines
    // via publish_stream(), and finally calling the saved cb when
    // xlean_load_status() flips to 1 or 2.
    std::string load_name = detect_load_magic(code);
    if (!load_name.empty()) {
#ifdef __EMSCRIPTEN__
        publish_stream("stdout", "Loading bundle '" + load_name + "'...\n");
        xlean_load_manifest_kick(load_name.c_str());
        auto* ctx = new LoadCtx{this, std::move(cb), load_name};
        emscripten_async_call(&poll_load_progress, ctx, 100);
        return;
#else
        std::string err = "%load is only supported in the WASM build";
        publish_execution_error("LoadError", err, {err});
        cb(xeus::create_error_reply(err, "LoadError", nl::json::array()));
        return;
#endif
    }

    // Call the Lean REPL
    std::string result_json = call_lean_repl(code, m_current_env);

    // Parse the result
    try {
        auto result = nl::json::parse(result_json);

        if (result.contains("error")) {
            std::string error_msg = result["error"].get<std::string>();
            publish_execution_error("LeanError", error_msg, {error_msg});
            cb(xeus::create_error_reply(error_msg, "LeanError", nl::json::array()));
            return;
        }

        // Update environment
        if (result.contains("env")) {
            m_current_env = result["env"].get<int>();
        }

        // Format output. Render messages the same way Lean's compiler
        // does — `<line>:<col>: <severity>: <data>` for warnings/errors,
        // and the bare data for info (which is what `#eval` / `#check`
        // emit). This matches the native kernel's renderer in
        // XeusKernel.lean and gives users a scannable trace instead of
        // the raw JSON envelope.
        nl::json pub_data;
        nl::json mime_bundle = nl::json::object();
        if (result.contains("messages")) {
            auto& messages = result["messages"];
            std::string rendered;

            auto append_line = [&rendered](const std::string& s) {
                if (!rendered.empty()) rendered += "\n";
                rendered += s;
            };

            for (auto& msg : messages) {
                std::string severity = msg.value("severity", "info");
                std::string data = msg.value("data", "");
                if (severity == "info") {
                    // Pull MIME-typed payloads (Display.html, etc.) out
                    // of info messages. Whatever is left is plain text.
                    std::string plain;
                    extract_mime_payloads(data, mime_bundle, plain);
                    if (!plain.empty()) append_line(plain);
                } else {
                    int line = 0, col = 0;
                    if (msg.contains("pos") && msg["pos"].is_object()) {
                        line = msg["pos"].value("line", 0);
                        col  = msg["pos"].value("column", 0);
                    }
                    append_line(std::to_string(line) + ":"
                                + std::to_string(col) + ": "
                                + severity + ": " + data);
                }
            }

            if (!rendered.empty()) {
                pub_data["text/plain"] = rendered;
            }
        }

        // Publish rich-display payloads first so they appear above the
        // plain-text result in the notebook (matches IPython ordering).
        if (!mime_bundle.empty()) {
            // Strip the trailing newline IO.println adds — important for
            // text/latex where MathJax dislikes the extra whitespace.
            for (auto it = mime_bundle.begin(); it != mime_bundle.end(); ++it) {
                if (it->is_string()) {
                    std::string v = it->get<std::string>();
                    rstrip_one_newline(v);
                    *it = v;
                }
            }
            // Always include a text/plain fallback so non-rich frontends
            // (and the notebook's text-only view) still show something.
            if (!mime_bundle.contains("text/plain")) {
                mime_bundle["text/plain"] = "[rich display]";
            }
            publish_execution_result(execution_counter, std::move(mime_bundle), nl::json::object());
        } else if (!pub_data.empty()) {
            publish_execution_result(execution_counter, std::move(pub_data), nl::json::object());
        }

        cb(xeus::create_successful_reply());

    } catch (const nl::json::parse_error&) {
        // Not JSON, treat as plain text output
        if (!result_json.empty()) {
            nl::json pub_data;
            pub_data["text/plain"] = result_json;
            publish_execution_result(execution_counter, std::move(pub_data), nl::json::object());
        }
        cb(xeus::create_successful_reply());
    }
}

nl::json interpreter::complete_request_impl(const std::string& code,
                                             int cursor_pos)
{
    std::cerr << "[WASM] complete_request_impl: ENTER (cursor=" << cursor_pos << ")" << std::endl;
    if (!m_initialized || !m_repl_state) {
        return xeus::create_complete_reply({}, cursor_pos, cursor_pos);
    }

    // Extract the token before the cursor for prefix matching.
    // Walk backwards from cursor_pos to find the start of the
    // identifier (letters, digits, dots, underscores, #).
    int start = cursor_pos;
    while (start > 0) {
        char c = code[start - 1];
        if (std::isalnum(c) || c == '.' || c == '_' || c == '#' || c == '\'') {
            start--;
        } else {
            break;
        }
    }
    std::string prefix = code.substr(start, cursor_pos - start);
    std::cerr << "[WASM] complete_request_impl: prefix='" << prefix << "'" << std::endl;

    if (prefix.empty()) {
        return xeus::create_complete_reply({}, cursor_pos, cursor_pos);
    }

    // Call Lean's complete function
    lean_object* prefix_obj = lean_mk_string(prefix.c_str());
    lean_object* state_ref = static_cast<lean_object*>(m_repl_state);
    lean_inc(state_ref);

    uint8_t has_env = (m_current_env >= 0) ? 1 : 0;
    uint32_t env_id = (m_current_env >= 0) ? static_cast<uint32_t>(m_current_env) : 0;

    lean_object* res = lean_wasm_repl_complete(state_ref, prefix_obj, env_id, has_env);

    if (lean_io_result_is_error(res)) {
        std::cerr << "[WASM] complete_request_impl: Lean error" << std::endl;
        lean_dec(res);
        return xeus::create_complete_reply({}, cursor_pos, cursor_pos);
    }

    lean_object* result = lean_io_result_get_value(res);
    const char* result_str = lean_string_cstr(result);
    std::string json_str = result_str ? result_str : "";
    lean_dec(res);

    std::cerr << "[WASM] complete_request_impl: result='" << json_str.substr(0, 200) << "'" << std::endl;

    // Parse the JSON response from Lean
    nl::json matches_list = nl::json::array();
    try {
        auto parsed = nl::json::parse(json_str);
        if (parsed.contains("matches")) {
            matches_list = parsed["matches"];
        }
    } catch (...) {
        std::cerr << "[WASM] complete_request_impl: JSON parse error" << std::endl;
    }

    return xeus::create_complete_reply(matches_list, start, cursor_pos);
}

nl::json interpreter::inspect_request_impl(const std::string& /*code*/,
                                            int /*cursor_pos*/,
                                            int /*detail_level*/)
{
    std::cerr << "[WASM] inspect_request_impl: ENTER" << std::endl;
    return xeus::create_inspect_reply(false);
}

nl::json interpreter::is_complete_request_impl(const std::string& /*code*/)
{
    std::cerr << "[WASM] is_complete_request_impl: ENTER" << std::endl;
    return xeus::create_is_complete_reply("complete");
}

nl::json interpreter::kernel_info_request_impl()
{
    std::cerr << "[WASM] kernel_info_request_impl: ENTER" << std::endl;
    return xeus::create_info_reply(
        "",                              // protocol version (auto-filled)
        "xlean",                         // implementation
        "0.1.0",                         // implementation_version
        "lean",                          // language name
        "4.0",                           // language version
        "text/x-lean4",                  // mimetype
        ".lean",                         // file_extension
        "haskell",                       // pygments_lexer (Lean 4 ~ Haskell)
        "haskell",                       // codemirror_mode (best available match)
        "Lean 4 Jupyter Kernel (WASM)"   // banner
    );
}

void interpreter::shutdown_request_impl()
{
    std::cerr << "[WASM] shutdown_request_impl: ENTER" << std::endl;
    if (m_repl_state) {
        lean_dec(static_cast<lean_object*>(m_repl_state));
        m_repl_state = nullptr;
    }
    m_initialized = false;
}

}  // namespace xeus_lean
