import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'notary-ticket.sh'

class NotaryTicketTests(unittest.TestCase):
    def run_ticket(self, failure, successes_after):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            command = root / 'ticket'
            command.write_text('#!/bin/bash\nn=0\n[ ! -f "$COUNT" ] || n=$(cat "$COUNT")\nn=$((n+1))\necho "$n" > "$COUNT"\n'
                               + f'[ "$n" -gt {successes_after} ] && exit 0\nexit {failure}\n')
            command.chmod(0o700)
            sleep = root / 'sleep'
            sleep.write_text('#!/bin/bash\nexit 0\n')
            sleep.chmod(0o700)
            env = dict(os.environ, COUNT=str(root / 'count'), PATH=str(root) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['bash', str(SCRIPT), str(command)], env=env, capture_output=True)
            return result.returncode, int((root / 'count').read_text())

    def test_transient_connection_recovers(self):
        self.assertEqual(self.run_ticket(68, 2), (0, 3))

    def test_nontransient_failure_is_not_hidden(self):
        self.assertEqual(self.run_ticket(65, 99), (65, 1))

    def test_retries_are_bounded_and_still_fail(self):
        self.assertEqual(self.run_ticket(68, 99), (68, 5))
