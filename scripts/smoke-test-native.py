#!/usr/bin/env python3
"""Smoke-test the native xlean kernel via jupyter_client.

Starts the kernel through the registered kernelspec, evaluates a
small Lean program, and asserts the output. Exits non-zero if the
kernel doesn't start, the eval doesn't produce a stream message, or
the produced text doesn't match.

Used by CI and by the docs/tutorials/docker-native.md happy-path
check. Keep this self-contained — no test-framework dependency.

Usage:
    python3 scripts/smoke-test-native.py [--kernel xlean]

Exit codes:
    0   all checks passed
    1   kernel start failed
    2   execute failed
    3   output mismatch
"""

import argparse
import sys
import textwrap
import time

try:
    from jupyter_client.manager import KernelManager
except ImportError:
    sys.stderr.write(
        "ERROR: jupyter_client is not installed. Try:\n"
        "    pip install --user jupyter_client\n"
    )
    sys.exit(1)


# Each case is (description, lean code, substring expected in stdout/stream).
CASES = [
    ("arithmetic", "#eval (1 + 2 + 3)", "6"),
    ("definition + use",
        textwrap.dedent("""\
            def square (x : Nat) : Nat := x * x
            #eval square 7
        """),
        "49"),
    ("IO println",
        '#eval IO.println "hello from native xlean"',
        "hello from native xlean"),
]


def run_one(km, code: str, timeout: float = 60.0) -> str:
    """Execute `code` in the kernel, return concatenated text outputs."""
    kc = km.client()
    kc.start_channels()
    try:
        kc.wait_for_ready(timeout=timeout)
        msg_id = kc.execute(code)
        outputs = []
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                msg = kc.get_iopub_msg(timeout=1.0)
            except Exception:
                continue
            parent = msg.get("parent_header", {}).get("msg_id")
            if parent != msg_id:
                continue
            mtype = msg["msg_type"]
            content = msg.get("content", {})
            if mtype == "stream":
                outputs.append(content.get("text", ""))
            elif mtype == "execute_result":
                data = content.get("data", {})
                outputs.append(str(data.get("text/plain", "")))
            elif mtype == "error":
                outputs.append("\n".join(content.get("traceback", [])))
            elif mtype == "status" and content.get("execution_state") == "idle":
                return "".join(outputs)
        raise TimeoutError(f"execute timed out after {timeout}s")
    finally:
        kc.stop_channels()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", default="xlean",
                    help="kernelspec name (default: xlean)")
    ap.add_argument("--timeout", type=float, default=120.0,
                    help="per-cell timeout, seconds (default 120)")
    args = ap.parse_args()

    print(f"[smoke] starting kernel: {args.kernel}", flush=True)
    km = KernelManager(kernel_name=args.kernel)
    try:
        km.start_kernel()
    except Exception as e:
        sys.stderr.write(f"[smoke] kernel start failed: {e}\n")
        sys.exit(1)

    failed = 0
    try:
        for desc, code, expected in CASES:
            print(f"[smoke] case: {desc}", flush=True)
            try:
                got = run_one(km, code, timeout=args.timeout)
            except Exception as e:
                sys.stderr.write(f"  EXECUTE FAILED: {e}\n")
                failed += 1
                continue
            if expected in got:
                print(f"  OK (output contains {expected!r})", flush=True)
            else:
                sys.stderr.write(
                    f"  MISMATCH: expected substring {expected!r}\n"
                    f"  got: {got!r}\n"
                )
                failed += 1
    finally:
        km.shutdown_kernel(now=True)

    if failed:
        sys.stderr.write(f"[smoke] {failed} case(s) failed\n")
        sys.exit(2 if failed > 0 else 0)
    print("[smoke] all cases passed")


if __name__ == "__main__":
    main()
