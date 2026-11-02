# outline

Read Ada units piecewise: the subprograms of a unit with their lines and contracts, one
subprogram or declaration in full, the declarations a caller needs, the uses of a name. For
people, and for coding agents that otherwise read a 600-line unit whole and keep it in their
context for every later request.

It is the successor, in Ada, of the `outline.py` of [etcs-dmi](https://github.com/milanredele/etcs-dmi)
and FreedomChat, where agents use it about 14 times each, measured over 306 agents. The Python
version finds declarations with line patterns; this one has a lexer.

## Status

Work in progress. In place:

- **The lexer** (`src/outline-lexer.ads`): the lexical elements of Ada 2022, one at a time,
  from a source in memory. It accepts any byte sequence and never raises: GNATprove proves the
  absence of run-time errors and its contracts (188 checks, no assumption). It tells a tick
  from a character literal (`Character'('(')`, `P.all'Size`), keeps `--` inside a string
  literal out of the comments, and counts lines as Python's universal newlines do (LF, CR LF,
  CR), so line numbers agree with `outline.py`.
- **The reference set** (`tests/reference/`): what `outline.py` prints for 30,603 commands over
  two code bases (626 files, 260,826 lines), as a SHA-256 per command. The Ada version has to
  reproduce it, apart from the places where `outline.py` is wrong, which will be listed with
  their reason. See below.

Next: the declaration scanner on top of the lexer, the commands of `outline.py` (`--spec`,
`--decl`, `--body`, `--refs`, `--units`, `--md`), the search roots from a project file's
`Source_Dirs`, and `--refs` from the cross-reference lines of the compiler's `.ali` files where
they exist.

## Building and checking

With [Alire](https://alire.ada.dev) 2.x:

```sh
alr build                                             # bin/outline
bin/outline --tokens src/outline-lexer.adb    # the tokens of a file (a development aid)
tests/run.sh                                          # build, lexer cases, proof
tests/run.sh etcs-dmi=../etcs-dmi FreedomChat=../FreedomChat   # and the corpora
```

`tests/run.sh` prints one PASS, FAIL or SKIP line per check: the build without a warning or
style message, the lexer's unit cases (`tests/lexer/test_lexer.adb`), per corpus given that
every `.ads` and `.adb` under its roots lexes back to itself with no invalid token and the line
counts of `outline.py --units` on the same checkout, and the proof of the lexer
(`gnatprove`, or `GNATPROVE=<path>`; `alr get gnatprove` fetches it).

## The reference set

`tests/reference/oracle_outline.py` is FreedomChat's `tools/outline.py` at `132ce12`, unchanged
except that its root and search roots come from `OUTLINE_ROOT` and `OUTLINE_ROOTS`.
`tests/reference/gen_reference.py` derives the commands from a corpus (every unit, every
subprogram and declaration name of it, the other ways of naming a unit, `--refs` for a sample
of names, the error cases, `--md` over the markdown files) and records for each the SHA-256 of
what the oracle printed: exit status, standard output, standard error. `corpora.txt` pins each
corpus to a revision. Only the commands and the hashes are committed, no source text; the
commands do name the units, subprograms and declarations of a corpus and the section numbers
of its markdown files. The full outputs go to `tests/reference/outputs/`, which is not
committed, for diffing.

```sh
tests/reference/gen_reference.py FreedomChat <checkout at 132ce12>            # write
tests/reference/gen_reference.py FreedomChat <checkout at 132ce12> --verify   # compare
```

## Licence

Apache-2.0.
