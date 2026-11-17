#!/usr/bin/env python3
"""Serial LP5 release budgets versus the change's base, with identical measurement harnesses.

The baseline defaults to where the measured branch left main (`git merge-base HEAD main`; on
main itself, the previous commit): the budget asks whether this change slowed the release
build. A fixed historical baseline stopped working as soon as main changed the Storybook
initial UI (its node count must match on both sides)."""
import argparse
import hashlib
import io
import math
import os
import json
from pathlib import Path
import re
import shutil
import signal
import statistics
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]
SCENES = ('branches_1000', 'for_10000', 'slots_1000', 'storybook_full',
          'portals_200', 'component_for_1000')
PHASES = ('mount', 'update', 'event', 'unmount')
# Budgeted: the minimum retired instructions of each timed region, plus requested memory. Every
# sample repeats identical work on a fresh Cx; what varies between samples (interrupts, page
# faults, other kernel work charged to the thread) only adds instructions, so the minimum is the
# code's own cost. Measured noise floors, same executable on a shared host (A/A max |change|):
# wall time p50/p95 up to 24%/160%, instruction p50 9%, p95 22%, minimum 3.6% (paired A/B
# median 0.15%). A wall-time budget therefore failed every change, the unchanged one included.
# Wall time and instruction quantiles stay in the evidence as diagnostics.
METRICS = tuple(f'{phase}_min_instr' for phase in PHASES) + ('peak_requested_bytes', 'allocations')
TIMINGS = tuple(f'{phase}_{q}_ns' for phase in PHASES for q in ('p50', 'p95'))
INSTRUCTION_QUANTILES = tuple(f'{phase}_{q}_instr' for phase in PHASES for q in ('p50', 'p95'))
UNITS = ('ns', 'instr')
HARNESS = ('examples/storybook/lp5_release_bench.zig', 'examples/storybook/lp5_release.yix.in')


def run_bounded(argv, *, cwd=None, timeout, stdout=None, stderr=None, text=False):
    """An interrupted wait kills the group and reaps its leader before returning."""
    process = subprocess.Popen(argv, cwd=cwd, stdout=stdout, stderr=stderr, text=text,
                               start_new_session=True)
    try:
        output, errors = process.communicate(timeout=timeout)
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()
        raise
    return subprocess.CompletedProcess(argv, process.returncode, output, errors)


