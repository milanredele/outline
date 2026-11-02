#!/usr/bin/env python3
# Copyright 2026 FreedomChat contributors
# SPDX-License-Identifier: Apache-2.0
# Ported from etcs-dmi test/tools/outline.py (same parser as subprogram_size.py), with the
# whole-unit --spec digest and the specification sections (--md) added.
"""An outline of an Ada unit or a specification file, for reading it piecewise instead of whole.

Ada units (the search roots: core/src, core/sim, core/tests/src, unishox_spark/src,
ada-mobile/runtime/src, ada-mobile/runtime/selftest; a unit is given by file name or Ada name: fc_session, Fc_Core.Links,
fc_core-links, core/src/fc_store.ads):

  tools/outline.py fc_session                  every subprogram of spec and body: lines, profile,
                                               the first line of each aspect (Global, Pre, Post, ...)
  tools/outline.py fc_session --spec           the digest of the spec: every subprogram declaration
                                               in full (contract and heading comment), no bodies;
                                               what a caller or an integrator needs
  tools/outline.py fc_session --spec Receive   one declaration with its contract and heading
                                               (a private subprogram: the profile of its body)
  tools/outline.py fc_session Receive          that subprogram in full: declaration and body
  tools/outline.py fc_session --body Receive   the body only
  tools/outline.py fc_store --decl             every other declaration (types, subtypes, constants,
                                               objects, with/use clauses): lines, first line
  tools/outline.py fc_store --decl Slot_Record that declaration in full (a record to its end record)
  tools/outline.py --refs Within_Bounds        every use outside its declaration, as file:line
  tools/outline.py --refs Valid --in core/src  limit the search to a directory
  tools/outline.py --units                     every unit under the roots, with its line counts

Specification (spec/*.md; a file is given by its number, 03, or its path):

  tools/outline.py --md 03                     the headings of spec/03-courier.md with their lines
  tools/outline.py --md 03 7.5                 that section (to the next heading of the same or a
                                               higher level), with line numbers
  tools/outline.py --md 03 --grep stamp        the lines matching, with the section they belong to
  tools/outline.py --md PLAN.md 3a             any markdown file: the section whose heading starts
                                               with the given number or words

Every listing shows first and last line, so that a following `sed -n A,Bp` is exact. The parser:
a declaration starts at `procedure` / `function` and ends at the matching `;` (a spec) or at the
`end Name;` at the same indentation (a body). Nested bodies are listed under their parent.
"""
import glob
import os
import re
import subprocess
import sys

ROOT = os.environ.get('OUTLINE_ROOT') or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOTS = (os.environ['OUTLINE_ROOTS'].split(':') if os.environ.get('OUTLINE_ROOTS') else
         ['core/src', 'core/sim', 'core/tests/src', 'unishox_spark/src',
          'ada-mobile/runtime/src', 'ada-mobile/runtime/selftest'])
START = re.compile(r'^(\s*)(?:overriding\s+)?(procedure|function)\s+("?[\w\.]+"?)', re.I)
ASPECT = re.compile(r'\b(Global|Depends|Pre|Post|Contract_Cases|Refined_Global|Refined_Depends|'
                    r'Refined_Post|Refined_State|Abstract_State|Initializes|Convention|Import|'
                    r'Export|External_Name|Inline|Ghost|SPARK_Mode|Annotate)\s*=>', re.I)


def all_units():
    out = []
    for r in ROOTS:
        for ext in ('ads', 'adb'):
            out += glob.glob(os.path.join(ROOT, r, '**', '*.' + ext), recursive=True)
    return sorted(os.path.relpath(p, ROOT) for p in out)


def unit_files(name):
    """The files of a unit given as path, file name or Ada name."""
    if os.path.isfile(name):
        return [os.path.relpath(os.path.abspath(name), ROOT)]
    if os.path.isfile(os.path.join(ROOT, name)):
        return [name]
    base = re.sub(r'\.ad[sb]$', '', name.lower()).replace('.', '-')
    hits = [p for p in all_units() if re.sub(r'\.ad[sb]$', '', os.path.basename(p)) == base]
    return sorted(hits, key=lambda p: not p.endswith('.ads'))   # the spec first


