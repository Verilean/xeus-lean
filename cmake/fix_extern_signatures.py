#!/usr/bin/env python3
"""
Fix IO world token signature mismatches between Lean-generated C code and
hand-written C++ implementations for WASM builds.

The Lean compiler erases IO world token parameters when generating C code,
but the hand-written C++ runtime/stubs may include them. In WASM, function
signature mismatches cause 'unreachable' traps at runtime.

This script:
1. Parses Lean-generated .c files for non-LEAN_EXPORT function declarations
   (these are @[extern] functions implemented in C++)
2. Parses C++ files for extern "C" function definitions
3. Finds signature mismatches (different parameter counts)
4. Patches the C++ files to match the Lean calling convention
5. Prints a summary of changes

Usage:
    python3 fix_extern_signatures.py <c_source_dir1> [c_source_dir2 ...] -- <cpp_dir1> [cpp_dir2 ...]

The '--' separator divides Lean-generated C source directories (left)
from C++ implementation directories (right).
"""

import re
import sys
import os
from collections import defaultdict


def count_params(param_str):
    """Count parameters in a C function parameter string."""
    param_str = param_str.strip()
    if not param_str or param_str == 'void':
        return 0
    depth = 0
    count = 1
    for c in param_str:
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ',' and depth == 0:
            count += 1
    return count


def split_params(param_str):
    """Split a C parameter string into individual parameters."""
    param_str = param_str.strip()
    if not param_str or param_str == 'void':
        return []
    params = []
    depth = 0
    current = ''
    for c in param_str:
        if c == '(':
            depth += 1
            current += c
        elif c == ')':
            depth -= 1
            current += c
        elif c == ',' and depth == 0:
            params.append(current.strip())
            current = ''
        else:
            current += c
    if current.strip():
        params.append(current.strip())
    return params


def parse_c_decls(c_dirs):
    """Extract non-LEAN_EXPORT function declarations from Lean-generated C files.

    These are forward declarations for @[extern] functions - the authoritative
    calling convention that C++ implementations must match.
    """
    decls = {}  # name -> (return_type, param_count, param_str, full_line)
    # Match: <return_type> <func_name>(<params>);
    # Function names can be any C identifier (lean_*, xeus_*, etc.)
    pattern = re.compile(
        r'^([a-zA-Z_][a-zA-Z_0-9* ]*?)\s+([a-zA-Z_][a-zA-Z_0-9]*)\s*\(([^)]*)\)\s*;'
    )

    for c_dir in c_dirs:
        for root, dirs, files in os.walk(c_dir):
            for fname in files:
                if not fname.endswith('.c'):
                    continue
                fpath = os.path.join(root, fname)
                try:
                    content = open(fpath, 'r', errors='replace').read()
                except:
                    continue

                for line in content.split('\n'):
                    line = line.strip()
                    # Skip Lean-defined functions, comments, preprocessor
                    if 'LEAN_EXPORT' in line or line.startswith('//') or line.startswith('#'):
                        continue
                    # Skip static declarations (internal to the .c file)
                    if line.startswith('static '):
                        continue
                    m = pattern.match(line)
                    if m:
                        ret_type = m.group(1).strip()
                        func_name = m.group(2)
                        params = m.group(3).strip()
                        nparams = count_params(params)
                        # Keep first occurrence (all should be consistent)
                        if func_name not in decls:
                            decls[func_name] = (ret_type, nparams, params, line)

    return decls


def parse_cpp_defs(cpp_dirs):
    """Extract extern "C" function definitions from C++ files."""
    defs = {}  # name -> (file, line_number, full_line, param_count, param_str)
    # Match: extern "C" [LEAN_EXPORT] <ret_type> <func_name>(<params>) {
    pattern = re.compile(
        r'extern\s+"C"\s+(?:LEAN_EXPORT\s+)?'
        r'([a-zA-Z_][a-zA-Z_0-9* ]*?)\s+'
        r'([a-zA-Z_][a-zA-Z_0-9]*)\s*\(([^)]*)\)\s*\{'
    )

    for cpp_dir in cpp_dirs:
        for root, dirs, files in os.walk(cpp_dir):
            for fname in files:
                if not fname.endswith('.cpp'):
                    continue
                fpath = os.path.join(root, fname)
                try:
                    lines = open(fpath, 'r', errors='replace').readlines()
                except:
                    continue

                for i, line in enumerate(lines):
                    m = pattern.search(line)
                    if m:
                        ret_type = m.group(1).strip()
                        func_name = m.group(2)
                        params = m.group(3).strip()
                        nparams = count_params(params)
                        if func_name not in defs:
                            defs[func_name] = (fpath, i + 1, line.rstrip(), nparams, params)

    return defs


