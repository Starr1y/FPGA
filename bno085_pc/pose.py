"""Right-handed quaternion geometry; components are x, y, z, w."""
import math
import tkinter as tk


def normalize(q):
    if not all(math.isfinite(v) for v in q):
        raise ValueError('非有限四元数')
    length = math.sqrt(sum(v*v for v in q))
    if length < 1e-8:
        raise ValueError('四元数长度为零')
    return tuple(v/length for v in q)


def multiply(a, b):
    x, y, z, w = a
    X, Y, Z, W = b
    return (w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
            w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z)


def rotate(q, v):
    x, y, z, w = q
    result = multiply(multiply(q, (*v, 0)), (-x, -y, -z, w))
    return result[:3]


def euler_deg(q):
    """ZYX roll/pitch/yaw, matching Firmware/attitude.c."""
    x, y, z, w = normalize(q)
    pitch = max(-1.0, min(1.0, 2*(w*y-z*x)))
    return (math.degrees(math.atan2(2*(w*x+y*z), 1-2*(x*x+y*y))),
            math.degrees(math.asin(pitch)),
            math.degrees(math.atan2(2*(w*z+x*y), 1-2*(y*y+z*z))))


def relative_quaternion(q, reference):
    x, y, z, w = reference
    return normalize(multiply((-x, -y, -z, w), q))


class PoseState:
    def __init__(self):
        self.last = None
        self.reference = None
        self.usable = False

    def update(self, frame):
        self.usable = False
        if frame['valid']:
            try:
                self.last = normalize(tuple(frame[k] for k in ('qx', 'qy', 'qz', 'qw')))
                self.usable = True
            except ValueError:
                pass

    def zero(self):
        if self.usable and self.last is not None:
            self.reference = self.last

    def restore(self):
        self.reference = None

    def displayed(self):
        q = self.last or (0, 0, 0, 1)
        if self.reference is None:
            return q
        return relative_quaternion(q, self.reference)


class PoseCanvas(tk.Canvas):
    """Orthographic fixed camera; distant surfaces paint first."""
    def __init__(self, parent, **kwargs):
        super().__init__(parent, bg='white', highlightthickness=0, **kwargs)

    def draw(self, q, valid, has_pose, relative, demo=False, size=None):
        self.delete('all')
        w, h = size or (self.winfo_width(), self.winfo_height())
        if w < 100 or h < 100:
            return
        scale = min(w/5.8, (h-65)/4.6)
        cx, cy = w/2, h/2+12
        # Camera faces the origin from (1, -1, 1); rows form an orthonormal basis.
        def project(v):
            x, y, z = v
            return (cx+scale*(x+y)/math.sqrt(2),
                    cy-scale*(-x+y+2*z)/math.sqrt(6),
                    (x-y+z)/math.sqrt(3))

        self.create_text(18, 20, anchor='w', text='实时 3D 姿态',
                         fill='#18334e', font=('Microsoft YaHei UI', 13, 'bold'))
        mode = '相对参考姿态' if relative else '原始姿态'
        state = '实时' if valid else ('数据失效 · 保留最后姿态' if has_pose else '等待有效姿态')
        if demo:
            state = '模拟数据 / 非实测 · '+state
        self.create_text(18, 46, anchor='w', text=mode+'  /  '+state,
                         fill='#087d60' if valid else '#8b6670', font=('Microsoft YaHei UI', 9))
        # World floor grid provides a stationary visual reference.
        for i in range(-2, 3):
            for a, b in (((i, -2, -.9), (i, 2, -.9)), ((-2, i, -.9), (2, i, -.9))):
                pa, pb = project(a), project(b)
                self.create_line(*pa[:2], *pb[:2], fill='#edf1f5')
        vertices = [(-1.2, -.7, -.10), (1.2, -.7, -.10), (1.2, .7, -.10), (-1.2, .7, -.10),
                    (-1.2, -.7, .10), (1.2, -.7, .10), (1.2, .7, .10), (-1.2, .7, .10)]
        points = [project(rotate(q, v)) for v in vertices]
        faces = [((0, 1, 2, 3), '#b3c4d3'), ((4, 5, 6, 7), '#b4e0d1'),
                 ((0, 1, 5, 4), '#579b8b'), ((1, 2, 6, 5), '#81baa8'),
                 ((2, 3, 7, 6), '#659f91'), ((3, 0, 4, 7), '#93c9b8')]
        primitives = []
        for indices, color in faces:
            polygon = [points[i] for i in indices]
            primitives.append((sum(p[2] for p in polygon)/len(polygon), 'face', polygon, color))
        chip = [project(rotate(q, v)) for v in ((-.32, -.28, .105), (.32, -.28, .105),
                                               (.32, .28, .105), (-.32, .28, .105))]
        primitives.append((sum(p[2] for p in chip)/4, 'face', chip, '#284d61'))
        axis_colors = ('#d94b4b', '#259760', '#397cd4')
        for i, (name, color) in enumerate(zip('XYZ', axis_colors)):
            vector = [0, 0, 0]
            vector[i] = 1.9
            # Segment depth sorting hides rear axes underneath nearer board faces.
            for n in range(16):
                a = project(rotate(q, tuple(v*n/16 for v in vector)))
                b = project(rotate(q, tuple(v*(n+1)/16 for v in vector)))
                primitives.append(((a[2]+b[2])/2, 'axis', (a, b, n == 15), color))
            tip = project(rotate(q, vector))
            primitives.append((tip[2], 'label', (tip, name), color))
        for _, kind, data, color in sorted(primitives, key=lambda p: p[0]):
            color = color if valid else ('#c4cbd3' if kind == 'face' else '#939eab')
            if kind == 'face':
                self.create_polygon(*[c for p in data for c in p[:2]], fill=color,
                                    outline='#657c8b' if valid else '#a6b0bb', width=1)
            elif kind == 'axis':
                a, b, arrow = data
                self.create_line(*a[:2], *b[:2], fill=color, width=3,
                                 arrow='last' if arrow else 'none', arrowshape=(9, 11, 4))
            else:
                tip, name = data
                self.create_text(tip[0]+10, tip[1]-10, text=name, fill=color,
                                 font=('Segoe UI', 12, 'bold'))
        self.create_text(18, h-16, anchor='w', text='X 红   Y 绿   Z 蓝   ·   右手坐标系 / 固定视角',
                         fill='#64778b', font=('Microsoft YaHei UI', 9))
