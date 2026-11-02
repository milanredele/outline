--  SPDX-License-Identifier: Apache-2.0
--
--  A source file as lines, with the two views of each line that the
--  scanners look at: without its comment, and its code (no comment, a
--  string literal as "", a character literal as ' '). The views come
--  from the lexer, so that -- inside a string literal is no comment and
--  '(' does not count as a parenthesis. In compatibility mode they are
--  made the way outline.py made them: everything from the first -- cut,
--  then "[^"]*" replaced by "".
--
--  Lines are numbered from 0, as outline.py numbers them internally;
--  they are split at LF, CR LF and a lone CR, as Python's universal
--  newlines split them, and decoded from UTF-8 (Outline.Text).

with Ada.Containers.Vectors;
with Outline.Text;

package Outline.Sources is

   use Outline.Text;

   package Line_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => UStr, "=" => U."=");

   type Source_File is record
      Raw        : Line_Vectors.Vector;
      No_Comment : Line_Vectors.Vector;
      Code       : Line_Vectors.Vector;
      Last_Ended : Boolean := True;
      --  the last line has a line terminator (readlines keeps a '\n')
   end record;

   function Load (Path : String; Compat : Boolean) return Source_File;
   --  The file at Path; an empty source when it cannot be read.

   function Count (S : Source_File) return Natural is
     (Natural (S.Raw.Length));

   function Raw (S : Source_File; K : Natural) return WWS is
     (+S.Raw (K));
   function No_Comment (S : Source_File; K : Natural) return WWS is
     (+S.No_Comment (K));
   function Code (S : Source_File; K : Natural) return WWS is
     (+S.Code (K));

end Outline.Sources;
