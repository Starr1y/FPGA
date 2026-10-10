"""Short-term relative displacement estimate from BNO085 acceleration and attitude."""
from collections import deque
import math
import tkinter as tk

from pose import normalize, rotate

GRAVITY = 9.80665
CALIBRATION_MS = 3000
MIN_CALIBRATION_SAMPLES = 45
MAX_GYRO_CAL = 0.05
MAX_ACCEL_STD = 0.08
MAX_STEP_MS = 250
ACCEL_DEADBAND = 0.04  # m/s²; suppress noise without discarding existing velocity
STATIONARY_MS = 1500
STATIONARY_ACCEL = 0.06
STATIONARY_GYRO = 0.015
STATIONARY_ACCEL_STD = 0.025
STATIONARY_GYRO_STD = 0.005
STATIONARY_ANGLE = 0.01  # radians over the observation window
GYRO_BIAS_TAU_MS = 30000


def length(v):
    return math.sqrt(sum(x*x for x in v))


def add(a, b):
    return tuple(x+y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def scale(a, k):
    return tuple(x*k for x in a)


class PositionState:
    def __init__(self):
        self.reset()

    def reset(self):
        self.mode = 'idle'
        self.message = '放稳设备后点击“静态初始化”'
        self.samples = []
        self.start_ms = None
        self.last_ms = None
        self.bias = (0.0, 0.0, 0.0)
        self.gyro_bias = (0.0, 0.0, 0.0)
        self.vertical_noise = 0.0
        self.reference_q = None
        self.linear = (0.0, 0.0, 0.0)
        self.linear_body = (0.0, 0.0, 0.0)
        self.gyro_corrected = (0.0, 0.0, 0.0)
        self.velocity = (0.0, 0.0, 0.0)
        self.position = (0.0, 0.0, 0.0)
        self.path = deque([(0.0, 0.0, 0.0)], maxlen=1000)
        self.holding = False
        self.stationary = False
        self.stationary_samples = deque()

    def start(self):
        self.reset()
        self.mode = 'calibrating'
        self.message = '静态初始化：请保持设备静止 3 秒'

    def abort(self, reason):
        self.reset()
        self.message = reason

    def zero_velocity(self):
        if self.mode == 'ready':
            self.velocity = (0.0, 0.0, 0.0)
            self.holding = True
            self.stationary_samples.clear()
            self.message = '静止锁定：速度归零，位置保持；点击“开始位置估算”后继续'

    def resume(self):
        if self.mode == 'ready':
            self.velocity = (0.0, 0.0, 0.0)
            self.holding = False
            self.stationary_samples.clear()
            self.stationary = False
            self.message = '正在估算相对位置 · IMU 积分会漂移'

    @property
    def progress(self):
        if self.mode != 'calibrating' or self.start_ms is None or self.last_ms is None:
            return 0.0
        return min(1.0, ((self.last_ms-self.start_ms) & 0xFFFFFFFF)/CALIBRATION_MS)

    def update(self, frame):
        if self.mode == 'idle':
            return
        if not frame['valid']:
            if self.mode == 'calibrating':
                self.abort('初始化中断：收到无效数据，请重试')
            else:
                self.last_ms = None
                self.velocity = (0.0, 0.0, 0.0)
                self.stationary_samples.clear()
                self.stationary = False
            return
        try:
            q = normalize(tuple(frame[k] for k in ('qx', 'qy', 'qz', 'qw')))
        except ValueError:
            if self.mode == 'calibrating':
                self.abort('初始化中断：姿态无效，请重试')
            else:
                self.last_ms = None
                self.velocity = (0.0, 0.0, 0.0)
                self.stationary_samples.clear()
                self.stationary = False
            return
        ms = frame['timestamp_ms']
        if self.last_ms is not None:
            step = (ms-self.last_ms) & 0xFFFFFFFF
            if step == 0:
                return
            if step >= 0x80000000:
                self.abort('设备时间回退：位置估算已重置，请重新初始化')
                return
            if step > MAX_STEP_MS:
                if self.mode == 'calibrating':
                    self.abort('初始化中断：数据间隔过长，请重试')
                else:
                    self.last_ms = ms
                    self.velocity = (0.0, 0.0, 0.0)
                    self.stationary_samples.clear()
                    self.stationary = False
                    self.message = '数据间隔过长，速度已清零；位置估算会漂移'
                return
        else:
            step = 0
        self.last_ms = ms
        a = tuple(frame[k] for k in ('ax', 'ay', 'az'))
        gyro = tuple(frame[k] for k in ('gx', 'gy', 'gz'))
        if self.mode == 'calibrating':
            if length(gyro) > MAX_GYRO_CAL:
                self.abort('初始化中断：检测到转动，请放稳后重试')
                return
            if self.start_ms is None:
                self.start_ms = ms
            self.samples.append((q, a, gyro))
            elapsed = (ms-self.start_ms) & 0xFFFFFFFF
            self.message = f'静态初始化 {min(elapsed/1000, 3):.1f} / 3.0 秒'
            if elapsed >= CALIBRATION_MS:
                self._finish_calibration()
            return
        world = rotate(q, sub(a, self.bias))
        world_linear = sub(world, (0.0, 0.0, GRAVITY))
        self.linear_body = rotate((-q[0], -q[1], -q[2], q[3]), world_linear)
        self.gyro_corrected = sub(gyro, self.gyro_bias)
        ref = self.reference_q
        self.linear = rotate((-ref[0], -ref[1], -ref[2], ref[3]), world_linear)
        self._update_stationary(ms, q, gyro)
        if step == 0 or self.holding:
            return
        if self.stationary:
            self.velocity = (0.0, 0.0, 0.0)
            self.message = '检测到持续静止：速度自动归零 · 位置估算会漂移'
            return
        dt = step/1000.0
        old_velocity = self.velocity
        effective_accel = self.linear if length(self.linear) >= ACCEL_DEADBAND else (0.0, 0.0, 0.0)
        self.velocity = add(old_velocity, scale(effective_accel, dt))
        self.position = add(self.position, scale(add(old_velocity, self.velocity), dt/2))
        self.path.append(self.position)

    def _update_stationary(self, ms, q, gyro):
        # Estimate bias only from a sustained, quiet window; motion cannot identify gyro bias.
        if length(self.linear) > STATIONARY_ACCEL or length(sub(gyro, self.gyro_bias)) > STATIONARY_GYRO:
            self.stationary_samples.clear()
            self.stationary = False
            return
        window = self.stationary_samples
        window.append((ms, q, self.linear, gyro))
        while window and ((ms-window[0][0]) & 0xFFFFFFFF) > STATIONARY_MS:
            window.popleft()
        self.stationary = False
        if len(window) < 2 or ((ms-window[0][0]) & 0xFFFFFFFF) < STATIONARY_MS:
            return
        first_q = window[0][1]
        if any(2*math.acos(min(1.0, abs(sum(x*y for x, y in zip(first_q, item[1]))))) > STATIONARY_ANGLE
               for item in window):
            return
        for index, limit in ((2, STATIONARY_ACCEL_STD), (3, STATIONARY_GYRO_STD)):
            for axis in range(3):
                values = [item[index][axis] for item in window]
                mean = sum(values)/len(values)
                if math.sqrt(sum((value-mean)**2 for value in values)/len(values)) > limit:
                    return
        self.stationary = True
        mean_gyro = tuple(sum(item[3][axis] for item in window)/len(window) for axis in range(3))
        alpha = min(1.0, (ms-window[-2][0])/GYRO_BIAS_TAU_MS)
        self.gyro_bias = add(scale(self.gyro_bias, 1-alpha), scale(mean_gyro, alpha))
        self.gyro_corrected = sub(gyro, self.gyro_bias)

    def _finish_calibration(self):
        n = len(self.samples)
        if n < MIN_CALIBRATION_SAMPLES:
            self.abort('初始化失败：有效样本不足，请重试')
            return
        axes = list(zip(*(a for _, a, _ in self.samples)))
        if any(math.sqrt(sum((v-sum(axis)/n)**2 for v in axis)/n) > MAX_ACCEL_STD for axis in axes):
            self.abort('初始化失败：加速度波动过大，请放稳后重试')
            return
        residuals = []
        for q, a, _ in self.samples:
            inverse = (-q[0], -q[1], -q[2], q[3])
            residuals.append(sub(a, rotate(inverse, (0.0, 0.0, GRAVITY))))
        self.bias = tuple(sum(v[i] for v in residuals)/n for i in range(3))
        self.gyro_bias = tuple(sum(gyro[i] for _, _, gyro in self.samples)/n for i in range(3))
        vertical = [rotate(q, sub(a, self.bias))[2]-GRAVITY for q, a, _ in self.samples]
        vertical_mean = sum(vertical)/n
        self.vertical_noise = math.sqrt(sum((v-vertical_mean)**2 for v in vertical)/n)
        first = self.samples[0][0]
        aligned = [q if sum(x*y for x, y in zip(q, first)) >= 0 else scale(q, -1)
                   for q, _, _ in self.samples]
        self.reference_q = normalize(tuple(sum(q[i] for q in aligned)/n for i in range(4)))
        self.mode = 'ready'
        self.samples.clear()
        self.linear = self.linear_body = self.gyro_corrected = (0.0, 0.0, 0.0)
        self.velocity = self.position = (0.0, 0.0, 0.0)
        self.path.clear()
        self.path.append(self.position)
        self.holding = True
        self.stationary = False
        self.stationary_samples.clear()
        self.message = '初始化完成 · 静止锁定；点击“开始位置估算”后移动'


class PositionCanvas(tk.Canvas):
    """Fixed isometric view of the bounded recent relative trajectory."""
    def __init__(self, parent, **kwargs):
        super().__init__(parent, bg='white', highlightthickness=0, **kwargs)

    def draw(self, points, current, valid, demo=False, size=None):
        self.delete('all')
        w, h = size or (self.winfo_width(), self.winfo_height())
        if w < 100 or h < 50:
            return
        cx, cy = w/2, h/2+8
        extent = max(0.25, *(abs(v) for point in points for v in point))
        scale_factor = min((w-100)/5, (h-45)/3)/extent

        def project(v):
            x, y, z = v
            return (cx+scale_factor*(x+y)/math.sqrt(2),
                    cy-scale_factor*(-x+y+2*z)/math.sqrt(6))

        origin = project((0, 0, 0))
        self.create_text(12, 12, text='XYZ 轨迹 / cm · 会漂移' + (' · 演示' if demo else ''),
                         anchor='w', fill='#18334e', font=('Microsoft YaHei UI', 10, 'bold'))
        for i, color in enumerate(('#d94b4b', '#259760', '#397cd4')):
            axis = [0.0, 0.0, 0.0]
            axis[i] = extent*.5
            tip = project(axis)
            self.create_line(*origin, *tip, fill=color, width=2, arrow='last')
            self.create_text(tip[0]+8, tip[1]-7, text='XYZ'[i], fill=color)
        self.create_oval(origin[0]-4, origin[1]-4, origin[0]+4, origin[1]+4, fill='#18334e')
        if len(points) > 1:
            coords = [coord for point in points for coord in project(point)]
            self.create_line(*coords, fill='#007fca', width=2)
        end = project(current)
        color = '#e47b20' if valid else '#9ca9b5'
        self.create_oval(end[0]-5, end[1]-5, end[0]+5, end[1]+5, fill=color, outline='white')
        self.create_text(w-12, h-12, text='当前位置' if valid else '未初始化 / 数据失效',
                         anchor='e', fill=color)
