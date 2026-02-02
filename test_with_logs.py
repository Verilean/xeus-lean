#!/usr/bin/env python3
"""Test with full kernel logs."""

import jupyter_client
import subprocess
import json
import time
import sys
import os
import threading

# Create a connection file
connection_info = {
    "control_port": 50160,
    "shell_port": 57503,
    "transport": "tcp",
    "signature_scheme": "hmac-sha256",
    "stdin_port": 52597,
    "hb_port": 42540,
    "ip": "127.0.0.1",
    "iopub_port": 40885,
    "key": "a0436f6c-1916-11e5-ab5e-60f81dc9b60b"
}

connection_file = "test_connection.json"
with open(connection_file, 'w') as f:
    json.dump(connection_info, f)

print("Starting xlean kernel...")

# Capture stderr in real-time
def print_stderr(proc):
    for line in iter(proc.stderr.readline, ''):
        if line:
            print(f"[KERNEL] {line.rstrip()}", file=sys.stderr)

kernel_proc = subprocess.Popen(
    ['./.lake/build/bin/xlean', connection_file],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1
)

stderr_thread = threading.Thread(target=print_stderr, args=(kernel_proc,), daemon=True)
stderr_thread.start()

time.sleep(2)

if kernel_proc.poll() is not None:
    stdout, stderr = kernel_proc.communicate()
    print("Kernel failed to start!")
    sys.exit(1)

print("Connecting client...")

km = jupyter_client.BlockingKernelClient(connection_file=connection_file)
km.load_connection_file()
km.start_channels()

timeout = 10
start = time.time()
while True:
    try:
        km.wait_for_ready(timeout=1)
        break
    except RuntimeError:
        if time.time() - start > timeout:
            print("Kernel not ready")
            kernel_proc.terminate()
            sys.exit(1)
        time.sleep(0.5)

print("Kernel ready!\n")

# Test simple evaluation
print("=== Test: #eval IO.println \"Script!\" ===")
msg_id = km.execute('#eval IO.println "Script!"')

time.sleep(2)

# Try to get all messages
try:
    while True:
        msg = km.get_iopub_msg(timeout=0.5)
        print(f"Message: {msg['msg_type']}")
        if msg['msg_type'] == 'execute_result':
            print(f"  Result: {msg['content']['data']['text/plain']}")
except:
    pass

time.sleep(2)

print("\n=== Shutting down ===")
km.shutdown()
kernel_proc.wait(timeout=5)
os.remove(connection_file)
