#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# The checks of ada_outline, one PASS/FAIL/SKIP line each; exit status 1 if one failed.
#
#   tests/run.sh [<corpus>=<checkout> ...]
#
#   1. build          alr build, no warning or style message (-gnatwe)
#   2. lexer cases    tests/lexer/bin/test_lexer, the unit cases
#   3. corpus <name>  per corpus given (a name of tests/reference/corpora.txt and a checkout
#                     of it, at any revision): every .ads/.adb under its roots lexes back to
#                     itself with no invalid token, and its line counts are those of the
#                     oracle (tests/reference/oracle_outline.py --units) on the same checkout
#   4. proof          gnatprove on the lexer: every check proved (SKIP without gnatprove)
#
# e.g. tests/run.sh etcs-dmi=../etcs-dmi FreedomChat=../FreedomChat
# ALR (default alr on PATH) and GNATPROVE (default gnatprove on PATH) may name the tools.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ALR=${ALR:-alr}
GNATPROVE=${GNATPROVE:-gnatprove}
LOGS=$ROOT/tests/obj
mkdir -p "$LOGS"
FAILED=0

report () { printf '%-4s  %s\n' "$1" "$2"; [ "$1" = FAIL ] && FAILED=1; return 0; }

cd "$ROOT" || exit 2
if "$ALR" -n build > "$LOGS/build.log" 2>&1; then
   report PASS build
else
   tail -20 "$LOGS/build.log"; report FAIL "build (log $LOGS/build.log)"
fi

if "$ALR" -n exec -- gprbuild -q -P tests/lexer/test_lexer.gpr > "$LOGS/lexer.log" 2>&1 \
   && tests/lexer/bin/test_lexer >> "$LOGS/lexer.log" 2>&1; then
   report PASS "lexer cases ($(tail -1 "$LOGS/lexer.log"))"
else
   tail -20 "$LOGS/lexer.log"; report FAIL "lexer cases (log $LOGS/lexer.log)"
fi

for arg in "$@"; do
   name=${arg%%=*}
   checkout=$(cd "${arg#*=}" && pwd) || { report FAIL "corpus $name: no checkout ${arg#*=}"; continue; }
   roots=$(awk -v n="$name" '$1 == n {print $3}' tests/reference/corpora.txt)
   [ -n "$roots" ] || { report FAIL "corpus $name: not in tests/reference/corpora.txt"; continue; }
   log=$LOGS/corpus-$name.log
   (cd "$checkout" && "$ROOT/tests/lexer/bin/test_lexer" --corpus $(echo "$roots" | tr ':' ' ')) \
      > "$log" 2>&1
   rc=$?
   grep -E '^ *[0-9]+ [^ ]+$' "$log" | awk '{print $1, $2}' | sort -k2 > "$LOGS/lines-$name.ada"
   (cd "$checkout" && OUTLINE_ROOT=$checkout OUTLINE_ROOTS=$roots \
       python3 "$ROOT/tests/reference/oracle_outline.py" --units) \
      | awk '{print $1, $5}' | sort -k2 > "$LOGS/lines-$name.py"
   files=$(wc -l < "$LOGS/lines-$name.ada")
   if [ $rc = 0 ] && cmp -s "$LOGS/lines-$name.ada" "$LOGS/lines-$name.py"; then
      report PASS "corpus $name ($files files, $(awk '{s+=$1} END {print s}' "$LOGS/lines-$name.ada") lines)"
   else
      grep -vE '^ *[0-9]+ [^ ]+$' "$log" | head -20
      diff "$LOGS/lines-$name.ada" "$LOGS/lines-$name.py" | head -10
      report FAIL "corpus $name (log $log)"
   fi
done

if command -v "$GNATPROVE" > /dev/null 2>&1; then
   if "$ALR" -n exec -- "$GNATPROVE" -P ada_outline.gpr -u ada_outline-lexer.adb -j0 \
         > "$LOGS/prove.log" 2>&1; then
      report PASS "proof ($(awk '$1 == "Total" {print $2 " checks, " ($NF == "." ? 0 : $NF) " unproved"}' obj/gnatprove/gnatprove.out))"
   else
      grep -E 'medium|high|low|error' "$LOGS/prove.log" | head -20
      report FAIL "proof (log $LOGS/prove.log)"
   fi
else
   report SKIP "proof (no gnatprove; GNATPROVE=<path>)"
fi
exit $FAILED
