--  SPDX-License-Identifier: Apache-2.0

package body Ada_Outline.Lexer with SPARK_Mode => On is

   subtype Word_Text is String (1 .. 12);

   Words : constant array (Reserved) of Word_Text :=
     ["abort       ", "abs         ", "abstract    ", "accept      ",
      "access      ", "aliased     ", "all         ", "and         ",
      "array       ", "at          ", "begin       ", "body        ",
      "case        ", "constant    ", "declare     ", "delay       ",
      "delta       ", "digits      ", "do          ", "else        ",
      "elsif       ", "end         ", "entry       ", "exception   ",
      "exit        ", "for         ", "function    ", "generic     ",
      "goto        ", "if          ", "in          ", "interface   ",
      "is          ", "limited     ", "loop        ", "mod         ",
      "new         ", "not         ", "null        ", "of          ",
      "or          ", "others      ", "out         ", "overriding  ",
      "package     ", "parallel    ", "pragma      ", "private     ",
      "procedure   ", "protected   ", "raise       ", "range       ",
      "record      ", "rem         ", "renames     ", "requeue     ",
      "return      ", "reverse     ", "select      ", "separate    ",
      "some        ", "subtype     ", "synchronized", "tagged      ",
      "task        ", "terminate   ", "then        ", "type        ",
      "until       ", "use         ", "when        ", "while       ",
      "with        ", "xor         "];

   subtype Word_Length is Positive range 2 .. 12;

   Lengths : constant array (Reserved) of Word_Length :=
     [5, 3, 8, 6, 6, 7, 3, 3, 5, 2, 5, 4, 4, 8, 7, 5, 5, 6, 2, 4, 5, 3, 5, 9,
      4, 3, 8, 7, 4, 2, 2, 9, 2, 7, 4, 3, 3, 3, 4, 2, 2, 6, 3, 10, 7, 8, 6, 7,
      9, 9, 5, 5, 6, 3, 7, 7, 6, 7, 6, 8, 4, 7, 12, 6, 4, 9, 4, 4, 5, 3, 4, 5,
      4, 3];

   function Image (W : Reserved) return String is
     (Words (W) (1 .. Lengths (W)));

   function Start (Source : String) return Cursor is
     (Pos => 1, Line => 1, Line_Start => 1, Tick_Next => False,
      After_Tick => False);

   --  The byte at I, or NUL past the end: lookahead without bound checks.
   function At_Pos (Source : String; I : Positive) return Character is
     (if I <= Source'Last then Source (I) else ASCII.NUL)
   with Pre => Source'First = 1;

   function Is_Word_Char (B : Character) return Boolean is
     (Is_Letter (B) or else Is_Digit (B) or else B = '_');

   function Is_Extended_Digit (B : Character) return Boolean is
     (Is_Digit (B) or else B in 'a' .. 'f' | 'A' .. 'F');

   --  The number of bytes of the UTF-8 sequence that B starts (1 for
   --  anything that is not the lead byte of a longer sequence).
   function UTF8_Length (B : Character) return Positive is
     (case Character'Pos (B) is
         when 16#C0# .. 16#DF# => 2,
         when 16#E0# .. 16#EF# => 3,
         when 16#F0# .. 16#F7# => 4,
         when others           => 1);

   --  The reserved word spelled by Source (First .. Last) in any case, if
   --  it is one.
   procedure Find_Word
     (Source : String;
      First  : Positive;
      Last   : Natural;
      Found  : out Boolean;
      Word   : out Reserved)
   with Pre => Source'First = 1 and then Last <= Source'Last
               and then First <= Last
   is
      Lower : Word_Text := [others => ' '];
   begin
      Found := False;
      Word := W_Abort;
      if Last - First + 1 not in Word_Length then
         return;
      end if;
      for I in First .. Last loop
         pragma Loop_Invariant (Last - First + 1 in Word_Length);
         declare
            B : constant Character := Source (I);
         begin
            if B in 'A' .. 'Z' then
               Lower (I - First + 1) :=
                 Character'Val (Character'Pos (B) + 32);
            elsif B in 'a' .. 'z' then
               Lower (I - First + 1) := B;
            else
               return;
            end if;
         end;
      end loop;
      for W in Reserved loop
         if Words (W) = Lower then
            Found := True;
            Word := W;
            return;
         end if;
      end loop;
   end Find_Word;

   --  Separators and line terminators from C.Pos on; C stops at the first
   --  byte of a token or past the end.
   procedure Skip_Separators (Source : String; C : in out Cursor)
   with Pre  => Fits (Source)
                and then Valid (Source, C),
        Post => Valid (Source, C)
   is
   begin
      while C.Pos <= Source'Last loop
         pragma Loop_Invariant (Valid (Source, C));
         case Source (C.Pos) is
            when ' ' | ASCII.HT | ASCII.VT | ASCII.FF =>
               C.Pos := C.Pos + 1;
            when ASCII.LF =>
               C.Pos := C.Pos + 1;
               C.Line := C.Line + 1;
               C.Line_Start := C.Pos;
            when ASCII.CR =>
               if At_Pos (Source, C.Pos + 1) = ASCII.LF then
                  C.Pos := C.Pos + 2;
               else
                  C.Pos := C.Pos + 1;
               end if;
               C.Line := C.Line + 1;
               C.Line_Start := C.Pos;
            when others =>
               exit;
         end case;
      end loop;
   end Skip_Separators;

   --  The last byte of the identifier that starts at First (a letter or
   --  an underscore), and whether its underscores break RM 2.3(3).
   procedure Scan_Identifier
     (Source    : String;
      First     : Positive;
      Last      : out Positive;
      Malformed : out Boolean)
   with Pre  => Fits (Source)
                and then First <= Source'Last,
        Post => Last in First .. Source'Last
   is
   begin
      Last := First;
      Malformed := Source (First) = '_';
      while Last < Source'Last and then Is_Word_Char (Source (Last + 1)) loop
         pragma Loop_Invariant (Last in First .. Source'Last - 1);
         if Source (Last + 1) = '_' and then Source (Last) = '_' then
            Malformed := True;
         end if;
         Last := Last + 1;
      end loop;
      if Source (Last) = '_' then
         Malformed := True;
      end if;
   end Scan_Identifier;

   --  Digits and underscores after Last; Last moves to the last of them.
   procedure Skip_Digits
     (Source : String; Last : in out Positive; Extended : Boolean)
   with Pre  => Fits (Source)
                and then Last <= Source'Last,
        Post => Last in Last'Old .. Source'Last
   is
   begin
      while Last < Source'Last
        and then (Source (Last + 1) = '_'
                  or else (if Extended then Is_Extended_Digit (Source (Last + 1))
                           else Is_Digit (Source (Last + 1))))
      loop
         pragma Loop_Invariant (Last in Last'Loop_Entry .. Source'Last - 1);
         Last := Last + 1;
      end loop;
   end Skip_Digits;

   --  The last byte of the numeric literal that starts at First (a digit):
   --  a decimal literal with fraction and exponent, or a based literal
   --  base#digits[.digits]#[exponent] (RM 2.4).
   procedure Scan_Number
     (Source    : String;
      First     : Positive;
      Last      : out Positive;
      Malformed : out Boolean)
   with Pre  => Fits (Source)
                and then First <= Source'Last,
        Post => Last in First .. Source'Last
   is
   begin
      Last := First;
      Malformed := False;
      Skip_Digits (Source, Last, Extended => False);
      if At_Pos (Source, Last + 1) = '#' then
         Last := Last + 1;
         Skip_Digits (Source, Last, Extended => True);
         if At_Pos (Source, Last + 1) = '.' then
            Last := Last + 1;
            Skip_Digits (Source, Last, Extended => True);
         end if;
         if At_Pos (Source, Last + 1) = '#' then
            Last := Last + 1;
         else
            Malformed := True;
            return;
         end if;
      elsif At_Pos (Source, Last + 1) = '.'
        and then Is_Digit (At_Pos (Source, Last + 2))
      then
         Last := Last + 1;
         Skip_Digits (Source, Last, Extended => False);
      end if;
      if At_Pos (Source, Last + 1) in 'e' | 'E' then
         if Is_Digit (At_Pos (Source, Last + 2)) then
            Last := Last + 1;
            Skip_Digits (Source, Last, Extended => False);
         elsif At_Pos (Source, Last + 2) in '+' | '-'
           and then Is_Digit (At_Pos (Source, Last + 3))
         then
            Last := Last + 2;
            Skip_Digits (Source, Last, Extended => False);
         end if;
      end if;
   end Scan_Number;

   --  The last byte of the string literal that starts at First (a quote):
   --  its closing quote, a doubled quote standing for one (RM 2.6); or,
   --  not closed on its line, the byte before the line end, Malformed.
   procedure Scan_String
     (Source    : String;
      First     : Positive;
      Last      : out Positive;
      Malformed : out Boolean)
   with Pre  => Fits (Source)
                and then First <= Source'Last,
        Post => Last in First .. Source'Last
   is
      J : Positive := First + 1;
   begin
      Malformed := True;
      Last := First;
      while J <= Source'Last and then not Is_Line_End (Source (J)) loop
         pragma Loop_Invariant (J in First + 1 .. Source'Last
                                and then Last in First .. J - 1);
         if Source (J) = '"' then
            if At_Pos (Source, J + 1) = '"' then
               Last := J + 1;
               J := J + 2;
            else
               Last := J;
               Malformed := False;
               return;
            end if;
         else
            Last := J;
            J := J + 1;
         end if;
      end loop;
   end Scan_String;

   procedure Next (Source : String; C : in out Cursor; T : out Token) is
      P    : Positive;
      Last : Positive;
      B    : Character;

      subtype Delimiter_Length is Positive range 1 .. 2;

      procedure Set_Delim (D : Delimiter_Kind; Length : Delimiter_Length)
      with Pre  => Fits (Source) and then P <= Source'Last
                   and then P + Length - 1 <= Source'Last
                   and then T.First = P,
           Post => Last = P + Length - 1 and then T.Kind = Delimiter
                   and then T.First = P
      is
      begin
         T.Kind := Delimiter;
         T.Delim := D;
         Last := P + Length - 1;
      end Set_Delim;

   begin
      Skip_Separators (Source, C);
      P := C.Pos;
      T := (Kind      => End_Of_Input,
            First     => P,
            Last      => P - 1,
            Line      => C.Line,
            Column    => P - C.Line_Start + 1,
            Word      => W_Abort,
            Delim     => Ampersand,
            Malformed => False);
      if P > Source'Last then
         return;
      end if;
      B := Source (P);
      Last := P;

      if Is_Letter (B) or else B = '_' then
         Scan_Identifier (Source, P, Last, T.Malformed);
         declare
            Found : Boolean;
            W     : Reserved;
         begin
            Find_Word (Source, P, Last, Found, W);
            if Found and then not C.After_Tick then
               T.Kind := Reserved_Word;
               T.Word := W;
            else
               T.Kind := Identifier;
            end if;
         end;

      elsif Is_Digit (B) then
         T.Kind := Numeric_Literal;
         Scan_Number (Source, P, Last, T.Malformed);

      elsif B = '"' then
         T.Kind := String_Literal;
         Scan_String (Source, P, Last, T.Malformed);

      elsif B = ''' then
         declare
            Lead   : constant Character := At_Pos (Source, P + 1);
            Length : constant Positive := UTF8_Length (Lead);
         begin
            if not C.Tick_Next
              and then P + 1 <= Source'Last
              and then not Is_Line_End (Lead)
              and then P + 1 + Length <= Source'Last
              and then Source (P + 1 + Length) = '''
            then
               T.Kind := Character_Literal;
               Last := P + 1 + Length;
            else
               Set_Delim (Apostrophe, 1);
            end if;
         end;

      elsif B = '-' and then At_Pos (Source, P + 1) = '-' then
         T.Kind := Comment;
         Last := P + 1;
         while Last < Source'Last and then not Is_Line_End (Source (Last + 1))
         loop
            pragma Loop_Invariant (Last in P + 1 .. Source'Last - 1);
            Last := Last + 1;
         end loop;

      else
         declare
            N : constant Character := At_Pos (Source, P + 1);
         begin
            case B is
               when '&'       => Set_Delim (Ampersand, 1);
               when '('       => Set_Delim (Left_Paren, 1);
               when ')'       => Set_Delim (Right_Paren, 1);
               when '['       => Set_Delim (Left_Bracket, 1);
               when ']'       => Set_Delim (Right_Bracket, 1);
               when '@'       => Set_Delim (At_Sign, 1);
               when ','       => Set_Delim (Comma, 1);
               when '+'       => Set_Delim (Plus, 1);
               when '-'       => Set_Delim (Minus, 1);
               when ';'       => Set_Delim (Semicolon, 1);
               when '|' | '!' => Set_Delim (Bar, 1);
               when '*' =>
                  if N = '*' then
                     Set_Delim (Double_Star, 2);
                  else
                     Set_Delim (Star, 1);
                  end if;
               when '.' =>
                  if N = '.' then
                     Set_Delim (Double_Dot, 2);
                  else
                     Set_Delim (Dot, 1);
                  end if;
               when '/' =>
                  if N = '=' then
                     Set_Delim (Not_Equal, 2);
                  else
                     Set_Delim (Slash, 1);
                  end if;
               when ':' =>
                  if N = '=' then
                     Set_Delim (Assign, 2);
                  else
                     Set_Delim (Colon, 1);
                  end if;
               when '<' =>
                  if N = '=' then
                     Set_Delim (Less_Equal, 2);
                  elsif N = '<' then
                     Set_Delim (Left_Label, 2);
                  elsif N = '>' then
                     Set_Delim (Box, 2);
                  else
                     Set_Delim (Less, 1);
                  end if;
               when '=' =>
                  if N = '>' then
                     Set_Delim (Arrow, 2);
                  else
                     Set_Delim (Equal, 1);
                  end if;
               when '>' =>
                  if N = '=' then
                     Set_Delim (Greater_Equal, 2);
                  elsif N = '>' then
                     Set_Delim (Right_Label, 2);
                  else
                     Set_Delim (Greater, 1);
                  end if;
               when others =>
                  T.Kind := Invalid;
            end case;
         end;
      end if;

      pragma Assert (T.Kind /= End_Of_Input and then T.First = P
                     and then Last in P .. Source'Last);
      T.Last := Last;
      C.Pos := Last + 1;
      if T.Kind /= Comment then
         C.After_Tick := T.Kind = Delimiter and then T.Delim = Apostrophe;
      end if;
      case T.Kind is
         when Comment =>
            null;    --  X --  a comment, then 'First: still a tick
         when Identifier | Character_Literal | String_Literal =>
            C.Tick_Next := True;
         when Reserved_Word =>
            C.Tick_Next := T.Word = W_All;
         when Delimiter =>
            C.Tick_Next := T.Delim in Right_Paren | Right_Bracket;
         when others =>
            C.Tick_Next := False;
      end case;
   end Next;

end Ada_Outline.Lexer;
