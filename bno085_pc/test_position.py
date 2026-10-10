"""Static initialization and relative-position checks without hardware."""
import math
import unittest

from position import PositionState, GRAVITY
from pose import rotate


def frame(ms, q=(0, 0, 0, 1), world_a=(0, 0, GRAVITY), gyro=(0, 0, 0), valid=1):
    inverse = (-q[0], -q[1], -q[2], q[3])
    a = rotate(inverse, world_a)
    return dict(timestamp_ms=ms, qx=q[0], qy=q[1], qz=q[2], qw=q[3],
                ax=a[0], ay=a[1], az=a[2], gx=gyro[0], gy=gyro[1], gz=gyro[2], valid=valid)


def calibrated():
    state = PositionState()
    state.start()
    for i in range(61):
        state.update(frame(i*50))
    assert state.mode == 'ready'
    assert state.holding
    state.resume()
    return state


class PositionTests(unittest.TestCase):
    def test_tilted_static_calibration_then_rotation(self):
        state = PositionState()
        state.start()
        q = (0, math.sin(math.radians(5)/2), 0, math.cos(math.radians(5)/2))
        for i in range(61):
            state.update(frame(i*50, q=q, world_a=(0, 0, GRAVITY+0.15)))
        self.assertEqual(state.mode, 'ready')
        self.assertAlmostEqual(state.position[0], 0)
        self.assertAlmostEqual(state.bias[2], 0.15*math.cos(math.radians(5)), places=3)
        state.update(frame(3050, q=(0, 0, 0, 1), world_a=(0, 0, GRAVITY+0.15)))
        self.assertLess(abs(state.linear[0]), 0.02)

    def test_acceleration_coasting_manual_stop_and_second_move(self):
        state = calibrated()
        for i in range(61, 81):
            state.update(frame(i*50, world_a=(1, 0, GRAVITY)))
        self.assertGreater(state.position[0], 0.4)
        self.assertAlmostEqual(state.velocity[0], 1.0, places=2)
        first_position = state.position[0]
        for i in range(81, 101):
            state.update(frame(i*50))
        self.assertGreater(state.position[0], first_position+0.9)
        self.assertAlmostEqual(state.velocity[0], 1.0, places=2)
        stopped_position = state.position
        state.zero_velocity()
        self.assertEqual(state.velocity, (0, 0, 0))
        self.assertEqual(state.position, stopped_position)
        self.assertTrue(state.holding)
        for i in range(101, 121):
            state.update(frame(i*50, world_a=(1, 0, GRAVITY)))
        self.assertEqual(state.position, stopped_position)
        state.resume()
        for i in range(121, 141):
            state.update(frame(i*50, world_a=(1, 0, GRAVITY)))
        self.assertGreater(state.position[0], stopped_position[0]+0.4)

    def test_calibration_holds_position_until_manual_start(self):
        state = PositionState()
        state.start()
        for i in range(61):
            state.update(frame(i*50))
        self.assertTrue(state.holding)
        for i in range(61, 261):
            state.update(frame(i*50, world_a=(.1, 0, GRAVITY)))
        self.assertEqual(state.position, (0, 0, 0))
        self.assertEqual(state.velocity, (0, 0, 0))
        state.resume()
        for i in range(261, 281):
            state.update(frame(i*50, world_a=(.1, 0, GRAVITY)))
        self.assertGreater(state.position[0], .04)

    def test_static_gyro_bias_and_body_acceleration(self):
        state = PositionState()
        state.start()
        q = (0, math.sin(math.radians(5)/2), 0, math.cos(math.radians(5)/2))
        bias = (0.005, -0.004, 0.003)
        for i in range(61):
            state.update(frame(i*50, q=q, gyro=bias))
        self.assertEqual(state.mode, 'ready')
        self.assertEqual(state.gyro_bias, bias)
        state.update(frame(3050, q=q, gyro=bias))
        self.assertLess(max(abs(v) for v in state.linear_body), 1e-8)
        self.assertLess(max(abs(v) for v in state.gyro_corrected), 1e-8)

    def test_small_static_noise_does_not_integrate_and_stationary_zeroes_velocity(self):
        state = calibrated()
        for i in range(61, 261):
            jitter = 0.025 if i % 2 else -0.025
            state.update(frame(i*50, world_a=(jitter, 0, GRAVITY)))
        self.assertEqual(state.position, (0, 0, 0))
        state.velocity = (0.5, 0, 0)
        for i in range(261, 281):
            state.update(frame(i*50))
        self.assertEqual(state.position, (0, 0, 0))
        self.assertEqual(state.velocity, (0, 0, 0))

    def test_stationary_window_zeroes_velocity_then_motion_resumes(self):
        state = calibrated()
        for i in range(61, 81):
            state.update(frame(i*50, world_a=(1, 0, GRAVITY)))
        self.assertGreater(state.velocity[0], .9)
        for i in range(81, 122):
            state.update(frame(i*50))
        self.assertTrue(state.stationary)
        self.assertEqual(state.velocity, (0, 0, 0))
        stopped = state.position
        for i in range(122, 162):
            state.update(frame(i*50))
        self.assertEqual(state.position, stopped)
        state.update(frame(8100, world_a=(1, 0, GRAVITY)))
        self.assertFalse(state.stationary)
        self.assertGreater(state.position[0], stopped[0])

    def test_online_gyro_bias_only_updates_during_stationary_window(self):
        state = calibrated()
        for i in range(61, 121):
            state.update(frame(i*50, gyro=(.008, 0, 0)))
        self.assertTrue(state.stationary)
        self.assertGreater(state.gyro_bias[0], 0)
        before = state.gyro_bias
        for i in range(121, 181):
            state.update(frame(i*50, world_a=(.5, 0, GRAVITY), gyro=(.1, 0, 0)))
        self.assertEqual(state.gyro_bias, before)
        self.assertFalse(state.stationary)

    def test_calibration_motion_invalid_gap_and_restart(self):
        state = PositionState()
        state.start()
        state.update(frame(0))
        state.update(frame(50, gyro=(0.1, 0, 0)))
        self.assertEqual(state.mode, 'idle')
        state.start()
        state.update(frame(0))
        state.update(frame(300))
        self.assertEqual(state.mode, 'idle')
        state.start()
        state.update(frame(0))
        state.update(frame(50, valid=0))
        self.assertEqual(state.mode, 'idle')
        state = calibrated()
        state.update(frame(2900))
        self.assertEqual(state.mode, 'idle')

    def test_duplicate_gap_reinitialize(self):
        state = calibrated()
        state.update(frame(3000, world_a=(1, 0, GRAVITY)))
        self.assertEqual(state.position, (0, 0, 0))
        state.update(frame(3050, world_a=(1, 0, GRAVITY)))
        self.assertGreater(state.position[0], 0)
        state.update(frame(3400, world_a=(1, 0, GRAVITY)))
        self.assertEqual(state.velocity, (0, 0, 0))
        state.start()
        self.assertEqual(state.position, (0, 0, 0))
        self.assertEqual(state.mode, 'calibrating')

    def test_position_axes_follow_initial_board_heading(self):
        state = PositionState()
        state.start()
        q = (0, 0, math.sqrt(.5), math.sqrt(.5))
        for i in range(61):
            state.update(frame(i*50, q=q))
        self.assertEqual(state.mode, 'ready')
        self.assertAlmostEqual(state.reference_q[2], math.sqrt(.5), places=5)
        state.resume()
        world_motion = (*rotate(q, (1, 0, 0))[:2], GRAVITY)
        for i in range(61, 81):
            state.update(frame(i*50, q=q, world_a=world_motion))
        self.assertGreater(state.position[0], 0.4)
        self.assertAlmostEqual(state.position[1], 0, places=5)


if __name__ == '__main__':
    unittest.main()
