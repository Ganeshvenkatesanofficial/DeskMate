# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = []
binaries = []
hiddenimports = [
    'tiktoken_ext.openai_public',
    'tiktoken_ext',
    'settings',
    'core',
    'core.config',
    'core.models',
    'core.telemetry',
    'routers',
    'routers.api_routes',
    'routers.folder_routes',
    'services',
    'services.folder_agent',
    'services.folder_agent.agent',
    'services.folder_agent.embedder',
    'services.folder_agent.events',
    'services.folder_agent.extract',
    'services.folder_agent.fs_service',
    'services.folder_agent.graph',
    'services.folder_agent.indexer',
    'services.folder_agent.ocr',
    'services.folder_agent.search',
    'services.folder_agent.security',
    'services.folder_agent.setup',
    'services.folder_agent.store',
    'services.folder_agent.thumbnails',
    'services.folder_agent.tools',
    'services.folder_agent.vector_store',
    'services.folder_agent.watcher',
    'send2trash',
    'networkx',
    'pypdf',
    'PIL',
    'PIL.Image',
    'sqlite3',
]

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
if os.path.exists('bin/native_screen_ocr'):
    binaries.append(('bin/native_screen_ocr', 'bin'))

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
