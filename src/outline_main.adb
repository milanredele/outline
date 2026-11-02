--  SPDX-License-Identifier: Apache-2.0
--
--  The command line of outline. For now only the lexer is in place:
--
--    outline --tokens FILE   every token of FILE: line:column, kind, text

with Ada.Command_Line;
with Ada.Text_IO;
with Outline.Files;
with Outline.Lexer;

procedure Outline_Main is
   use Ada.Text_IO;
   use Outline.Lexer;

   procedure Dump_Tokens (Path : String) is
      Source : constant String := Outline.Files.Read (Path);
      C      : Cursor := Start (Source);
      T      : Token;
   begin
      loop
         Next (Source, C, T);
         exit when T.Kind = End_Of_Input;
         Put_Line (T.Line'Image & ":" & T.Column'Image & " "
                   & T.Kind'Image
                   & (if T.Kind = Delimiter then " " & T.Delim'Image else "")
                   & (if T.Malformed then " MALFORMED" else "")
                   & "  " & Source (T.First .. T.Last));
      end loop;
   end Dump_Tokens;

   package CL renames Ada.Command_Line;
begin
   if CL.Argument_Count = 2 and then CL.Argument (1) = "--tokens" then
      Dump_Tokens (CL.Argument (2));
   else
      Put_Line (Standard_Error, "usage: outline --tokens FILE");
      CL.Set_Exit_Status (CL.Failure);
   end if;
end Outline_Main;
