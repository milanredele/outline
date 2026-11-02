--  SPDX-License-Identifier: Apache-2.0
--
--  Text as Python 3 sees it, where outline.py's output depends on it:
--  lines are decoded from UTF-8 into code points (an invalid sequence
--  becomes U+FFFD as with errors='replace'), widths and slices count code
--  points, \s and \w follow str.isspace and str.isalnum closely enough for
--  source text. The output is encoded back to UTF-8.

with Ada.Strings.Wide_Wide_Unbounded;

package Outline.Text is

   subtype WWS is Wide_Wide_String;
   subtype WWC is Wide_Wide_Character;
   package U renames Ada.Strings.Wide_Wide_Unbounded;
   subtype UStr is U.Unbounded_Wide_Wide_String;

   function "+" (S : WWS) return UStr renames U.To_Unbounded_Wide_Wide_String;
   function "+" (S : UStr) return WWS renames U.To_Wide_Wide_String;

   type WWS_List is array (Positive range <>) of UStr;

   function Decode (S : String) return WWS;
   --  UTF-8 to code points; each maximal invalid subpart is one U+FFFD.

   function Encode (W : WWS) return String;
   --  Code points to UTF-8.

   function To_WWS (S : String) return WWS renames Decode;

   function Is_Space (C : WWC) return Boolean;
   --  str.isspace: the ASCII separators, 16#1C# .. 16#1F#, 16#85#, and the
   --  Unicode space separators, line and paragraph separators.

   function Is_Word (C : WWC) return Boolean;
   --  The \w of Python's re for str: letters, digits, the underscore.

   function Is_ASCII_Word (C : WWC) return Boolean is
     (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');
   --  \w of GNU grep in the C locale.

   function Lower (W : WWS) return WWS;
   --  str.lower with the simple case mapping.

   function Strip (W : WWS) return WWS;
   function LStrip (W : WWS) return WWS;
   function RStrip (W : WWS) return WWS;
   --  str.strip, lstrip, rstrip: Python whitespace.

   function Strip_Chars (W : WWS; Chars : WWS) return WWS;
   function LStrip_Chars (W : WWS; Chars : WWS) return WWS;
   function RStrip_Chars (W : WWS; Chars : WWS) return WWS;
   --  str.strip (Chars) and its left and right halves.

   function Collapse (W : WWS) return WWS;
   --  re.sub (r'\s+', ' ', W).

   function Head (W : WWS; N : Natural) return WWS;
   --  W[:N].

   function Starts_With (W, Prefix : WWS) return Boolean;
   function Ends_With (W, Suffix : WWS) return Boolean;

   function Equal_CI (A, B : WWS) return Boolean;
   --  A.lower () == B.lower ().

   function Has_At (W : WWS; Pos : Positive; Pat : WWS;
                    Case_Insensitive : Boolean := False) return Boolean;
   --  W (Pos ..) begins with Pat.

   function Boundary (W : WWS; Pos : Positive;
                      ASCII_Words : Boolean := False) return Boolean;
   --  \b before W (Pos) (Pos may be W'Last + 1): the characters on both
   --  sides differ in being word characters, the ends counting as not.

   function Find_Word (W : WWS; Word : WWS; From : Positive;
                       Case_Insensitive : Boolean := False) return Natural;
   --  The first position at or after From of Word between two \b
   --  (re.search (r'\bWord\b')), or 0.

   function Skip_Spaces (W : WWS; Pos : Positive) return Positive;
   --  The first position at or after Pos that is not Python whitespace
   --  (W'Last + 1 if none).

   function Index_CI (W, Pat : WWS) return Natural;
   --  re.search (re.escape (Pat), W, re.I): the first position, 0 if none;
   --  an empty Pat is found at W'First.

   function First_Word (W : WWS) return WWS;
   --  W.split ()[0], "" when W has no word.

   function Img (N : Integer; Width : Natural := 0) return WWS;
   --  f'{N:Widthd}': right-aligned, never cut.

   function Pad (W : WWS; Width : Natural) return WWS;
   --  f'{W:<Width}': left-aligned, never cut.

   function Zfill (W : WWS; Width : Natural) return WWS;
   --  str.zfill.

   function Repr (W : WWS) return WWS;
   --  repr (W) of a str.

   procedure Put_Line (W : WWS);
   procedure Put_Error (W : WWS);
   --  W in UTF-8 and a line end, on standard output and standard error.

end Outline.Text;
