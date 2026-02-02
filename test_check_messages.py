#!/usr/bin/env python3
"""Check all messages from kernel to understand output format."""

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

time.sleep(2)

if kernel_proc.poll() is not None:
    stdout, stderr = kernel_proc.communicate()
    print("KERNEL STDOUT:", stdout)
    print("KERNEL STDERR:", stderr)
    print("Kernel failed to start!")
    sys.exit(1)

print("Kernel started, connecting client...")

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
            print("Kernel not ready after timeout")
            kernel_proc.terminate()
            sys.exit(1)
        time.sleep(0.5)

print("Kernel is ready!")

# Test: #eval IO.println and see ALL messages
print("\n=== Executing: #eval IO.println \"Script!\" ===")
msg_id = km.execute('#eval IO.println "Script!"')

# Collect ALL messages for 3 seconds
messages = []
end_time = time.time() + 3
while time.time() < end_time:
    try:
        msg = km.get_iopub_msg(timeout=0.5)
        messages.append(msg)
        print(f"Message type: {msg['msg_type']}")
        if msg['msg_type'] == 'execute_result':
            print(f"  Content: {msg['content']}")
        elif msg['msg_type'] == 'stream':
            print(f"  Stream name: {msg['content']['name']}")
            print(f"  Stream text: {msg['content']['text']}")
        elif msg['msg_type'] == 'error':
            print(f"  Error: {msg['content']}")
    except:
        continue

print(f"\nTotal messages received: {len(messages)}")
print("\n=== All message types ===")
for msg in messages:
    print(f"- {msg['msg_type']}")

print("\n=== Shutting down ===")
km.shutdown()
kernel_proc.wait(timeout=5)
os.remove(connection_file)
print("Test completed!")
