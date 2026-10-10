"""Geometry and GUI regression checks; never opens a hardware port."""
import csv
import math
from pathlib import Path
import tempfile
import time
import tkinter as tk
import unittest

from app import App
from pose import PoseState, normalize, rotate
from protocol import parse_line
from recording import Recorder, EventRecorder
from test_app import SAMPLE, changed


class GeometryTests(unittest.TestCase):
    def assertVector(self, actual, expected):
        for a, b in zip(actual, expected):
            self.assertAlmostEqual(a, b, places=6)

    def test_identity_normalization_and_right_handed_axes(self):
        self.assertVector(rotate(normalize((0, 0, 0, 4)), (1, 2, 3)), (1, 2, 3))
        s = math.sqrt(.5)
        for q, v, expected in (((s, 0, 0, s), (0, 1, 0), (0, 0, 1)),
                               ((0, s, 0, s), (0, 0, 1), (1, 0, 0)),
                               ((0, 0, s, s), (1, 0, 0), (0, 1, 0))):
            self.assertVector(rotate(q, v), expected)

    def test_relative_pose_and_restore(self):
        pose = PoseState()
        s = math.sqrt(.5)
        pose.update(parse_line(changed(qz=s, qw=s)))
        original = pose.displayed()
        pose.zero()
        self.assertVector(rotate(pose.displayed(), (1, 0, 0)), (1, 0, 0))
        pose.update(parse_line(changed(qz=1, qw=0)))
        self.assertVector(rotate(pose.displayed(), (1, 0, 0)), (0, 1, 0))
        pose.restore()
        self.assertVector(rotate(pose.displayed(), (1, 0, 0)), (-1, 0, 0))
        self.assertNotEqual(original, pose.displayed())

    def test_invalid_quaternion_retains_last_pose(self):
        pose = PoseState()
        pose.update(parse_line(SAMPLE))
        last = pose.last
        for frame in (changed(valid=0, state=10), changed(qw=0)):
            pose.update(parse_line(frame))
            self.assertFalse(pose.usable)
            self.assertEqual(pose.last, last)
        for q in ((0, 0, 0, 0), (math.nan, 0, 0, 1)):
            with self.assertRaises(ValueError):
                normalize(q)


