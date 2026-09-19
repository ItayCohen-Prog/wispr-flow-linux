#!/usr/bin/env python3
"""Measure a disposable preview using synthetic events and /proc CPU/RSS.

CPU percentages are relative to one logical core. RSS includes the full preview
and Qt process; it is not incremental plugin memory. GPU cost is not measured.
"""
import argparse
import json
import math
import os
from pathlib import Path
import socket
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--socket', required=True)
parser.add_argument('--shell-pid', required=True, type=int)
parser.add_argument('--compositor-pid', required=True, type=int)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
pids = {'compositor': args.compositor_pid, 'capsule_and_preview': args.shell_pid}


def snapshot():
    result = {}
    for name, pid in pids.items():
        # Everything after the final ')' follows the comm field in proc(5).
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        result[name] = {
            'ticks': int(fields[11]) + int(fields[12]),
            'rss_mib': int(fields[21]) * os.sysconf('SC_PAGE_SIZE') / 1048576,
        }
    return result


results = []
with socket.socket(socket.AF_UNIX) as client:
    client.connect(args.socket)

    def send(channel, payload):
        client.sendall((json.dumps({'t': channel, 'p': payload}) + '\n').encode())

    try:
        for stage in ['hidden', 'notification', 'listening', 'processing']:
            send('notification:clear', None)
            status = stage if stage in ['listening', 'processing'] else 'idle'
            send('status:dictationStatus', status)
            if stage == 'notification':
                send('notification:show', {
                    'title': 'Microphone unavailable',
                    'body': 'Choose another input device and try again.',
                    'timeout': 60000,
                    'actions': [{'text': 'Try again', 'callback': 'Retry'}],
                })
            time.sleep(2)  # Exclude the opening transition from steady-state cost.
            before = snapshot()
            start = time.monotonic()
            while time.monotonic() - start < 10:
                if stage == 'listening':
                    send('status:audioLevel', (1 + math.sin(time.monotonic() * 7)) / 2)
                time.sleep(1 / 30)
            elapsed = time.monotonic() - start
            after = snapshot()
            result = {'stage': stage, 'seconds': elapsed}
            for name in pids:
                cpu_seconds = (after[name]['ticks'] - before[name]['ticks']) / os.sysconf('SC_CLK_TCK')
                result[name] = {
                    'cpu_percent_one_core': round(cpu_seconds / elapsed * 100, 2),
                    'rss_mib': round(after[name]['rss_mib'], 1),
                }
            results.append(result)
            args.output.write_text(json.dumps(results, indent=2) + '\n')
            print(json.dumps(result), flush=True)
    finally:
        send('notification:clear', None)
        send('status:dictationStatus', 'idle')
