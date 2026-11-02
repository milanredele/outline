#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run every command of the reference set with bin/outline and compare with the oracle's hashes.

  compare.py <corpus> <checkout> [--compat] [--known] [--jobs N] [--show N]

<corpus> and <checkout> as for gen_reference.py. --compat runs outline with OUTLINE_PY_COMPAT=1,
where it must reproduce outline.py exactly; without it, outline fixes what outline.py gets
wrong, and a command may differ only for a reason of known_differences.txt. With --known, a
differing command whose argv is listed there under that corpus counts as expected (with
--compat, only the help group); the run then fails only on unexplained differences and on
listed commands that no longer differ.

What outline printed for a differing command goes to outputs/<corpus>-ada[-compat]/<id>.txt,
next to the oracle's outputs/<corpus>/<id>.txt (written by gen_reference.py), for diffing;
--show N prints the first N diffs.
"""
import concurrent.futures
import difflib
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BINARY = os.path.join(HERE, '..', '..', 'bin', 'outline')

sys.path.insert(0, HERE)
from gen_reference import corpus_line, normalise, record  # noqa: E402


def known(corpus, only=None):
    """{argv json: reason} of known_differences.txt for the corpus (of group `only`)."""
    out = {}
    path = os.path.join(HERE, 'known_differences.txt')
    if not os.path.exists(path):
        return out
    reason = ''
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('## '):
            reason = line[3:]
        elif line.startswith(corpus + '\t') and (only is None or reason.startswith(only + ':')):
            out[line.split('\t', 1)[1]] = reason
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    corpus, checkout = argv[0], os.path.abspath(argv[1])
    compat = '--compat' in argv
    jobs = int(argv[argv.index('--jobs') + 1]) if '--jobs' in argv else 4
    show = int(argv[argv.index('--show') + 1]) if '--show' in argv else 0
    _, roots = corpus_line(corpus)
    env = dict(os.environ, OUTLINE_ROOT=checkout, OUTLINE_ROOTS=':'.join(roots))
    env.pop('OUTLINE_PY_COMPAT', None)
    if compat:
        env['OUTLINE_PY_COMPAT'] = '1'
    rows = []
    for line in open(os.path.join(HERE, corpus + '.tsv')):
        if not line.startswith('#'):
            cid, digest, status, norm, args = line.rstrip('\n').split('\t')
            rows.append((cid, digest, norm, args))
    outdir = os.path.join(HERE, 'outputs', corpus + '-ada' + ('-compat' if compat else ''))
    os.makedirs(outdir, exist_ok=True)

    def run(row):
        cid, digest, norm, args = row
        p = subprocess.run([BINARY] + json.loads(args), cwd=checkout, env=env,
                           capture_output=True)
        out = p.stdout.decode('utf-8', 'surrogateescape')
        err = p.stderr.decode('utf-8', 'surrogateescape')
        text = record(p.returncode, normalise(norm, out), err)
        mine = hashlib.sha256(text.encode('utf-8', 'surrogateescape')).hexdigest()
        if mine != digest:
            with open(os.path.join(outdir, cid + '.txt'), 'w', encoding='utf-8',
                      errors='surrogateescape') as fh:
                fh.write(text)
            return row
        return None

    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        differ = [r for r in pool.map(run, rows) if r]
    expected = (known(corpus, 'help' if compat else None) if '--known' in argv else {})
    unexplained = [r for r in differ if r[3] not in expected]
    stale = set(expected) - {r[3] for r in differ}
    print(f'{corpus}{" (compat)" if compat else ""}: {len(rows)} commands, '
          f'{len(rows) - len(differ)} equal, {len(differ)} differ'
          + (f' ({len(differ) - len(unexplained)} known, {len(unexplained)} unexplained, '
             f'{len(stale)} known but equal)' if '--known' in argv else ''))
    for cid, _, _, args in unexplained[:max(show, 20)]:
        print(f'  {cid} {args}')
    for args in sorted(stale)[:20]:
        print(f'  known but equal: {args}')
    for cid, _, _, args in unexplained[:show]:
        oracle = open(os.path.join(HERE, 'outputs', corpus, cid + '.txt'),
                      encoding='utf-8', errors='surrogateescape').read().splitlines()
        mine = open(os.path.join(outdir, cid + '.txt'), encoding='utf-8',
                    errors='surrogateescape').read().splitlines()
        print(f'--- {cid} {args}')
        for d in list(difflib.unified_diff(oracle, mine, 'outline.py', 'outline', n=1,
                                           lineterm=''))[2:40]:
            print(d)
    return 1 if unexplained or stale else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
