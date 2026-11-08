#!/usr/bin/env python3
"""Jalankan: python3 tools/build_all.py  -> roster staff + file .rbxmx siap pasang."""
import os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
for s in ("build_staff.py", "build_rbxmx.py"):
    r = subprocess.run([sys.executable, os.path.join(here, s)])
    if r.returncode != 0: sys.exit(r.returncode)
