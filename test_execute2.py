#!/usr/bin/env python3
"""Test script to execute code in xlean kernel and capture stderr."""

import subprocess
import time
import sys
import json
from jupyter_client import BlockingKernelClient
import threading

def print_stderr(proc):
    """Print stderr in real-time."""
    for line in iter(proc.stderr.readline, ''):
        if not line:
            break
        print(f"[KERNEL STDERR] {line}", end='', file=sys.stderr)

# Start the xlean kernel
print("Starting xlean kernel...")
proc = subprocess.Popen(
    ['./build/xlean', '-f', './build/test_connection.json'],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1
)

# Start thread to print stderr
stderr_thread = threading.Thread(target=print_stderr, args=(proc,))
stderr_thread.daemon = True
stderr_thread.start()

# Wait for startup
time.sleep(3)

# Check if process is still running
if proc.poll() is not None:
    print("ERROR: Kernel exited early")
    sys.exit(1)

try:
    # Create a client to connect to the kernel
    client = BlockingKernelClient()

    with open('./build/test_connection.json', 'r') as f:
        conn_info = json.load(f)

    client.load_connection_info(conn_info)
    client.start_channels()

    # Wait for kernel to be ready
    print("Waiting for kernel to be ready...")
    client.wait_for_ready(timeout=10)
    print("Kernel is ready!")

    # Execute simple code
    print("\\nExecuting: #eval 2 + 2")
    msg_id = client.execute("#eval 2 + 2", allow_stdin=False)

    # Wait for execution to complete
    timeout = 10
    start = time.time()
    got_result = False
    while time.time() - start < timeout:
        try:
            msg = client.get_iopub_msg(timeout=2)
            msg_type = msg['header']['msg_type']
            print(f"[CLIENT] Message type: {msg_type}")
            if msg_type == 'execute_result':
                print("[CLIENT] Result:", msg['content']['data'])
                got_result = True
            elif msg_type == 'error':
                print("[CLIENT] Error:", msg['content'])
                got_result = True
            elif msg_type == 'stream':
                print("[CLIENT] Stream:", msg['content']['text'])
        except Exception as e:
            print(f"[CLIENT] Timeout or error getting message: {e}")
            break

    if not got_result:
        print("\\n[CLIENT] No result received!")

    # Check if kernel is still alive
    time.sleep(1)
    if proc.poll() is not None:
        print("\\n[ERROR] Kernel process died!")
    else:
        print("\\n[OK] Kernel is still running")

except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
finally:
    try:
        client.stop_channels()
    except:
        pass
    proc.terminate()
    proc.wait()
    print("\\nTest finished")
