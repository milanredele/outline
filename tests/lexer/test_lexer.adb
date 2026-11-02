--  SPDX-License-Identifier: Apache-2.0
--
--  The tests of Ada_Outline.Lexer.
--
--    test_lexer                  the unit cases below; exit status 1 on a failure
--    test_lexer --corpus DIR...  every .ads and .adb under the directories:
--                                the tokens and the separators between them
--                                give back the file, no Invalid token, every
--                                Malformed one listed; one line per file,
--                                "<lines> <path>", the line count as
--                                Python's readlines gives it, to compare with
--                                the oracle's --units

with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada_Outline.Files;
with Ada_Outline.Lexer;

procedure Test_Lexer is
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;
   use Ada_Outline.Lexer;

   Failures : Natural := 0;
   Cases    : Natural := 0;

   LF : constant Character := ASCII.LF;
   CR : constant Character := ASCII.CR;

   --  The tokens of Source as "K:text" joined by " | ": K is I identifier,
   --  W reserved word, N number, C character literal, S string literal,
   --  D delimiter, R comment (remark), X invalid; a ! after K marks a
   --  Malformed token; @L.C the line and column when Positions.
   function Render (Source : String; Positions : Boolean := False)
     return String
   is
      C      : Cursor := Start (Source);
      T      : Token;
      Result : Unbounded_String;
   begin
      loop
         Next (Source, C, T);
         exit when T.Kind = End_Of_Input;
         if Length (Result) > 0 then
            Append (Result, " | ");
         end if;
         Append (Result,
                 (case T.Kind is
                     when Identifier        => "I",
                     when Reserved_Word     => "W",
                     when Numeric_Literal   => "N",
                     when Character_Literal => "C",
                     when String_Literal    => "S",
                     when Delimiter         => "D",
                     when Comment           => "R",
                     when Invalid           => "X",
                     when End_Of_Input      => "E"));
         if T.Malformed then
            Append (Result, "!");
         end if;
         if Positions then
            Append (Result, "@" & T.Line'Image (2 .. T.Line'Image'Last) & "."
                    & T.Column'Image (2 .. T.Column'Image'Last));
         end if;
         Append (Result, ":" & Source (T.First .. T.Last));
      end loop;
      if Positions then
         Append (Result, " | E@" & T.Line'Image (2 .. T.Line'Image'Last)
                 & "." & T.Column'Image (2 .. T.Column'Image'Last));
      end if;
      return To_String (Result);
   end Render;

   procedure Check
     (Name : String; Source : String; Expected : String;
      Positions : Boolean := False)
   is
      S   : constant String (1 .. Source'Length) := Source;
      Got : constant String := Render (S, Positions);
   begin
      Cases := Cases + 1;
      if Got /= Expected then
         Failures := Failures + 1;
         Put_Line ("FAIL " & Name);
         Put_Line ("  expected: " & Expected);
         Put_Line ("  got:      " & Got);
      end if;
   end Check;

   procedure Unit_Cases is
   begin
      Check ("empty", "", "");
      Check ("separators only", " " & ASCII.HT & LF & ASCII.FF, "");
      Check ("identifiers and reserved words in any case",
             "Procedure PROC is BEGIN null; End",
             "W:Procedure | I:PROC | W:is | W:BEGIN | W:null | D:; | W:End");
      Check ("Ada 2022 reserved words",
             "parallel some overriding synchronized interface",
             "W:parallel | W:some | W:overriding | W:synchronized"
             & " | W:interface");
      Check ("not reserved", "Abstract_State Ghost Pre Post Returns",
             "I:Abstract_State | I:Ghost | I:Pre | I:Post | I:Returns");
      Check ("malformed identifiers", "a__b c_ _d",
             "I!:a__b | I!:c_ | I!:_d");
      Check ("UTF-8 identifier", "Größe := 1;",
             "I:Größe | D::= | N:1 | D:;");

      Check ("comment", "X; -- note ""q"" 'c'",
             "I:X | D:; | R:-- note ""q"" 'c'");
      Check ("comment to the end of the line only",
             "-- a" & LF & "B -- c" & CR & LF & "D",
             "R:-- a | I:B | R:-- c | I:D");
      Check ("minus is not a comment", "A - B -1",
             "I:A | D:- | I:B | D:- | N:1");

      Check ("string with doubled quotes",
             """a """"b"""" c"" & """"",
             "S:""a """"b"""" c"" | D:& | S:""""");
      Check ("string holding --", "F (""--config""));",
             "I:F | D:( | S:""--config"" | D:) | D:) | D:;");
      Check ("unterminated string ends at the line end",
             "S := ""abc" & LF & "X;",
             "I:S | D::= | S!:""abc | I:X | D:;");
      Check ("string ending in a doubled quote, unterminated",
             """ab""""", "S!:""ab""""");

      Check ("character literals", "C := 'a'; D := ' '; E := ''';",
             "I:C | D::= | C:'a' | D:; | I:D | D::= | C:' ' | D:; | I:E"
             & " | D::= | C:''' | D:;");
      Check ("character literals of delimiters", "('(', ')', ';', '""')",
             "D:( | C:'(' | D:, | C:')' | D:, | C:';' | D:, | C:'""' | D:)");
      Check ("UTF-8 character literal", "C := 'é';",
             "I:C | D::= | C:'é' | D:;");
      Check ("tick after an identifier", "S'First S'Image (X)",
             "I:S | D:' | I:First | I:S | D:' | I:Image | D:( | I:X | D:)");
      Check ("tick after a closing parenthesis", "F (X)'Old A (1)'('x')",
             "I:F | D:( | I:X | D:) | D:' | I:Old | I:A | D:( | N:1 | D:)"
             & " | D:' | D:( | C:'x' | D:)");
      Check ("qualified character", "Character'('(')",
             "I:Character | D:' | D:( | C:'(' | D:)");
      Check ("tick after all", "P.all'Size",
             "I:P | D:. | W:all | D:' | I:Size");
      Check ("reserved words as attributes", "X'Access T'Range F'Digits",
             "I:X | D:' | I:Access | I:T | D:' | I:Range | I:F | D:'"
             & " | I:Digits");
      Check ("tick after a comment between", "X -- c" & LF & "'First",
             "I:X | R:-- c | D:' | I:First");
      Check ("tick after a closing bracket", "[1, 2]'Length",
             "D:[ | N:1 | D:, | N:2 | D:] | D:' | I:Length");
      Check ("lone apostrophe at the end", "X := '",
             "I:X | D::= | D:'");
      Check ("apostrophe before a line end", "X := '" & LF & "a'",
             "I:X | D::= | D:' | I:a | D:'");

      Check ("decimal literals", "1 1_000 3.14 1.0E-3 2E6 6.0e+2",
             "N:1 | N:1_000 | N:3.14 | N:1.0E-3 | N:2E6 | N:6.0e+2");
      Check ("based literals", "16#FF# 2#1010_1010# 16#F.8#E1 16#ff#",
             "N:16#FF# | N:2#1010_1010# | N:16#F.8#E1 | N:16#ff#");
      Check ("unclosed based literal", "16#FF;", "N!:16#FF | D:;");
      Check ("a range is not a fraction", "1..10 A (1 .. N)",
             "N:1 | D:.. | N:10 | I:A | D:( | N:1 | D:.. | I:N | D:)");
      Check ("no exponent without digits", "1E X 2e+",
             "N:1 | I:E | I:X | N:2 | I:e | D:+");

      Check ("compound delimiters", "=> .. ** := /= >= <= << >> <>",
             "D:=> | D:.. | D:** | D::= | D:/= | D:>= | D:<= | D:<< | D:>>"
             & " | D:<>");
      Check ("compound delimiters without spaces", "W:=1<=2>=3/=4<>5;",
             "I:W | D::= | N:1 | D:<= | N:2 | D:>= | N:3 | D:/= | N:4"
             & " | D:<> | N:5 | D:;");
      Check ("Ada 2022 delimiters", "[for I in 1 .. 3 => @ + I]",
             "D:[ | W:for | I:I | W:in | N:1 | D:.. | N:3 | D:=> | D:@"
             & " | D:+ | I:I | D:]");
      Check ("exclamation mark is a bar", "when A ! B",
             "W:when | I:A | D:! | I:B");
      Check ("invalid bytes", "A $ # ? \ B" & ASCII.NUL,
             "I:A | X:$ | X:# | X:? | X:\ | I:B | X:" & ASCII.NUL);

      Check ("lines and columns",
             "A" & LF & "  B" & CR & LF & "C" & CR & "   D" & LF,
             "I@1.1:A | I@2.3:B | I@3.1:C | I@4.4:D | E@5.1", True);
      Check ("columns after a tab",
             ASCII.HT & "X", "I@1.2:X | E@1.3", True);
      Check ("end of input with no final line end", "A" & LF & "B",
             "I@1.1:A | I@2.1:B | E@2.2", True);
   end Unit_Cases;

   --  The corpus check of one file.
   procedure Check_File (Path : String) is
      Source    : constant String := Ada_Outline.Files.Read (Path);
      C         : Cursor := Start (Source);
      T         : Token;
      Expect    : Positive := 1;     --  the first byte not yet covered
      Bad       : Boolean := False;
      Lines     : Natural;
   begin
      loop
         Next (Source, C, T);
         for I in Expect .. T.First - 1 loop
            if Source (I) not in ' ' | ASCII.HT | ASCII.VT | ASCII.FF
                                 | ASCII.LF | ASCII.CR
            then
               Put_Line (Path & ":" & T.Line'Image & ": byte" & I'Image
                         & " is neither in a token nor a separator");
               Bad := True;
            end if;
         end loop;
         exit when T.Kind = End_Of_Input;
         if T.Kind = Invalid then
            Put_Line (Path & ":" & T.Line'Image & ": invalid token "
                      & Source (T.First .. T.Last));
            Bad := True;
         elsif T.Malformed then
            Put_Line (Path & ":" & T.Line'Image & ": malformed "
                      & T.Kind'Image & " " & Source (T.First .. T.Last));
         end if;
         Expect := T.Last + 1;
      end loop;
      if Bad then
         Failures := Failures + 1;
      end if;
      --  readlines: one line per terminator, and the last line when it has
      --  none
      Lines := T.Line - 1;
      if Source'Length > 0
        and then Source (Source'Last) not in ASCII.LF | ASCII.CR
      then
         Lines := Lines + 1;
      end if;
      Put_Line (Lines'Image & " " & Path);
      Cases := Cases + 1;
   end Check_File;

   procedure Walk (Dir : String) is
      use Ada.Directories;
      S : Search_Type;
      E : Directory_Entry_Type;
   begin
      Start_Search (S, Dir, "", [Directory | Ordinary_File => True,
                                 others => False]);
      while More_Entries (S) loop
         Get_Next_Entry (S, E);
         declare
            Name : constant String := Simple_Name (E);
            Full : constant String := Full_Name (E);
         begin
            if Kind (E) = Directory then
               if Name /= "." and then Name /= ".." then
                  Walk (Full);
               end if;
            elsif Name'Length > 4
              and then Name (Name'Last - 3 .. Name'Last) in ".ads" | ".adb"
            then
               Check_File (Full);
            end if;
         end;
      end loop;
      End_Search (S);
   end Walk;

   package CL renames Ada.Command_Line;
begin
   if CL.Argument_Count >= 2 and then CL.Argument (1) = "--corpus" then
      for I in 2 .. CL.Argument_Count loop
         Walk (CL.Argument (I));
      end loop;
      Put_Line (Standard_Error, "files:" & Cases'Image & ", failed:"
                & Failures'Image);
   else
      Unit_Cases;
      Put_Line ("cases:" & Cases'Image & ", failed:" & Failures'Image);
   end if;
   if Failures > 0 then
      CL.Set_Exit_Status (CL.Failure);
   end if;
end Test_Lexer;
