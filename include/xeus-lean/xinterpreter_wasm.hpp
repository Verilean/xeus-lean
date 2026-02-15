/***************************************************************************
* Copyright (c) 2025, xeus-lean contributors
*
* Distributed under the terms of the Apache Software License 2.0.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#ifndef XEUS_LEAN_INTERPRETER_WASM_HPP
#define XEUS_LEAN_INTERPRETER_WASM_HPP

#include <string>
#include <memory>

#include "nlohmann/json.hpp"
#include "xeus_lean_config.hpp"
#include "xeus/xinterpreter.hpp"

namespace nl = nlohmann;

namespace xeus_lean
{
    class XEUS_LEAN_API interpreter : public xeus::xinterpreter
    {
    public:
        interpreter();
        virtual ~interpreter();

    protected:
        void configure_impl() override;

        void execute_request_impl(send_reply_callback cb,
                                  int execution_counter,
                                  const std::string& code,
                                  xeus::execute_request_config config,
                                  nl::json user_expressions) override;

        nl::json complete_request_impl(const std::string& code,
                                       int cursor_pos) override;

        nl::json inspect_request_impl(const std::string& code,
                                      int cursor_pos,
                                      int detail_level) override;

        nl::json is_complete_request_impl(const std::string& code) override;

        nl::json kernel_info_request_impl() override;

        void shutdown_request_impl() override;

    private:
        bool m_initialized;
        int m_current_env;

        // Lean runtime state (opaque pointers to lean_object*)
        void* m_repl_state;

        bool initialize_lean_runtime();
        std::string call_lean_repl(const std::string& code, int env);
    };
}

#endif
