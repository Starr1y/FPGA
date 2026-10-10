"""Seven-zone and downstroke recognition tests at current 20 Hz telemetry rate."""
import csv
import math
from pathlib import Path
import tempfile
import unittest

from instrument import InstrumentState
from pose import multiply
from recording import EventRecorder


def frame(ms, yaw=0, pitch=0, valid=1, sequence=1):
    half = math.radians(yaw)/2
    pitch_half = math.radians(pitch)/2
    q = multiply((0, 0, math.sin(half), math.cos(half)),
                 (0, math.sin(pitch_half), 0, math.cos(pitch_half)))
    return {'timestamp_ms': ms, 'sequence': sequence, 'valid': valid,
            'qx': q[0], 'qy': q[1], 'qz': q[2], 'qw': q[3]}


class InstrumentTests(unittest.TestCase):
    def setUp(self):
        self.state = InstrumentState()
        self.state.reset((0, 0, 0, 1), .01)

    def feed(self, ms, yaw=0, pitch=0, vertical=0, gyro=(0, 0, 0), valid=1):
        return self.state.update(frame(ms, yaw, pitch, valid, ms//50),
                                 (0, 0, vertical), gyro)

    def test_seven_zones_and_hysteresis(self):
        for i, yaw in enumerate((-60, -40, -20, 0, 20, 40, 60)):
            self.feed(i*50, yaw)
            self.assertEqual(self.state.zone, i)
        self.state.reset((0, 0, 0, 1), .01)
        self.feed(0, -60)
        self.feed(50, -48)
        self.assertEqual(self.state.zone, 0)
        self.feed(100, -46)
        self.assertEqual(self.state.zone, 1)
        self.feed(150, -52)
        self.assertEqual(self.state.zone, 1)
        self.feed(200, -54)
        self.assertEqual(self.state.zone, 0)

    def test_hit_latches_zone_strength_and_rearms(self):
        for ms in range(0, 350, 50):
            self.feed(ms)
        self.assertTrue(self.state.armed)
        self.feed(350, yaw=0, pitch=-10, vertical=-1)
        self.feed(400, yaw=40, pitch=-12, vertical=-2)
        event = self.feed(450, yaw=40, pitch=-12)
        self.assertEqual((event['note'], event['zone']), ('Fa', 4))
        self.assertGreater(event['strength'], 1)
        self.assertIsNone(self.feed(500, yaw=40, pitch=-12, vertical=-2))
        for ms in range(550, 950, 50):
            self.feed(ms, yaw=40)
        self.assertTrue(self.state.armed)
        self.feed(950, yaw=40, pitch=-10, vertical=-1)
        self.feed(1000, yaw=40, pitch=-10)
        event = self.feed(1050, yaw=40, pitch=-10)
        self.assertEqual(event['note'], 'La')

    def test_out_of_range_invalid_and_gap_block_hits(self):
        for ms in range(0, 350, 50):
            self.feed(ms, yaw=72)
        self.assertTrue(self.state.out_of_range)
        self.feed(350, yaw=72, pitch=-10, vertical=-2)
        self.assertIsNone(self.feed(450, yaw=72))
        self.feed(500, valid=0)
        self.assertFalse(self.state.armed)

    def test_acceleration_without_pitch_down_is_not_a_hit(self):
        for ms in range(0, 350, 50):
            self.feed(ms)
        self.feed(350, vertical=-3)
        self.assertIsNone(self.state.pending)
        self.assertTrue(self.state.armed)
        self.feed(1000)
        self.assertFalse(self.state.armed)

    def test_sensitivity_and_future_button_pitch(self):
        for ms in range(0, 350, 50):
            self.feed(ms)
        self.assertIsNone(self.state.update(frame(350, pitch=-7), (0, 0, -.8), (0, 0, 0), 1.5))
        self.assertIsNone(self.state.pending)
        self.assertEqual(self.state.update_button(True, 10), 0)
        self.assertAlmostEqual(self.state.update_button(True, 20), 1)
        self.assertEqual(self.state.update_button(False, 25), 0)

    def test_event_csv_is_separate_and_exclusive(self):
        with tempfile.TemporaryDirectory(prefix='bno085_events_') as folder:
            path = Path(folder)/'events.csv'
            recorder = EventRecorder(path, 'COM7')
            recorder.write({'timestamp_ms': 350, 'sequence': 7, 'zone': 4,
                            'note': 'Fa', 'yaw_deg': 0.0, 'strength': 42})
            recorder.close()
            with path.open(encoding='utf-8-sig', newline='') as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(rows[0]['strength'], '42')
            self.assertEqual(rows[0]['note'], 'Fa')
            with self.assertRaises(FileExistsError):
                EventRecorder(path, 'COM7')


if __name__ == '__main__':
    unittest.main()