def declarations(lines):
    """[(indent, kind, name, first, last, is_body, expr)] of every subprogram declaration;
    a body ends at its `end Name;` at the same indentation, a spec at the `;` that closes it
    (depth 0, outside parentheses), an expression function at its ';'."""
    out = []
    for i, line in enumerate(lines):
        m = START.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        name = m.group(3).strip('"')
        depth = 0
        is_body = None
        expr = False
        j = i
        while j < len(lines) and j < i + 200 and is_body is None:
            s = re.sub(r'--.*', '', lines[j])
            s = re.sub(r'"[^"]*"', '""', s)
            for tok in re.finditer(r'\(|\)|;|\bis\b', s):
                t = tok.group(0)
                if t == '(':
                    depth += 1
                elif t == ')':
                    depth -= 1
                elif depth == 0 and t == ';':
                    is_body = False
                    break
                elif depth == 0 and t == 'is':
                    rest = s[tok.end():]
                    if not rest.strip():
                        k = j + 1
                        while k < len(lines) and not re.sub(r'--.*', '', lines[k]).strip():
                            k += 1
                        rest = re.sub(r'--.*', '', lines[k]) if k < len(lines) else ''
                    if re.match(r'\s*(\(|new\b|abstract\b|null\b|separate\b)', rest):
                        is_body = False
                        expr = True
                    else:
                        is_body = True
                    break
            j += 1
        last = j - 1
        if is_body is False and expr:
            depth = 0
            for k in range(i, min(len(lines), i + 200)):
                s = re.sub(r'--.*', '', lines[k])
                s = re.sub(r'"[^"]*"', '""', s)
                stop = False
                for tok in re.finditer(r'\(|\)|;', s):
                    if tok.group(0) == '(':
                        depth += 1
                    elif tok.group(0) == ')':
                        depth -= 1
                    elif depth == 0:
                        last = k
                        stop = True
                        break
                if stop:
                    break
        if is_body:
            end = re.compile(r'^' + ' ' * indent + r'end\s+"?' + re.escape(name) + r'"?\s*;', re.I)
            for k in range(j, len(lines)):
                if end.match(lines[k]):
                    last = k
                    break
        elif is_body is False:
            last = j - 1
        out.append((indent, m.group(2).lower(), name, i, last, bool(is_body), expr))
    return out


DECL = re.compile(r'^(\s*)(?:(type|subtype)\s+("?[\w]+"?)|([\w]+(?:\s*,\s*[\w]+)*)\s*:(?!=)|'
                  r'(with|use)\s+([\w\.]+(?:\s*,\s*[\w\.]+)*)\s*;)', re.I)


def other_declarations(lines):
    """[(indent, kind, name, first, last)] of the declarations that are not subprograms:
    types and subtypes (a record ends at its `end record;`, anything else at the `;` at
    depth 0), objects and components, context clauses. Lines inside a subprogram body are
    left out, so that a local variable does not hide a package one."""
    inside = [(first, last) for _, _, _, first, last, is_body, _ in declarations(lines) if is_body]
    out = []
    i = 0
    while i < len(lines):
        if any(a < i <= b for a, b in inside):
            i += 1
            continue
        m = DECL.match(lines[i])
        if not m or lines[i].strip().startswith('--'):
            i += 1
            continue
        indent = len(m.group(1))
        if m.group(2):
            kind, name = m.group(2).lower(), m.group(3).strip('"')
        elif m.group(4):
            kind, name = 'object', m.group(4)
        else:
            kind, name = m.group(5).lower(), m.group(6)
        last = i
        depth = 0
        record = False
        for k in range(i, min(len(lines), i + 400)):
            s = re.sub(r'--.*', '', lines[k])
            s = re.sub(r'"[^"]*"', '""', s)
            if re.search(r'\bis\b\s*(tagged\s+|limited\s+)*record\b', s) \
                    or re.search(r'\bwith\s+record\b', s):
                record = True
            if record:
                if re.match(r'^' + ' ' * indent + r'end\s+record\s*;', lines[k], re.I):
                    last = k
                    break
                continue
            stop = False
            for tok in re.finditer(r'\(|\)|;', s):
                if tok.group(0) == '(':
                    depth += 1
                elif tok.group(0) == ')':
                    depth -= 1
                elif depth == 0:
                    last = k
                    stop = True
                    break
            if stop:
                break
        out.append((indent, kind, name, i, last))
        i = last + 1
    return out


def read(path):
    return open(os.path.join(ROOT, path), encoding='utf-8', errors='replace').readlines()


def heading(lines, first):
    """The comment block right above a declaration."""
    k = first - 1
    block = []
    while k >= 0 and lines[k].strip().startswith('--'):
        block.insert(0, lines[k].rstrip('\n'))
        k -= 1
    return block


def trailing(lines, last):
    """The comment block right below a declaration (this project's convention for the
    description of a subprogram)."""
    k = last + 1
    block = []
    while k < len(lines) and lines[k].strip().startswith('--'):
        block.append(lines[k].rstrip('\n'))
        k += 1
    return block


def profile(lines, first, last):
    """The declaration without its body: up to the `is` or `;`."""
    out = []
    for k in range(first, last + 1):
        s = lines[k].rstrip('\n')
        out.append(s)
        t = re.sub(r'--.*', '', s)
        if re.search(r'\bis\b\s*$', t) or t.rstrip().endswith(';'):
            if not re.search(r'\bwith\b', ''.join(out)) or t.rstrip().endswith(';'):
                break
    return out


