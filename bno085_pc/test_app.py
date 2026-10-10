import binascii
import csv
from pathlib import Path
import queue
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch

from protocol import FIELDS, FrameError, LineBuffer, SequenceTracker, demo_line, parse_line
from recording import Recorder
from transport import Reader

SAMPLE = (b'IMU,1,39,2000,5,1,0.000000,0.000000,0.000000,0.000000,0.000000,9.812500,'
          b'0.000000,0.000000,0.000000,0.000000,0.000000,0.000000,1.000000,2,3,3,'
          b'0.250000,40,40,40,0,0,0,0,0,DB7F\r\n')


def changed(**kwargs):
    fields = SAMPLE.decode().strip().split(',')[:-1]
    for key, value in kwargs.items():
        fields[FIELDS.index(key)] = str(value)
    payload = ','.join(fields).encode('ascii')
    return payload+f',{binascii.crc_hqx(payload, 0xFFFF):04X}\r\n'.encode()


class ProtocolTests(unittest.TestCase):
    def test_firmware_fixture(self):
        f = parse_line(SAMPLE)
        self.assertEqual(f['sequence'], 39)
        self.assertEqual(f['az'], 9.8125)
        self.assertEqual(f['crc16'], 'DB7F')
        self.assertEqual(len(f.values), 32)

    def test_crc_reject(self):
        with self.assertRaises(FrameError) as result:
            parse_line(SAMPLE.replace(b'9.812500', b'9.712500'))
        self.assertEqual(result.exception.kind, 'crc')

    def test_schema_and_ranges(self):
        for kwargs in ({'version': 2}, {'valid': 2}, {'state': 8}, {'rotation_accuracy': 4},
                       {'sequence': -1}, {'timestamp_ms': 4294967296}, {'sh2_error': -2147483649},
                       {'ax': 'nan'}, {'ay': 'inf'}, {'az': 2001}, {'qx': 'garbage'},
                       {'state': 10}, {'quaternion_age_ms': 1000}):
            with self.subTest(kwargs=kwargs), self.assertRaises(FrameError):
                parse_line(changed(**kwargs))

    def test_invalid_status_preserved(self):
        f = parse_line(changed(valid=0, state=10, quaternion_age_ms=4294967295, sh2_error=-6, bus_error=7))
        self.assertEqual(f['valid'], 0)
        self.assertEqual(f['sh2_error'], -6)

    def test_prefix_and_comments(self):
        self.assertEqual(parse_line(b'\xffgarbled'+SAMPLE)['sequence'], 39)
        for line in (b'', b'\r\n', b'#BOOT,BNO085_UART\r\n'):
            self.assertIsNone(parse_line(line))
        for line in (b'junk', b'IMU,1,', SAMPLE.replace(b',DB7F', b',ZZZZ')):
            with self.assertRaises(FrameError):
                parse_line(line)

    def test_chunked_framing(self):
        stream = SAMPLE*5
        for size in (1, 3, 17, 200, 4096):
            buffer = LineBuffer()
            result = []
            for i in range(0, len(stream), size):
                result += buffer.feed(stream[i:i+size])
            self.assertEqual(len(result), 5)
            self.assertTrue(all(parse_line(row)['valid'] for row in result))

    def test_bounded_overflow_recovery(self):
        buffer = LineBuffer()
        rows = buffer.feed(b'x'*100000+b'\n'+SAMPLE)
        self.assertGreater(buffer.overflows, 0)
        self.assertLess(len(buffer.buffer), 1025)
        self.assertEqual(parse_line(rows[-1])['sequence'], 39)

    def test_demo_data(self):
        for seq in (0, 1, 50, 1000, 0xFFFFFFFF):
            f = parse_line(demo_line(seq))
            self.assertEqual(f['sequence'], seq)
            self.assertAlmostEqual(sum(f[k]**2 for k in ('qx', 'qy', 'qz', 'qw')), 1, places=5)

    def test_sequence_gaps_duplicate_restart_and_wrap(self):
        tracker = SequenceTracker()
        for seq, ms in ((10, 500), (11, 550), (14, 700), (14, 700)):
            tracker.update(parse_line(changed(sequence=seq, timestamp_ms=ms)))
        self.assertEqual((tracker.missing, tracker.duplicates), (2, 1))
        self.assertTrue(tracker.update(parse_line(changed(sequence=0, timestamp_ms=0))))
        tracker = SequenceTracker()
        tracker.update(parse_line(changed(sequence=0xFFFFFFFF, timestamp_ms=0xFFFFFFF0)))
        self.assertFalse(tracker.update(parse_line(changed(sequence=0, timestamp_ms=34))))
        self.assertEqual(tracker.missing, 0)

    def test_recording_and_no_overwrite(self):
        with tempfile.TemporaryDirectory(prefix='bno085_test_') as temp:
            path = Path(temp)/'test.csv'
            recorder = Recorder(path, 'DEMO')
            recorder.write(parse_line(SAMPLE))
            recorder.write(parse_line(changed(valid=0, state=10)))
            recorder.close()
            with path.open(encoding='utf-8-sig', newline='') as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]['source'], 'DEMO')
            self.assertEqual(rows[1]['valid'], '0')
            with self.assertRaises(FileExistsError):
                Recorder(path, 'COM3')


class ReaderTests(unittest.TestCase):
    def test_demo_thread_shutdown(self):
        events = queue.Queue(maxsize=20)
        reader = Reader('', events, True)
        reader.start()
        time.sleep(.13)
        reader.stop_event.set()
        reader.join(1)
        self.assertFalse(reader.is_alive())
        messages = list(events.queue)
        self.assertEqual(messages[0][0], 'open')
        self.assertEqual(messages[-1][0], 'closed')
        self.assertGreater(sum(event[0] == 'data' for event in messages), 1)

    def test_open_error(self):
        class FailingSerial:
            def open(self):
                raise OSError('port busy')
            def close(self):
                pass
        fake = types.SimpleNamespace(Serial=FailingSerial, EIGHTBITS=8, PARITY_NONE='N', STOPBITS_ONE=1)
        events = queue.Queue()
        with patch.dict(sys.modules, serial=fake):
            Reader('COM_FAKE', events).run()
        self.assertEqual([event[0] for event in events.queue], ['error', 'closed'])

    def test_read_only_serial_configuration(self):
        events = queue.Queue()
        reader = Reader('COM_FAKE', events)
        class FakeSerial:
            in_waiting = len(SAMPLE)
            closed = False
            def open(self):
                self.assertions = (self.baudrate, self.bytesize, self.parity, self.stopbits, self.dtr, self.rts)
            def read(self, size):
                reader.stop_event.set()
                return SAMPLE
            def close(self):
                self.closed = True
        instance = FakeSerial()
        fake = types.SimpleNamespace(Serial=lambda: instance, EIGHTBITS=8, PARITY_NONE='N', STOPBITS_ONE=1)
        with patch.dict(sys.modules, serial=fake):
            reader.run()
        self.assertEqual(instance.assertions, (115200, 8, 'N', 1, False, False))
        self.assertTrue(instance.closed)
        self.assertEqual([event[0] for event in events.queue], ['open', 'data', 'closed'])

    def test_queue_overflow_does_not_block(self):
        events = queue.Queue(maxsize=1)
        reader = Reader('', events, True)
        reader.post('data', SAMPLE)
        reader.post('data', SAMPLE)
        self.assertEqual(reader.dropped, 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
