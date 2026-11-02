#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# The checks of outline, one PASS/FAIL/SKIP line each; exit status 1 if one failed.
#
#   tests/run.sh [<corpus>=<checkout> ...]
#
#   1. build             alr build, no warning or style message (-gnatwe)
#   2. lexer cases       tests/lexer/bin/test_lexer, the unit cases
#   3. config            tests/config/run.sh: root and search roots, operators, compat mode
#   per corpus given (a name of tests/reference/corpora.txt and a checkout of it):
#   4. lexer <name>      every .ads/.adb under its roots lexes back to itself with no invalid
#                        token, and its line counts are those of the oracle
#                        (tests/reference/oracle_outline.py --units) on the same checkout
#   5. compat <name>     the reference set with OUTLINE_PY_COMPAT=1: every command prints what
#                        outline.py printed, the help text aside (checkout at the pinned revision)
#   6. reference <name>  the reference set: every command prints what outline.py printed, or
#                        differs as tests/reference/known_differences.txt says
#   7. proof             gnatprove on the lexer: every check proved (SKIP without gnatprove)
#
# e.g. tests/run.sh etcs-dmi=../etcs-dmi FreedomChat=../FreedomChat
# Steps 5 and 6 need the checkout at the revision of corpora.txt and take minutes
# (etcs-dmi: about 4 each on two cores); OUTLINE_QUICK=1 skips them.
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

if tests/config/run.sh > "$LOGS/config.log" 2>&1; then
   report PASS "config ($(tail -1 "$LOGS/config.log"))"
else
   tail -20 "$LOGS/config.log"; report FAIL "config (log $LOGS/config.log)"
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
      report PASS "lexer $name ($files files, $(awk '{s+=$1} END {print s}' "$LOGS/lines-$name.ada") lines)"
   else
      grep -vE '^ *[0-9]+ [^ ]+$' "$log" | head -20
      diff "$LOGS/lines-$name.ada" "$LOGS/lines-$name.py" | head -10
      report FAIL "lexer $name (log $log)"
   fi
   if [ "${OUTLINE_QUICK:-0}" = 1 ]; then
      report SKIP "compat $name, reference $name (OUTLINE_QUICK=1)"
      continue
   fi
   for mode in compat reference; do
      log=$LOGS/$mode-$name.log
      flag=; [ $mode = compat ] && flag=--compat
      if python3 tests/reference/compare.py "$name" "$checkout" $flag --known > "$log" 2>&1; then
         report PASS "$mode $name ($(head -1 "$log" | cut -d: -f2- | sed 's/^ //'))"
      else
         head -25 "$log"; report FAIL "$mode $name (log $log)"
      fi
   done
done

if command -v "$GNATPROVE" > /dev/null 2>&1; then
   if "$ALR" -n exec -- "$GNATPROVE" -P outline.gpr -u outline-lexer.adb -j0 \
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
