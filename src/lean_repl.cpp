/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#include "xeus-lean/lean_repl.hpp"

#include <algorithm>
#include <cctype>
#include <sstream>
#include <stdexcept>
#include <cstring>
#include <iostream>

#include <lean/lean.h>

// External C functions from Lean FFI
extern "C" {
lean_object* lean_repl_init(lean_object* unit);
lean_object* lean_repl_execute_cmd(lean_object* handle, lean_object* cmd_json, lean_object* world);
lean_object* lean_repl_free(lean_object* handle, lean_object* world);
void lean_initialize_runtime_module();
void lean_initialize(void);
void lean_init_task_manager();
lean_object* initialize_xeus_x2dlean_ReplFFI(uint8_t builtin);
}

// Note: lean_io_result_is_ok and lean_io_result_get_value are defined in lean.h

using json = nlohmann::json;

namespace xeus_lean {

static bool lean_initialized = false;

LeanRepl::LeanRepl() : m_stdin_fd(-1), m_stdout_fd(-1), m_pid(-1), m_current_env(std::nullopt) {
    std::cerr << "[LeanRepl] Constructor starting..." << std::endl;

    // Initialize Lean runtime if not already done
    if (!lean_initialized) {
        std::cerr << "[LeanRepl] Initializing Lean runtime..." << std::endl;
        lean_initialize();
        std::cerr << "[LeanRepl] lean_initialize() done" << std::endl;
        lean_init_task_manager();
        std::cerr << "[LeanRepl] lean_init_task_manager() done" << std::endl;
        lean_initialize_runtime_module();
        std::cerr << "[LeanRepl] lean_initialize_runtime_module() done" << std::endl;

        // TODO: Module initialization causes segfault - investigate
        // std::cerr << "[LeanRepl] Initializing ReplFFI module..." << std::endl;
        // lean_object* init_res = initialize_xeus_x2dlean_ReplFFI(0);
        // if (!lean_io_result_is_ok(init_res)) {
        //     std::cerr << "[LeanRepl] ReplFFI initialization failed!" << std::endl;
        //     lean_dec(init_res);
        //     throw std::runtime_error("Failed to initialize ReplFFI module");
        // }
        // lean_dec(init_res);
        // std::cerr << "[LeanRepl] ReplFFI module initialized" << std::endl;

        lean_initialized = true;
    }

    std::cerr << "[LeanRepl] Creating unit object..." << std::endl;
    // Initialize the REPL
    lean_object* unit = lean_box(0);
    std::cerr << "[LeanRepl] Calling lean_repl_init..." << std::endl;
    lean_object* init_result = lean_repl_init(unit);
    std::cerr << "[LeanRepl] lean_repl_init returned" << std::endl;

    if (lean_io_result_is_ok(init_result)) {
        std::cerr << "[LeanRepl] Init succeeded, getting handle..." << std::endl;
        m_handle = lean_io_result_get_value(init_result);
        lean_inc(m_handle);  // Increment reference count
        std::cerr << "[LeanRepl] Handle obtained successfully" << std::endl;
    } else {
        std::cerr << "[LeanRepl] Init failed!" << std::endl;
        lean_dec(init_result);
        throw std::runtime_error("Failed to initialize Lean REPL");
    }

    lean_dec(init_result);
    std::cerr << "[LeanRepl] Constructor completed successfully" << std::endl;
}

LeanRepl::~LeanRepl() {
    if (m_handle) {
        lean_object* world = lean_io_mk_world();
        lean_object* free_result = lean_repl_free(m_handle, world);
        lean_dec(free_result);
        lean_dec(m_handle);
    }
}

json LeanRepl::send_command(const json& cmd) {
    std::cerr << "[LeanRepl::send_command] Starting with cmd: " << cmd.dump() << std::endl;
    std::string cmd_str = cmd.dump();

    std::cerr << "[LeanRepl::send_command] Creating Lean string..." << std::endl;
    // Convert C++ string to Lean string
    lean_object* lean_str = lean_mk_string(cmd_str.c_str());
    lean_object* world = lean_io_mk_world();

    std::cerr << "[LeanRepl::send_command] Calling lean_repl_execute_cmd..." << std::endl;
    // Call the Lean FFI function
    lean_object* result = lean_repl_execute_cmd(m_handle, lean_str, world);
    std::cerr << "[LeanRepl::send_command] lean_repl_execute_cmd returned" << std::endl;

    // Check if IO operation succeeded
    if (!lean_io_result_is_ok(result)) {
        std::cerr << "[LeanRepl::send_command] Execution failed" << std::endl;
        lean_dec(result);
        throw std::runtime_error("Lean REPL execution failed");
    }

    std::cerr << "[LeanRepl::send_command] Getting result value..." << std::endl;
    // Get the result value (a Lean string containing JSON)
    lean_object* result_str = lean_io_result_get_value(result);

    // Convert Lean string to C++ string
    const char* c_str = lean_string_cstr(result_str);
    std::string response_str(c_str);
    std::cerr << "[LeanRepl::send_command] Got response: " << response_str << std::endl;

    lean_dec(result);

    std::cerr << "[LeanRepl::send_command] Parsing JSON..." << std::endl;
    // Parse JSON response
    try {
        return json::parse(response_str);
    } catch (const json::parse_error& e) {
        std::cerr << "[LeanRepl::send_command] JSON parse error!" << std::endl;
        throw std::runtime_error("Failed to parse JSON response from Lean REPL: " +
                               std::string(e.what()) + "\nResponse: " + response_str);
    }
}

repl_result LeanRepl::execute(const std::string& code, std::optional<int> env_id) {
    try {
        json cmd;
        cmd["cmd"] = code;
        if (env_id.has_value()) {
            cmd["env"] = env_id.value();
        } else if (m_current_env.has_value()) {
            cmd["env"] = m_current_env.value();
        }

        json response = send_command(cmd);

        // Check for error response
        if (response.contains("error")) {
            return {false, "", response["error"].get<std::string>(), response, std::nullopt};
        }

        // Extract environment ID
        std::optional<int> new_env;
        if (response.contains("env")) {
            new_env = response["env"].get<int>();
            m_current_env = new_env;
        }

        // Format output from messages and sorries
        std::ostringstream output;

        if (response.contains("messages") && response["messages"].is_array()) {
            for (const auto& msg : response["messages"]) {
                if (msg.contains("data")) {
                    output << msg["data"].get<std::string>() << "\n";
                }
            }
        }

        if (response.contains("sorries") && response["sorries"].is_array()) {
            for (const auto& sorry : response["sorries"]) {
                if (sorry.contains("goal")) {
                    output << "Goal: " << sorry["goal"].get<std::string>() << "\n";
                }
            }
        }

        return {true, output.str(), "", response, new_env};

    } catch (const std::exception& e) {
        return {false, "", std::string("Error communicating with Lean REPL: ") + e.what(),
                json(), std::nullopt};
    }
}

std::string LeanRepl::extract_identifier(const std::string& code, int cursor_pos,
                                         int& start, int& end) {
    auto is_ident_char = [](char c) -> bool {
        return std::isalnum(static_cast<unsigned char>(c)) ||
               c == '_' || c == '\'' || c == '.';  // Support qualified names
    };

    const std::size_t code_size = code.size();
    const std::size_t cursor = static_cast<std::size_t>(
        std::max(0, std::min(cursor_pos, static_cast<int>(code_size))));

    std::size_t s = cursor;
    while (s > 0 && is_ident_char(code[s - 1])) {
        --s;
    }

    std::size_t e = cursor;
    while (e < code_size && is_ident_char(code[e])) {
        ++e;
    }

    start = static_cast<int>(s);
    end = static_cast<int>(e);
    return code.substr(s, e - s);
}

completion_result LeanRepl::complete(const std::string& code, int cursor_pos) {
    int start, end;
    std::string prefix = extract_identifier(code, cursor_pos, start, end);

    // For now, return basic Lean keywords and common functions
    // TODO: Query the Lean environment for available identifiers
    static const std::vector<std::string> keywords = {
        "def", "theorem", "lemma", "example", "axiom", "inductive",
        "structure", "class", "instance", "namespace", "section",
        "variable", "variables", "constant", "import", "open",
        "by", "have", "show", "from", "let", "in",
        "match", "with", "do", "if", "then", "else",
        "fun", "λ", "forall", "∀", "exists", "∃",
        "Nat", "Int", "String", "Bool", "List", "Array", "Option",
        "Nat.add", "Nat.mul", "List.map", "List.filter",
        "simp", "rfl", "intro", "apply", "exact", "cases", "induction",
        "rw", "rewrite", "unfold", "split", "contradiction"
    };

    std::vector<std::string> matches;
    for (const auto& kw : keywords) {
        if (kw.rfind(prefix, 0) == 0) {  // Starts with prefix
            matches.push_back(kw);
        }
    }

    return {matches, start, end};
}

std::string LeanRepl::inspect(const std::string& code, int cursor_pos) {
    int start, end;
    std::string ident = extract_identifier(code, cursor_pos, start, end);

    if (ident.empty()) {
        return "";
    }

    try {
        // Try to get info using #check command
        json cmd;
        cmd["cmd"] = "#check " + ident;
        if (m_current_env.has_value()) {
            cmd["env"] = m_current_env.value();
        }

        json response = send_command(cmd);

        if (response.contains("messages") && response["messages"].is_array() &&
            !response["messages"].empty()) {
            const auto& msg = response["messages"][0];
            if (msg.contains("data")) {
                return msg["data"].get<std::string>();
            }
        }

        return "No information available for: " + ident;

    } catch (const std::exception&) {
        return "";
    }
}

std::string LeanRepl::is_complete(const std::string& code) {
    // Simple heuristic: check if code ends with a complete declaration
    std::string trimmed = code;
    while (!trimmed.empty() && std::isspace(trimmed.back())) {
        trimmed.pop_back();
    }

    if (trimmed.empty()) {
        return "incomplete";
    }

    // Check for incomplete multi-line constructs
    int open_parens = 0, open_braces = 0, open_brackets = 0;
    bool in_string = false;
    bool in_comment = false;

    for (size_t i = 0; i < trimmed.size(); ++i) {
        char c = trimmed[i];

        if (in_string) {
            if (c == '"' && (i == 0 || trimmed[i-1] != '\\')) {
                in_string = false;
            }
            continue;
        }

        if (c == '"') {
            in_string = true;
            continue;
        }

        if (i + 1 < trimmed.size() && trimmed[i] == '-' && trimmed[i+1] == '-') {
            in_comment = true;
            continue;
        }

        if (in_comment) {
            if (c == '\n') in_comment = false;
            continue;
        }

        if (c == '(') open_parens++;
        else if (c == ')') open_parens--;
        else if (c == '{') open_braces++;
        else if (c == '}') open_braces--;
        else if (c == '[') open_brackets++;
        else if (c == ']') open_brackets--;
    }

    if (open_parens > 0 || open_braces > 0 || open_brackets > 0 || in_string) {
        return "incomplete";
    }

    // Check if it looks like a complete statement
    // Complete statements typically end with specific keywords or patterns
    if (trimmed.find("by") != std::string::npos &&
        trimmed.back() != '.' && trimmed.back() != ')') {
        return "incomplete";
    }

    return "complete";
}

} // namespace xeus_lean
