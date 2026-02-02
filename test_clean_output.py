#!/usr/bin/env python3
"""Test that the new Lean-owned kernel produces clean output for info messages."""

import jupyter_client
import subprocess
import json
import time
import sys
import os

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
kernel_proc = subprocess.Popen(
    ['./.lake/build/bin/xlean', connection_file],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

# Wait for kernel to initialize
time.sleep(2)

# Check if kernel started successfully
if kernel_proc.poll() is not None:
    stdout, stderr = kernel_proc.communicate()
    print("KERNEL STDOUT:", stdout)
    print("KERNEL STDERR:", stderr)
    print("Kernel failed to start!")
    sys.exit(1)

print("Kernel started, connecting client...")

# Connect client
km = jupyter_client.BlockingKernelClient(connection_file=connection_file)
km.load_connection_file()
km.start_channels()

# Wait for kernel to be ready
timeout = 10
start = time.time()
while True:
    try:
        km.wait_for_ready(timeout=1)
        break
    except RuntimeError:
        if time.time() - start > timeout:
            print("Kernel not ready after timeout")
            kernel_proc.terminate()
            sys.exit(1)
        time.sleep(0.5)

print("Kernel is ready!")

# Test 1: Simple IO output (should be clean)
print("\n=== Test 1: IO.println (should show clean output) ===")
msg_id = km.execute('def main : IO Unit := IO.println "Hello, World!"')
while True:
    try:
        msg = km.get_iopub_msg(timeout=2)
        if msg['msg_type'] == 'execute_result':
            result = msg['content']['data']['text/plain']
            print(f"Output: {result}")
            if result == '':
                print("✓ Empty output (as expected for definition)")
            break
        elif msg['msg_type'] == 'error':
            print(f"✗ Error: {msg['content']}")
            break
    except:
        print("✗ No result received")
        break

# Test 2: Eval IO (should show just "Hello, World!")
print("\n=== Test 2: #eval main (should show just 'Hello, World!') ===")
msg_id = km.execute('#eval main')
while True:
    try:
        msg = km.get_iopub_msg(timeout=2)
        if msg['msg_type'] == 'execute_result':
            result = msg['content']['data']['text/plain']
            print(f"Output: {result}")
            # Check if output is clean (just "Hello, World!" without JSON)
            if result == "Hello, World!":
                print("✓ Clean output!")
            elif '{' in result or 'messages' in result:
                print("✗ Verbose JSON output (should be cleaned)")
            break
        elif msg['msg_type'] == 'error':
            print(f"✗ Error: {msg['content']}")
            break
    except:
        print("✗ No result received")
        break

# Test 3: Check that errors still show full details
print("\n=== Test 3: Error case (should show full JSON) ===")
msg_id = km.execute('def broken := 1 + "string"')
while True:
    try:
        msg = km.get_iopub_msg(timeout=2)
        if msg['msg_type'] == 'execute_result':
            result = msg['content']['data']['text/plain']
            print(f"Output: {result}")
            if '{' in result and 'messages' in result:
                print("✓ Full JSON for errors (as expected)")
            break
        elif msg['msg_type'] == 'error':
            print(f"Error: {msg['content']}")
            break
    except:
        print("✗ No result received")
        break

print("\n=== Shutting down ===")
km.shutdown()
kernel_proc.wait(timeout=5)
os.remove(connection_file)
print("Test completed!")
