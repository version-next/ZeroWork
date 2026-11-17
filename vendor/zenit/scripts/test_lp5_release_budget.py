#!/usr/bin/env python3
"""Fail-closed measurement evidence contract (independent of timing comparisons)."""
import copy
import json
import os
from pathlib import Path
import shutil
import signal
import unittest
import subprocess
import sys
import tempfile
import time
from measure_lp5_release import METRICS, TIMINGS, INSTRUCTION_QUANTILES, UNITS, SCENES, validate_observation, run_bounded, compare_metric, change_base


ARRAYS = tuple((p, u) for p in ('mount', 'update', 'event', 'incremental', 'unmount') for u in UNITS)


class ChangeBase(unittest.TestCase):
    def test_branch_measures_against_where_it_left_main_and_main_against_its_parent(self):
        with tempfile.TemporaryDirectory() as root:
            def git(*argv):
                return subprocess.check_output(['git', '-c', 'user.email=t@t', '-c', 'user.name=t', *argv], cwd=root, text=True).strip()
            git('init', '-q', '-b', 'main')
            git('commit', '-q', '--allow-empty', '-m', 'one')
            first = git('rev-parse', 'HEAD')
            git('commit', '-q', '--allow-empty', '-m', 'two')
            fork = git('rev-parse', 'HEAD')
            self.assertEqual(first, change_base(Path(root)))
            git('switch', '-q', '-c', 'topic')
            git('commit', '-q', '--allow-empty', '-m', 'change')
            git('switch', '-q', 'main')
            git('commit', '-q', '--allow-empty', '-m', 'main moves on')
            git('switch', '-q', 'topic')
            self.assertEqual(fork, change_base(Path(root)))


