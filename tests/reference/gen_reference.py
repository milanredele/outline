#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate the reference set of ada-outline from the Python outline.py it replaces.

  gen_reference.py <corpus> <checkout>            write <corpus>.tsv and outputs/<corpus>/
  gen_reference.py <corpus> <checkout> --verify   regenerate and compare with <corpus>.tsv

<corpus> is a line of corpora.txt (name, git revision, search roots); <checkout> is a
checkout of that corpus at that revision (`git archive` of it, or a worktree).

The oracle is oracle_outline.py: tools/outline.py of FreedomChat at 132ce12 with its root and
search roots read from OUTLINE_ROOT and OUTLINE_ROOTS (colon-separated), nothing else changed.

The reference holds no source text: <corpus>.tsv has one line per command, with the SHA-256 of
what the oracle printed (exit status, stdout, stderr), so it can be published even when the
corpus cannot. outputs/<corpus>/<id>.txt keeps the full output for diffing; it is not
committed.

The command set, derived from the corpus so that it covers everything the oracle does:
  --units; per unit (a file base name, spec and body together): the outline, --spec, --decl;
  per subprogram name of the unit: <unit> <Name>, --spec <Name>, --body <Name> (when a body
  exists); per declaration name: --decl <Name>; the unit given by path, by Ada name and in
  another case for a sample; --refs for a sample of names, with and without --in; the error
  cases (no unit, no subprogram, no declaration, no body); --md over the markdown files of
  the corpus: the headings, every section by its key, --grep for a few words.
