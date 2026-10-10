"""Seven-zone keyboard experiment. No absolute position or audio generation."""
import math
import tkinter as tk

from pose import euler_deg, normalize, relative_quaternion, rotate

NOTES = ('Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si')
ZONE_MIN = -70.0
ZONE_MAX = 70.0
ZONE_WIDTH = 20.0
HYSTERESIS_DEG = 3.0
ARM_MS = 300
REFRACTORY_MS = 120
STRENGTH_WINDOW_MS = 100
MAX_STEP_MS = 250


def magnitude(values):
    return math.sqrt(sum(value*value for value in values))


class InstrumentState:
    def __init__(self):
        self.reset()

    def reset(self, reference_q=None, vertical_noise=0.0):
        self.reference_q = reference_q
        self.vertical_noise = vertical_noise
        self.yaw = None
        self.pitch = None
        self.zone = None
        self.out_of_range = False
        self.armed = False
        self.quiet_since = None
        self.last_ms = None
        self.last_vertical = None
        self.last_pitch = None
        self.arm_pitch = None
        self.last_trigger_ms = None
        self.pending = None
        self.last_event = None
        self.status = '请先静态初始化'
        self.button_reference_pitch = None
        self.bend_semitones = 0.0

    def invalidate(self):
        self.armed = False
        self.quiet_since = None
        self.last_ms = None
        self.last_vertical = None
        self.last_pitch = None
        self.arm_pitch = None
        self.last_trigger_ms = None
        self.pending = None
        self.status = '数据失效：击打检测暂停'

    def update_button(self, pressed, pitch_deg):
        """Reserved for a future physical button; not connected to today's UART."""
        if pressed:
            if self.button_reference_pitch is None:
                self.button_reference_pitch = pitch_deg
            self.bend_semitones = max(-2.0, min(2.0, (pitch_deg-self.button_reference_pitch)/10.0))
        else:
            self.button_reference_pitch = None
            self.bend_semitones = 0.0
        return self.bend_semitones

    def _select_zone(self, yaw):
        self.out_of_range = not ZONE_MIN <= yaw <= ZONE_MAX
        if self.out_of_range:
            return
        target = min(6, max(0, int((yaw-ZONE_MIN)//ZONE_WIDTH)))
        if self.zone is None:
            self.zone = target
        elif target > self.zone and yaw >= ZONE_MIN+(self.zone+1)*ZONE_WIDTH+HYSTERESIS_DEG:
            self.zone = target
        elif target < self.zone and yaw <= ZONE_MIN+self.zone*ZONE_WIDTH-HYSTERESIS_DEG:
            self.zone = target

    def update(self, frame, linear_body, gyro_corrected, sensitivity=1.0):
        """Return one finalized hit event, or None. Uses device time in milliseconds."""
        if self.reference_q is None or not frame['valid']:
            self.invalidate()
            return None
        try:
            q = normalize(tuple(frame[k] for k in ('qx', 'qy', 'qz', 'qw')))
        except ValueError:
            self.invalidate()
            return None
        ms = frame['timestamp_ms']
        step = 0
        if self.last_ms is not None:
            step = (ms-self.last_ms) & 0xFFFFFFFF
            if step == 0:
                return None
            if step >= 0x80000000 or step > MAX_STEP_MS:
                self.invalidate()
        self.last_ms = ms
        _, self.pitch, self.yaw = euler_deg(relative_quaternion(q, self.reference_q))
        self._select_zone(self.yaw)
        vertical = rotate(q, linear_body)[2]
        sensitivity = max(0.5, min(2.0, float(sensitivity)))
        threshold = max(0.6, 6*self.vertical_noise)*sensitivity
        pitch_rate = ((self.pitch-self.last_pitch)*1000/step
                      if self.last_pitch is not None and step > 0 else 0.0)
        self.last_pitch = self.pitch
        event = None
        if self.pending is not None:
            self.pending['peak_down_m_s2'] = max(self.pending['peak_down_m_s2'], -vertical)
            self.pending['peak_pitch_rate_deg_s'] = max(self.pending['peak_pitch_rate_deg_s'], -pitch_rate)
            if ((ms-self.pending['timestamp_ms']) & 0xFFFFFFFF) >= STRENGTH_WINDOW_MS:
                hit = self.pending
                rate_strength = max(0.0, min(1.0, (hit['peak_pitch_rate_deg_s']-18)/70))
                accel_strength = max(0.0, min(1.0, hit['peak_down_m_s2']/3))
                hit['strength'] = max(1, min(127, round(1+126*(.7*rate_strength+.3*accel_strength))))
                del hit['peak_down_m_s2']
                del hit['peak_pitch_rate_deg_s']
                self.last_event = event = hit
                self.pending = None
        quiet = abs(vertical) < threshold*.35 and magnitude(gyro_corrected) < .04
        if quiet:
            if self.quiet_since is None:
                self.quiet_since = ms
            if ((ms-self.quiet_since) & 0xFFFFFFFF) >= ARM_MS and self.pending is None:
                if not self.armed:
                    self.arm_pitch = self.pitch
                    self.armed = True
        else:
            self.quiet_since = None
        self.last_vertical = vertical
        cooled = self.last_trigger_ms is None or ((ms-self.last_trigger_ms) & 0xFFFFFFFF) >= REFRACTORY_MS
        pitch_drop = self.arm_pitch-self.pitch if self.arm_pitch is not None else 0.0
        if self.armed and cooled and pitch_drop >= 6.0*sensitivity and pitch_rate <= -18.0*sensitivity:
            self.armed = False
            self.arm_pitch = None
            self.quiet_since = None
            self.last_trigger_ms = ms
            if not self.out_of_range and self.zone is not None:
                self.pending = {'timestamp_ms': ms, 'sequence': frame['sequence'],
                                'zone': self.zone+1, 'note': NOTES[self.zone],
                                'yaw_deg': round(self.yaw, 3),
                                'peak_down_m_s2': max(0.0, -vertical),
                                'peak_pitch_rate_deg_s': -pitch_rate}
        self.status = ('越界：禁止击打' if self.out_of_range else
                       '力度采样中' if self.pending else
                       '已武装：等待下拍' if self.armed else '等待动作恢复／静止武装')
        return event


class KeyboardCanvas(tk.Canvas):
    def __init__(self, parent, **kwargs):
        super().__init__(parent, bg='white', highlightthickness=0, **kwargs)

    def draw(self, zone, yaw, out_of_range, active, size=None, flash_zone=None):
        self.delete('all')
        w, h = size or (self.winfo_width(), self.winfo_height())
        if w < 100 or h < 45:
            return
        cx, cy = w/2, h+8
        radius = min(w*.46, h*1.8)
        def point(angle, distance):
            angle = math.radians(angle)
            return cx+math.sin(angle)*distance, cy-math.cos(angle)*distance
        for index, name in enumerate(NOTES):
            a = ZONE_MIN+index*ZONE_WIDTH
            b = a+ZONE_WIDTH
            polygon = [point(a, radius*.16), point(a, radius),
                       point(b, radius), point(b, radius*.16)]
            coords = [value for vertex in polygon for value in vertex]
            selected = active and zone == index and not out_of_range
            flashing = active and flash_zone == index
            self.create_polygon(*coords, fill='#ffbd55' if flashing else
                                '#d7f3e9' if selected else '#eaf0f6',
                                outline='#9ab1c6', width=2 if selected else 1)
            x, y = point((a+b)/2, radius*.72)
            self.create_text(x, y, text=name, fill='#794000' if flashing else
                             '#087d60' if selected else '#18334e',
                             font=('Segoe UI', 9, 'bold' if selected or flashing else 'normal'))
        if yaw is not None:
            x, y = point(max(ZONE_MIN, min(ZONE_MAX, yaw)), radius*.94)
            self.create_oval(x-4, y-4, x+4, y+4,
                             fill='#b42318' if out_of_range else '#e47b20', outline='white')
