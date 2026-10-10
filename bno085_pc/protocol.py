"""BNO085 UART v1 framing. No serial/UI dependency."""
from dataclasses import dataclass
import binascii
import math

FIELDS = ('tag version sequence timestamp_ms state valid roll_deg pitch_deg yaw_deg '
          'ax ay az gx gy gz qx qy qz qw rotation_accuracy accel_accuracy gyro_accuracy '
          'heading_accuracy_rad quaternion_count accel_count gyro_count '
          'quaternion_age_ms accel_age_ms gyro_age_ms bus_error sh2_error crc16').split()
FLOATS = set(range(6, 19)) | {22}
STATES = {0: '启动', 1: '连接 IMU', 2: '查询版本', 3: '配置报告', 4: '等待数据',
          5: '正常采集', 10: '启动失败', 11: '产品查询失败', 12: '配置失败',
          13: '数据超时', 14: 'I²C 传输错误'}


class FrameError(ValueError):
    def __init__(self, kind, message):
        self.kind = kind
        super().__init__(message)


@dataclass(frozen=True)
class Frame:
    values: dict
    raw: str

    def __getitem__(self, name):
        return self.values[name]


def parse_line(line):
    line = line.rstrip(b'\r\n')
    if not line or line.startswith(b'#'):
        return None
    # Recover from the partial/garbled prefix seen when opening a live UART.
    start = line.find(b'IMU,')
    if start < 0:
        raise FrameError('format', '没有 IMU 帧头')
    line = line[start:]
    try:
        text = line.decode('ascii')
        parts = text.split(',')
        if len(parts) != 32:
            raise ValueError('字段数量不是 32')
        payload, checksum = line.rsplit(b',', 1)
        if len(checksum) != 4 or any(c not in b'0123456789abcdefABCDEF' for c in checksum):
            raise ValueError('CRC 格式错误')
        if binascii.crc_hqx(payload, 0xFFFF) != int(checksum, 16):
            raise FrameError('crc', 'CRC 校验失败')
        if parts[:2] != ['IMU', '1']:
            raise ValueError('不支持的协议版本')
        values = {'tag': 'IMU', 'version': 1, 'crc16': checksum.decode().upper()}
        for i in range(2, 31):
            if i in FLOATS:
                value = float(parts[i])
                if not math.isfinite(value) or abs(value) > 2000:
                    raise ValueError('浮点数据无效')
            else:
                value = int(parts[i])
                low, high = (-2147483648, 2147483647) if i == 30 else (0, 4294967295)
                if not low <= value <= high:
                    raise ValueError('整数越界')
            values[FIELDS[i]] = value
        if values['valid'] not in (0, 1) or values['state'] not in STATES:
            raise ValueError('状态值无效')
        if any(values[name] > 3 for name in FIELDS[19:22]):
            raise ValueError('精度等级无效')
        if values['valid'] and (values['state'] != 5 or any(values[k] >= 1000 for k in FIELDS[26:29])):
            raise ValueError('valid 与状态/数据年龄矛盾')
        return Frame(values, text)
    except FrameError:
        raise
    except (ValueError, UnicodeError) as exc:
        raise FrameError('format', str(exc)) from exc


class LineBuffer:
    """Bound memory even for a broken sender which never emits a newline."""
    def __init__(self):
        self.buffer = bytearray()
        self.overflows = 0

    def feed(self, data):
        lines = []
        for byte in data:
            if byte == 10:
                lines.append(bytes(self.buffer))
                self.buffer.clear()
            else:
                self.buffer.append(byte)
                if len(self.buffer) > 1024:
                    self.buffer.clear()
                    self.overflows += 1
        return lines


class SequenceTracker:
    def __init__(self):
        self.previous = None
        self.missing = self.duplicates = self.restarts = 0

    def update(self, frame):
        current = (frame['sequence'], frame['timestamp_ms'])
        restart = False
        if self.previous is not None:
            ds = (current[0] - self.previous[0]) & 0xFFFFFFFF
            dt = (current[1] - self.previous[1]) & 0xFFFFFFFF
            if ds >= 0x80000000 or dt >= 0x80000000:
                self.restarts += 1
                restart = True
            elif ds == 0:
                self.duplicates += 1
            else:
                self.missing += ds - 1
        self.previous = current
        return restart


def demo_line(sequence):
    t = sequence / 20
    values = ['IMU', '1', str(sequence & 0xFFFFFFFF), str((sequence*50) & 0xFFFFFFFF), '5', '1']
    roll = 30*math.sin(t*.6)
    pitch = 15*math.sin(t*.35)
    yaw = 50*math.sin(t*.2)
    r, p, y = [math.radians(a)/2 for a in (roll, pitch, yaw)]
    qx = math.sin(r)*math.cos(p)*math.cos(y)-math.cos(r)*math.sin(p)*math.sin(y)
    qy = math.cos(r)*math.sin(p)*math.cos(y)+math.sin(r)*math.cos(p)*math.sin(y)
    qz = math.cos(r)*math.cos(p)*math.sin(y)-math.sin(r)*math.sin(p)*math.cos(y)
    qw = math.cos(r)*math.cos(p)*math.cos(y)+math.sin(r)*math.sin(p)*math.sin(y)
    numbers = [roll, pitch, yaw, -.5*math.sin(t), .5*math.cos(t), 9.80665,
               .2*math.cos(t), .1*math.sin(t), .05*math.cos(t*.5), qx, qy, qz, qw]
    values += [f'{v:.6f}' for v in numbers]
    values += ['3', '3', '3', '0.100000'] + [str(sequence & 0xFFFFFFFF)]*3 + ['0']*5
    payload = ','.join(values).encode('ascii')
    return payload + f',{binascii.crc_hqx(payload, 0xFFFF):04X}\r\n'.encode()
