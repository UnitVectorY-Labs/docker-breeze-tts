"""Assemble only the interpreter and audio ELF dependencies for Distroless."""
from pathlib import Path
import glob
import os
import re
import shutil
import subprocess

root = Path('/opt/runtime-root')


def copy_file(source):
    source = Path(source)
    target = root / str(source).lstrip('/')
    target.parent.mkdir(parents=True, exist_ok=True)
    # Materialize symlinks so no target outside the assembled tree is needed.
    shutil.copy2(source, target, follow_symlinks=True)


files = ['/usr/local/bin/python3.13', '/usr/bin/sox', '/usr/bin/ffmpeg', '/usr/bin/ffprobe']
files += glob.glob('/usr/lib/*-linux-gnu/libgomp.so.1')
files += glob.glob('/usr/lib/*-linux-gnu/libsndfile.so.1')
files += glob.glob('/usr/lib/*-linux-gnu/sox/*.so')
for filename in files:
    copy_file(filename)
    output = subprocess.check_output(['ldd', filename], text=True)
    if 'not found' in output:
        raise RuntimeError(output)
    for dependency in re.findall(r'(/[^\s()]+)', output):
        if Path(dependency).is_file():
            copy_file(dependency)

stdlib = Path('/usr/local/lib/python3.13')
shutil.copytree(stdlib, root / str(stdlib).lstrip('/'),
                ignore=shutil.ignore_patterns('site-packages', 'ensurepip', '__pycache__'))
(root / 'usr/local/bin/python3').symlink_to('python3.13')
(root / 'usr/local/bin/python').symlink_to('python3.13')
for directory in ['home/tts/.cache/huggingface', 'home/tts/.cache/numba', 'tmp']:
    path = root / directory
    path.mkdir(parents=True, exist_ok=True)
    os.chown(path, 1000, 1000)
for directory in ['home/tts', 'home/tts/.cache']:
    os.chown(root / directory, 1000, 1000)
# No installer in the published venv (metadata remains available).
site = Path('/opt/venv/lib/python3.13/site-packages')
for path in [site / 'pip', *site.glob('pip-*.dist-info')]:
    if path.exists():
        shutil.rmtree(path)
for path in Path('/opt/venv/bin').glob('pip*'):
    path.unlink()
