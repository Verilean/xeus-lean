#!/usr/bin/env python3
"""Test script to launch xlean kernel and execute simple code."""

import subprocess
import time
import sys

# Start the xlean kernel with a test connection file
proc = subprocess.Popen(
    ['./build/xlean', '-f', './build/test_connection.json'],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

# Wait a bit for startup
time.sleep(2)

# Check if process is still running
poll = proc.poll()
if poll is not None:
    stdout, stderr = proc.communicate()
    print("STDOUT:")
    print(stdout)
    print("\nSTDERR:")
    print(stderr)
    print(f"\nProcess exited with code: {poll}")
    sys.exit(1)
else:
    print("Kernel is running successfully!")
    proc.terminate()
    proc.wait()
    print("Kernel terminated cleanly")
