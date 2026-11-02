--  SPDX-License-Identifier: Apache-2.0
--
--  The lexical elements of Ada 2022 (RM 2.2-2.8), one at a time, from a
--  source held in a String. The lexer never raises and accepts any byte
--  sequence: what is not Ada comes out as an Invalid token of one byte, a
--  string literal or character literal that is not closed on its line as
--  a Malformed one, and scanning goes on. Every byte of the source is
--  either inside exactly one token or a separator (space, tab, vertical
--  tab, form feed, line terminator), so the tokens and the gaps between
--  them give back the source.
--
--  Lines are counted as Python's universal newlines count them, which is
--  what the outline.py this replaces printed: LF, CR LF and a lone CR each
--  end a line. Bytes from 128 up are taken as letters, so identifiers in
--  UTF-8 scan as identifiers and a UTF-8 character literal ('é') as a
--  character literal.
--
--  An apostrophe is a character literal or a tick (RM 2.2(10)); it is a
--  tick after an identifier, a closing parenthesis or bracket, a string
--  or character literal, or the reserved word `all` (X'First, F (Y)'Old,
--  P.all'Size, Character'('x')), and otherwise the start of a character
--  literal when the byte after the next one is an apostrophe.

package Outline.Lexer with SPARK_Mode => On is

   type Token_Kind is
     (Identifier,         --  also an attribute designator after a tick,
      --                     even Access, Delta, Digits, Mod and Range
      Reserved_Word,      --  see Word
      Numeric_Literal,    --  decimal or based, with exponent
      Character_Literal,  --  'x', including the quotes
      String_Literal,     --  "...", including the quotes, "" inside
      Delimiter,          --  see Delim
      Comment,            --  from -- to the end of the line, terminator excluded
      Invalid,            --  one byte that starts no lexical element
      End_Of_Input);

   type Reserved is
     (W_Abort, W_Abs, W_Abstract, W_Accept, W_Access, W_Aliased, W_All,
      W_And, W_Array, W_At, W_Begin, W_Body, W_Case, W_Constant, W_Declare,
      W_Delay, W_Delta, W_Digits, W_Do, W_Else, W_Elsif, W_End, W_Entry,
      W_Exception, W_Exit, W_For, W_Function, W_Generic, W_Goto, W_If, W_In,
      W_Interface, W_Is, W_Limited, W_Loop, W_Mod, W_New, W_Not, W_Null,
      W_Of, W_Or, W_Others, W_Out, W_Overriding, W_Package, W_Parallel,
      W_Pragma, W_Private, W_Procedure, W_Protected, W_Raise, W_Range,
      W_Record, W_Rem, W_Renames, W_Requeue, W_Return, W_Reverse, W_Select,
      W_Separate, W_Some, W_Subtype, W_Synchronized, W_Tagged, W_Task,
      W_Terminate, W_Then, W_Type, W_Until, W_Use, W_When, W_While, W_With,
      W_Xor);
   --  The reserved words of Ada 2022 (RM 2.9), in the order of the RM.

   type Delimiter_Kind is
     (Ampersand, Apostrophe, Left_Paren, Right_Paren, Star, Plus, Comma,
      Minus, Dot, Slash, Colon, Semicolon, Less, Equal, Greater, Bar,
      Left_Bracket, Right_Bracket, At_Sign,
      Arrow, Double_Dot, Double_Star, Assign, Not_Equal, Greater_Equal,
      Less_Equal, Left_Label, Right_Label, Box);
   --  RM 2.2(9) and 2.2(14); `[`, `]` and `@` of Ada 2022; `!` (RM J.2)
   --  comes out as Bar. A tick is an Apostrophe.

   type Token is record
      Kind      : Token_Kind     := End_Of_Input;
      First     : Positive       := 1;
      Last      : Natural        := 0;
      Line      : Positive       := 1;
      Column    : Positive       := 1;
      Word      : Reserved       := W_Abort;
      Delim     : Delimiter_Kind := Ampersand;
      Malformed : Boolean        := False;
   end record;
   --  Source (First .. Last) is the text of the token; End_Of_Input has
   --  Last = First - 1. Line and Column (a byte count from 1) are those of
   --  First. Word is meaningful for a Reserved_Word, Delim for a Delimiter;
   --  Malformed marks a string or character literal not closed on its
   --  line, a based literal without its closing #, an identifier with a
   --  leading, doubled or trailing underscore.

   Max_Source : constant := Integer'Last - 8;

   type Cursor is private;
   --  Where the next token starts, the line count and what came before.

   function Fits (Source : String) return Boolean is
     (Source'First = 1 and then Source'Last in 0 .. Max_Source);
   --  A source the lexer takes: indexed from 1, short enough that looking
   --  a few bytes past its end does not overflow.

   function Valid (Source : String; C : Cursor) return Boolean;
   --  C is a cursor into Source (what Start and Next keep true).

   function Start (Source : String) return Cursor
   with Pre  => Fits (Source),
        Post => Valid (Source, Start'Result);
   --  A cursor at the beginning of Source.

   procedure Next (Source : String; C : in out Cursor; T : out Token)
   with Pre  => Fits (Source) and then Valid (Source, C),
        Post => Valid (Source, C)
                and then (if T.Kind = End_Of_Input
                          then T.Last = T.First - 1
                               and then T.First = Source'Last + 1
                          else T.First <= T.Last
                               and then T.Last <= Source'Last);
   --  The next token of Source after C, and C advanced past it; at the
   --  end, End_Of_Input with First = Source'Last + 1, again and again.

   function Line_Of (C : Cursor) return Positive;
   --  The line where C stands (after the last token Next returned and the
   --  separators that followed it are not yet counted).

   function Is_Letter (B : Character) return Boolean is
     (B in 'a' .. 'z' | 'A' .. 'Z' or else Character'Pos (B) >= 128);
   function Is_Digit (B : Character) return Boolean is (B in '0' .. '9');
   function Is_Line_End (B : Character) return Boolean is
     (B = ASCII.LF or else B = ASCII.CR);

   function Image (W : Reserved) return String
   with Post => Image'Result'First = 1 and then Image'Result'Length in 2 .. 12;
   --  The word in lower case: Image (W_Procedure) = "procedure".

private

   type Cursor is record
      Pos        : Positive := 1;   --  the next byte to look at
      Line       : Positive := 1;
      Line_Start : Positive := 1;   --  the first byte of that line
      Tick_Next  : Boolean  := False;
      --  an apostrophe here would be a tick: the previous token was an
      --  identifier, a ) or ], a literal or `all`
      After_Tick : Boolean  := False;
      --  the previous token was a tick: a reserved word here is an
      --  attribute designator (X'Range, P'Access)
   end record;

   function Valid (Source : String; C : Cursor) return Boolean is
     (C.Pos - 1 <= Source'Last and then C.Line <= C.Pos
      and then C.Line_Start <= C.Pos);

   function Line_Of (C : Cursor) return Positive is (C.Line);

end Outline.Lexer;