class DashboardTests(unittest.TestCase):
    def setUp(self):
        self.root = tk.Tk()
        self.root.withdraw()
        self.app = App(self.root)
        self.app.connected = True
        self.app.consume(SAMPLE, time.monotonic())
        self.app.tick()

    def tearDown(self):
        if self.app.recorder or self.app.event_recorder:
            self.app.stop_recording()
        self.root.destroy()

    def test_reference_does_not_change_frame_history_or_csv(self):
        before = dict(self.app.last_frame.values)
        histories = [list(h) for h in self.app.history]
        with tempfile.TemporaryDirectory(prefix='bno085_dashboard_') as folder:
            path = Path(folder)/'data.csv'
            self.app.recorder = Recorder(path, 'DEMO')
            self.app.zero_view()
            self.assertIsNotNone(self.app.pose.reference)
            self.app.consume(changed(sequence=40, timestamp_ms=2050), time.monotonic())
            self.app.stop_recording()
            with path.open(encoding='utf-8-sig', newline='') as stream:
                row = next(csv.DictReader(stream))
            for name in ('roll_deg', 'pitch_deg', 'yaw_deg', 'qx', 'qy', 'qz', 'qw'):
                self.assertEqual(float(row[name]), before[name])
        self.assertEqual([list(h)[:1] for h in self.app.history], histories)
        self.app.restore_view()
        self.assertIsNone(self.app.pose.reference)

    def test_timeout_invalid_and_reconnect(self):
        original = self.app.pose.last
        self.app.zero_view()
        self.app.last_received = time.monotonic()-2
        self.app.tick()
        self.assertIn('超时', self.app.status_label['text'])
        self.assertEqual(str(self.app.zero_button['state']), 'disabled')
        self.assertEqual(self.app.pose.last, original)
        self.app.restore_view()
        self.app.zero_view()
        self.assertIsNone(self.app.pose.reference)
        self.app.consume(changed(valid=0, state=10), time.monotonic())
        self.app.tick()
        self.assertEqual(self.app.pose.last, original)
        self.assertEqual(str(self.app.zero_button['state']), 'disabled')
        self.app.events.put(('closed', None, time.monotonic()))
        self.app.tick()
        self.assertIsNone(self.app.pose.reference)
        self.app.reset_session()
        self.assertIsNone(self.app.pose.last)

    def test_tabs_pause_clear_resize_and_diagnostics(self):
        self.root.deiconify()
        for size in ('1280x900', '1000x720'):
            self.root.geometry(size)
            self.root.update()
            for tab in range(3):
                self.app.notebook.select(tab)
                self.root.update()
                self.app.plots[tab].draw(self.app.history[tab], time.monotonic(), 30)
                self.assertGreater(len(self.app.plots[tab].find_all()), 20)
            self.app.tick()
            self.assertGreater(len(self.app.pose_canvas.find_all()), 30)
            self.app.notebook.select(3)
            self.root.update()
            self.app.keyboard_canvas.draw(self.app.instrument_state.zone,
                                          self.app.instrument_state.yaw, False, False)
            self.assertGreater(len(self.app.keyboard_canvas.find_all()), 8)
            for widget in (self.app.keyboard_canvas, self.app.keyboard_values,
                           self.app.hit_sensitivity):
                self.assertGreaterEqual(widget.winfo_height(), widget.winfo_reqheight()
                                        if widget != self.app.keyboard_canvas else 45)
                self.assertLessEqual(widget.winfo_rooty()+widget.winfo_height(),
                                     self.root.winfo_rooty()+self.root.winfo_height())
            self.app.keyboard_canvas.event_generate('<Button-1>', x=20, y=20)
            self.root.update()
            self.assertIsNotNone(self.app.keyboard_zoom)
            self.assertGreaterEqual(self.app.keyboard_zoom_canvas.winfo_width(), 500)
            self.app.keyboard_zoom_canvas.event_generate('<Button-1>', x=20, y=20)
            self.root.update()
            self.assertIsNone(self.app.keyboard_zoom)
            self.app.notebook.select(4)
            self.root.update()
            self.app.position_canvas.draw(self.app.position_state.path,
                                          self.app.position_state.position, False)
            self.assertGreater(len(self.app.position_canvas.find_all()), 8)
            self.app.toggle_diagnostics()
            self.root.update()
            for widget in (self.app.pose_canvas, self.app.notebook, self.app.message):
                self.assertGreater(widget.winfo_height(), 70 if widget == self.app.pose_canvas else 10)
                self.assertLessEqual(widget.winfo_rooty()+widget.winfo_height(),
                                     self.root.winfo_rooty()+self.root.winfo_height())
            for side_tab, names in enumerate((('roll_deg', 'pitch_deg', 'yaw_deg'),
                                              ('ax', 'ay', 'az'), ('gx', 'gy', 'gz'))):
                self.app.sidebar_notebook.select(side_tab)
                self.root.update()
                for name in names:
                    raw = self.app.value_labels[name]
                    corrected = (self.app.relative_labels if side_tab == 0
                                 else self.app.corrected_labels)[name]
                    for widget in (raw, corrected):
                        self.assertGreaterEqual(widget.winfo_height(), widget.winfo_reqheight())
                        self.assertLessEqual(widget.winfo_rooty()+widget.winfo_height(),
                                             self.root.winfo_rooty()+self.root.winfo_height())
            self.app.toggle_diagnostics()
        self.app.pause_plot()
        self.app.consume(changed(sequence=41, timestamp_ms=2100, qz=.707107, qw=.707107), time.monotonic())
        self.app.tick()
        self.assertNotEqual(self.app.pose.last, (0, 0, 0, 1))
        self.assertEqual(self.app.good, 2)
        self.app.clear_plots()
        self.assertTrue(all(not h for h in self.app.history))
        self.assertIsNotNone(self.app.pose.last)
        self.app.pause_plot()

    def test_position_initialization_ui_and_disconnect(self):
        self.assertEqual(self.app.notebook.tab(self.app.notebook.select(), 'text'), '七音区验证')
        self.app.sidebar_notebook.select(1)
        self.app.tick()
        self.assertEqual(self.app.corrected_labels['ax']['text'], '—')
        self.app.initialize_position()
        self.assertEqual(self.app.position_state.mode, 'calibrating')
        self.app.tick()
        self.assertIn('静态初始化', self.app.position_status['text'])
        self.app.events.put(('closed', None, time.monotonic()))
        self.app.tick()
        self.assertEqual(self.app.position_state.mode, 'idle')
        self.assertIsNone(self.app.instrument_state.reference_q)

    def test_live_keyboard_event_and_separate_csv(self):
        with tempfile.TemporaryDirectory(prefix='bno085_keyboard_') as folder:
            raw_path = Path(folder)/'raw.csv'
            event_path = Path(folder)/'raw_events.csv'
            self.app.recorder = Recorder(raw_path, 'COM7')
            self.app.event_recorder = EventRecorder(event_path, 'COM7')
            self.app.initialize_position()
            for i in range(61):
                self.app.consume(changed(sequence=40+i, timestamp_ms=2050+i*50), time.monotonic())
            for i in range(61, 68):
                self.app.consume(changed(sequence=40+i, timestamp_ms=2050+i*50), time.monotonic())
            self.app.consume(changed(sequence=108, timestamp_ms=5450,
                                     qy=-.087156, qw=.996195, az=8.0), time.monotonic())
            self.assertEqual(self.app.keyboard_flash_zone, 3)
            self.app.consume(changed(sequence=109, timestamp_ms=5500,
                                     qy=-.087156, qw=.996195, az=7.0), time.monotonic())
            self.app.consume(changed(sequence=110, timestamp_ms=5550,
                                     qy=-.087156, qw=.996195), time.monotonic())
            self.app.tick()
            self.assertIn('Fa', self.app.keyboard_values['text'])
            self.assertEqual(self.app.keyboard_flash_zone, 3)
            self.app.keyboard_canvas.draw(3, 0, False, True, size=(600, 180), flash_zone=3)
            fills = [self.app.keyboard_canvas.itemcget(item, 'fill')
                     for item in self.app.keyboard_canvas.find_all()]
            self.assertIn('#ffbd55', fills)
            self.app.toggle_keyboard_zoom()
            self.root.update()
            self.assertIsNotNone(self.app.keyboard_zoom)
            self.app.keyboard_zoom_canvas.draw(3, 0, False, True,
                                               size=(900, 480), flash_zone=3)
            self.assertGreater(len(self.app.keyboard_zoom_canvas.find_all()), 8)
            self.app.close_keyboard_zoom()
            self.assertIsNone(self.app.keyboard_zoom)
            self.app.stop_recording()
            with event_path.open(encoding='utf-8-sig', newline='') as stream:
                events = list(csv.DictReader(stream))
            self.assertEqual(len(events), 1)
            self.assertEqual(events[0]['note'], 'Fa')
            with raw_path.open(encoding='utf-8-sig', newline='') as stream:
                self.assertEqual(next(csv.reader(stream))[2], 'tag')

    def test_tilted_static_sidebar_shows_raw_and_corrected(self):
        self.app.initialize_position()
        angle = math.radians(5)/2
        q = (0, math.sin(angle), 0, math.cos(angle))
        a = rotate((-q[0], -q[1], -q[2], q[3]), (0, 0, 9.80665))
        for i in range(61):
            self.app.consume(changed(sequence=40+i, timestamp_ms=2050+i*50,
                                     pitch_deg=5, qy=q[1], qw=q[3],
                                     ax=a[0], ay=a[1], az=a[2],
                                     gx=.005, gy=-.004, gz=.003), time.monotonic())
        self.app.consume(changed(sequence=101, timestamp_ms=5100, pitch_deg=5,
                                 qy=q[1], qw=q[3], ax=a[0], ay=a[1], az=a[2],
                                 gx=.005, gy=-.004, gz=.003), time.monotonic())
        self.app.sidebar_notebook.select(1)
        self.app.tick()
        self.assertGreater(abs(float(self.app.value_labels['ax']['text'])), .8)
        self.assertLess(abs(float(self.app.corrected_labels['ax']['text'])), .01)
        self.app.sidebar_notebook.select(2)
        self.root.update()
        self.assertEqual(self.app.value_labels['gx']['text'], '0.005')
        self.assertEqual(self.app.corrected_labels['gx']['text'], '0.000')
        self.app.last_received = time.monotonic()-2
        self.app.tick()
        self.assertEqual(self.app.corrected_labels['gx']['fg'], '#9ca9b5')

    def test_static_init_zeroes_displayed_attitude_but_keeps_raw_frame(self):
        self.app.initialize_position()
        for i in range(61):
            self.app.consume(changed(sequence=40+i, timestamp_ms=2050+i*50,
                                     yaw_deg=90, qz=math.sqrt(.5), qw=math.sqrt(.5)),
                             time.monotonic())
        for i in range(2):
            self.app.consume(changed(sequence=101+i, timestamp_ms=5100+i*50,
                                     yaw_deg=90, qz=math.sqrt(.5), qw=math.sqrt(.5)),
                             time.monotonic())
        self.app.tick()
        self.assertEqual(self.app.position_state.mode, 'ready')
        self.assertAlmostEqual(float(self.app.value_labels['yaw_deg']['text']), 90, places=2)
        self.assertAlmostEqual(float(self.app.relative_labels['yaw_deg']['text']), 0, places=2)
        self.assertEqual(self.app.last_frame['yaw_deg'], 90)
        self.assertIn('原始', self.app.value_titles[0]['text'])
        self.assertEqual(len(self.app.history[0][-1][1]), 6)
        self.assertAlmostEqual(self.app.history[0][-1][1][2], 90)
        self.assertAlmostEqual(self.app.history[0][-1][1][5], 0, places=2)
        for index in range(3):
            self.assertEqual(len(self.app.history[index][-1][1]), 6)
            self.app.plots[index].draw(self.app.history[index], time.monotonic(), 30, size=(1000, 180))
            dashed = [item for item in self.app.plots[index].find_all()
                      if self.app.plots[index].type(item) == 'line'
                      and self.app.plots[index].itemcget(item, 'dash')]
            self.assertGreaterEqual(len(dashed), 3)
        self.assertEqual(self.app.corrected_labels['az']['text'], '0.000')
        self.assertEqual(self.app.corrected_labels['gz']['text'], '0.000')
        self.app.sidebar_notebook.select(1)
        self.root.update()
        self.assertEqual(self.app.sidebar_notebook.tab(self.app.sidebar_notebook.select(), 'text'), '加速度')
        self.assertEqual(self.app.value_labels['ax']['text'], '0.000')
        self.assertEqual(self.app.corrected_labels['ax']['text'], '0.000')
        self.assertEqual(str(self.app.zero_velocity_button['state']), 'normal')
        self.assertTrue(self.app.position_state.holding)
        self.assertEqual(self.app.zero_velocity_button['text'], '开始位置估算')
        self.app.toggle_position_motion()
        self.assertFalse(self.app.position_state.holding)
        self.app.position_state.position = (0.1, 0.0, 0.0)
        self.app.position_state.velocity = (1.0, 0.0, 0.0)
        self.app.confirm_stationary()
        self.assertTrue(self.app.position_state.holding)
        self.assertEqual(self.app.position_state.velocity, (0.0, 0.0, 0.0))
        self.assertEqual(self.app.position_state.position, (0.1, 0.0, 0.0))
        self.app.tick()
        self.assertEqual(self.app.zero_velocity_button['text'], '开始位置估算')
        self.assertIn('cm', self.app.position_values['text'])
        self.assertIn('距原点偏移', self.app.position_values['text'])
        self.assertIn('X=+10.0 cm', self.app.position_values['text'])
        self.assertIn('Y=+0.0 cm', self.app.position_values['text'])
        self.assertIn('Z=+0.0 cm', self.app.position_values['text'])
        self.app.restore_view()
        self.app.tick()
        self.assertAlmostEqual(float(self.app.value_labels['yaw_deg']['text']), 90, places=2)
        self.assertAlmostEqual(float(self.app.relative_labels['yaw_deg']['text']), 0, places=2)

    def test_demo_continuous_acquisition_and_shutdown(self):
        self.app.start(True)
        deadline = time.monotonic()+.4
        while time.monotonic() < deadline:
            self.root.update()
            time.sleep(.01)
        self.assertGreaterEqual(self.app.good, 5)
        self.assertIn('非实测', self.app.status_label['text'])
        reader = self.app.reader
        self.app.zero_view()
        self.app.toggle_connection()
        self.assertIsNone(self.app.pose.reference)
        reader.join(1)
        self.app.tick()
        self.assertFalse(reader.is_alive())
        self.assertFalse(self.app.connected)


if __name__ == '__main__':
    unittest.main(verbosity=2)
