--  SPDX-License-Identifier: Apache-2.0
--
--  The declarations of a source file, found as outline.py finds them.
--
--  A subprogram declaration starts on a line that begins with
--  [overriding] procedure or function and its name. It is a body when an
--  `is` at parenthesis depth 0 comes before a `;` and is not followed by
--  `(`, new, abstract, null or separate; a body ends at the line
--  `end Name;` at the indentation of its first line. Otherwise it is a
--  spec, ending at its `;`; after `is (`, `is new`, `is abstract`,
--  `is null` and `is separate` it is an expression function (Expr).
--
--  The other declarations are those whose line begins with type or
--  subtype and a name, with names and a colon (objects, components), or
--  with a with or use clause; a record type ends at its `end record;`
--  at its indentation, anything else at the `;` at depth 0. Lines inside
--  a subprogram body are left out.
--
--  Where outline.py is wrong, this is not, unless Outline.Config.Compat
--  says so for that fix:
--  * an expression function, instance or `is separate` that spans lines
--    ends at its `;` (outline.py ends it at the line of its `is`);
--  * an operator function (function "+") is a declaration, named + (its
--    name does not match outline.py's [\w.]+).

with Ada.Containers.Vectors;
with Outline.Sources;
with Outline.Text;

package Outline.Scan is

   use Outline.Text;

   type Subprogram is record
      Indent  : Natural := 0;
      Kind    : UStr;              --  "procedure" or "function"
      Name    : UStr;              --  without quotes
      First   : Natural := 0;      --  lines, from 0
      Last    : Natural := 0;
      Is_Body : Boolean := False;
      Expr    : Boolean := False;
   end record;

   package Subprogram_Vectors is new Ada.Containers.Vectors
     (Positive, Subprogram);

   function Declarations
     (S : Outline.Sources.Source_File) return Subprogram_Vectors.Vector;

   type Other is record
      Indent : Natural := 0;
      Kind   : UStr;   --  type, subtype, object, with, use
      Name   : UStr;   --  for an object or a clause, the names as written
      First  : Natural := 0;
      Last   : Natural := 0;
   end record;

   package Other_Vectors is new Ada.Containers.Vectors (Positive, Other);

   function Other_Declarations
     (S : Outline.Sources.Source_File) return Other_Vectors.Vector;

   function Aspect_At (Line : WWS; Name : out UStr) return Boolean;
   --  ASPECT.search (Line): the first aspect mark of outline.py's list
   --  (Global, Depends, Pre, Post, ..., Annotate) followed by =>; Name is
   --  the mark as written.

end Outline.Scan;
