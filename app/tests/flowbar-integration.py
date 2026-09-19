#!/usr/bin/env python3
"""Run against a disposable native preview, never against a user's shell.
Usage: python tests/flowbar-integration.py --config omarchy/preview.qml --socket /tmp/lab-flowbar.sock
Requires the preview and hyprctl to address the same isolated Hyprland instance.
"""
import argparse
import json
import socket
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config', required=True)
parser.add_argument('--socket', required=True)
args = parser.parse_args()

def state():
    return json.loads(subprocess.check_output(['quickshell', '-p', args.config, 'ipc', 'call', 'wisprflowbar', 'state']))

def visible():
    layers = json.loads(subprocess.check_output(['hyprctl', '-j', 'layers']))
    return any(layer['namespace'] == 'wispr-flowbar' for monitor in layers.values() for level in monitor['levels'].values() for layer in level)

def recording_bounds():
    layers = json.loads(subprocess.check_output(['hyprctl', '-j', 'layers']))
    for monitor in layers.values():
        for level in monitor['levels'].values():
            for layer in level:
                if layer['namespace'] == 'wispr-flowbar':
                    return 220 <= layer['w'] <= 228 and 90 <= layer['h'] <= 98
    return False

def eventually(fn, expected, label):
    until = time.monotonic() + 3
    while time.monotonic() < until:
        if fn() == expected:
            print('PASS', label, flush=True)
            return
        time.sleep(.05)
    raise AssertionError(label)

with socket.socket(socket.AF_UNIX) as client:
    client.connect(args.socket)
    def send(t, p=None):
        client.sendall((json.dumps({'t': t, 'p': p}) + '\n').encode())
    send('notification:clear')
    for i in range(3):
        send('status:dictationStatus', 'listening')
        eventually(visible, True, f'opening {i+1}')
        eventually(recording_bounds, True, f'capsule-sized layer {i+1}')
        send('status:dictationStatus', 'idle')
        eventually(visible, False, f'closing {i+1}')
    send('notification:show', {'title':'Test error', 'body':'Notification without recording', 'timeout':1000})
    eventually(visible, True, 'standalone notification opens')
    eventually(visible, False, 'notification expires')
    client.sendall(b'{invalid json}\n')
    send('status:dictationStatus', 'processing')
    eventually(lambda: state()['mode'], 'processing', 'recovers after malformed message')
    eventually(visible, True, 'processing opens')
    send('status:dictationStatus', 'idle')
    eventually(visible, False, 'processing closes')
