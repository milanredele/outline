--  SPDX-License-Identifier: Apache-2.0
--
--  The command line of ada_outline. For now only the lexer is in place:
--
--    ada_outline --tokens FILE   every token of FILE: line:column, kind, text

with Ada.Command_Line;
with Ada.Text_IO;
with Ada_Outline.Files;
with Ada_Outline.Lexer;

procedure Ada_Outline_Main is
   use Ada.Text_IO;
   use Ada_Outline.Lexer;

   procedure Dump_Tokens (Path : String) is
      Source : constant String := Ada_Outline.Files.Read (Path);
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
      Put_Line (Standard_Error, "usage: ada_outline --tokens FILE");
      CL.Set_Exit_Status (CL.Failure);
   end if;
end Ada_Outline_Main;
