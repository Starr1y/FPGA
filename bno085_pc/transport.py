"""Background acquisition. Never touches Tk and never transmits to the MCU."""
import queue
import threading
import time
from protocol import demo_line


class Reader(threading.Thread):
    def __init__(self, port, events, demo=False):
        super().__init__(daemon=True)
        self.port, self.events, self.demo = port, events, demo
        self.stop_event = threading.Event()
        self.dropped = 0

    def post(self, kind, payload=None):
        try:
            self.events.put_nowait((kind, payload, time.monotonic()))
        except queue.Full:
            self.dropped += 1

    def run(self):
        connection = None
        try:
            if self.demo:
                self.post('open', '演示模式：模拟数据，不代表真实 IMU')
                seq = 0
                while not self.stop_event.is_set():
                    self.post('data', demo_line(seq))
                    seq += 1
                    self.stop_event.wait(.05)
            else:
                import serial
                connection = serial.Serial()
                connection.port = self.port
                connection.baudrate = 115200
                connection.timeout = .2
                connection.bytesize = serial.EIGHTBITS
                connection.parity = serial.PARITY_NONE
                connection.stopbits = serial.STOPBITS_ONE
                connection.rtscts = connection.dsrdtr = connection.xonxoff = False
                connection.dtr = connection.rts = False
                connection.open()
                self.post('open', f'{self.port} · 115200 / 8N1')
                while not self.stop_event.is_set():
                    data = connection.read(min(max(connection.in_waiting, 1), 4096))
                    if data:
                        self.post('data', data)
        except Exception as exc:
            self.post('error', f'{type(exc).__name__}: {exc}')
        finally:
            try:
                if connection is not None:
                    connection.close()
            except Exception as exc:
                self.post('error', f'关闭串口失败：{exc}')
            finally:
                self.post('closed')
