"""Run the source UI using repository-root docs, FPGA project and results."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'source'))
import tanglab
tanglab.ROOT=ROOT
if __name__=='__main__':raise SystemExit(tanglab.main())
