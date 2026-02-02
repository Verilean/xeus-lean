#!/usr/bin/env python3
"""Test script to execute code in xlean kernel."""

import subprocess
import time
import sys
import json
from jupyter_client import BlockingKernelClient

# Start the xlean kernel
print("Starting xlean kernel...")
proc = subprocess.Popen(
    ['./build/xlean', '-f', './build/test_connection.json'],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

# Wait for startup
time.sleep(2)

# Check if process is still running
if proc.poll() is not None:
    stdout, stderr = proc.communicate()
    print("STDOUT:", stdout)
    print("STDERR:", stderr)
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
    print("Executing: #eval 2 + 2")
    msg_id = client.execute("#eval 2 + 2")

    # Wait for execution to complete
    timeout = 10
    start = time.time()
    while time.time() - start < timeout:
        try:
            msg = client.get_iopub_msg(timeout=1)
            print(f"Message type: {msg['header']['msg_type']}")
            if msg['header']['msg_type'] == 'execute_result':
                print("Result:", msg['content']['data'])
            elif msg['header']['msg_type'] == 'error':
                print("Error:", msg['content'])
            elif msg['header']['msg_type'] == 'stream':
                print("Stream:", msg['content']['text'])
        except:
            break

    print("Test completed")

except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
finally:
    client.stop_channels()
    proc.terminate()
    proc.wait()