def validate_observation(code, stdout, stderr):
    if code or stderr.strip():
        raise ValueError('benchmark failed/leaked')
    data = json.loads(stdout)
    rss = data.get('max_rss_bytes')
    samples = data.get('samples')
    if (type(samples) is not int or samples < 5 or type(rss) not in (int, float)
            or not math.isfinite(rss) or rss <= 0):
        raise ValueError('missing timing/RSS evidence')
    p95_index = (samples * 95 + 99) // 100 - 1
    if [r['scenario'] for r in data['results']] != list(SCENES):
        raise ValueError('missing/duplicate scenario')
    for row in data['results']:
        if row['residual_bytes'] != 0:
            raise ValueError('nonzero residual')
        for metric in (*METRICS, *TIMINGS, *INSTRUCTION_QUANTILES, *(f'incremental_{q}_{u}' for q in ('p50', 'p95') for u in UNITS), 'incremental_min_instr', 'nodes'):
            number = row[metric]
            if type(number) not in (int, float) or not math.isfinite(number) or number < 0:
                raise ValueError('invalid measurement: '+metric)
        if any(row[metric] <= 0 for metric in (*METRICS, *TIMINGS, *INSTRUCTION_QUANTILES)) or row['nodes'] <= 0:
            raise ValueError('missing positive measurement')
        # The executable reports chronological raw samples before sorting its
        # local copies. Check the evidence independently; do not trust summary
        # fields or silently repair them before the unchanged budget comparison.
        for prefix, unit in ((p, u) for p in (*PHASES, 'incremental') for u in UNITS):
            raw = row[f'{prefix}_samples_{unit}']
            if type(raw) is not list or len(raw) != samples:
                raise ValueError(f'missing/truncated samples: {prefix} ({unit})')
            for number in raw:
                if (type(number) not in (int, float) or not math.isfinite(number)
                        or number < 0 or (prefix != 'incremental' and number == 0)):
                    raise ValueError(f'invalid raw sample: {prefix} ({unit})')
            ordered = sorted(raw)
            if (row[f'{prefix}_p50_{unit}'] != ordered[samples // 2]
                    or row[f'{prefix}_p95_{unit}'] != ordered[p95_index]):
                raise ValueError(f'reported quantile differs from raw samples: {prefix} ({unit})')
            if unit == 'instr' and row[f'{prefix}_min_instr'] != ordered[0]:
                raise ValueError(f'reported minimum differs from raw samples: {prefix}')
    return data



def compare_metric(aa_before, aa_after, before, after, limit=5):
    """Preregistered rule: seven or more paired rounds, no discarded samples.

    A/A dispersion is the maximum absolute paired change. When it exceeds
    the budget, use the median of paired A/B percentage changes (rather than
    a ratio of independently aggregated quantiles). Require A/A's paired median
    within +/-limit too: a persistently biased control cannot qualify a result.
    Never subtract dispersion from a regression or enlarge the budget.
    """
    arrays = (aa_before, aa_after, before, after)
    if len(before) < 7 or any(len(x) != len(before) for x in arrays):
        raise ValueError('at least seven complete A/A and A/B pairs required')
    if any(type(v) not in (int, float) or not math.isfinite(v) or v <= 0
           for values in arrays for v in values):
        raise ValueError('invalid comparison input')
    aa = [(b/a-1)*100 for a, b in zip(aa_before, aa_after)]
    ab = [(b/a-1)*100 for a, b in zip(before, after)]
    dispersion = max(abs(x) for x in aa)
    aa_median = statistics.median(aa)
    ratio = (statistics.median(after)/statistics.median(before)-1)*100
    paired = statistics.median(ab)
    noisy = dispersion > limit + 1e-9
    change = paired if noisy else ratio
    qualified = abs(aa_median) <= limit + 1e-9
    return dict(aa_changes_percent=aa, ab_changes_percent=ab,
                aa_dispersion_percent=dispersion, aa_median_percent=aa_median,
                aa_exceeds_budget=noisy, aa_qualified=qualified,
                estimator='median_paired_changes' if noisy else 'ratio_of_medians',
                ratio_of_medians_percent=ratio, paired_median_percent=paired,
                change_percent=change, limit_percent=limit,
                passed=qualified and change <= limit + 1e-9)


def change_base(root=ROOT):
    """Where HEAD left main; on main itself, its previous commit."""
    def rev(*argv):
        return subprocess.check_output(['git', *argv], cwd=root, text=True).strip()
    head = rev('rev-parse', 'HEAD')
    base = rev('merge-base', 'HEAD', 'main')
    return rev('rev-parse', 'HEAD^1') if base == head else base


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--baseline', default=None, help='Git ref (default: the change base, see above)')
    parser.add_argument('--after', default='working-tree', help='Git ref or working-tree')
    parser.add_argument('--pairs', type=int, default=7)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    if args.baseline is None:
        args.baseline = change_base()
    if args.pairs < 7:
        parser.error('at least seven alternating pairs are required')
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    report = dict(baseline=args.baseline, after=args.after, pairs=args.pairs, commands=[], configurations={}, snapshots={}, rule='aa-qualified-adaptive-median-v2-min-instructions', complete=False, passed=False)

    def run(argv, cwd, label, timeout=1800):
        start = time.monotonic()
        with (evidence / (label + '.log')).open('w') as log:
            result = run_bounded(argv, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        report['commands'].append(dict(argv=argv, cwd=str(cwd), exit_code=result.returncode, seconds=time.monotonic()-start))
        if result.returncode:
            raise RuntimeError(label + ' failed')

    def snapshot(ref, label):
        dest = ROOT / '.zig-cache' / ('lp5-release-' + label)
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True)
        archive = subprocess.check_output(['git', 'archive', 'HEAD' if ref == 'working-tree' else ref], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(dest, filter='data')
        if ref == 'working-tree':
            # Overlay the actual current inputs, including deletions and new files.
            paths = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT).decode().split('\0')
            for relative in filter(None, paths):
                source = ROOT / relative
                target = dest / relative
                if source.is_file():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
                elif target.is_file():
                    target.unlink()
        inventory = {str(p.relative_to(dest)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in dest.rglob('*') if p.is_file() and p.suffix in ('.zig', '.zon', '.yix', '.yss')}
        report['snapshots'][label] = dict(ref=ref, inputs_sha256=hashlib.sha256(
            json.dumps(inventory, sort_keys=True).encode()).hexdigest())
        (evidence/(label+'-inputs.json')).write_text(json.dumps(inventory, indent=2)+'\n')
        for relative in HARNESS:
            target = dest / relative.removesuffix('.in')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        main = dest / 'examples/storybook/main.zig'
        old = '@import("lp3b_bench.zig")'
        text = main.read_text()
        if text.count(old) != 1:
            raise RuntimeError('measurement entry anchor changed')
        main.write_text(text.replace(old, '@import("lp5_release_bench.zig")'))
        return dest

    try:
        checkouts = {mode: snapshot(ref, mode) for mode, ref in (('before', args.baseline), ('after', args.after))}
        report['harness_sha256'] = {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in HARNESS}
        for optimize in ('fast', 'safe'):
            binaries = {}
            sizes = {}
            for mode, checkout in checkouts.items():
                label = optimize + '-' + mode
                run([args.zig, 'build', 'storybook-exe', '-Doptimize='+optimize, '-Dlp3b-measure=true', '-Ddev-preview=false', '-j1'], checkout, label+'-build')
                binary = evidence / label
                shutil.copy2(checkout / 'zig-out/bin/storybook', binary)
                binaries[mode] = binary
                # Ordinary full Storybook size, with the measurement entry erased.
                run([args.zig, 'build', 'storybook-exe', '-Doptimize='+optimize, '-Dlp3b-measure=false', '-Ddev-preview=false', '-j1'], checkout, label+'-production-build')
                production = evidence / (label + '-production')
                shutil.copy2(checkout / 'zig-out/bin/storybook', production)
                run(['strip', str(production)], checkout, label+'-strip')
                sizes[mode] = production.stat().st_size
            values = {mode: [] for mode in ('aa_before', 'aa_after', 'before', 'after')}
            for pair in range(args.pairs):
                # Counterbalance control/treatment order; A/A uses the exact same file.
                order = ('aa_before', 'aa_after', 'before', 'after')
                for mode in (order if pair % 2 == 0 else tuple(reversed(order))):
                    binary = binaries['before' if mode.startswith('aa_') else mode]
                    observed_at = time.time()
                    wall_start = time.monotonic()
                    cpu_start = os.times()
                    load_before = os.getloadavg() if hasattr(os, 'getloadavg') else None
                    result = run_bounded([str(binary)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=600)
                    cpu_end = os.times()
                    observation = dict(start_unix_seconds=observed_at,
                        wall_seconds=time.monotonic()-wall_start,
                        child_user_seconds=cpu_end.children_user-cpu_start.children_user,
                        child_system_seconds=cpu_end.children_system-cpu_start.children_system,
                        host_load_before=load_before,
                        host_load_after=os.getloadavg() if hasattr(os, 'getloadavg') else None)
                    (evidence / f'{optimize}-{mode}-{pair}.stdout').write_text(result.stdout)
                    (evidence / f'{optimize}-{mode}-{pair}.stderr').write_text(result.stderr)
                    report['commands'].append(dict(argv=[str(binary)], exit_code=result.returncode))
                    data = validate_observation(result.returncode, result.stdout, result.stderr)
                    # Diagnostic context only: budgets always use the original
                    # wall-clock samples, regardless of host load or CPU ratio.
                    data['process_observation'] = observation
                    values[mode].append(data)
            aggregate = {}
            for mode, observations in values.items():
                aggregate[mode] = dict(stripped_bytes=sizes['before' if mode.startswith('aa_') else mode], sha256=hashlib.sha256(binaries['before' if mode.startswith('aa_') else mode].read_bytes()).hexdigest(),
                    max_rss_bytes=statistics.median(v['max_rss_bytes'] for v in observations), scenarios={})
                for index, scene in enumerate(SCENES):
                    metrics = (*METRICS, *TIMINGS, *INSTRUCTION_QUANTILES, *(f'incremental_{q}_{u}' for q in ('p50', 'p95') for u in UNITS), 'incremental_min_instr', 'nodes', 'residual_bytes')
                    aggregate[mode]['scenarios'][scene] = {metric: statistics.median(v['results'][index][metric] for v in observations) for metric in metrics}
            changes = {}
            wall_time = {}
            decisions = {}
            failures = []
            for scene in SCENES:
                before = aggregate['before']['scenarios'][scene]
                after = aggregate['after']['scenarios'][scene]
                if before['nodes'] != after['nodes']:
                    raise RuntimeError('node count changed: '+scene)
                metrics = METRICS + (('incremental_min_instr',) if scene in ('for_10000', 'component_for_1000') else ())
                decisions[scene] = {}
                for metric in metrics:
                    decisions[scene][metric] = compare_metric(*[
                        [v['results'][SCENES.index(scene)][metric] for v in values[mode]]
                        for mode in ('aa_before', 'aa_after', 'before', 'after')])
                    decision = decisions[scene][metric]
                    if not decision['passed']:
                        failures.append(f"{scene}/{metric}: {decision['change_percent']:+.3f}%, A/A median {decision['aa_median_percent']:+.3f}%")
                changes[scene] = {metric: decision['change_percent'] for metric, decision in decisions[scene].items()}
                # Not budgeted (see METRICS): reported so a wall-time-only effect stays visible.
                wall_time[scene] = {metric: (after[metric]/before[metric]-1)*100 for metric in TIMINGS}
            size_percent = (sizes['after']/sizes['before']-1)*100
            rss_decision = compare_metric(*[[v['max_rss_bytes'] for v in values[mode]]
                for mode in ('aa_before', 'aa_after', 'before', 'after')])
            rss_percent = rss_decision['change_percent']
            if size_percent > 3:
                failures.append(f'stripped_bytes: {size_percent:+.3f}%')
            if not rss_decision['passed']:
                failures.append(f'process_RSS: {rss_percent:+.3f}% (A/A qualified={rss_decision["aa_qualified"]})')
            report['configurations'][optimize] = dict(values=values, aggregate=aggregate, changes_percent=changes,
                wall_time_change_percent=wall_time, size_percent=size_percent, rss_percent=rss_percent, decisions=decisions, rss_decision=rss_decision, failures=failures)
        report['complete'] = True
        report['passed'] = all(not config['failures'] for config in report['configurations'].values())
    except BaseException as exc:
        report['error'] = f'{type(exc).__name__}: {exc}'
    (evidence / 'result.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'commands'}, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