def generate_patched_line(func_name, cpp_line, stage0_nparams, cpp_nparams, cpp_params, stage0_params):
    """Generate the patched C++ line to match stage0 parameter count."""
    params = split_params(cpp_params)

    if stage0_nparams < cpp_nparams:
        # Stage0 has FEWER params - remove trailing params (usually world tokens)
        kept_params = params[:stage0_nparams]
        new_params = ', '.join(kept_params) if kept_params else ''
    elif stage0_nparams > cpp_nparams:
        # Stage0 has MORE params - need to add params
        # Use the stage0 param types for the extras
        s0_params = split_params(stage0_params)
        for i in range(cpp_nparams, stage0_nparams):
            if i < len(s0_params):
                params.append(s0_params[i])
            else:
                params.append('lean_object *')
        new_params = ', '.join(params)
    else:
        return cpp_line  # no change needed

    old_sig = f"{func_name}({cpp_params})"
    new_sig = f"{func_name}({new_params})"
    return cpp_line.replace(old_sig, new_sig)


def main():
    if '--' not in sys.argv:
        print(f"Usage: {sys.argv[0]} <c_dir1> [c_dir2 ...] -- <cpp_dir1> [cpp_dir2 ...]",
              file=sys.stderr)
        sys.exit(1)

    sep = sys.argv.index('--')
    c_dirs = sys.argv[1:sep]
    cpp_dirs = sys.argv[sep + 1:]

    if not c_dirs or not cpp_dirs:
        print("Error: need at least one C dir and one C++ dir", file=sys.stderr)
        sys.exit(1)

    # Parse both sides
    c_decls = parse_c_decls(c_dirs)
    cpp_defs = parse_cpp_defs(cpp_dirs)

    print(f"Lean C declarations: {len(c_decls)}", file=sys.stderr)
    print(f"C++ definitions: {len(cpp_defs)}", file=sys.stderr)

    # Find mismatches
    mismatches = []
    for func_name in sorted(cpp_defs.keys()):
        if func_name not in c_decls:
            continue
        s0_ret, s0_nparams, s0_params, s0_line = c_decls[func_name]
        cpp_file, cpp_lineno, cpp_line, cpp_nparams, cpp_params = cpp_defs[func_name]
        if s0_nparams != cpp_nparams:
            mismatches.append((func_name, s0_nparams, cpp_nparams,
                             cpp_file, cpp_lineno, cpp_line, cpp_params, s0_params))

    if not mismatches:
        print("No signature mismatches found!", file=sys.stderr)
        return

    print(f"\nFound {len(mismatches)} signature mismatches:", file=sys.stderr)

    # Group by file for efficient patching
    patches_by_file = defaultdict(list)
    for func_name, s0_n, cpp_n, cpp_file, lineno, cpp_line, cpp_params, s0_params in mismatches:
        direction = f"stage0={s0_n} args, C++={cpp_n} args"
        print(f"  {func_name}: {direction}", file=sys.stderr)
        print(f"    file: {cpp_file}:{lineno}", file=sys.stderr)
        print(f"    Lean C: {c_decls[func_name][3]}", file=sys.stderr)
        print(f"    C++:    {cpp_line}", file=sys.stderr)

        new_line = generate_patched_line(func_name, cpp_line, s0_n, cpp_n, cpp_params, s0_params)
        if new_line != cpp_line:
            patches_by_file[cpp_file].append((cpp_line, new_line, func_name))
            print(f"    fixed:  {new_line}", file=sys.stderr)
        else:
            print(f"    WARNING: could not auto-patch", file=sys.stderr)

    # Apply patches
    patched_count = 0
    for fpath, patches in patches_by_file.items():
        content = open(fpath, 'r').read()
        for old_line, new_line, func_name in patches:
            if old_line in content:
                content = content.replace(old_line, new_line, 1)
                patched_count += 1
            else:
                print(f"  WARNING: could not find line to patch for {func_name} in {fpath}",
                      file=sys.stderr)
        open(fpath, 'w').write(content)

    print(f"\nPatched {patched_count}/{len(mismatches)} functions in "
          f"{len(patches_by_file)} files", file=sys.stderr)


if __name__ == '__main__':
    main()
