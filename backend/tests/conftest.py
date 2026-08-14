import atexit
import os
import shutil
import tempfile

_TEST_DIR = tempfile.mkdtemp(prefix="moneylock-test-")
os.environ["DATABASE_URL"] = f"sqlite:///{_TEST_DIR}/test_moneylock.db"
atexit.register(shutil.rmtree, _TEST_DIR, ignore_errors=True)