# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = []
binaries = []
hiddenimports = [
    'tiktoken_ext.openai_public',
    'tiktoken_ext',
    'core',
    'core.config',
    'core.database',
    'core.models',
    'core.telemetry',
    'routers',
    'routers.ws_common',
    'routers.ws_file_agent',
    'routers.ws_personal_agent',
    'routers.api_routes',
    'services',
    'services.file_copilot',
    'services.file_copilot.agent',
    'services.file_copilot.tools',
    'services.file_copilot.rag_tools',
    'services.personal_assistant',
    'services.personal_assistant.agent',
    'services.personal_assistant.tools',
    'sqlite3',
    'duckduckgo_search',
    'sqlalchemy',
    'pypdf',
    'PIL',
    'PIL.Image',
    'faiss',
    'sentence_transformers',
    'mcp',
    'mcp.types',
]

packages_to_collect = [
    'uvicorn',
    'websockets',
    'fastapi',
    'smolagents',
    'litellm',
    'langfuse',
    'qdrant_client',
    'fastembed',
    'tiktoken',
    'googleapiclient',
    'google_auth_oauthlib',
    'duckduckgo_search',
    'sqlalchemy',
    'pypdf',
    'PIL',
    'faiss',
    'sentence_transformers',
]

for pkg in packages_to_collect:
    try:
        tmp_ret = collect_all(pkg)
        datas += tmp_ret[0]
        binaries += tmp_ret[1]
        hiddenimports += tmp_ret[2]
    except Exception:
        pass

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
