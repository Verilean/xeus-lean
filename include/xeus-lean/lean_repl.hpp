/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#ifndef XEUS_LEAN_REPL_HPP
#define XEUS_LEAN_REPL_HPP

#include <string>
#include <vector>
#include <optional>
#include "nlohmann/json.hpp"
#include "xeus_lean_config.hpp"
#include <lean/lean.h>

namespace xeus_lean {

struct repl_result {
    bool ok;
    std::string output;
    std::string error;
    nlohmann::json response;  // Full JSON response from Lean REPL
    std::optional<int> env;    // Environment ID if available
};

struct completion_result {
    std::vector<std::string> matches;
    int cursor_start;
    int cursor_end;
};

class XEUS_LEAN_API LeanRepl {
public:
    LeanRepl();
    ~LeanRepl();

    // Execute a command in the REPL
    repl_result execute(const std::string& code, std::optional<int> env_id = std::nullopt);

    // Get completion candidates
    completion_result complete(const std::string& code, int cursor_pos);

    // Inspect an identifier (get type information)
    std::string inspect(const std::string& code, int cursor_pos);

    // Check if code is complete
    std::string is_complete(const std::string& code);

    // Get current environment ID
    std::optional<int> current_env() const { return m_current_env; }

private:
    // Send a JSON command to the REPL and get response
    nlohmann::json send_command(const nlohmann::json& cmd);

    // Extract identifier at cursor position
    std::string extract_identifier(const std::string& code, int cursor_pos,
                                   int& start, int& end);

    // Lean REPL handle (Lean object pointer)
    lean_object* m_handle;

    // Legacy members (unused, kept for compatibility)
    int m_stdin_fd;
    int m_stdout_fd;
    int m_pid;

    // Current environment state
    std::optional<int> m_current_env;

    // Buffer for reading JSON responses (unused)
    std::string m_read_buffer;
};

} // namespace xeus_lean

#endif
