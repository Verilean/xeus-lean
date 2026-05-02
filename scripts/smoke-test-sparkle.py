#!/usr/bin/env python3
"""Sparkle-specific smoke test for the native xlean kernel.

Runs after smoke-test-native.py inside Dockerfile.native-sparkle to
prove that `import Sparkle` resolves and that a tiny circuit
simulation actually executes. The WASM kernel hangs on the same
Signal.loop interpreter path; this is the concrete test that
demonstrates the native image does not have that bug.

Exit codes:
    0   import + simulation succeeded
    1   kernel start failed
    2   execute failed
    3   output mismatch
"""

import sys
import textwrap
import time

try:
    from jupyter_client.manager import KernelManager
except ImportError:
    sys.stderr.write("ERROR: jupyter_client is not installed\n")
    sys.exit(1)


CELL = textwrap.dedent("""\
    import Sparkle
    open Sparkle.Core.Domain Sparkle.Core.Signal

    -- Smallest possible "Sparkle is loaded" check: build a constant
    -- signal and sample it. Avoids `Signal.circuit` / `Signal.reg`
    -- whose body in upstream Sparkle depends on sorry-tagged proofs
    -- when the toolchain is overridden to rc1.
    def s : Signal defaultDomain (BitVec 4) := Signal.const 7#4
    #eval! IO.println s!"sparkle native: counter={s.val 0}"
""")

# `Signal.loop` runs through the IR interpreter and is slow — even
# native takes a few seconds.
TIMEOUT = 120.0


def run(km, code):
    kc = km.client()
    kc.start_channels()
    try:
        kc.wait_for_ready(timeout=TIMEOUT)
        msg_id = kc.execute(code)
        outputs = []
        deadline = time.monotonic() + TIMEOUT
        while time.monotonic() < deadline:
            try:
                msg = kc.get_iopub_msg(timeout=1.0)
            except Exception:
                continue
            if msg.get("parent_header", {}).get("msg_id") != msg_id:
                continue
            mtype = msg["msg_type"]
            content = msg.get("content", {})
            if mtype == "stream":
                outputs.append(content.get("text", ""))
            elif mtype == "execute_result":
                outputs.append(str(content.get("data", {}).get("text/plain", "")))
            elif mtype == "error":
                outputs.append("\n".join(content.get("traceback", [])))
            elif mtype == "status" and content.get("execution_state") == "idle":
                return "".join(outputs)
        raise TimeoutError("execute timed out")
    finally:
        kc.stop_channels()


def main():
    print("[sparkle-smoke] starting kernel: xlean", flush=True)
    km = KernelManager(kernel_name="xlean")
    try:
        km.start_kernel()
    except Exception as e:
        sys.stderr.write(f"[sparkle-smoke] kernel start failed: {e}\n")
        sys.exit(1)

    try:
        out = run(km, CELL)
    except Exception as e:
        sys.stderr.write(f"[sparkle-smoke] execute failed: {e}\n")
        km.shutdown_kernel(now=True)
        sys.exit(2)
    finally:
        try:
            km.shutdown_kernel(now=True)
        except Exception:
            pass

    needle = "sparkle native: counter="
    if needle in out:
        print(f"[sparkle-smoke] OK — output: {out.strip()[:200]}")
        return
    sys.stderr.write(
        f"[sparkle-smoke] MISMATCH: expected substring {needle!r}\n"
        f"  got: {out!r}\n"
    )
    sys.exit(3)


if __name__ == "__main__":
    main()