def print_range(lines, first, last):
    for k in range(first, last + 1):
        print(f'{k + 1:5d}  {lines[k].rstrip()}')


def outline(path):
    lines = read(path)
    print(f'== {path} ({len(lines)} lines)')
    for indent, kind, name, first, last, is_body, expr in declarations(lines):
        prof = ' '.join(l.strip() for l in lines[first:min(last + 1, first + 12)])
        prof = re.sub(r'\s+', ' ', prof)
        prof = re.split(r'\s+(?:is\b|with\b|;)', prof)[0]
        tag = 'body' if is_body else ('expr' if expr else 'spec')
        print(f'{" " * (indent // 3)}{first + 1:5d}-{last + 1:<5d} {tag} {prof}')
        for k in range(first, last + 1):
            a = ASPECT.search(lines[k])
            if a and not is_body or (a and k < first + 40 and 'Refined' in a.group(1)):
                print(f'{" " * (indent // 3)}            {lines[k].strip()[:100]}')


def list_decls(path):
    lines = read(path)
    print(f'== {path} ({len(lines)} lines)')
    for indent, kind, name, first, last in other_declarations(lines):
        if kind == 'object' and indent > 3:
            continue      # a record component: shown with its record
        text = re.sub(r'\s+', ' ', lines[first].strip())[:90]
        print(f'{" " * (indent // 3)}{first + 1:5d}-{last + 1:<5d} {kind:7s} {text}')


def show_decl(path, name):
    lines = read(path)
    found = False
    for indent, kind, n, first, last in other_declarations(lines):
        if not any(x.strip().lower() == name.lower() for x in n.split(',')):
            continue
        found = True
        print(f'== {path}:{first + 1}-{last + 1} ({kind})')
        for l in heading(lines, first):
            print(l)
        print_range(lines, first, last)
        for l in trailing(lines, last):
            print(f'       {l.strip()}')
        print()
    return found


def show(path, name, bodies_only=False):
    lines = read(path)
    found = False
    for indent, kind, n, first, last, is_body, expr in declarations(lines):
        if n.lower() != name.lower() or (bodies_only and not is_body):
            continue
        found = True
        print(f'== {path}:{first + 1}-{last + 1} ({"body" if is_body else "spec"})')
        for l in heading(lines, first):
            print(l)
        print_range(lines, first, last)
        if not is_body:
            for l in trailing(lines, last):
                print(f'       {l.strip()}')
        print()
    return found


def show_spec(path, name=None):
    """The declaration(s) with contract, without the body: what a caller needs. A spec
    declaration is printed whole, a body is cut after its profile (a private subprogram
    still shows its parameters and the comments around it). With no name: every
    declaration of the file that is not a body (the digest of a spec)."""
    lines = read(path)
    found = False
    for indent, kind, n, first, last, is_body, expr in declarations(lines):
        if name is None and (is_body or indent > 3):
            continue
        if name is not None and n.lower() != name.lower():
            continue
        found = True
        tag = 'body, profile only' if is_body else ('expression function' if expr else 'spec')
        print(f'== {path}:{first + 1}-{last + 1} ({tag})')
        for l in heading(lines, first):
            print(l)
        if is_body:
            prof = profile(lines, first, last)
            for k, l in enumerate(prof):
                print(f'{first + k + 1:5d}  {l}')
        else:
            print_range(lines, first, last)
            for l in trailing(lines, last):
                print(f'       {l.strip()}')
        print()
    return found


def refs(name, roots):
    pat = r'\b' + re.escape(name) + r'\b'
    cmd = ['grep', '-rn', '-E', pat, '--include=*.ads', '--include=*.adb'] + roots
    res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    decl = re.compile(r'^\s*(overriding\s+)?(procedure|function|package|type|subtype)\s+' + pat,
                      re.I)
    endl = re.compile(r'^\s*end\s+' + pat, re.I)
    n = 0
    for line in res.stdout.splitlines():
        f, ln, text = line.split(':', 2)
        if decl.match(text) or endl.match(text) or text.strip().startswith('--'):
            continue
        n += 1
        print(f'{f}:{ln}: {text.strip()[:110]}')
    print(f'-- {n} uses of {name} (declarations, end lines and comments left out)')


def list_units():
    for p in all_units():
        lines = read(p)
        n = len(declarations(lines))
        print(f'{len(lines):6d} lines {n:4d} subprograms  {p}')


# --- specification files ------------------------------------------------------------------

HEADING = re.compile(r'^(#{1,6})\s+(.*)$')


