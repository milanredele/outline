# outline

Read Ada units piecewise: the subprograms of a unit with their lines and contracts, one
subprogram or declaration in full, the declarations a caller needs, the uses of a name, one
section of a markdown specification. For people, and for coding agents that otherwise read a
600-line unit whole and keep it in their context for every later request.

It is the successor, in Ada, of the `outline.py` of [etcs-dmi](https://github.com/milanredele/etcs-dmi)
and FreedomChat, where agents call it about 14 times each (measured over 306 agents). It does
everything `outline.py` does, with the same commands and the same output, and fixes the places
where `outline.py`'s line patterns go wrong (below). It needs no Python and no compiled project:
it reads the sources as they are, also while they do not compile.

```sh
outline fc_session                  # every subprogram of spec and body: lines, profile, aspects
outline fc_session --spec           # every declaration of the spec in full, no bodies
outline fc_session --spec Receive   # one declaration with its contract and heading comment
outline fc_session Receive          # that subprogram in full: declaration and body
outline fc_session --body Receive   # the body only
outline fc_store --decl             # every other declaration: types, subtypes, objects, clauses
outline fc_store --decl Slot_Record # that declaration in full (a record to its end record)
outline --refs Within_Bounds        # every use outside its declaration, as file:line
outline --refs Valid --in core/src  # limit the search to a directory
outline --units                     # every unit under the roots, with its line counts
outline --md 03                     # the headings of spec/03-*.md with their lines
outline --md 03 7.5                 # that section, with line numbers
outline --md 03 --grep stamp        # the matching lines, with the section they belong to
outline --md PLAN.md 3a             # any markdown file
outline --where                     # the root and the search roots in use
```

A unit is given by file name or Ada name (`fc_session`, `Fc_Core.Links`, `fc_core-links`,
`core/src/fc_store.ads`). Every listing shows first and last line, so that a following
`sed -n A,Bp` is exact.

## Where it looks

The **root** is `$OUTLINE_ROOT`, else the nearest directory upwards from the current one that
holds a `.outline` file or a `.git`, else the current directory. Paths are shown relative to it.

The **search roots**, searched recursively for `.ads` and `.adb`:

1. `$OUTLINE_ROOTS`, colon-separated;
2. else the lines of `<root>/.outline` (blank lines and `#` comments skipped; `spec: <dir>`
   names the directory of the numbered files of `--md NN`, default `spec`);
3. else the `Source_Dirs` of the project files `<root>/*.gpr` (a trailing `/**` dropped, a
   directory inside another one dropped);
4. else the root itself, without `obj`, `bin`, `lib` and `alire`.

For etcs-dmi the project files give exactly the roots its `outline.py` had. FreedomChat has no
project file at its top, so it takes a `.outline`:

```
# the search roots of outline
core/src
core/sim
core/tests/src
unishox_spark/src
ada-mobile/runtime/src
ada-mobile/runtime/selftest
spec: spec
```

Replacing `outline.py` in a project is then `python3 tools/outline.py` → `outline` in its
agent instructions.

## Where it differs from outline.py

Each difference can be switched off with `OUTLINE_PY_COMPAT` (`1` or `all` for every one, or a
comma-separated list of their names), which is how the port is checked:

- **`views`**: comments, string literals and character literals come from a lexer, not from
  cutting each line at its first `--` and pairing quotes. `--` inside a string literal is no
  comment (`Argument (1) = "--config"`), and a character literal such as `'('` or `';'` does
  not count as a parenthesis or a semicolon.
- **`expr_end`**: an expression function, an instance or `is separate` that spans lines ends at
  its `;`. `outline.py` meant to, but ended it at the line of its `is`, so `--spec` of a
  multi-line expression function showed its first line only, without the expression and
  without its `Pre` and `Post`.
- **`operators`**: operator functions (`function "+"`, `function "<"`) are declarations, named
  `+` and `<`; `outline.py`'s name pattern did not match them. A name may be given with its
  quotes (`--spec '"+"'`).

Not a difference in output: the help text describes `outline`, and the commands `outline.py`
crashed on (`--refs` or `--body` without a name) print an error instead.

## How it is checked

```sh
tests/run.sh                                                   # build, lexer, config, proof
tests/run.sh etcs-dmi=../etcs-dmi FreedomChat=../FreedomChat   # and the reference set
```

One PASS, FAIL or SKIP line per check:

- **build** without a warning or style message;
- **lexer cases** (`tests/lexer/test_lexer.adb`, 39 cases): ticks and character literals
  (`Character'('(')`, `P.all'Size`), doubled quotes, based literals, Ada 2022 delimiters, line
  counting as Python's universal newlines count;
- **config** (`tests/config/run.sh`, 23 cases): root and search roots from `.outline`, project
  files, the fallback and the environment; operator functions; compatibility mode;
- per corpus: **lexer** (every file lexes back to itself, no invalid token, line counts equal
  to `outline.py`'s), **compat** and **reference** (below; checkouts at the revisions of
  `tests/reference/corpora.txt`, minutes each, `OUTLINE_QUICK=1` skips them);
- **proof**: GNATprove on the lexer, which accepts any bytes and never raises: 188 checks
  proved, run-time checks, contracts and termination (`GNATPROVE=<path>`, or
  `alr get gnatprove`).

### The reference set

What `outline.py` printed for 30,603 commands over two code bases (etcs-dmi `f91dcba1`, 511
files; FreedomChat `132ce12`, 115 files; 260,826 lines): every unit, every subprogram and
declaration name of it with every command that takes one, the other ways of naming a unit,
`--refs` for a sample of names with and without `--in`, the error cases, `--md` over every
markdown file. `tests/reference/oracle_outline.py` is FreedomChat's `tools/outline.py` with its
root and search roots read from the environment; `gen_reference.py` derives the commands and
records the SHA-256 of each output (exit status, standard output, standard error).

- With `OUTLINE_PY_COMPAT=1`, `outline` prints what `outline.py` printed for all 30,603
  commands, the 4 help texts aside (`compare.py --compat`).
- With its fixes, 26,810 commands print the same and 3,793 differ, each attributed to the fix
  that causes it by running it with that fix alone (`attribute.py`, listed in
  `known_differences.txt`): `expr_end` 3,778, `operators` 6, both together 3, `views` with
  `expr_end` 2 (the `"--config"` line above), help 4.

The committed reference holds no source text: the commands and a hash per command. The commands
name the units, subprograms and declarations of the corpora and the section numbers of their
markdown files. The full outputs go to `tests/reference/outputs/`, which is not committed.

### Speed

On etcs-dmi, against `outline.py` (Python 3.13, GNU grep for `--refs`):

| command | outline.py | outline |
|---|---:|---:|
| `evc_sessions` | 53 ms | 16 ms |
| `evc_sessions --spec` | 36 ms | 9 ms |
| `--units` (511 files) | 480 ms | 429 ms |
| `--refs Evaluate` | 51 ms | 53 ms |

## Building

With [Alire](https://alire.ada.dev) 2.x, `alr install outline` puts it on your path. In a checkout,
`alr build` gives `bin/outline` and `alr install` installs that build. It needs GNAT 12 or newer,
and runs on Linux and macOS, not on Windows: it handles paths as POSIX paths.

`alr build -- -XOUTLINE_STRICT=yes` makes warnings errors, as `tests/run.sh` does.
`outline --tokens FILE` prints the tokens of a file (a development aid).

## Licence

Apache-2.0.
