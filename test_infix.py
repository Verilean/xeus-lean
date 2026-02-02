#!/usr/bin/env python3
"""Test infix operators vs explicit function calls."""

import jupyter_client
import subprocess
import json
import time
import sys
import os

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

kernel_proc = subprocess.Popen(
    ['./.lake/build/bin/xlean', connection_file],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

time.sleep(2)

km = jupyter_client.BlockingKernelClient(connection_file=connection_file)
km.load_connection_file()
km.start_channels()
km.wait_for_ready(timeout=10)

print("=== Test 1: #eval 1+1 (infix operator) ===")
msg_id = km.execute('#eval 1+1')
time.sleep(1)
try:
    while True:
        msg = km.get_iopub_msg(timeout=0.5)
        if msg['msg_type'] == 'execute_result':
            print(f"Result: {msg['content']['data']['text/plain']}")
            break
except:
    pass

print("\n=== Test 2: #eval Nat.add 1 1 (explicit function) ===")
msg_id = km.execute('#eval Nat.add 1 1')
time.sleep(1)
try:
    while True:
        msg = km.get_iopub_msg(timeout=0.5)
        if msg['msg_type'] == 'execute_result':
            print(f"Result: {msg['content']['data']['text/plain']}")
            break
except:
    pass

print("\n=== Test 3: With import Lean ===")
msg_id = km.execute('import Lean')
time.sleep(1)
# Clear messages
try:
    while True:
        km.get_iopub_msg(timeout=0.2)
except:
    pass

print("Now trying #eval 1+1 after import...")
msg_id = km.execute('#eval 1+1')
time.sleep(1)
try:
    while True:
        msg = km.get_iopub_msg(timeout=0.5)
        if msg['msg_type'] == 'execute_result':
            print(f"Result: {msg['content']['data']['text/plain']}")
            break
except:
    pass

km.shutdown()
kernel_proc.wait(timeout=5)
os.remove(connection_file)