class BudgetDecisions(unittest.TestCase):
    def test_budget_counts_instructions_never_wall_time(self):
        # Same-binary A/A wall time moved by up to +24% on a shared host.
        self.assertFalse([m for m in METRICS if m.endswith('_ns')])
        for phase in ('mount', 'update', 'event', 'unmount'):
            self.assertIn(phase + '_min_instr', METRICS)
        self.assertFalse([m for m in METRICS if m.endswith(('_p50_instr', '_p95_instr'))])

    def test_reported_minimum_must_match_raw_instruction_samples(self):
        evidence = BudgetEvidence()
        evidence.setUp()
        for prefix in ('mount', 'update', 'event', 'incremental', 'unmount'):
            for delta in (-1, 1):
                with self.subTest(prefix=prefix, delta=delta):
                    data = copy.deepcopy(evidence.good)
                    data['results'][0][f'{prefix}_min_instr'] += delta
                    with self.assertRaises(ValueError):
                        validate_observation(0, json.dumps(data), '')

    def test_quiet_control_retains_original_estimator_and_five_percent(self):
        self.assertTrue(compare_metric(*([[100]*7]*3), [105]*7)['passed'])
        self.assertFalse(compare_metric(*([[100]*7]*3), [105.01]*7)['passed'])
        self.assertEqual(compare_metric(*([[100]*7]*4))['estimator'], 'ratio_of_medians')

    def test_noisy_control_requires_fixed_multi_round_paired_median(self):
        result = compare_metric([100]*7, [80, 120, 90, 110, 100, 101, 99],
                                [100, 200, 100, 200, 100, 200, 100],
                                [100, 202, 99, 198, 102, 199, 101])
        self.assertTrue(result['aa_exceeds_budget'])
        self.assertTrue(result['passed'])
        self.assertEqual(result['estimator'], 'median_paired_changes')
        self.assertAlmostEqual(result['change_percent'], 0)

    def test_control_bias_cannot_be_waived_as_noise(self):
        self.assertFalse(compare_metric([100]*7, [110]*7, [100]*7, [100]*7)['passed'])
        self.assertFalse(compare_metric([100]*7, [90]*7, [100]*7, [100]*7)['passed'])

    def test_missing_pairs_and_invalid_values_fail_closed(self):
        for bad in ([100]*6, [100]*8, [100]*6+[float('nan')], [100]*6+[0]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                compare_metric([100]*7, bad, [100]*7, [100]*7)

    def test_stable_fifteen_percent_regression_mutation_is_rejected(self):
        # Inject a stable multiplicative +15% into treatment only. Even a
        # control with 40% dispersion must not mask this real regression.
        baseline = [100, 200, 300, 100, 200, 300, 100]
        for control in ([100]*7, [60, 140, 70, 130, 100, 101, 99]):
            with self.subTest(control=control):
                clean = compare_metric([100]*7, control, baseline, baseline)
                mutant = compare_metric([100]*7, control, baseline, [v*1.15 for v in baseline])
                self.assertTrue(clean['passed'])
                self.assertFalse(mutant['passed'])
                self.assertAlmostEqual(mutant['change_percent'], 15)


class BudgetEvidence(unittest.TestCase):
    def setUp(self):
        self.good = dict(samples=11, warmups=5, updates_per_sample=20,
                         max_rss_bytes=1024, renderer='none',
                         allocator='CountingAllocator(DebugAllocator)', results=[dict(
                             scenario=scene, residual_bytes=0, nodes=50,
                             **{metric: 100 for metric in (*METRICS, *TIMINGS, *INSTRUCTION_QUANTILES)}) for scene in SCENES])
        self.with_raw_samples(self.good, 11)

    @staticmethod
    def with_raw_samples(data, samples):
        # Independently pinned expected indices; do not duplicate the validator.
        p50_index, p95_index = {5: (2, 4), 6: (3, 5), 11: (5, 10),
                                20: (10, 18), 51: (25, 48)}[samples]
        data['samples'] = samples
        for row in data['results']:
            for prefix, unit in ARRAYS:
                # Descending input proves validation sorts a copy rather than
                # assuming the emitted raw arrays have already been sorted.
                base = 0 if prefix == 'incremental' else 100
                raw = list(reversed(range(base, base + samples)))
                ordered = sorted(raw)
                row[f'{prefix}_samples_{unit}'] = raw
                row[f'{prefix}_p50_{unit}'] = ordered[p50_index]
                row[f'{prefix}_p95_{unit}'] = ordered[p95_index]
                if unit == 'instr':
                    row[f'{prefix}_min_instr'] = ordered[0]

    def test_timeout_after_success_markers(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            run_bounded([sys.executable, '-c', 'import time; print("All tests passed", flush=True); time.sleep(10)'],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=.1)

    @unittest.skipUnless(os.name == 'posix' and hasattr(os, 'killpg'),
                         'POSIX process-group interruption contract')
    def test_interruption_stops_real_child_group_before_source_restoration_returns(self):
        # Run the real mutator in an isolated checkout. Its executable fixture
        # forks a real descendant after a successful baseline; no Zig build or
        # signal to the unittest runner is involved. A success marker precedes
        # the interrupt, so it cannot stand in for process completion.
        scripts = Path(__file__).resolve().parent
        signals = [signal.SIGINT, signal.SIGTERM]
        if hasattr(signal, 'SIGHUP'):
            signals.append(signal.SIGHUP)
        for signum in signals:
            with self.subTest(signal=signum), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                os.mkfifo(root/'group.fifo', 0o600)
                read_fd = os.open(root/'group.fifo', os.O_RDONLY | os.O_NONBLOCK)
                self.addCleanup(os.close, read_fd)
                (root/'scripts').mkdir()
                for name in ('measure_lp5_release.py', 'test_lp5_release_oracle_mutation.py',
                             'test_component_view_mutation.py'):
                    shutil.copy2(scripts/name, root/'scripts'/name)
                target = root/'src/ui/template.zig'
                target.parent.mkdir(parents=True)
                original = ('pub fn viewEmit(self: @This(), scope: *Scope, cx: *Cx, '
                            'sink: v.Sink) anyerror!void {\n}\n')
                target.write_text(original)
                (root/'original.zig').write_text(original)
                executable = root/'fake-zig'
                executable.write_text('#!' + sys.executable + '\n' + '''import json
import os
from pathlib import Path
import subprocess
import sys
import time
root = Path(__file__).resolve().parent
if (root/'src/ui/template.zig').read_bytes() == (root/'original.zig').read_bytes():
    print('All tests passed', flush=True)
    raise SystemExit(0)
(root/'leader.pid').write_text(str(os.getpid()))
write_fd = os.open(root/'group.fifo', os.O_WRONLY)
worker = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'],
                          pass_fds=(write_fd,))
print('All tests passed', flush=True)
temporary = root/'group.tmp'
temporary.write_text(json.dumps(dict(leader=os.getpid(), worker=worker.pid)))
temporary.replace(root/'group.json')
time.sleep(60)
''')
                executable.chmod(0o700)
                evidence = root/'evidence'
                process = subprocess.Popen([
                    sys.executable, str(root/'scripts/test_lp5_release_oracle_mutation.py'),
                    '--zig', str(executable), '--evidence', str(evidence)],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    start_new_session=True)
                group = None
                try:
                    deadline = time.monotonic() + 8
                    while not (root/'group.json').is_file():
                        if process.poll() is not None or time.monotonic() >= deadline:
                            self.fail('mutated subprocess group did not become ready')
                        time.sleep(.01)
                    group = json.loads((root/'group.json').read_text())
                    with self.assertRaises(BlockingIOError):
                        os.read(read_fd, 1)
                    self.assertNotEqual(target.read_text(), original)
                    self.assertIn('All tests passed', (evidence/'release_extra_scope.log').read_text())
                    os.kill(process.pid, signum)
                    output, errors = process.communicate(timeout=8)
                    self.assertEqual(process.returncode, 1, (output, errors))
                    report = json.loads((evidence/'result.json').read_text())
                    self.assertFalse(report['passed'])
                    self.assertIn('KeyboardInterrupt', report['error'])
                    self.assertTrue(report['source_restored'])
                    self.assertEqual(target.read_text(), original)
                    # Both real processes retain a FIFO writer throughout
                    # sleep. Kernel EOF therefore proves that killing/reaping
                    # only the leader cannot satisfy the cleanup contract. An
                    # exited zombie has already closed its FDs and is harmless.
                    deadline = time.monotonic() + 3
                    while True:
                        try:
                            self.assertEqual(os.read(read_fd, 1), b'')
                            break
                        except BlockingIOError:
                            if time.monotonic() >= deadline:
                                self.fail('child group still holds the lifetime FIFO')
                            time.sleep(.01)
                finally:
                    # Also clean up when testing the unfixed implementation:
                    # failed evidence must not leave its sleeping children alive.
                    leader = group['leader'] if group else (
                        int((root/'leader.pid').read_text()) if (root/'leader.pid').is_file() else None)
                    if leader is not None:
                        try:
                            os.killpg(leader, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    if process.poll() is None:
                        process.kill()
                    process.communicate(timeout=3)

    def test_complete(self):
        self.assertEqual(validate_observation(0, json.dumps(self.good), ''), self.good)

    def test_variable_sample_counts_use_upper_median_and_nearest_rank_p95(self):
        for samples in (5, 6, 20, 51):
            with self.subTest(samples=samples):
                data = copy.deepcopy(self.good)
                self.with_raw_samples(data, samples)
                original = copy.deepcopy(data)
                self.assertEqual(validate_observation(0, json.dumps(data), ''), original)
                # In particular n=20 uses index 18, not the maximum at index 19.
                if samples == 20:
                    self.assertEqual(data['results'][0]['mount_p95_ns'], 118)

    def test_missing_truncated_extra_and_non_array_raw_evidence(self):
        for prefix, unit in ARRAYS:
            key = f'{prefix}_samples_{unit}'
            for defect in ('missing', 'short', 'long', 'string', 'object', 'null'):
                with self.subTest(prefix=prefix, unit=unit, defect=defect):
                    data = copy.deepcopy(self.good)
                    row = data['results'][0]
                    if defect == 'missing':
                        row.pop(key)
                    elif defect == 'short':
                        row[key].pop()
                    elif defect == 'long':
                        row[key].append(row[key][-1])
                    else:
                        row[key] = {'string': 'samples', 'object': {}, 'null': None}[defect]
                    with self.assertRaises((ValueError, KeyError)):
                        validate_observation(0, json.dumps(data), '')

    def test_invalid_raw_numbers_are_rejected_in_every_array(self):
        for prefix, unit in ARRAYS:
            for value in (float('nan'), float('inf'), -float('inf'), -1, True, '100', None):
                with self.subTest(prefix=prefix, unit=unit, value=value):
                    data = copy.deepcopy(self.good)
                    data['results'][0][f'{prefix}_samples_{unit}'][0] = value
                    with self.assertRaises(ValueError):
                        validate_observation(0, json.dumps(data), '')

    def test_zero_only_allowed_in_incremental_raw_samples(self):
        for prefix, unit in ((p, u) for p, u in ARRAYS if p != 'incremental'):
            with self.subTest(prefix=prefix):
                data = copy.deepcopy(self.good)
                data['results'][0][f'{prefix}_samples_{unit}'][0] = 0
                with self.assertRaises(ValueError):
                    validate_observation(0, json.dumps(data), '')
        data = copy.deepcopy(self.good)
        for row in data['results']:
            for unit in UNITS:
                row[f'incremental_samples_{unit}'] = [0] * data['samples']
                row[f'incremental_p50_{unit}'] = row[f'incremental_p95_{unit}'] = 0
            row['incremental_min_instr'] = 0
        self.assertEqual(validate_observation(0, json.dumps(data), ''), data)

    def test_reported_quantiles_cannot_hide_or_invent_a_tail(self):
        for prefix, unit in ARRAYS:
            for quantile in ('p50', 'p95'):
                for delta in (-1, 1):
                    with self.subTest(prefix=prefix, unit=unit, quantile=quantile, delta=delta):
                        data = copy.deepcopy(self.good)
                        data['results'][0][f'{prefix}_{quantile}_{unit}'] += delta
                        with self.assertRaises(ValueError):
                            validate_observation(0, json.dumps(data), '')
            # A larger raw maximum must not survive behind the old p95 summary
            # for the 11-sample fixture, whose nearest-rank p95 is its maximum.
            data = copy.deepcopy(self.good)
            data['results'][0][f'{prefix}_samples_{unit}'][0] += 1000
            with self.subTest(prefix=prefix, unit=unit, defect='raw_tail_changed'), self.assertRaises(ValueError):
                validate_observation(0, json.dumps(data), '')

    def test_samples_requires_an_actual_integer_of_at_least_five(self):
        for value in (True, False, 11.0, float('nan'), float('inf'), '11', None, -1, 0, 4):
            with self.subTest(samples=value):
                data = copy.deepcopy(self.good)
                data['samples'] = value
                with self.assertRaises(ValueError):
                    validate_observation(0, json.dumps(data), '')
        data = copy.deepcopy(self.good)
        data.pop('samples')
        with self.assertRaises(ValueError):
            validate_observation(0, json.dumps(data), '')

    def test_success_payload_cannot_hide_crash_timeout_or_leak(self):
        for code, stderr in ((1, ''), (-11, ''), (0, 'panic: after success'),
                             (0, '[gpa] memory address leaked'), (0, 'timed out after success'), (0, '[zenit_control_flow] rebuild failed'),
                             (0, '[reactive.Signal] graph.markSignalWritten failed')):
            with self.subTest(code=code, stderr=stderr), self.assertRaises(ValueError):
                validate_observation(code, json.dumps(self.good), stderr)

    def test_missing_duplicate_and_partial_measurements(self):
        variants = []
        for mutate in (
            lambda d: d['results'].pop(),
            lambda d: d['results'].append(d['results'][0]),
            lambda d: d['results'][0].pop('update_p95_ns'),
            lambda d: d['results'][0].pop('update_p95_instr'),
            lambda d: d['results'][0].pop('unmount_samples_instr'),
            lambda d: d['results'][0].update(residual_bytes=1),
            lambda d: d['results'][0].update(peak_requested_bytes=0),
            lambda d: d['results'][0].update(update_p50_ns=float('nan')),
            lambda d: d.update(samples=0),
            lambda d: d.update(max_rss_bytes=0),
            lambda d: d.update(max_rss_bytes=float('nan')),
            lambda d: d.update(max_rss_bytes=float('inf')),
        ):
            data = copy.deepcopy(self.good)
            mutate(data)
            variants.append(data)
        for data in variants:
            with self.subTest(data=data), self.assertRaises((ValueError, KeyError)):
                validate_observation(0, json.dumps(data), '')


if __name__ == '__main__':
    unittest.main()
