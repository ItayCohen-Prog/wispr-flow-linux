#!/usr/bin/env bash
# Add --background without suppressing onboarding, deep links or explicit Hub opens.
set -uo pipefail
bundle=${1:-}
[[ -f $bundle ]] || { echo 'Usage: linux-background-launch.sh <main/index.js>' >&2; exit 2; }
python3 - "$bundle" <<'PY'
from pathlib import Path
import re
import os
import subprocess
import sys
import tempfile

path = Path(sys.argv[1])
s = path.read_text(encoding='utf-8', errors='surrogateescape')
marker = 'WISPR_LINUX_BACKGROUND_LAUNCH'
if marker in s:
    print('Background launch already patched')
    sys.exit(0)
# This predicate is shared by ready-to-show and app activation. Derive the prefs
# symbol from the real launch-policy expression, not a minifier identifier.
pattern = re.compile(r'(?P<head>[\w$]+=\(\)=>)(?P<el>[\w$]+)\.app\.isPackaged\?(?P<state>[\w$]+)\.RA\.prefs\?\.isUpdating\?\((?P<log>[^;]*?"Not showing hub window at launch: app is updating")')
matches = list(pattern.finditer(s))
if len(matches) != 1:
    sys.exit(f'Expected one launch-policy anchor, found {len(matches)}')
m = matches[0]
guard = ('/*' + marker + '*/("linux"===process.platform&&'
         'process.argv.includes("--background")&&!process.argv.includes("--show-hub")&&'
         + m['state'] + '.RA.prefs?.user?.onboardingCompleted)?!1:')
s = s[:m.end('head')] + guard + s[m.end('head'):]
# Repeated background launches are no-ops, but quit/deep-link requests retain
# their original behavior. Linux must enter the existing deep-link branch too.
pattern = re.compile(r'(\.app\.on\("second-instance",\((?P<event>[\w$]+),(?P<argv>[\w$]+)\)=>\{)(?P<body>.*?)(?P<log>[\w$]+\(\)\.info\("User tried to open the app a second time while it was already running"\))')
matches = list(pattern.finditer(s))
if len(matches) != 1:
    sys.exit(f'Expected one second-instance anchor, found {len(matches)}')
m = matches[0]
body, count = re.subn(r'if\(([\w$]+)\.H8\)\{const', r'if(\1.H8||"linux"===process.platform){const', m['body'])
if count != 1:
    sys.exit(f'Expected one second-instance deep-link branch, found {count}')
argv = m['argv']
body += ('if("linux"===process.platform&&' + argv + '.includes("--background")&&!'
         + argv + '.includes("--show-hub"))return;')
s = s[:m.start('body')] + body + s[m.end('body'):]
# Check before replacing. Unknown bundle shapes leave the input untouched.
with tempfile.NamedTemporaryFile(mode='w', suffix='.js', dir=path.parent, delete=False) as f:
    tmp = Path(f.name)
    f.write(s)
try:
    subprocess.run(['node', '--check', str(tmp)], check=True, capture_output=True)
    os.chmod(tmp, path.stat().st_mode)
    tmp.replace(path)
finally:
    tmp.unlink(missing_ok=True)
print('Patched background launch and repeated-launch policy')
PY
