"""KEY30 desktop palette matched to duo04_panel.v; presentation only."""
from pathlib import Path
from PySide6 import QtGui as G, QtWidgets as W

BG='#f3dfb5'
PAPER='#fffdf7'
INK='#242532'
LEFT='#f25538'
RIGHT='#d98221'

STYLE='''
QWidget { color:#242532; font-family:"Microsoft YaHei UI","Microsoft YaHei"; font-size:13px; }
QMainWindow, QWidget#appBody { background:#f3dfb5; }
QLabel { background:transparent; }
QFrame#headerCard { background:#fffdf7; border-radius:14px; }
QLabel#brand { font-size:27px; font-weight:900; letter-spacing:2px; }
QLabel#subtitle { color:#706659; font-size:12px; }
QLabel#connectionStatus { color:#625847; padding:5px 10px; background:#faf1df; border-radius:7px; }
QLabel#footerHint { color:#706659; padding:5px 2px; font-size:12px; }
QPushButton { background:#faf1df; border:1px solid #ddc7a3; border-radius:7px; padding:7px 12px; min-height:20px; font-weight:500; }
QPushButton:hover { background:#ffdec1; border-color:#db9974; }
QPushButton:pressed, QPushButton:checked { background:#ffcfb4; border-color:#f25538; }
QPushButton:disabled { color:#a39a8b; background:#f0e9db; border-color:#e4dac8; }
QPushButton[role="primary"] { color:white; background:#e94e36; border-color:#e94e36; font-weight:600; }
QPushButton[role="primary"]:hover { background:#d9452e; }
QPushButton[role="stop"] { color:#b73929; background:#ffe4df; border-color:#ecb6a9; font-weight:600; }
QPushButton[role="left"]:checked { color:white; background:#f25538; border-color:#e94e36; }
QPushButton[role="right"]:checked { color:white; background:#d98221; border-color:#c47519; }
QTabWidget::pane { background:#fffdf7; border:0; border-radius:12px; top:3px; }
QTabBar::tab { background:#e8cea2; color:#6c5b44; border:0; border-radius:8px; padding:11px 22px; margin:4px 6px 7px 0; }
QTabBar::tab:selected { background:#fffdf7; color:#c84630; font-weight:700; }
QTabBar::tab:hover:!selected { background:#ffdec1; }
QGroupBox { background:#fffdf7; border:1px solid #e8d5b6; border-radius:10px; margin-top:14px; padding:14px 10px 10px; font-weight:600; }
QGroupBox::title { subcontrol-origin:margin; left:14px; padding:0 6px; color:#70604c; }
QGroupBox[hand="left"] { border-top:3px solid #f25538; }
QGroupBox[hand="left"]::title { color:#d9452e; }
QGroupBox[hand="right"] { border-top:3px solid #ee9b33; }
QGroupBox[hand="right"]::title { color:#b46a16; }
QLineEdit,QComboBox,QSpinBox,QDoubleSpinBox { background:#faf1df; border:1px solid #dfcbaa; border-radius:6px; padding:6px; min-height:18px; selection-background-color:#f25538; selection-color:white; }
QLineEdit:focus,QComboBox:focus,QSpinBox:focus,QDoubleSpinBox:focus { border-color:#f25538; }
QComboBox::drop-down { border:0; width:22px; }
QComboBox QAbstractItemView { background:#fffdf7; color:#242532; selection-background-color:#ffdec1; selection-color:#242532; border:1px solid #dfcbaa; padding:4px; }
QCheckBox { spacing:8px; padding:3px 0; }
QCheckBox::indicator { width:16px; height:16px; border:1px solid #bfa77f; border-radius:4px; background:#fffdf7; }
QCheckBox::indicator:checked { background:#f25538; border:3px solid #ffd7bd; }
QSlider::groove:horizontal { height:5px; background:#ead5b1; border-radius:2px; }
QSlider::sub-page:horizontal { background:#ee9b33; border-radius:2px; }
QSlider::handle:horizontal { width:16px; margin:-6px 0; background:#f25538; border:2px solid #fffdf7; border-radius:9px; }
QTableWidget,QPlainTextEdit,QTextEdit { background:#fffdf7; alternate-background-color:#faf1df; border:1px solid #e8d5b6; border-radius:7px; gridline-color:#eee0ca; selection-background-color:#ffdec1; selection-color:#242532; }
QHeaderView::section { background:#f8ead8; color:#70604c; border:0; border-right:1px solid #e8d5b6; padding:8px 4px; }
QProgressBar { background:#f6dfbf; border:0; border-radius:6px; min-height:16px; text-align:center; }
QProgressBar::chunk { background:#ee9b33; border-radius:6px; }
QScrollArea { border:0; background:#fffdf7; }
QScrollArea > QWidget > QWidget { background:#fffdf7; }
QScrollBar:vertical { background:#faf1df; width:10px; margin:0; }
QScrollBar::handle:vertical { background:#d7bb8d; min-height:30px; border-radius:5px; }
QScrollBar::add-line:vertical,QScrollBar::sub-line:vertical { height:0; }
QMenu { background:#fffdf7; border:1px solid #ddc7a3; padding:6px; }
QMenu::item { padding:7px 24px; border-radius:4px; }
QMenu::item:selected { background:#ffdec1; }
QToolTip { color:#242532; background:#fff8e9; border:1px solid #ddc7a3; padding:6px; }
QLabel#scoreDrop { background:#faf1df; color:#8b7251; border:1px dashed #cd9e65; border-radius:10px; padding:8px; }
'''

def apply(window):
    assets=Path(__file__).resolve().parent/'theme_assets'
    arrows=''
    for direction in ('up','down'):
        url=(assets/(direction+'.svg')).as_posix()
        arrows+=f'QSpinBox::{direction}-arrow,QDoubleSpinBox::{direction}-arrow {{ image:url("{url}");width:10px;height:7px; }}'
    url=(assets/'down.svg').as_posix()
    arrows+=f'QComboBox::down-arrow {{ image:url("{url}");width:10px;height:7px; }}'
    arrows+='QSpinBox::up-button,QDoubleSpinBox::up-button,QSpinBox::down-button,QDoubleSpinBox::down-button { width:20px; background:#f8ead8; border:0; }'
    window.setStyleSheet(STYLE+arrows)
    app=W.QApplication.instance()
    palette=app.palette()
    for role,color in [(G.QPalette.ColorRole.Window,BG),(G.QPalette.ColorRole.WindowText,INK),
                       (G.QPalette.ColorRole.Base,PAPER),(G.QPalette.ColorRole.AlternateBase,'#faf1df'),
                       (G.QPalette.ColorRole.Text,INK),(G.QPalette.ColorRole.Button,'#faf1df'),
                       (G.QPalette.ColorRole.ButtonText,INK),(G.QPalette.ColorRole.Highlight,'#ffcfb4'),
                       (G.QPalette.ColorRole.HighlightedText,INK)]:
        palette.setColor(role,G.QColor(color))
    app.setPalette(palette)

def plot_style(plot):
    plot.setBackground(PAPER)
    for name in ('left','bottom'):
        axis=plot.getAxis(name)
        axis.setPen('#cdbb9b');axis.setTextPen('#706659')
        axis.setLabel(**{'color':INK})
    plot.showGrid(x=True,y=True,alpha=.12)
