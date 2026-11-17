#!/usr/bin/env python3
"""Prove LP5 boundary normalization cannot hide production scope changes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import signal
import subprocess
from test_component_view_mutation import is_compile_failure
from measure_lp5_release import run_bounded

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'pub fn viewEmit(self: @This(), scope: *Scope, cx: *Cx, sink: v.Sink) anyerror!void {'
MUTANTS = (
    ('release_extra_scope', ENTRY,
     ENTRY + '\n            if (comptime !preview_enabled) { _ = try scope.childScope(); }'),
    ('release_changed_ownership', ENTRY,
     'pub fn viewEmit(self: @This(), caller: *Scope, cx: *Cx, sink: v.Sink) anyerror!void {\n'
     '            const scope = if (comptime !preview_enabled) try caller.childScope() else caller;'),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    path = ROOT/'src/ui/template.zig'
    original = path.read_bytes()
    report = dict(mutants=[], source_sha256=hashlib.sha256(original).hexdigest())
    pending = None

    def run(name):
        with (args.evidence/(name+'.log')).open('w') as log:
            result = run_bounded([args.zig, 'build', 'test-template-equivalence', '-j1'], cwd=ROOT,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=900)
        return result.returncode, (args.evidence/(name+'.log')).read_text()
    previous = {}

    def interrupted(signum, _):
        raise KeyboardInterrupt(f'signal {signum}')

    for name in ('SIGTERM', 'SIGHUP'):
        sig = getattr(signal, name, None)
        if sig is not None:
            previous[sig] = signal.signal(sig, interrupted)
    try:
        report['baseline_exit'], _ = run('baseline')
        if report['baseline_exit']:
            raise RuntimeError('baseline failed')
        for name, old, new in MUTANTS:
            source = original.decode()
            if source.count(old) != 1:
                raise RuntimeError('stale anchor: '+name)
            pending = source.replace(old, new).encode()
            path.write_bytes(pending)
            code, output = run(name)
            if path.read_bytes() != pending:
                raise RuntimeError('concurrent target edit')
            path.write_bytes(original)
            pending = None
            detected = (code != 0 and not is_compile_failure(output)
                        and re.search(r'LP3 differential mismatch|release/preview differential', output) is not None
                        and re.search(r'panic:|test crashed|timed out', output, re.I) is None)
            report['mutants'].append(dict(name=name, exit_code=code, detected=detected))
            if not detected:
                raise RuntimeError('not rejected by semantic oracle: '+name)
        report['restored_exit'], _ = run('restored')
    except BaseException as exc:
        report['error'] = f'{type(exc).__name__}: {exc}'
    finally:
        if pending is not None and path.read_bytes() == pending:
            path.write_bytes(original)
        report['source_restored'] = path.read_bytes() == original
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        report['passed'] = (report.get('baseline_exit') == report.get('restored_exit') == 0
                            and report['source_restored'] and len(report['mutants']) == len(MUTANTS)
                            and all(m['detected'] for m in report['mutants']) and 'error' not in report)
        (args.evidence/'result.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
