############################################################################
# GenerateSymbolTable.cmake
# Generates a C++ lookup table for WASM dlsym replacement.
# In WASM/emscripten, dlsym doesn't work without -sMAIN_MODULE.
# Uses a shell script for speed (cmake string ops are too slow for 200k+ symbols).
############################################################################

function(generate_wasm_symbol_table OUTPUT_FILE)
    set(TARGET_NAMES ${ARGN})

    # Find llvm-nm
    find_program(LLVM_NM llvm-nm)
    if(NOT LLVM_NM)
        get_filename_component(_emcc_dir "${CMAKE_C_COMPILER}" DIRECTORY)
        find_program(LLVM_NM llvm-nm HINTS "${_emcc_dir}")
    endif()
    if(NOT LLVM_NM)
        message(FATAL_ERROR "llvm-nm not found, needed for WASM symbol table generation. "
            "Add llvmPackages.bintools-unwrapped to your nix-shell.")
    endif()
    message(STATUS "Using llvm-nm: ${LLVM_NM}")

    # Resolve target names to output file paths using generator expressions
    set(_lib_files "")
    foreach(_target ${TARGET_NAMES})
        if(TARGET ${_target})
            list(APPEND _lib_files "$<TARGET_FILE:${_target}>")
        else()
            list(APPEND _lib_files "${_target}")
        endif()
    endforeach()

    set(_gen_script "${CMAKE_CURRENT_SOURCE_DIR}/cmake/gen_wasm_symtab.sh")

    add_custom_command(
        OUTPUT "${OUTPUT_FILE}"
        COMMAND sh "${_gen_script}" "${LLVM_NM}" "${OUTPUT_FILE}" ${_lib_files}
        DEPENDS ${TARGET_NAMES} "${_gen_script}"
        COMMENT "Generating WASM symbol table"
        VERBATIM
    )
endfunction()