Normalisation (the `norm` column): `refs` sorts the use lines, whose order is grep's directory
order in the oracle; `none` compares the output as printed.
"""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def corpus_line(name):
    for line in open(os.path.join(HERE, 'corpora.txt')):
        f = line.split()
        if f and not f[0].startswith('#') and f[0] == name:
            return f[1], f[2].split(':')
    sys.exit(f'gen_reference: no corpus {name} in corpora.txt')


def load_oracle(root, roots):
    os.environ['OUTLINE_ROOT'] = root
    os.environ['OUTLINE_ROOTS'] = ':'.join(roots)
    spec = importlib.util.spec_from_file_location('oracle', os.path.join(HERE, 'oracle_outline.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run(oracle, argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            status = oracle.main(argv)
        except SystemExit as e:
            status = e.code if isinstance(e.code, int) else 1
        except Exception as e:                       # the oracle's own failures are recorded too
            print(f'oracle exception: {type(e).__name__}: {e}', file=sys.stderr)
            status = 99
    return status or 0, out.getvalue(), err.getvalue()


def normalise(norm, stdout):
    if norm == 'refs':
        lines = stdout.splitlines(keepends=True)
        body, tail = lines[:-1], lines[-1:]
        return ''.join(sorted(body)) + ''.join(tail)
    return stdout


def record(status, stdout, stderr):
    return f'exit {status}\n--- stdout\n{stdout}--- stderr\n{stderr}'


def ada_name(path):
    base = re.sub(r'\.ad[sb]$', '', os.path.basename(path))
    return '.'.join(p.capitalize() for p in base.split('-'))


def commands(oracle, root):
    """[(argv, norm)] for the corpus, in a stable order."""
    os.chdir(root)
    cmds = [(['--units'], 'none')]
    units = {}
    for p in oracle.all_units():
        units.setdefault(re.sub(r'\.ad[sb]$', '', os.path.basename(p)), []).append(p)
    every_name = set()
    for k, base in enumerate(sorted(units)):
        files = units[base]
        cmds += [([base], 'none'), ([base, '--spec'], 'none'), ([base, '--decl'], 'none')]
        subs, bodies, decls = set(), set(), set()
        for f in files:
            lines = oracle.read(f)
            for d in oracle.declarations(lines):
                subs.add(d[2])
                if d[5]:
                    bodies.add(d[2])
            for d in oracle.other_declarations(lines):
                if d[1] in ('with', 'use'):
                    continue
                for n in d[2].split(','):
                    decls.add(n.strip())
        for n in sorted(subs):
            cmds += [([base, n], 'none'), ([base, '--spec', n], 'none')]
            if n in bodies:
                cmds.append(([base, '--body', n], 'none'))
        for n in sorted(decls):
            cmds.append(([base, '--decl', n], 'none'))
        every_name |= {n for n in subs | decls if re.match(r'^\w+$', n)}
        if k % 10 == 0:                              # the other ways to name a unit
            cmds += [([files[0]], 'none'), ([ada_name(files[0])], 'none'),
                     ([ada_name(files[0]).upper(), '--spec'], 'none'),
                     ([os.path.basename(files[-1])], 'none')]
            if subs:
                n = sorted(subs)[0]
                cmds += [([base, n.upper()], 'none'), ([base, '--spec', n.lower()], 'none')]
    cmds += [(['no_such_unit_xyz'], 'none'), ([sorted(units)[0], 'No_Such_Subprogram_Xyz'], 'none'),
             ([sorted(units)[0], '--decl', 'No_Such_Decl_Xyz'], 'none'),
             ([sorted(units)[0], '--spec', 'No_Such_Subprogram_Xyz'], 'none'),
             ([sorted(units)[0], '--body', 'No_Such_Subprogram_Xyz'], 'none')]
    names = sorted(every_name)
    step = max(1, len(names) // 300)
    roots = os.environ['OUTLINE_ROOTS'].split(':')
    for k, n in enumerate(names[::step]):
        cmds.append((['--refs', n], 'refs'))
        if k % 5 == 0:
            cmds.append((['--refs', n, '--in', roots[k // 5 % len(roots)]], 'refs'))
    cmds.append((['--refs', 'No_Such_Name_Xyz'], 'refs'))
    md = []
    for d, _, fs in os.walk(root):
        rel = os.path.relpath(d, root)
        if rel.split(os.sep)[0] in ('obj', 'alire', 'node_modules', '.git') or 'node_modules' in rel:
            continue
        md += [os.path.normpath(os.path.join(rel, f)) for f in fs if f.endswith('.md')]
    for p in sorted(md):
        lines = oracle.read(p)
        if len(lines) > 5000:
            continue
        cmds.append((['--md', p], 'none'))
        keys = []
        for level, title, first, last in oracle.md_headings(lines):
            t = title.lower().lstrip('*').strip()
            if t:
                keys.append(t.split()[0].rstrip('.').strip('*'))
        for key in sorted(set(keys))[:60]:
            cmds.append((['--md', p, key], 'none'))
        for w in ('the', 'Ada', 'TODO'):
            cmds.append((['--md', p, '--grep', w], 'none'))
    for m in sorted(os.listdir(os.path.join(root, 'spec'))) if os.path.isdir(os.path.join(root, 'spec')) else []:
        if re.match(r'^\d\d-.*\.md$', m):
            cmds += [(['--md', m[:2]], 'none'), (['--md', str(int(m[:2]))], 'none')]
    cmds += [(['--md'], 'none'), (['--md', 'no_such_spec.md'], 'none'), (['--help'], 'none'), ([], 'none')]
    return cmds


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    corpus, checkout = argv[0], os.path.abspath(argv[1])
    verify = '--verify' in argv
    revision, roots = corpus_line(corpus)
    oracle = load_oracle(checkout, roots)
    outdir = os.path.join(HERE, 'outputs', corpus)
    os.makedirs(outdir, exist_ok=True)
    tsv = os.path.join(HERE, corpus + '.tsv')
    old = {}
    if verify:
        for line in open(tsv):
            if not line.startswith('#'):
                f = line.rstrip('\n').split('\t')
                old[f[4]] = f[1]
    rows = []
    for k, (argv_c, norm) in enumerate(commands(oracle, checkout)):
        os.chdir(checkout)
        status, out, err = run(oracle, argv_c)
        text = record(status, normalise(norm, out), err)
        digest = hashlib.sha256(text.encode('utf-8', 'surrogateescape')).hexdigest()
        cid = f'{k:06d}'
        with open(os.path.join(outdir, cid + '.txt'), 'w', encoding='utf-8', errors='surrogateescape') as fh:
            fh.write(text)
        rows.append((cid, digest, status, norm, json.dumps(argv_c)))
    if verify:
        bad = [r for r in rows if old.get(r[4]) != r[1]]
        missing = set(old) - {r[4] for r in rows}
        print(f'{corpus}: {len(rows)} commands, {len(bad)} differ, {len(missing)} missing')
        return 1 if bad or missing else 0
    with open(tsv, 'w') as fh:
        fh.write(f'# corpus {corpus} at {revision}, roots {":".join(roots)}; '
                 f'id, sha256 of the record, exit status, normalisation, argv\n')
        for r in rows:
            fh.write('\t'.join(str(x) for x in r) + '\n')
    by_status = {}
    for r in rows:
        by_status[r[2]] = by_status.get(r[2], 0) + 1
    print(f'{corpus}: {len(rows)} commands, exit statuses {by_status}, written {tsv}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
