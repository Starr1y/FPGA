from pathlib import Path
from PySide6.QtCore import QLibraryInfo
source=Path(SPECPATH)/'source'
translation=Path(QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath))/'qtbase_zh_CN.qm'
# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    [str(source/'lite29.py')],
    pathex=[str(source)],
    binaries=[],
    datas=[(str(source/'score_assets'), 'score_assets'), (str(translation), 'PySide6/translations'), (str(source/'theme_assets'), 'theme_assets')],
    hiddenimports=['serial.tools.list_ports_windows'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['matplotlib', 'scipy', 'pandas', 'torch', 'tensorflow', 'cv2', 'IPython', 'notebook', 'pytest', 'tkinter', 'PyQt5', 'PyQt6', 'PySide2'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='TangLab',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='TangLab',
)
