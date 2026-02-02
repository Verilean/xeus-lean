/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#include <algorithm>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "nlohmann/json.hpp"

#include "xeus/xhelper.hpp"
#include "xeus/xinput.hpp"
#include "xeus/xinterpreter.hpp"

#include "xeus-lean/xinterpreter.hpp"

namespace nl = nlohmann;

namespace xeus_lean {

interpreter::interpreter() {
    xeus::register_interpreter(this);
}

void interpreter::configure_impl() {
    // Initialize the Lean REPL subprocess
    std::cerr << "[Interpreter] configure_impl() starting..." << std::endl;
    try {
        m_repl = std::make_unique<LeanRepl>();
        std::cerr << "[Interpreter] LeanRepl created successfully" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[Interpreter] Failed to initialize Lean REPL: " << e.what() << std::endl;
        throw;
    }
    std::cerr << "[Interpreter] configure_impl() completed" << std::endl;
}

void interpreter::execute_request_impl(send_reply_callback cb,
                                       int execution_counter,
                                       const std::string& code,
                                       xeus::execute_request_config config,
                                       nl::json /*user_expressions*/) {
    std::cerr << "[Interpreter] execute_request_impl() called with code: " << code << std::endl;
    // Execute code in Lean REPL
    std::cerr << "[Interpreter] calling m_repl->execute()..." << std::endl;
    auto result = m_repl->execute(code);
    std::cerr << "[Interpreter] m_repl->execute() returned, ok=" << result.ok << std::endl;

    if (!result.ok) {
        // Execution failed - send error
        const std::string& error_msg = result.error;
        std::vector<std::string> traceback{error_msg};

        publish_execution_error("LeanError", error_msg, traceback);

        nl::json traceback_json = nl::json::array();
        traceback_json.push_back(error_msg);

        cb(xeus::create_error_reply(error_msg, "LeanError", traceback_json));
        return;
    }

    // Success - process output
    if (!config.silent && !result.output.empty()) {
        nl::json pub_data;
        pub_data["text/plain"] = result.output;

        // If there are sorries with goals, also format them nicely
        if (result.response.contains("sorries") &&
            result.response["sorries"].is_array() &&
            !result.response["sorries"].empty()) {

            std::ostringstream formatted;
            formatted << result.output << "\n";
            formatted << "Proof goals:\n";

            for (const auto& sorry : result.response["sorries"]) {
                if (sorry.contains("goal")) {
                    formatted << sorry["goal"].get<std::string>() << "\n";
                }
            }

            pub_data["text/plain"] = formatted.str();
        }

        publish_execution_result(execution_counter, std::move(pub_data),
                                nl::json::object());
    }

    cb(xeus::create_successful_reply(nl::json::array(), nl::json::object()));
}

nl::json interpreter::complete_request_impl(const std::string& code, int cursor_pos) {
    auto result = m_repl->complete(code, cursor_pos);

    return xeus::create_complete_reply(
        result.matches,
        result.cursor_start,
        result.cursor_end
    );
}

nl::json interpreter::inspect_request_impl(const std::string& code,
                                           int cursor_pos,
                                           int /*detail_level*/) {
    std::string info = m_repl->inspect(code, cursor_pos);

    if (info.empty()) {
        return xeus::create_inspect_reply(false);
    }

    nl::json data;
    data["text/plain"] = info;

    return xeus::create_inspect_reply(true, data, data);
}

nl::json interpreter::is_complete_request_impl(const std::string& code) {
    std::string status = m_repl->is_complete(code);
    return xeus::create_is_complete_reply(status, "  ");
}

void interpreter::shutdown_request_impl() {
    std::cout << "Shutting down Lean kernel..." << std::endl;
    m_repl.reset();
}

nl::json interpreter::kernel_info_request_impl() {
    const std::string protocol_version = "5.3";
    const std::string implementation = "xlean";
    const std::string implementation_version = XEUS_LEAN_VERSION;
    const std::string language_name = "lean";
    const std::string language_version = "4.0";  // TODO: Get from Lean
    const std::string language_mimetype = "text/x-lean";
    const std::string language_file_extension = ".lean";
    const std::string language_pygments_lexer = "lean";
    const std::string language_codemirror_mode = "lean4";
    const std::string language_nbconvert_exporter = "";
    const std::string banner = R"(
 __  __     ______     ______     __   __
/\_\_\_\   /\  ___\   /\  __ \   /\ "-.\ \
\/_/\_\/_  \ \  __\   \ \  __ \  \ \ \-.  \
  /\_\/\_\  \ \_____\  \ \_\ \_\  \ \_\\"\_\
  \/_/\/_/   \/_____/   \/_/\/_/   \/_/ \/_/

xeus-lean: A Jupyter kernel for Lean 4
)";
    const bool debugger = false;

    nl::json help_links = nl::json::array();
    help_links.push_back(nl::json::object({
        {"text", "Lean Documentation"},
        {"url", "https://lean-lang.org/documentation/"}
    }));
    help_links.push_back(nl::json::object({
        {"text", "Lean Zulip Chat"},
        {"url", "https://leanprover.zulipchat.com/"}
    }));

    return xeus::create_info_reply(
        protocol_version, implementation, implementation_version,
        language_name, language_version, language_mimetype,
        language_file_extension, language_pygments_lexer,
        language_codemirror_mode, language_nbconvert_exporter,
        banner, debugger, help_links
    );
}

} // namespace xeus_lean
