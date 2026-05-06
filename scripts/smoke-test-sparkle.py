#!/usr/bin/env python3
"""Sparkle-specific smoke test for the native xlean kernel.

Runs after smoke-test-native.py inside Dockerfile.native-sparkle to
prove that `import Sparkle` resolves and the core types kind-check.
xeus-lean and Sparkle now pin the same Lean toolchain (4.28.0 final),
so olean headers match and `Signal.circuit` macros are sorry-free —
this test stays narrow on purpose, more elaborate simulation lives in
the bundled `sparkle-native-demo.ipynb`.

Exit codes:
    0   import resolved + types kind-checked
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

    -- Build a tiny stateful counter via `Signal.circuit` and evaluate
    -- it. This exercises the full path: import resolves, `Signal.reg`
    -- macro expands, the circuit goes through `Signal.loop`, and the
    -- C FFI symbol `sparkle_eval_at` is reachable from the
    -- interpreter (only true if xlean was relinked against
    -- libsparkle_*.a). A regression on any of those layers fails
    -- this single cell.
    def counter4 : Signal defaultDomain (BitVec 4) :=
      Signal.circuit do
        let count <- Signal.reg 0#4;
        count <~ count + 1#4;
        return count

    #eval IO.println s!"sparkle native: counter4(15)={(counter4.val 15).toNat}"
""").replace('<-', '←')

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

    needle = "sparkle native: counter4(15)=15"
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
