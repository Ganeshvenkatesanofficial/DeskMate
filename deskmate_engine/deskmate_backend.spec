# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all, collect_submodules

datas = []
binaries = []
# Every engine module (routers and services are imported by name at startup),
# plus the few third-party modules loaded dynamically.
hiddenimports = (
    ['settings']
    + collect_submodules('core')
    + collect_submodules('routers')
    + collect_submodules('services')
    + ['tiktoken_ext', 'tiktoken_ext.openai_public', 'sqlite3']
)

packages_to_collect = [
    'uvicorn',
    'websockets',
    'fastapi',
    'pydantic',
    'smolagents',
    'litellm',
    'tiktoken',
    'qdrant_client',
    'fastembed',
    'numpy',
    'networkx',
    'pypdf',
    'PIL',
    'send2trash',
    'requests',
    'dotenv',
]

for pkg in packages_to_collect:
    try:
        tmp_ret = collect_all(pkg)
        datas += tmp_ret[0]
        binaries += tmp_ret[1]
        hiddenimports += tmp_ret[2]
    except Exception:
        pass

import os
# Apple Vision OCR helper (makes pictures searchable); resolved via sys._MEIPASS/bin.
if os.path.exists('bin/macos_ocr'):
    binaries.append(('bin/macos_ocr', 'bin'))

a = Analysis(
    ['backend.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='deskmate_backend',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
