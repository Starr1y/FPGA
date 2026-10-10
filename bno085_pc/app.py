"""Run: python PC/app.py [--demo] [--smoke-test]."""
import argparse
from collections import deque
from datetime import datetime
import math
from pathlib import Path
import queue
import sys
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

sys.path.insert(0, str(Path(__file__).parent / 'vendor'))
from protocol import LineBuffer, FrameError, parse_line, SequenceTracker, STATES
from transport import Reader
from recording import Recorder, EventRecorder
from pose import PoseState, PoseCanvas, euler_deg, relative_quaternion
from position import PositionState, PositionCanvas
from instrument import InstrumentState, KeyboardCanvas, NOTES

BG, INK, MUTED = '#eef3f8', '#18334e', '#64778b'
COLORS = ('#007fca', '#e47b20', '#0b9879')


class Plot(tk.Canvas):
    def __init__(self, parent, title, labels, **kwargs):
        super().__init__(parent, bg='white', highlightthickness=0, **kwargs)
        self.title, self.labels = title, labels

    def draw(self, points, now, window, size=None):
        self.delete('all')
        w, h = size or (self.winfo_width(), self.winfo_height())
        if w < 100 or h < 70:
            return
        left, right, top, bottom = 66, w-18, 30, h-25
        self.create_text(12, 14, text=self.title, anchor='w', fill=INK,
                         font=('Microsoft YaHei UI', 10, 'bold'))
        for i, name in enumerate(self.labels):
            x = w-(505 if len(self.labels) == 6 else 215)+i*(82 if len(self.labels) == 6 else 68)
            self.create_text(x, 14, text=('┄ ' if i >= 3 else '━ ')+name,
                             fill=COLORS[i % 3], anchor='w')
        visible = [(t, values) for t, values in points if now-window <= t <= now]
        values = [v for _, group in visible for v in group if math.isfinite(v)]
        if values:
            low, high = min(values), max(values)
            pad = max((high-low)*.12, .05)
            low, high = low-pad, high+pad
        else:
            low, high = -1, 1
        for i in range(4):
            y = top+(bottom-top)*i/3
            self.create_line(left, y, right, y, fill='#e7edf4')
            self.create_text(left-8, y, text=f'{high-(high-low)*i/3:.2f}', anchor='e', fill=MUTED)
        for i in range(5):
            x = left+(right-left)*i/4
            self.create_line(x, top, x, bottom, fill='#f0f3f7')
            self.create_text(x, bottom+13, text=f'{-window+window*i/4:g}s', fill=MUTED)
        for channel in range(len(self.labels)):
            coords = []
            previous = None
            for t, group in visible:
                value = group[channel]
                broken = not math.isfinite(value) or (previous is not None and
                          (t-previous[0] > .3 or ('姿态' in self.title and abs(value-previous[1]) > 180)))
                if broken:
                    if len(coords) >= 4:
                        self.create_line(*coords, fill=COLORS[channel % 3], width=2,
                                         dash=(4, 3) if channel >= 3 else ())
                    coords = []
                if math.isfinite(value):
                    coords.extend((left+(t-(now-window))/window*(right-left),
                                   bottom-(value-low)/(high-low)*(bottom-top)))
                    previous = (t, value)
                else:
                    previous = None
            if len(coords) >= 4:
                self.create_line(*coords, fill=COLORS[channel % 3], width=2,
                                 dash=(4, 3) if channel >= 3 else ())
        if not visible:
            self.create_text((left+right)/2, (top+bottom)/2, text='等待有效数据', fill=MUTED)