def md_file(name):
    if os.path.isfile(os.path.join(ROOT, name)):
        return name
    if os.path.isfile(name):
        return os.path.relpath(os.path.abspath(name), ROOT)
    hits = sorted(glob.glob(os.path.join(ROOT, 'spec', name.zfill(2) + '-*.md')))
    return os.path.relpath(hits[0], ROOT) if hits else None


def md_headings(lines):
    """[(level, title, first, last)]: a section ends before the next heading of the same or a
    higher level (fenced code is skipped)."""
    heads = []
    fence = False
    for i, l in enumerate(lines):
        if l.startswith('```'):
            fence = not fence
            continue
        m = HEADING.match(l)
        if m and not fence:
            heads.append([len(m.group(1)), m.group(2).strip(), i, len(lines) - 1])
    for a, h in enumerate(heads):
        for h2 in heads[a + 1:]:
            if h2[0] <= h[0]:
                h[3] = h2[2] - 1
                break
    return [tuple(h) for h in heads]


def md_toc(path):
    lines = read(path)
    print(f'== {path} ({len(lines)} lines)')
    for level, title, first, last in md_headings(lines):
        print(f'{"  " * (level - 1)}{first + 1:5d}-{last + 1:<5d} {title[:90]}')


def md_section(path, key):
    lines = read(path)
    key_l = key.lower()
    found = False
    for level, title, first, last in md_headings(lines):
        t = title.lower().lstrip('*').strip()
        number = t.split()[0].rstrip('.').strip('*') if t else ''
        if number == key_l or t.startswith(key_l + ' ') or t == key_l \
                or (number.startswith(key_l + '.') and False):
            found = True
            print(f'== {path}:{first + 1}-{last + 1}')
            print_range(lines, first, last)
            print()
    return found


def md_grep(path, word):
    lines = read(path)
    heads = md_headings(lines)
    pat = re.compile(re.escape(word), re.I)
    n = 0
    for i, l in enumerate(lines):
        if pat.search(l):
            sec = ''
            for level, title, first, last in heads:
                if first <= i <= last:
                    sec = title[:40]
            n += 1
            print(f'{path}:{i + 1} [{sec}] {l.strip()[:120]}')
    print(f'-- {n} lines match {word!r}')


# --- main ----------------------------------------------------------------------------------

def main(argv):
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    if argv[0] == '--units':
        list_units()
        return 0
    if argv[0] == '--refs':
        roots = ROOTS
        if '--in' in argv:
            roots = [argv[argv.index('--in') + 1]]
        refs(argv[1], roots)
        return 0
    if argv[0] == '--md':
        if len(argv) < 2:
            print('outline: --md needs a specification number or a markdown path', file=sys.stderr)
            return 1
        path = md_file(argv[1])
        if not path:
            print(f'outline: no specification file {argv[1]}', file=sys.stderr)
            return 1
        if len(argv) == 2:
            md_toc(path)
            return 0
        if argv[2] == '--grep':
            md_grep(path, ' '.join(argv[3:]))
            return 0
        if not md_section(path, ' '.join(argv[2:])):
            print(f'outline: no section {" ".join(argv[2:])} in {path}', file=sys.stderr)
            return 1
        return 0
    files = unit_files(argv[0])
    if not files:
        print(f'outline: no unit {argv[0]} under {", ".join(ROOTS)}', file=sys.stderr)
        return 1
    opts = argv[1:]
    if opts and opts[0] == '--decl':
        if len(opts) == 1:
            for f in files:
                list_decls(f)
            return 0
        ok = any([show_decl(f, opts[1]) for f in files])
        if not ok:
            print(f'outline: no declaration {opts[1]} in {", ".join(files)}', file=sys.stderr)
            return 1
        return 0
    if opts and opts[0] == '--spec':
        if len(opts) == 1:
            specs = [f for f in files if f.endswith('.ads')] or files
            ok = any([show_spec(f) for f in specs])
        else:
            ok = False
            for f in files:           # the spec first; a body's profile only when private
                ok = show_spec(f, opts[1])
                if ok:
                    break
        if not ok:
            print(f'outline: no subprogram {opts[1:]} in {", ".join(files)}', file=sys.stderr)
            return 1
        return 0
    if opts and opts[0] == '--body':
        ok = any([show(f, opts[1], bodies_only=True) for f in files if f.endswith('.adb')])
        if not ok:
            print(f'outline: no body {opts[1]} in {", ".join(files)}', file=sys.stderr)
            return 1
        return 0
    if opts:
        ok = any([show(f, opts[0]) for f in files])
        if not ok:
            print(f'outline: no subprogram {opts[0]} in {", ".join(files)}', file=sys.stderr)
            return 1
        return 0
    for f in files:
        outline(f)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
