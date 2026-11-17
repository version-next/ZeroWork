#!/usr/bin/env python3
"""LP3b paired Fast/Safe release-tree vs comptime-builder measurements, serial."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time
ROOT = Path(__file__).resolve().parents[1]
METRICS = ('mount_p50_ns', 'mount_p95_ns', 'update_p50_ns', 'update_p95_ns', 'event_p50_ns', 'event_p95_ns', 'peak_requested_bytes', 'allocations')
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', default='zig'); parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--pairs', type=int, default=5)
    parser.add_argument('--production-size-only', action='store_true', help='complete production sizing for an existing benchmark result')
    args = parser.parse_args(); args.evidence.mkdir(parents=True, exist_ok=True)
    evidence = args.evidence.resolve(); report = dict(commands=[], pairs=args.pairs, configurations={}, decision='retain_dual_paths')
    if args.production_size_only:
        report = json.loads((evidence/'result.json').read_text())
        if not report.get('complete'): raise RuntimeError('complete timing evidence is required first')
    def run(argv, label, timeout=1800):
        started = time.monotonic()
        with (evidence/(label+'.log')).open('w') as log:
            child = subprocess.run(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        record = dict(command=argv, exit_code=child.returncode, elapsed_s=time.monotonic()-started)
        report['commands'].append(record)
        if child.returncode: raise RuntimeError(label+' failed')
        return record
    try:
        for optimize in (() if args.production_size_only else ('fast', 'safe')):
            binaries = {}; sizes = {}; compile_s = {}
            for mode in ('tree', 'template'):
                label = optimize+'-'+mode
                result = run([args.zig, 'build', 'storybook-exe', '-j1', '-Doptimize='+optimize, '-Dlp3b-measure=true', '-Dlp3b-template='+str(mode=='template').lower()], label+'-build')
                binary = evidence/label; shutil.copy2(ROOT/'zig-out/bin/storybook', binary); binaries[mode] = binary
                stripped = evidence/(label+'-stripped'); shutil.copy2(binary, stripped)
                run(['strip', str(stripped)], label+'-strip')
                sizes[mode] = stripped.stat().st_size; compile_s[mode] = result['elapsed_s']
            observations = {mode:[] for mode in binaries}
            for pair in range(args.pairs):
                for mode in (('tree', 'template') if pair % 2 == 0 else ('template', 'tree')):
                    binary = binaries[mode]
                    label = f'{optimize}-{mode}-{pair}'
                    result = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=300)
                    (evidence/(label+'.stdout')).write_text(result.stdout)
                    (evidence/(label+'.stderr')).write_text(result.stderr)
                    report['commands'].append(dict(command=[str(binary)], exit_code=result.returncode))
                    if result.returncode or re.search(r'panic:|leaked|\[gpa\].*leak', result.stderr, re.I): raise RuntimeError(label+' failed/leaked')
                    data = json.loads(result.stdout)
                    if not isinstance(data.get('max_rss_bytes'), int) or data['max_rss_bytes'] <= 0: raise RuntimeError('missing process RSS evidence')
                    observations[mode].append(data)
            aggregate = {}
            for mode, values in observations.items():
                aggregate[mode] = dict(stripped_bytes=sizes[mode], compile_s=compile_s[mode],
                    max_rss_bytes=statistics.median(v['max_rss_bytes'] for v in values),
                    sha256=hashlib.sha256(binaries[mode].read_bytes()).hexdigest(), scenarios={})
                for index, scenario in enumerate(('component_wall', 'for_10000', 'storybook_full')):
                    samples = [v['results'][index] for v in values]
                    if not all(s['scenario']==scenario and s['residual_bytes']==0 for s in samples): raise RuntimeError('scenario/residual contract failed')
                    aggregate[mode]['scenarios'][scenario] = {metric:statistics.median(s[metric] for s in samples) for metric in (*METRICS, 'incremental_p50_ns', 'nodes', 'residual_bytes')}
            changes = {}; failures = []
            for scenario in aggregate['tree']['scenarios']:
                a = aggregate['tree']['scenarios'][scenario]; b = aggregate['template']['scenarios'][scenario]
                if a['nodes'] != b['nodes']: raise RuntimeError('benchmark tree count changed')
                changes[scenario] = {metric:(b[metric]/a[metric]-1)*100 for metric in METRICS}
                failures += [f'{optimize}/{scenario}/{metric}: {value:+.2f}%' for metric, value in changes[scenario].items() if value > 5]
            binary_percent = (sizes['template']/sizes['tree']-1)*100
            if binary_percent > 3: failures.append(f'{optimize}/stripped_bytes: {binary_percent:+.2f}%')
            rss_percent = (aggregate['template']['max_rss_bytes']/aggregate['tree']['max_rss_bytes']-1)*100
            if rss_percent > 5: failures.append(f'{optimize}/process_RSS: {rss_percent:+.2f}%')
            report['configurations'][optimize] = dict(aggregate=aggregate, changes_percent=changes, binary_percent=binary_percent, rss_percent=rss_percent, budget_failures=failures)
        # Size the ordinary native application, without the measurement entry.
        # Benchmark executable sizes remain separately recorded for audit.
        for optimize in ('fast', 'safe'):
            config = report['configurations'][optimize]
            sizes = {}
            for mode in ('tree', 'template'):
                label = optimize+'-'+mode+'-production'
                result = run([args.zig, 'build', 'storybook-exe', '-j1', '-Doptimize='+optimize, '-Dlp3b-measure=false', '-Dlp3b-template='+str(mode=='template').lower()], label+'-build')
                binary = evidence/label; shutil.copy2(ROOT/'zig-out/bin/storybook', binary)
                run(['strip', str(binary)], label+'-strip')
                sizes[mode] = dict(stripped_bytes=binary.stat().st_size, compile_s=result['elapsed_s'], sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
            config['production_sizes'] = sizes
            config['benchmark_binary_percent'] = config.get('benchmark_binary_percent', config['binary_percent'])
            config['binary_percent'] = (sizes['template']['stripped_bytes']/sizes['tree']['stripped_bytes']-1)*100
            config['budget_failures'] = [failure for failure in config['budget_failures'] if '/stripped_bytes:' not in failure]
            if config['binary_percent'] > 3: config['budget_failures'].append(f"{optimize}/stripped_bytes: {config['binary_percent']:+.2f}%")
        report['production_size_complete'] = True
        report['budget_passed'] = all(not v['budget_failures'] for v in report['configurations'].values())
        report['complete'] = True
        if report['budget_passed']: report['decision'] = 'migration_requires_review_of_compile_time_errors_and_LP4_independence'
    except BaseException as exc: report.update(complete=False, error=f'{type(exc).__name__}: {exc}')
    (evidence/'result.json').write_text(json.dumps(report, indent=2)+'\n'); print(json.dumps(report, indent=2))
    return 0 if report['complete'] else 1
if __name__ == '__main__': raise SystemExit(main())