class App:
    def __init__(self, root):
        self.root = root
        root.title('BNO085 IMU 测试上位机')
        root.geometry('1280x900')
        root.minsize(1000, 720)
        root.configure(bg=BG)
        style = ttk.Style(root)
        style.theme_use('clam')
        style.configure('TButton', padding=(10, 4), font=('Microsoft YaHei UI', 10))
        style.configure('TCombobox', padding=5)
        self.reader = None
        self.events = queue.Queue(maxsize=1000)
        self.recorder = None
        self.event_recorder = None
        self.keyboard_zoom = None
        self.keyboard_zoom_canvas = None
        self.closing = False
        self.close_deadline = None
        self.connected = False
        self.demo = False
        self.paused = False
        self.last_draw = 0
        self.history = [deque(maxlen=1400) for _ in range(3)]
        self.reset_session()
        root.grid_columnconfigure(0, weight=1)
        root.grid_rowconfigure(4, weight=3, minsize=270)
        root.grid_rowconfigure(6, weight=2, minsize=80)
        header = tk.Frame(root, bg='white', padx=20, pady=4)
        header.grid(row=0, column=0, sticky='ew')
        tk.Label(header, text='BNO085  /  姿态实验台', bg='white', fg=INK,
                 font=('Microsoft YaHei UI', 20, 'bold')).pack(side='left')
        tk.Label(header, text='UART · 115200 / 8N1 · CRC16', bg='white', fg=MUTED,
                 font=('Segoe UI', 11)).pack(side='right')
        toolbar = tk.Frame(root, bg=BG, padx=16, pady=3)
        toolbar.grid(row=1, column=0, sticky='ew')
        self.port = ttk.Combobox(toolbar, width=12, state='normal')
        self.port.pack(side='left', padx=(0, 6))
        self.port.set('COM3')
        self.refresh_button = ttk.Button(toolbar, text='刷新串口', command=self.refresh_ports)
        self.refresh_button.pack(side='left', padx=3)
        self.connect_button = ttk.Button(toolbar, text='连接设备', command=self.toggle_connection)
        self.connect_button.pack(side='left', padx=3)
        self.demo_button = ttk.Button(toolbar, text='演示模式', command=lambda: self.start(True))
        self.demo_button.pack(side='left', padx=3)
        self.record_button = ttk.Button(toolbar, text='开始记录 CSV', command=self.toggle_recording, state='disabled')
        self.record_button.pack(side='right', padx=3)
        self.initialize_button = ttk.Button(toolbar, text='静态初始化（3 秒）',
                                            command=self.initialize_position, state='disabled')
        self.initialize_button.pack(side='right', padx=3)
        self.zero_velocity_button = ttk.Button(toolbar, text='开始位置估算',
                                               command=self.toggle_position_motion, state='disabled')
        self.zero_velocity_button.pack(side='right', padx=3)
        self.record_label = tk.Label(root, text='未记录 · CSV 不覆盖已有文件', bg=BG, fg=MUTED, anchor='w')
        self.record_label.grid(row=2, column=0, sticky='ew', padx=20)
        self.status_label = tk.Label(root, text='未连接：请先关闭串口助手，再连接 CH340 串口。',
                                     bg='#dce7f2', fg=INK, anchor='w', padx=12, pady=2,
                                     font=('Microsoft YaHei UI', 11, 'bold'))
        self.status_label.grid(row=3, column=0, sticky='ew', padx=16, pady=(5, 3))
        body = tk.Frame(root, bg=BG)
        body.grid(row=4, column=0, sticky='nsew', padx=16, pady=5)
        body.grid_columnconfigure(0, weight=3, uniform='dashboard')
        body.grid_columnconfigure(1, weight=2, uniform='dashboard')
        body.grid_rowconfigure(0, weight=1)
        model = tk.Frame(body, bg='white')
        model.grid(row=0, column=0, sticky='nsew', padx=(0, 8))
        self.pose_canvas = PoseCanvas(model, height=260)
        self.pose_canvas.pack(fill='both', expand=True)
        modelbar = tk.Frame(model, bg='white', padx=12, pady=4)
        modelbar.pack(fill='x')
        self.zero_button = ttk.Button(modelbar, text='视图归零', command=self.zero_view, state='disabled')
        self.zero_button.pack(side='left')
        self.restore_button = ttk.Button(modelbar, text='恢复原始姿态', command=self.restore_view, state='disabled')
        self.restore_button.pack(side='left', padx=6)
        tk.Label(modelbar, text='只影响模型显示', bg='white', fg=MUTED).pack(side='right')
        sidebar = tk.Frame(body, bg=BG)
        sidebar.grid(row=0, column=1, sticky='nsew')
        sidebar.grid_columnconfigure(0, weight=1)
        sidebar.grid_rowconfigure(0, weight=1)
        cards = ttk.Notebook(sidebar)
        cards.grid(row=0, column=0, sticky='nsew')
        self.sidebar_notebook = cards
        self.value_labels = {}
        self.relative_labels = {}
        self.corrected_labels = {}
        self.value_titles = {}
        groups = [('姿态角  /  °', ('roll_deg', 'pitch_deg', 'yaw_deg'), ('Roll', 'Pitch', 'Yaw')),
                  ('加速度  /  m/s² · 含重力', ('ax', 'ay', 'az'), ('X', 'Y', 'Z')),
                  ('角速度  /  rad/s', ('gx', 'gy', 'gz'), ('X', 'Y', 'Z'))]
        for row_index, (title, names, labels) in enumerate(groups):
            card = tk.Frame(cards, bg='white', padx=12, pady=2)
            cards.add(card, text=('姿态', '加速度', '角速度')[row_index])
            raw_title = ('原始姿态角  /  °', '原始加速度  /  m/s² · 含重力', '原始角速度  /  rad/s')[row_index]
            title_label = tk.Label(card, text=raw_title, bg='white', fg=MUTED,
                                   font=('Microsoft YaHei UI', 9))
            title_label.pack(anchor='w')
            self.value_titles[row_index] = title_label
            row = tk.Frame(card, bg='white')
            row.pack(fill='x', pady=(1, 0))
            for i, (name, label) in enumerate(zip(names, labels)):
                box = tk.Frame(row, bg='white')
                box.pack(side='left', expand=True, fill='x')
                tk.Label(box, text=label, bg='white', fg=COLORS[i],
                         font=('Segoe UI', 9, 'bold')).pack(side='left')
                widget = tk.Label(box, text='—', bg='white', fg=INK, font=('Consolas', 12, 'bold'))
                widget.pack(side='left', padx=(3, 0))
                self.value_labels[name] = widget
            corrected_title = ('静态归零姿态角  /  °', '校正加速度  /  m/s² · 去重力',
                               '校正角速度  /  rad/s · 零偏校正')[row_index]
            tk.Label(card, text=corrected_title, bg='white', fg=MUTED,
                     font=('Microsoft YaHei UI', 9)).pack(anchor='w', pady=(8, 0))
            corrected_row = tk.Frame(card, bg='white')
            corrected_row.pack(fill='x')
            for i, name in enumerate(names):
                box = tk.Frame(corrected_row, bg='white')
                box.pack(side='left', expand=True, fill='x')
                tk.Label(box, text=labels[i], bg='white', fg=COLORS[i],
                         font=('Segoe UI', 9, 'bold')).pack(side='left')
                widget = tk.Label(box, text='—', bg='white', fg=INK,
                                  font=('Consolas', 12, 'bold'))
                widget.pack(side='left', padx=(3, 0))
                if row_index == 0:
                    self.relative_labels[name] = widget
                else:
                    self.corrected_labels[name] = widget
        self.detail_label = tk.Label(sidebar, text='精度等级：—', bg=BG, fg=MUTED, anchor='w',
                                     justify='left', font=('Microsoft YaHei UI', 9))
        self.detail_label.grid(row=1, column=0, sticky='ew', pady=1)
        plotbar = tk.Frame(root, bg=BG, padx=16)
        plotbar.grid(row=5, column=0, sticky='ew', pady=1)
        tk.Label(plotbar, text='滚动时间窗', bg=BG, fg=MUTED).pack(side='left')
        self.window = ttk.Combobox(plotbar, values=('10', '30', '60'), width=5, state='readonly')
        self.window.set('30')
        self.window.pack(side='left', padx=8)
        self.pause_button = ttk.Button(plotbar, text='暂停绘图', command=self.pause_plot)
        self.pause_button.pack(side='left', padx=3)
        ttk.Button(plotbar, text='清空曲线', command=self.clear_plots).pack(side='left', padx=3)
        tk.Label(plotbar, text='暂停绘图不影响接收与 CSV 记录', bg=BG, fg=MUTED).pack(side='right')
        plots = ttk.Notebook(root)
        plots.grid(row=6, column=0, sticky='nsew', padx=16, pady=(0, 4))
        self.notebook = plots
        self.plots = []
        for index, (title, _, labels) in enumerate(groups):
            panel = tk.Frame(plots, bg='white')
            plots.add(panel, text=title.split('  /')[0])
            corrected_names = ('零R', '零P', '零Y') if index == 0 else ('校X', '校Y', '校Z')
            title = title+' · 实线原始，虚线校正'
            labels = (('原R', '原P', '原Y') if index == 0 else ('原X', '原Y', '原Z'))+corrected_names
            plot = Plot(panel, title, labels, height=180)
            plot.pack(fill='both', expand=True)
            self.plots.append(plot)
        keyboard_panel = tk.Frame(plots, bg='white')
        plots.add(keyboard_panel, text='七音区验证')
        keyboard_info = tk.Frame(keyboard_panel, bg='white', width=380)
        keyboard_info.pack(side='left', fill='y', padx=(12, 4))
        keyboard_info.pack_propagate(False)
        self.keyboard_status = tk.Label(keyboard_info, text='请先静态初始化', bg='white', fg=MUTED,
                                        anchor='w', justify='left', font=('Microsoft YaHei UI', 10, 'bold'))
        self.keyboard_status.pack(fill='x', pady=(3, 0))
        self.keyboard_values = tk.Label(keyboard_info, text='相对 Yaw/Pitch：— / —   音区：—   力度：—',
                                        bg='white', fg=INK, anchor='w', justify='left')
        self.keyboard_values.pack(fill='x')
        settings = tk.Frame(keyboard_info, bg='white')
        settings.pack(fill='x', pady=(2, 0))
        tk.Label(settings, text='敲击灵敏度', bg='white', fg=MUTED).pack(side='left')
        self.hit_sensitivity = ttk.Combobox(settings, values=('0.75', '1.00', '1.25', '1.50'),
                                             width=5, state='readonly')
        self.hit_sensitivity.set('1.00')
        self.hit_sensitivity.pack(side='left', padx=5)
        tk.Label(settings, text='单击音区图放大', bg='white', fg=MUTED).pack(side='right')
        self.keyboard_canvas = KeyboardCanvas(keyboard_panel, height=120)
        self.keyboard_canvas.pack(side='right', fill='both', expand=True)
        self.keyboard_canvas.bind('<Button-1>', self.toggle_keyboard_zoom)
        self.keyboard_canvas.config(cursor='hand2')
        position_panel = tk.Frame(plots, bg='white')
        plots.add(position_panel, text='位置诊断')
        position_info = tk.Frame(position_panel, bg='white', width=530)
        position_info.pack(side='left', fill='y', padx=(12, 4))
        position_info.pack_propagate(False)
        self.position_status = tk.Label(position_info, text='放稳设备后点击“静态初始化”',
                                        bg='white', fg=MUTED, anchor='nw', justify='left', wraplength=510)
        self.position_status.pack(fill='x', pady=(3, 0))
        tk.Label(position_info, text='积分演示：不能用于选音或测距', bg='white', fg='#b42318',
                 anchor='w').pack(fill='x')
        self.position_values = tk.Label(position_info, text='线性加速度 X/Y/Z：— m/s²    距原点偏移：X=— cm  Y=— cm  Z=— cm',
                                        bg='white', fg=INK, anchor='nw', justify='left', wraplength=510,
                                        font=('Consolas', 10))
        self.position_values.pack(fill='x')
        self.position_canvas = PositionCanvas(position_panel, height=120)
        self.position_canvas.pack(side='right', fill='both', expand=True)
        plots.select(keyboard_panel)
        self.stats_label = tk.Label(root, text='', bg=BG, fg=MUTED, anchor='w',
                                    font=('Microsoft YaHei UI', 9))
        self.stats_label.grid(row=7, column=0, sticky='ew', padx=20)
        self.diagnostic_button = ttk.Button(root, text='展开详细诊断', command=self.toggle_diagnostics)
        self.diagnostic_button.grid(row=8, column=0, sticky='w', padx=16, pady=2)
        self.diagnostic_panel = tk.Frame(root, bg='white', padx=10, pady=2)
        self.raw_label = tk.Label(self.diagnostic_panel, text='最近完整帧：—', bg='white', fg=MUTED,
                                  anchor='w', justify='left', font=('Consolas', 9))
        self.raw_label.pack(fill='x')
        self.diagnostic_label = tk.Label(self.diagnostic_panel, bg='white', fg=MUTED,
                                         anchor='w', justify='left', font=('Microsoft YaHei UI', 9))
        self.diagnostic_label.pack(fill='x')
        self.diagnostics_open = False
        self.message = tk.Label(root, text='不自动连接、不向 STM32 发送命令。先完成串口验证，再判断传感器精度。',
                                bg=BG, fg=MUTED, anchor='w', wraplength=1120)
        self.message.grid(row=10, column=0, sticky='ew', padx=18, pady=(2, 4))
        root.bind('<Configure>', lambda event: self.message.configure(wraplength=max(200, event.width-36))
                  if event.widget == root else None)
        root.protocol('WM_DELETE_WINDOW', self.close)
        self.refresh_ports()
        root.after(50, self.tick)

    def reset_session(self):
        self.pose = PoseState()
        self.position_state = PositionState()
        self.instrument_state = InstrumentState()
        self.keyboard_flash_zone = None
        self.keyboard_flash_until = 0.0
        self.lines = LineBuffer()
        self.tracker = SequenceTracker()
        self.good = self.crc_errors = self.format_errors = self.invalid = 0
        self.last_frame = None
        self.last_received = None
        self.rate_times = deque(maxlen=300)
        self.link_message = '未连接'
        for history in self.history:
            history.clear()

    def pose_is_fresh(self):
        return bool(self.connected and self.last_received is not None and
                    time.monotonic()-self.last_received < 1.5 and self.pose.usable)

    def zero_view(self):
        if self.pose_is_fresh():
            self.pose.zero()

    def initialize_position(self):
        if self.pose_is_fresh() and self.last_frame and self.last_frame['valid']:
            self.position_state.start()
            self.instrument_state.reset()
            self.keyboard_flash_zone = None

    def close_keyboard_zoom(self, event=None):
        if self.keyboard_zoom is not None:
            window, self.keyboard_zoom = self.keyboard_zoom, None
            self.keyboard_zoom_canvas = None
            if window.winfo_exists():
                window.destroy()

    def toggle_keyboard_zoom(self, event=None):
        if self.keyboard_zoom is not None:
            self.close_keyboard_zoom()
            return
        window = tk.Toplevel(self.root)
        window.title('七音区验证 · 放大视图')
        window.geometry('900x540')
        window.minsize(600, 360)
        window.configure(bg='white')
        window.transient(self.root)
        window.protocol('WM_DELETE_WINDOW', self.close_keyboard_zoom)
        window.bind('<Escape>', self.close_keyboard_zoom)
        label = tk.Label(window, text='单击画面或按 Esc 关闭 · 击打时音区短暂变色',
                         bg='white', fg=MUTED, font=('Microsoft YaHei UI', 12))
        label.pack(fill='x', pady=8)
        canvas = KeyboardCanvas(window)
        canvas.pack(fill='both', expand=True)
        canvas.bind('<Button-1>', self.close_keyboard_zoom)
        canvas.config(cursor='hand2')
        self.keyboard_zoom = window
        self.keyboard_zoom_canvas = canvas
        self.draw_keyboard(canvas, time.monotonic())

    def draw_keyboard(self, canvas, now):
        instrument = self.instrument_state
        active = self.pose_is_fresh() and instrument.reference_q is not None
        flash = self.keyboard_flash_zone if now < self.keyboard_flash_until else None
        canvas.draw(instrument.zone, instrument.yaw, instrument.out_of_range,
                    active, flash_zone=flash)

    def confirm_stationary(self):
        if self.pose_is_fresh() and self.position_state.mode == 'ready':
            self.position_state.zero_velocity()

    def toggle_position_motion(self):
        if not self.pose_is_fresh() or self.position_state.mode != 'ready':
            return
        if self.position_state.holding:
            self.position_state.resume()
        else:
            self.position_state.zero_velocity()

    def restore_view(self):
        self.pose.restore()

    def toggle_diagnostics(self):
        self.diagnostics_open = not self.diagnostics_open
        if self.diagnostics_open:
            self.diagnostic_panel.grid(row=9, column=0, sticky='ew', padx=16)
        else:
            self.diagnostic_panel.grid_remove()
        self.diagnostic_button.config(text='收起详细诊断' if self.diagnostics_open else '展开详细诊断')

    def refresh_ports(self):
        try:
            from serial.tools import list_ports
            ports = list(list_ports.comports())
            self.port['values'] = [p.device for p in ports]
            if ports and self.port.get() not in self.port['values']:
                preferred = next((p for p in ports if 'CH340' in p.description.upper()), ports[0])
                self.port.set(preferred.device)
        except ImportError:
            self.message.config(text='缺少 pySerial；可先用演示模式。安装方式见 PC/README.md。')
        except Exception as exc:
            self.message.config(text=f'串口枚举失败，可手动输入 COM 号：{exc}')

    def start(self, demo=False):
        if self.reader is not None:
            return
        if not demo and not self.port.get().strip():
            messagebox.showwarning('请选择串口', '刷新或输入 CH340 的 COM 号。')
            return
        self.reset_session()
        self.events = queue.Queue(maxsize=1000)
        for label in self.value_labels.values():
            label.config(text='—', fg=MUTED)
        for label in self.relative_labels.values():
            label.config(text='—', fg=MUTED)
        for label in self.corrected_labels.values():
            label.config(text='—', fg=MUTED)
        self.detail_label.config(text='精度等级：—    四元数：—')
        self.raw_label.config(text='最近完整帧：—')
        self.demo = demo
        self.connected = False
        self.reader = Reader(self.port.get().strip(), self.events, demo)
        self.reader.start()
        self.connect_button.config(text='断开连接')
        self.demo_button.config(state='disabled')
        self.port.config(state='disabled')
        self.refresh_button.config(state='disabled')
        self.link_message = '正在连接…'
        self.message.config(text='演示模式使用模拟数据。' if demo else '正在打开串口；如果被占用，请关闭 SSCOM 的串口。')

    def toggle_connection(self):
        if self.reader:
            self.pose.restore()
            self.pose.usable = False
            self.position_state.reset()
            self.instrument_state.reset()
            self.reader.stop_event.set()
            self.connect_button.config(state='disabled')
            self.link_message = '正在断开…'
        else:
            self.start()

    def stop_recording(self):
        event_recorder, self.event_recorder = self.event_recorder, None
        if event_recorder:
            try:
                event_recorder.close()
            except OSError as exc:
                self.record_label.config(text=f'事件 CSV 关闭失败：{exc}', fg='#b42318')
        if self.recorder:
            recorder, self.recorder = self.recorder, None
            try:
                recorder.close()
                self.record_label.config(text=f'已保存 {recorder.rows} 行 · {recorder.file.name}')
            except OSError as exc:
                self.record_label.config(text=f'文件关闭/保存失败：{exc}', fg='#b42318')
            self.record_button.config(text='开始记录 CSV')

    def toggle_recording(self):
        if self.recorder:
            self.stop_recording()
            return
        if not self.connected:
            return
        directory = Path(__file__).parent / 'recordings'
        try:
            directory.mkdir(exist_ok=True)
        except OSError as exc:
            messagebox.showerror('无法创建记录目录', str(exc))
            return
        prefix = 'DEMO' if self.demo else 'BNO085'
        path = filedialog.asksaveasfilename(initialdir=directory,
            initialfile=f'{prefix}_{datetime.now():%Y%m%d_%H%M%S}.csv',
            defaultextension='.csv', filetypes=[('CSV', '*.csv')])
        if path and self.connected:
            try:
                event_path = Path(path).with_name(Path(path).stem+'_events.csv')
                if event_path.exists():
                    raise FileExistsError(f'事件记录已存在：{event_path}')
                self.recorder = Recorder(path, 'DEMO' if self.demo else self.port.get())
                self.event_recorder = EventRecorder(event_path,
                                                    'DEMO' if self.demo else self.port.get())
                self.record_button.config(text='停止记录')
                self.record_label.config(text=f'正在记录原始 CSV 与事件 CSV · {path}', fg='#087d60')
            except OSError as exc:
                self.stop_recording()
                messagebox.showerror('无法开始记录', f'{exc}\n请选择新的文件名，不覆盖已有记录。')

    def pause_plot(self):
        self.paused = not self.paused
        self.pause_button.config(text='继续绘图' if self.paused else '暂停绘图')

    def clear_plots(self):
        for history in self.history:
            history.clear()

    def relative_attitude(self):
        reference = self.position_state.reference_q
        if reference is None or not self.pose.usable or self.pose.last is None:
            return None
        return euler_deg(relative_quaternion(self.pose.last, reference))

    def consume(self, data, timestamp):
        for line in self.lines.feed(data):
            try:
                frame = parse_line(line)
            except FrameError as exc:
                if exc.kind == 'crc':
                    self.crc_errors += 1
                else:
                    self.format_errors += 1
                self.message.config(text=f'已丢弃损坏行：{exc}（串口打开瞬间可能有半帧）')
                continue
            if frame is None:
                if line.startswith(b'#BOOT'):
                    self.message.config(text='检测到 STM32 启动消息，等待 IMU 报告。')
                continue
            self.good += 1
            if not frame['valid']:
                self.invalid += 1
            if self.tracker.update(frame):
                self.clear_plots()
                self.position_state.abort('设备重启：位置估算已重置，请重新初始化')
                self.instrument_state.reset()
                self.keyboard_flash_zone = None
                self.message.config(text='检测到设备计数/时间回退，已开始新的曲线段。')
            self.last_frame, self.last_received = frame, timestamp
            self.pose.update(frame)
            prior_position_mode = self.position_state.mode
            self.position_state.update(frame)
            if prior_position_mode == 'calibrating' and self.position_state.mode == 'ready':
                self.pose.reference = self.position_state.reference_q
                self.instrument_state.reset(self.position_state.reference_q,
                                            self.position_state.vertical_noise)
            elif prior_position_mode == 'ready' and self.position_state.mode != 'ready':
                self.instrument_state.reset()
            if self.position_state.mode == 'ready' and frame['valid']:
                was_pending = self.instrument_state.pending is not None
                event = self.instrument_state.update(frame, self.position_state.linear_body,
                    self.position_state.gyro_corrected, float(self.hit_sensitivity.get()))
                if not was_pending and self.instrument_state.pending:
                    self.keyboard_flash_zone = self.instrument_state.pending['zone']-1
                    self.keyboard_flash_until = time.monotonic()+0.45
                if event:
                    self.keyboard_flash_zone = event['zone']-1
                    self.keyboard_flash_until = time.monotonic()+0.45
                if event and self.event_recorder:
                    try:
                        self.event_recorder.write(event)
                    except (OSError, ValueError) as exc:
                        self.stop_recording()
                        self.message.config(text=f'事件记录失败，已停止写入：{exc}')
            else:
                self.instrument_state.invalidate()
            self.rate_times.append(timestamp)
            names = [('roll_deg', 'pitch_deg', 'yaw_deg'), ('ax', 'ay', 'az'), ('gx', 'gy', 'gz')]
            for index, (history, keys) in enumerate(zip(self.history, names)):
                values = tuple(frame[k] for k in keys) if frame['valid'] else (math.nan,)*3
                if index == 0:
                    relative = self.relative_attitude() if frame['valid'] else None
                    values += relative if relative is not None else (math.nan,)*3
                elif self.position_state.mode == 'ready' and frame['valid']:
                    values += (self.position_state.linear_body if index == 1
                               else self.position_state.gyro_corrected)
                else:
                    values += (math.nan,)*3
                history.append((timestamp, values))
            if self.recorder:
                try:
                    self.recorder.write(frame)
                except (OSError, ValueError) as exc:
                    self.stop_recording()
                    self.message.config(text=f'记录失败，已停止写入：{exc}')

    def tick(self):
        if self.closing:
            if self.reader is None or not self.reader.is_alive() or time.monotonic() >= self.close_deadline:
                self.root.destroy()
            else:
                self.root.after(50, self.tick)
            return
        for _ in range(250):
            try:
                kind, payload, timestamp = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == 'open':
                self.connected = True
                self.link_message = payload
                self.record_button.config(state='normal')
            elif kind == 'data':
                self.consume(payload, timestamp)
            elif kind == 'error':
                self.link_message = '串口错误 / 已断开'
                self.message.config(text=f'{payload}；检查 USB、COM 号及串口是否被占用。')
            elif kind == 'closed':
                self.connected = False
                self.pose.restore()
                self.pose.usable = False
                self.position_state.reset()
                self.instrument_state.reset()
        if self.reader is not None and not self.reader.is_alive() and self.events.empty():
            self.connected = False
            self.pose.restore()
            self.pose.usable = False
            self.position_state.reset()
            self.instrument_state.reset()
            self.stop_recording()
            self.reader = None
            self.connect_button.config(text='连接设备', state='normal')
            self.demo_button.config(state='normal')
            self.refresh_button.config(state='normal')
            self.port.config(state='normal')
            self.record_button.config(state='disabled')
            self.link_message = '已断开（显示的数值是最后一帧）'
        now = time.monotonic()
        fresh = self.connected and self.last_received is not None and now-self.last_received < 1.5
        valid = fresh and self.last_frame is not None and self.last_frame['valid']
        if self.position_state.mode == 'calibrating' and not fresh:
            self.position_state.abort('初始化中断：数据超时，请重试')
        prefix = '[演示 / 非实测] ' if self.demo else ''
        if self.connected:
            if self.last_frame is None:
                text, color = '串口已打开，等待 CRC 正确的数据…', '#996000'
            elif not fresh:
                text, color = '数据超时：超过 1.5 秒未收到正确帧，以下数值已过期', '#b42318'
            elif not valid:
                text, color = f'IMU 数据无效：{STATES[self.last_frame["state"]]}（valid=0）', '#b42318'
            else:
                text, color = '正在采集 · state=5 / valid=1', '#087d60'
        else:
            text, color = self.link_message, MUTED
        self.status_label.config(text=prefix+text, fg=color)
        while self.rate_times and now-self.rate_times[0] > 5:
            self.rate_times.popleft()
        rate = 0
        if fresh and len(self.rate_times) > 1:
            span = self.rate_times[-1]-self.rate_times[0]
            rate = (len(self.rate_times)-1)/span if span > 0 else 0
        dropped = self.reader.dropped if self.reader else 0
        self.stats_label.config(text=f'接收 {rate:.1f} Hz   正确帧 {self.good}   CRC 错 {self.crc_errors}   格式错 {self.format_errors}   '
            f'报告年龄 {" / ".join(str(self.last_frame[k]) for k in ("quaternion_age_ms", "accel_age_ms", "gyro_age_ms")) if self.last_frame else "—"} ms   '
            f'bus / sh2 {str(self.last_frame["bus_error"])+" / "+str(self.last_frame["sh2_error"]) if self.last_frame else "—"}')
        self.diagnostic_label.config(text=
            f'无效报告 {self.invalid}   序号缺口 {self.tracker.missing}   重复 {self.tracker.duplicates}   '
            f'重启/回退 {self.tracker.restarts}   队列丢块 {dropped}   缓冲溢出 {self.lines.overflows}')
        if self.last_frame:
            f = self.last_frame
            for name, label in self.value_labels.items():
                label.config(text=f'{f[name]:.3f}', fg=INK if valid else '#9ca9b5')
            relative = self.relative_attitude()
            for i, name in enumerate(('roll_deg', 'pitch_deg', 'yaw_deg')):
                self.relative_labels[name].config(text=f'{relative[i]:.3f}' if relative else '—',
                                                   fg=INK if valid and relative else '#9ca9b5')
            calibrated = self.position_state.mode == 'ready'
            for names, values in ((('ax', 'ay', 'az'), self.position_state.linear_body),
                                  (('gx', 'gy', 'gz'), self.position_state.gyro_corrected)):
                for name, value in zip(names, values):
                    self.corrected_labels[name].config(text=f'{value:.3f}' if calibrated else '—',
                                                       fg=INK if valid and calibrated else '#9ca9b5')
            norm = math.sqrt(sum(f[k]**2 for k in ('ax', 'ay', 'az')))
            self.detail_label.config(text=f'精度(0–3)：姿态 {f["rotation_accuracy"]} / 加速度 {f["accel_accuracy"]} / 陀螺 {f["gyro_accuracy"]}\n'
                f'|a|={norm:.3f} m/s²   航向误差估计 {math.degrees(f["heading_accuracy_rad"]):.1f}°',
                fg=MUTED if valid else '#9ca9b5')
            self.raw_label.config(text=f'最近完整帧：seq={f["sequence"]}   t={f["timestamp_ms"]} ms   '
                f'报告数={f["quaternion_count"]}/{f["accel_count"]}/{f["gyro_count"]}\n'
                f'年龄={f["quaternion_age_ms"]}/{f["accel_age_ms"]}/{f["gyro_age_ms"]} ms   '
                f'bus_error={f["bus_error"]}   sh2_error={f["sh2_error"]}\n'
                f'原始姿态=({f["roll_deg"]:.3f}, {f["pitch_deg"]:.3f}, {f["yaw_deg"]:.3f})°   '
                f'q=({f["qx"]:.6f}, {f["qy"]:.6f}, {f["qz"]:.6f}, {f["qw"]:.6f})')
        pose_valid = self.pose_is_fresh()
        self.zero_button.config(state='normal' if pose_valid else 'disabled')
        self.initialize_button.config(state='normal' if pose_valid else 'disabled')
        self.zero_velocity_button.config(state='normal' if pose_valid and self.position_state.mode == 'ready'
                                         else 'disabled')
        self.zero_velocity_button.config(text='开始位置估算' if self.position_state.holding
                                         else '确认静止／位置锁定')
        self.restore_button.config(state='normal' if self.pose.reference else 'disabled')
        self.pose_canvas.draw(self.pose.displayed(), pose_valid, self.pose.last is not None,
                              self.pose.reference is not None, self.demo)
        position_valid = valid and self.position_state.mode == 'ready'
        position_message = self.position_state.message
        if self.position_state.mode == 'ready' and not valid:
            position_message = '数据失效或超时：位置已冻结，恢复后继续估算'
        self.position_status.config(text=position_message,
                                    fg='#087d60' if position_valid else MUTED)
        if self.position_state.mode == 'ready':
            linear = ' / '.join(f'{v:+.3f}' for v in self.position_state.linear)
            offsets = '  '.join(f'{axis}={value*100:+.1f} cm'
                                for axis, value in zip('XYZ', self.position_state.position))
            self.position_values.config(text=f'线性加速度 X/Y/Z：{linear} m/s²    距原点偏移：{offsets}',
                                        fg=INK if position_valid else '#9ca9b5')
        else:
            self.position_values.config(text='线性加速度 X/Y/Z：— m/s²    距原点偏移：X=— cm  Y=— cm  Z=— cm', fg=MUTED)
        self.position_canvas.draw(self.position_state.path, self.position_state.position,
                                  position_valid, self.demo)
        instrument = self.instrument_state
        keyboard_valid = valid and instrument.reference_q is not None
        zone_text = NOTES[instrument.zone] if instrument.zone is not None else '—'
        last = instrument.last_event
        self.keyboard_status.config(text=instrument.status if keyboard_valid else
                                    '数据失效／请先静态初始化',
                                    fg='#087d60' if keyboard_valid and not instrument.out_of_range else MUTED)
        self.keyboard_values.config(text=(f'Yaw/Pitch：{instrument.yaw:+.1f}° / {instrument.pitch:+.1f}°   音区：{zone_text}'
            f'{"（越界）" if instrument.out_of_range else ""}   '
            f'最近击打：{last["note"]} / 力度 {last["strength"]} / t={last["timestamp_ms"]} ms'
            if keyboard_valid and instrument.yaw is not None and last else
            f'Yaw/Pitch：{instrument.yaw:+.1f}° / {instrument.pitch:+.1f}°   音区：{zone_text}'
            f'{"（越界）" if instrument.out_of_range else ""}   最近击打：—'
            if keyboard_valid and instrument.yaw is not None else
            'Yaw/Pitch：— / —   音区：—   最近击打：—'),
            fg=INK if keyboard_valid else MUTED)
        self.keyboard_canvas.draw(instrument.zone, instrument.yaw,
                                  instrument.out_of_range, keyboard_valid,
                                  flash_zone=self.keyboard_flash_zone if now < self.keyboard_flash_until else None)
        if self.keyboard_zoom_canvas is not None:
            self.draw_keyboard(self.keyboard_zoom_canvas, now)
        if not self.paused and now-self.last_draw >= .2:
            for plot, history in zip(self.plots, self.history):
                plot.draw(history, now, int(self.window.get()))
            self.last_draw = now
        self.root.after(50, self.tick)

    def close(self):
        self.closing = True
        self.close_keyboard_zoom()
        self.close_deadline = time.monotonic()+2
        self.stop_recording()
        if self.reader:
            self.reader.stop_event.set()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--demo', action='store_true')
    parser.add_argument('--smoke-test', action='store_true', help='hidden demo GUI self-test; no COM port opened')
    args = parser.parse_args()
    root = tk.Tk()
    app = App(root)
    if args.smoke_test:
        root.withdraw()
        failures = []
        def check():
            try:
                assert app.good >= 20, app.good
                assert app.last_frame['valid'] == 1
                assert app.crc_errors == app.format_errors == 0
                for plot, history in zip(app.plots, app.history):
                    plot.draw(history, time.monotonic(), 30, size=(1000, 150))
                    assert len(plot.find_all()) > 20
                app.pause_plot()
                app.pause_plot()
                app.clear_plots()
                print('GUI demo acquisition, parsing, rendering and shutdown: PASS')
            except Exception as exc:
                failures.append(exc)
            finally:
                app.close()
        app.start(True)
        root.after(1800, check)
        root.mainloop()
        if failures:
            raise failures[0]
    else:
        if args.demo:
            root.after(100, lambda: app.start(True))
        root.mainloop()


if __name__ == '__main__':
    main()
