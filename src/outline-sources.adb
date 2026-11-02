--  SPDX-License-Identifier: Apache-2.0

with Ada.Strings.Unbounded;
with Outline.Files;
with Outline.Lexer;

package body Outline.Sources is

   --  outline.py's views: re.sub (r'--.*', '', Line), then
   --  re.sub (r'"[^"]*"', '""', ...)
   function Py_No_Comment (Line : WWS) return WWS is
   begin
      for I in Line'First .. Line'Last - 1 loop
         if Line (I) = '-' and then Line (I + 1) = '-' then
            return Line (Line'First .. I - 1);
         end if;
      end loop;
      return Line;
   end Py_No_Comment;

   function Py_Code (Line : WWS) return WWS is
      S      : constant WWS := Py_No_Comment (Line);
      Result : UStr;
      I      : Integer := S'First;
   begin
      while I <= S'Last loop
         if S (I) = '"' then
            declare
               J : Integer := I + 1;
            begin
               while J <= S'Last and then S (J) /= '"' loop
                  J := J + 1;
               end loop;
               if J <= S'Last then
                  U.Append (Result, """""");
                  I := J + 1;
               else
                  U.Append (Result, S (I .. S'Last));
                  I := S'Last + 1;
               end if;
            end;
         else
            U.Append (Result, S (I));
            I := I + 1;
         end if;
      end loop;
      return +Result;
   end Py_Code;

   function Load (Path : String; Compat : Boolean) return Source_File is
      use Ada.Strings.Unbounded;
      use Outline.Lexer;
      Result : Source_File;
   begin
      declare
         Bytes : constant String := Outline.Files.Read (Path);

         type Literal is record
            First, Last : Positive;
            Kind        : Token_Kind;
         end record;
         package Literal_Vectors is new Ada.Containers.Vectors
           (Positive, Literal);
         package Natural_Vectors is new Ada.Containers.Vectors
           (Positive, Natural);
         Literals   : Literal_Vectors.Vector;
         N_Lit      : Natural := 0;
         Comment_At : Natural_Vectors.Vector;
         --  per line from 1, the byte where its comment starts (0: none)

         function Comment_Of (Line : Positive) return Natural is
           (if Line <= Comment_At.Last_Index then Comment_At (Line) else 0);

         Line_First : Positive := 1;
         Line_No    : Positive := 1;
         Next_Lit   : Positive := 1;

         procedure Add_Line (First, Last : Integer) is
            Raw_Bytes : constant String := Bytes (First .. Last);
            Cut       : constant Natural := Comment_Of (Line_No);
            End_Code  : constant Integer :=
              (if Cut /= 0 then Cut - 1 else Last);
            Code_B    : Unbounded_String;
            P         : Integer := First;
         begin
            Result.Raw.Append (+Decode (Raw_Bytes));
            if Compat then
               declare
                  W : constant WWS := Decode (Raw_Bytes);
               begin
                  Result.No_Comment.Append (+Py_No_Comment (W));
                  Result.Code.Append (+Py_Code (W));
               end;
            else
               Result.No_Comment.Append (+Decode (Bytes (First .. End_Code)));
               while Next_Lit <= N_Lit
                 and then Literals (Next_Lit).First <= End_Code
               loop
                  declare
                     L : constant Literal := Literals (Next_Lit);
                  begin
                     if L.First >= First then
                        Append (Code_B, Bytes (P .. L.First - 1));
                        Append (Code_B, (if L.Kind = String_Literal
                                         then """""" else "' '"));
                        P := L.Last + 1;
                     end if;
                  end;
                  Next_Lit := Next_Lit + 1;
               end loop;
               if P <= End_Code then
                  Append (Code_B, Bytes (P .. End_Code));
               end if;
               Result.Code.Append (+Decode (To_String (Code_B)));
            end if;
            Line_No := Line_No + 1;
         end Add_Line;

         C : Cursor := Start (Bytes);
         T : Token;
         I : Positive := 1;
      begin
         if not Compat then
            loop
               Next (Bytes, C, T);
               exit when T.Kind = End_Of_Input;
               case T.Kind is
                  when Comment =>
                     while Comment_At.Last_Index < T.Line loop
                        Comment_At.Append (0);
                     end loop;
                     Comment_At (T.Line) := T.First;
                  when String_Literal | Character_Literal =>
                     N_Lit := N_Lit + 1;
                     Literals.Append (Literal'(T.First, T.Last, T.Kind));
                  when others =>
                     null;
               end case;
            end loop;
         end if;

         while I <= Bytes'Last loop
            if Bytes (I) = ASCII.LF then
               Add_Line (Line_First, I - 1);
               I := I + 1;
               Line_First := I;
            elsif Bytes (I) = ASCII.CR then
               Add_Line (Line_First, I - 1);
               if I < Bytes'Last and then Bytes (I + 1) = ASCII.LF then
                  I := I + 2;
               else
                  I := I + 1;
               end if;
               Line_First := I;
            else
               I := I + 1;
            end if;
         end loop;
         if Line_First <= Bytes'Last then
            Add_Line (Line_First, Bytes'Last);
            Result.Last_Ended := False;
         end if;
      end;
      return Result;
   exception
      when others =>
         return (others => <>);
   end Load;

end Outline.Sources;
