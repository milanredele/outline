#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Attribute every command where outline differs from outline.py to the fix that causes it.

  attribute.py <corpus> <checkout> ... [--write]

For each corpus, every command of the reference set is run with all fixes on (the default);
each command that differs from the oracle is run again with one fix on and the others off
(OUTLINE_PY_COMPAT listing the others), once per fix. A command is attributed to the fix
under which it differs alone, to two fixes when it differs under each of them alone or only
under both together; anything else is reported.
--write rewrites known_differences.txt: a `## <fix>: <reason>` heading per group and one line
per command, `<corpus>\\t<argv>`.
"""
import concurrent.futures
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BINARY = os.path.join(HERE, '..', '..', 'bin', 'outline')
sys.path.insert(0, HERE)
from gen_reference import corpus_line, normalise, record  # noqa: E402

FIXES = {
    'views': 'comments, string and character literals found by the lexer: `--` inside a string '
             'literal is no comment, a character literal such as \'(\' or \';\' is no '
             'delimiter',
    'expr_end': 'an expression function, instance or `is separate` that spans lines ends at its '
                '`;` (outline.py ends it at the line of its `is`)',
    'operators': 'operator functions (function "+") are declarations; a name may be given with '
                 'its quotes',
    'help': 'the help text describes outline, not outline.py',
    'views+expr_end': 'both: the `;` that ends a multi-line expression function comes after '
                      'a string literal holding `--`',
    'expr_end+operators': 'both: a multi-line operator expression function, or each fix '
                          'changes a part of the output',
    'views+operators': 'both',
}


def digest_of(argv, checkout, roots, compat):
    env = dict(os.environ, OUTLINE_ROOT=checkout, OUTLINE_ROOTS=':'.join(roots))
    env.pop('OUTLINE_PY_COMPAT', None)
    if compat:
        env['OUTLINE_PY_COMPAT'] = compat
    p = subprocess.run([BINARY] + argv, cwd=checkout, env=env, capture_output=True)
    return p.returncode, p.stdout.decode('utf-8', 'surrogateescape'), \
        p.stderr.decode('utf-8', 'surrogateescape')


def main(argv):
    write = '--write' in argv
    pairs = [a for a in argv if a != '--write']
    groups = {k: [] for k in list(FIXES) + ['several']}
    status = 0
    for corpus, checkout in zip(pairs[0::2], pairs[1::2]):
        checkout = os.path.abspath(checkout)
        _, roots = corpus_line(corpus)
        rows = []
        for line in open(os.path.join(HERE, corpus + '.tsv')):
            if not line.startswith('#'):
                cid, digest, _, norm, args = line.rstrip('\n').split('\t')
                rows.append((digest, norm, args))

        def hashed(row, compat):
            digest, norm, args = row
            st, out, err = digest_of(json.loads(args), checkout, roots, compat)
            text = record(st, normalise(norm, out), err)
            return hashlib.sha256(text.encode('utf-8', 'surrogateescape')).hexdigest() != digest

        with concurrent.futures.ThreadPoolExecutor(4) as pool:
            differ = [r for r, d in zip(rows, pool.map(lambda r: hashed(r, ''), rows)) if d]
            single = {}
            for fix in ('views', 'expr_end', 'operators'):
                others = ','.join(f for f in ('views', 'expr_end', 'operators') if f != fix)
                single[fix] = list(pool.map(lambda r: hashed(r, others), differ))
            compat_all = list(pool.map(lambda r: hashed(r, 'all'), differ))
            pairs = {}
            for a, b in (('views', 'expr_end'), ('views', 'operators'), ('expr_end', 'operators')):
                off = ','.join(f for f in ('views', 'expr_end', 'operators') if f not in (a, b))
                pairs[a + '+' + b] = list(pool.map(lambda r: hashed(r, off), differ))
        for k, row in enumerate(differ):
            args = row[2]
            causes = [f for f in single if single[f][k]]
            if json.loads(args) in ([], ['--help'], ['-h']) and compat_all[k]:
                groups['help'].append((corpus, args))
            elif len(causes) == 1:
                groups[causes[0]].append((corpus, args))
            elif len(causes) == 2:
                groups['+'.join(causes)].append((corpus, args))
            elif not causes and [p for p in pairs if pairs[p][k]]:
                pair = [p for p in pairs if pairs[p][k]][0]
                groups.setdefault(pair, []).append((corpus, args))
            else:
                groups['several'].append((corpus, args))
        print(f'{corpus}: {len(rows)} commands, {len(differ)} differ: '
              + ', '.join(f'{f} {sum(1 for c, _ in groups[f] if c == corpus)}'
                          for f in groups))
    if groups['several']:
        print('differing only with several fixes together, or with none alone:')
        for c, a in groups['several'][:20]:
            print(f'  {c} {a}')
        status = 1
    if write:
        with open(os.path.join(HERE, 'known_differences.txt'), 'w', encoding='utf-8') as fh:
            fh.write('# The commands of the reference set where outline does not print what '
                     'outline.py printed,\n# by the fix that causes it (attribute.py --write); '
                     'compare.py --known checks them.\n')
            for fix, reason in FIXES.items():
                fh.write(f'\n## {fix}: {reason}\n')
                for c, a in groups[fix]:
                    fh.write(f'{c}\t{a}\n')
            if groups['several']:
                fh.write('\n## several: differs only with several fixes together\n')
                for c, a in groups['several']:
                    fh.write(f'{c}\t{a}\n')
    return status


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
