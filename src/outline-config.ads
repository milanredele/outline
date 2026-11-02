--  SPDX-License-Identifier: Apache-2.0
--
--  Where outline looks.
--
--  The root: OUTLINE_ROOT, else the nearest directory upwards from the
--  current one that holds a file .outline or a .git, else the current
--  directory. Paths are shown relative to it.
--
--  The search roots, directories under the root searched recursively for
--  .ads and .adb files (hidden ones skipped):
--    1. OUTLINE_ROOTS, colon-separated;
--    2. else the lines of <root>/.outline (blank lines and # comments
--       skipped; a line `spec: <dir>` names the directory of the numbered
--       markdown files of --md NN, default spec);
--    3. else the Source_Dirs of the project files <root>/*.gpr (string
--       literals of `for Source_Dirs use (...)`, a trailing /** dropped;
--       a project without Source_Dirs counts its own directory; a
--       directory inside another one is dropped, as the search is
--       recursive anyway);
--    4. else the root itself, without obj, bin, lib and alire.
--
--  OUTLINE_PY_COMPAT makes outline reproduce outline.py where outline.py
--  is wrong, for checking the port: 1 (or all) for every fix, else a
--  comma-separated list of views, expr_end, operators (see Fix).

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package Outline.Config is

   use Ada.Strings.Unbounded;

   package Path_Vectors is new Ada.Containers.Vectors
     (Positive, Unbounded_String);
   subtype Path_List is Path_Vectors.Vector;

   type Fix is
     (Views,       --  comments, strings, character literals from the lexer
      Expr_End,    --  a multi-line expression function ends at its ';'
      Operators);  --  operator functions ("+") are declarations
   --  Where outline does not do what outline.py does (Outline.Sources,
   --  Outline.Scan).

   procedure Initialize;
   --  Reads the environment and the files above.

   function Compat (F : Fix) return Boolean;
   --  Fix F is off: outline.py's behaviour.
   function Root return String;
   function Roots return Path_List;
   function Spec_Dir return String;

   function Join (Dir, Path : String) return String;
   --  os.path.join (Dir, Path).

   function Rel_Path (Path : String; Start : String) return String;
   --  os.path.relpath (Path, Start): both made absolute and normalized
   --  without resolving links.

   function Is_File (Path : String) return Boolean;
   --  os.path.isfile.

   function All_Units return Path_List;
   --  The .ads and .adb files under the search roots, relative to the
   --  root, sorted.

   function Unit_Files (Name : String) return Path_List;
   --  The files of a unit given as a path (from the current directory or
   --  the root), a file name or an Ada name (fc_session, Fc_Core.Links,
   --  fc_core-links): the spec first.

   function Md_File (Name : String) return String;
   --  A markdown file given as a path or by its number in the spec
   --  directory (03 or 3: <spec>/03-*.md); "" when there is none.

   function Joined (List : Path_List) return String;
   --  ", ".join (List).

   generic
      with procedure Visit (Path : String);
   procedure Walk (Dir : String; Hidden : Boolean);
   --  Every file under Dir, recursively, in sorted order (Path is Dir
   --  joined with the path below it); entries starting with a dot are
   --  skipped unless Hidden.

end Outline.Config;
