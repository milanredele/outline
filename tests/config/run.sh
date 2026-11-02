#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Where outline looks, and what outline.py could not do: the root and search roots from
# .outline, from the project files, or the fallback; running from a subdirectory; operator
# functions. Builds small trees in a temporary directory; exit status 1 on a failure.
set -u
BIN=$(cd "$(dirname "$0")/../.." && pwd)/bin/outline
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
unset OUTLINE_ROOT OUTLINE_ROOTS OUTLINE_PY_COMPAT
FAILS=0
CASES=0

# expect <name> <expected text, a line of the output> <command...>
expect () {
   name=$1; want=$2; shift 2
   CASES=$((CASES + 1))
   got=$("$@" 2>&1)
   if ! printf '%s\n' "$got" | grep -qxF -- "$want"; then
      FAILS=$((FAILS + 1))
      echo "FAIL $name"; echo "  wanted the line: $want"; echo "$got" | sed 's/^/  got: /' | head -12
   fi
}

# a project file with Source_Dirs, run from a subdirectory under .git
mkdir -p "$T/p1/.git" "$T/p1/src" "$T/p1/lib/deep" "$T/p1/obj" "$T/p1/src/sub"
cat > "$T/p1/p1.gpr" <<'EOF'
project P1 is
   for Source_Dirs use ("src", "lib/**");   --  "commented" (not a dir)
   for Object_Dir use "obj";
end P1;
EOF
cat > "$T/p1/src/geo.ads" <<'EOF'
package Geo is
   type Point is record
      X, Y : Integer;
   end record;
   function "+" (Left, Right : Point) return Point is
     ((Left.X + Right.X, Left.Y + Right.Y));
   function Norm (P : Point) return Natural
     with Post => Norm'Result >= 0;
end Geo;
EOF
printf 'package Deep is\n   procedure Run;\nend Deep;\n' > "$T/p1/lib/deep/deep.ads"
printf 'package Junk is\nend Junk;\n' > "$T/p1/obj/junk.ads"
expect "gpr: search roots" "search roots: src, lib" sh -c "cd '$T/p1/src/sub' && '$BIN' --where"
expect "gpr: root found upwards" "root: $T/p1" sh -c "cd '$T/p1/src/sub' && '$BIN' --where"
expect "gpr: a unit under lib/**" "== lib/deep/deep.ads (3 lines)" sh -c "cd '$T/p1/src' && '$BIN' deep"
expect "gpr: obj is not searched" "outline: no unit junk under src, lib" sh -c "cd '$T/p1' && '$BIN' junk"
expect "operator listed" "     5-6     expr function \"+\" (Left, Right : Point) return Point" \
   sh -c "cd '$T/p1' && '$BIN' geo"
expect "operator by name" "== src/geo.ads:5-6 (spec)" sh -c "cd '$T/p1' && '$BIN' geo +"
expect "operator by quoted name" "== src/geo.ads:5-6 (expression function)" \
   sh -c "cd '$T/p1' && '$BIN' geo --spec '\"+\"'"
expect "multi-line expression function in --spec" "    6       ((Left.X + Right.X, Left.Y + Right.Y));" \
   sh -c "cd '$T/p1' && '$BIN' geo --spec"
expect "aspect line in the outline" "             with Post => Norm'Result >= 0;" \
   sh -c "cd '$T/p1' && '$BIN' geo"
expect "record declaration" "== src/geo.ads:2-4 (type)" sh -c "cd '$T/p1' && '$BIN' geo --decl Point"

# two project files, one root inside another: searched once
mkdir -p "$T/p4/.git" "$T/p4/src/inner"
printf 'project A is\n   for Source_Dirs use ("src/inner");\nend A;\n' > "$T/p4/a.gpr"
printf 'project B is\n   for Source_Dirs use ("src", "src/inner");\nend B;\n' > "$T/p4/b.gpr"
printf 'package Once is\nend Once;\n' > "$T/p4/src/inner/once.ads"
expect "nested roots dropped" "search roots: src" sh -c "cd '$T/p4' && '$BIN' --where"
expect "nested roots: one unit" "     2 lines    0 subprograms  src/inner/once.ads" \
   sh -c "cd '$T/p4' && '$BIN' --units"

# .outline: the search roots and the spec directory; nested root wins over .git above
mkdir -p "$T/p2/.git" "$T/p2/w/a" "$T/p2/w/b" "$T/p2/w/docs"
printf '# roots\na\n\nspec: docs\n' > "$T/p2/w/.outline"
printf 'procedure Main is\nbegin\n   null;\nend Main;\n' > "$T/p2/w/a/main.adb"
printf 'package Other is\nend Other;\n' > "$T/p2/w/b/other.ads"
printf '# Title\n\n## 1 First\nalpha\n## 2 Second\nbeta\n' > "$T/p2/w/docs/01-intro.md"
expect ".outline: roots" "search roots: a" sh -c "cd '$T/p2/w/a' && '$BIN' --where"
expect ".outline: spec dir" "spec directory: docs" sh -c "cd '$T/p2/w' && '$BIN' --where"
expect ".outline: unit" "    1-4     body procedure Main" sh -c "cd '$T/p2/w' && '$BIN' main"
expect ".outline: not a root" "outline: no unit other under a" sh -c "cd '$T/p2/w' && '$BIN' other"
expect ".outline: --md by number" "== docs/01-intro.md:5-6" sh -c "cd '$T/p2/w' && '$BIN' --md 1 2"
expect "environment beats .outline" "search roots: b" \
   sh -c "cd '$T/p2/w' && OUTLINE_ROOTS=b '$BIN' --where"

# no .outline, no project file: the root itself, without obj and alire
mkdir -p "$T/p3/.git" "$T/p3/src" "$T/p3/alire/cache"
printf 'package Kept is\nend Kept;\n' > "$T/p3/src/kept.ads"
printf 'package Cached is\nend Cached;\n' > "$T/p3/alire/cache/cached.ads"
expect "fallback: root" "search roots: ." sh -c "cd '$T/p3' && '$BIN' --where"
expect "fallback: unit" "== src/kept.ads (2 lines)" sh -c "cd '$T/p3' && '$BIN' kept"
expect "fallback: alire skipped" "outline: no unit cached under ." sh -c "cd '$T/p3' && '$BIN' cached"

# compatibility mode: outline.py's behaviour
expect "compat: operator not listed" "     7-8     spec function Norm (P : Point) return Natural" \
   sh -c "cd '$T/p1' && OUTLINE_PY_COMPAT=1 '$BIN' geo"
expect "compat: expression function ends at is" "     5-5     expr function \"+\" (Left, Right : Point) return Point" \
   sh -c "cd '$T/p1' && OUTLINE_PY_COMPAT=expr_end '$BIN' geo"

echo "cases: $CASES, failed: $FAILS"
[ $FAILS = 0 ]
