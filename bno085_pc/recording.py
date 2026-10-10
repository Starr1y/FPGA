import csv
from datetime import datetime, timezone
from protocol import FIELDS


class Recorder:
    def __init__(self, path, source):
        # Never overwrite an existing recording, even if a dialog confirmed it.
        self.file = open(path, 'x', newline='', encoding='utf-8-sig')
        self.source = source
        self.rows = 0
        self.writer = csv.writer(self.file)
        try:
            self.writer.writerow(['host_time_utc', 'source', *FIELDS])
            self.file.flush()
        except Exception:
            self.file.close()
            raise

    def write(self, frame):
        self.writer.writerow([datetime.now(timezone.utc).isoformat(), self.source,
                              *[frame[k] for k in FIELDS]])
        self.rows += 1
        if self.rows % 20 == 0:
            self.file.flush()

    def close(self):
        self.file.close()


class EventRecorder:
    """Separate keyboard events; the firmware CSV schema stays untouched."""
    FIELDS = ('host_time_utc', 'source', 'timestamp_ms', 'sequence', 'zone',
              'note', 'yaw_deg', 'strength')

    def __init__(self, path, source):
        self.file = open(path, 'x', newline='', encoding='utf-8-sig')
        self.source = source
        self.rows = 0
        self.writer = csv.writer(self.file)
        try:
            self.writer.writerow(self.FIELDS)
            self.file.flush()
        except Exception:
            self.file.close()
            raise

    def write(self, event):
        self.writer.writerow([datetime.now(timezone.utc).isoformat(), self.source,
                              *[event[key] for key in self.FIELDS[2:]]])
        self.rows += 1
        self.file.flush()

    def close(self):
        self.file.close()
