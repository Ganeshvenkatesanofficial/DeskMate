# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = []
binaries = []
hiddenimports = [
    'tiktoken_ext.openai_public',
    'tiktoken_ext',
    'settings',
    'core',
    'core.settings',
    'core.config',
    'core.database',
    'core.models',
    'core.telemetry',
    'routers',
    'routers.ws_common',
    'routers.ws_file_agent',
    'routers.ws_personal_agent',
    'routers.ws_meeting_agent',
    'routers.meeting_routes',
    'routers.api_routes',
    'services',
    'services.file_copilot',
    'services.file_copilot.agent',
    'services.file_copilot.tools',
    'services.file_copilot.rag_tools',
    'services.personal_assistant',
    'services.personal_assistant.agent',
    'services.personal_assistant.tools',
    'services.meeting_intelligence',
    'services.meeting_intelligence.config',
    'services.meeting_intelligence.live_pipeline',
    'services.meeting_intelligence.screen_capture',
    'services.meeting_intelligence.screen_capture_service',
    'services.meeting_intelligence.screen_capture_service.screen_capture',
    'services.meeting_intelligence.pdf_generator',
    'services.meeting_intelligence.summarizer',
    'services.meeting_intelligence.export_service',
    'services.meeting_intelligence.locate_anything',
    'services.meeting_intelligence.modules',
    'services.meeting_intelligence.modules.action_inference',
    'services.meeting_intelligence.modules.change_detector',
    'services.meeting_intelligence.modules.cursor_detector',
    'services.meeting_intelligence.modules.decision_gate',
    'services.meeting_intelligence.modules.heuristic_classifier',
    'services.meeting_intelligence.modules.interaction_detector',
    'services.meeting_intelligence.modules.locate_anything',
    'services.meeting_intelligence.modules.roi_extractor',
    'services.meeting_intelligence.modules.spatial_analyzer',
    'services.meeting_intelligence.modules.step_builder',
    'services.meeting_intelligence.modules.tracker',
    'services.meeting_intelligence.transcriber',
    'services.meeting_intelligence.transcriber.audio_extractor',
    'services.meeting_intelligence.transcriber.chunked_transcriber',
    'services.meeting_intelligence.transcriber.live_audio_recorder',
    'services.meeting_intelligence.transcriber.voxtral_service',
    'services.meeting_intelligence.audio_service',
    'services.meeting_intelligence.audio_service.audio_extractor',
    'services.meeting_intelligence.audio_service.chunked_transcriber',
    'services.meeting_intelligence.audio_service.live_audio_recorder',
    'services.meeting_intelligence.audio_service.voxtral_service',
    'services.meeting_intelligence.utils',
    'services.meeting_intelligence.utils.hardware_check',
    'sqlite3',
    'duckduckgo_search',
    'sqlalchemy',
    'pypdf',
    'PIL',
    'PIL.Image',
    'faiss',
    'sentence_transformers',
    'fpdf',
]

packages_to_collect = [
    'uvicorn',
    'websockets',
    'fastapi',
    'pydantic',
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
    'fpdf2',
    'cv2',
    'numpy',
    'mss',
    'sounddevice',
    'soundfile',
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
if os.path.exists('helpers/macos_audio_capture'):
    binaries.append(('helpers/macos_audio_capture', 'helpers'))
if os.path.exists('services/meeting_intelligence/audio_service/macos_audio_capture'):
    binaries.append(('services/meeting_intelligence/audio_service/macos_audio_capture', 'services/meeting_intelligence/audio_service'))

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
