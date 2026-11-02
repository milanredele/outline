--  SPDX-License-Identifier: Apache-2.0

with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Outline.Files;
with Outline.Lexer;
with Outline.Scan;
with Outline.Sources;
with Outline.Text;

package body Outline.Commands is

   use Outline.Text;
   use Outline.Sources;
   use Outline.Scan;

   function Load (Path : String) return Source_File is
     (Load (Outline.Config.Join (Outline.Config.Root, Path),
            Outline.Config.Compat (Outline.Config.Views)));

   function Spaces (N : Natural) return WWS is [1 .. N => ' '];

   function Name_Arg (Name : String) return WWS is
     (if Outline.Config.Compat (Outline.Config.Operators) then Decode (Name)
      else Strip_Chars (Decode (Name), """"));
   --  A name given on the command line; outside compatibility mode an
   --  operator symbol may come with its quotes ("+").

   function Is_Comment_Line (S : Source_File; K : Natural) return Boolean is
     (Starts_With (Strip (Raw (S, K)), "--"));

   procedure Print_Heading (S : Source_File; First : Natural) is
      K : Integer := First - 1;
   begin
      while K >= 0 and then Is_Comment_Line (S, K) loop
         K := K - 1;
      end loop;
      for J in K + 1 .. First - 1 loop
         Put_Line (Raw (S, J));
      end loop;
   end Print_Heading;

   procedure Print_Trailing (S : Source_File; Last : Natural) is
      K : Natural := Last + 1;
   begin
      while K < Count (S) and then Is_Comment_Line (S, K) loop
         Put_Line ("       " & Strip (Raw (S, K)));
         K := K + 1;
      end loop;
   end Print_Trailing;

   procedure Print_Range (S : Source_File; First, Last : Natural) is
   begin
      for K in First .. Last loop
         Put_Line (Img (K + 1, 5) & "  " & RStrip (Raw (S, K)));
      end loop;
   end Print_Range;

   function Lines_Image (S : Source_File) return WWS is
     (" (" & Img (Count (S)) & " lines)");

   function Span (First, Last : Natural) return WWS is
     (Img (First + 1, 5) & "-" & Pad (Img (Last + 1), 5));

   --  re.split (r'\s+(?:is\b|with\b|;)', P)[0]
   function Cut_Profile (P : WWS) return WWS is
   begin
      for I in P'Range loop
         if Is_Space (P (I)) then
            declare
               Q : constant Positive := Skip_Spaces (P, I);
            begin
               if (Has_At (P, Q, "is") and then Boundary (P, Q + 2))
                 or else (Has_At (P, Q, "with") and then Boundary (P, Q + 4))
                 or else (Q <= P'Last and then P (Q) = ';')
               then
                  return P (P'First .. I - 1);
               end if;
            end;
         end if;
      end loop;
      return P;
   end Cut_Profile;

   procedure Outline_Unit (Path : String) is
      S : constant Source_File := Load (Path);
   begin
      Put_Line ("== " & Decode (Path) & Lines_Image (S));
      for D of Declarations (S) loop
         declare
            Joined : UStr;
            Ind    : constant WWS := Spaces (D.Indent / 3);
            Tag    : constant WWS :=
              (if D.Is_Body then "body" elsif D.Expr then "expr" else "spec");
            Mark   : UStr;
         begin
            for K in D.First .. Natural'Min (D.Last + 1, D.First + 12) - 1 loop
               if K > D.First then
                  U.Append (Joined, " ");
               end if;
               U.Append (Joined, Strip (Raw (S, K)));
            end loop;
            Put_Line (Ind & Span (D.First, D.Last) & " " & Tag & " "
                      & Cut_Profile (Collapse (+Joined)));
            for K in D.First .. D.Last loop
               if Aspect_At (Raw (S, K), Mark)
                 and then (not D.Is_Body
                           or else (K < D.First + 40
                                    and then U.Index (Mark, "Refined") > 0))
               then
                  Put_Line (Ind & Spaces (12) & Head (Strip (Raw (S, K)), 100));
               end if;
            end loop;
         end;
      end loop;
   end Outline_Unit;

   procedure List_Decls (Path : String) is
      S : constant Source_File := Load (Path);
   begin
      Put_Line ("== " & Decode (Path) & Lines_Image (S));
      for O of Other_Declarations (S) loop
         if not (+O.Kind = "object" and then O.Indent > 3) then
            Put_Line (Spaces (O.Indent / 3) & Span (O.First, O.Last) & " "
                      & Pad (+O.Kind, 7) & " "
                      & Head (Collapse (Strip (Raw (S, O.First))), 90));
         end if;
      end loop;
   end List_Decls;

   function Names_Contain (Names : WWS; Name : WWS) return Boolean is
      First : Positive := Names'First;
   begin
      for I in Names'First .. Names'Last + 1 loop
         if I > Names'Last or else Names (I) = ',' then
            if Equal_CI (Strip (Names (First .. I - 1)), Name) then
               return True;
            end if;
            First := I + 1;
         end if;
      end loop;
      return False;
   end Names_Contain;

   function Show_Decl (Path, Name : String) return Boolean is
      S     : constant Source_File := Load (Path);
      Found : Boolean := False;
   begin
      for O of Other_Declarations (S) loop
         if Names_Contain (+O.Name, Decode (Name)) then
            Found := True;
            Put_Line ("== " & Decode (Path) & ":" & Img (O.First + 1) & "-"
                      & Img (O.Last + 1) & " (" & (+O.Kind) & ")");
            Print_Heading (S, O.First);
            Print_Range (S, O.First, O.Last);
            Print_Trailing (S, O.Last);
            Put_Line ("");
         end if;
      end loop;
      return Found;
   end Show_Decl;

   function Show (Path, Name : String; Bodies_Only : Boolean := False)
     return Boolean
   is
      S     : constant Source_File := Load (Path);
      Found : Boolean := False;
   begin
      for D of Declarations (S) loop
         if Equal_CI (+D.Name, Name_Arg (Name))
           and then (D.Is_Body or else not Bodies_Only)
         then
            Found := True;
            Put_Line ("== " & Decode (Path) & ":" & Img (D.First + 1) & "-"
                      & Img (D.Last + 1) & " ("
                      & (if D.Is_Body then "body" else "spec") & ")");
            Print_Heading (S, D.First);
            Print_Range (S, D.First, D.Last);
            if not D.Is_Body then
               Print_Trailing (S, D.Last);
            end if;
            Put_Line ("");
         end if;
      end loop;
      return Found;
   end Show;

   --  The declaration of a body without the body: up to the line that
   --  ends in `is` (after the aspects, if any) or in `;`.
   procedure Print_Profile (S : Source_File; First, Last : Natural) is
      Lines : UStr;   --  the lines so far, joined without separator
   begin
      for K in First .. Last loop
         declare
            Line : constant WWS := Raw (S, K);
            T    : constant WWS := RStrip (No_Comment (S, K));
            Ends_Is : constant Boolean :=
              Ends_With (T, "is") and then Boundary (T, T'Last - 1);
            Ends_Semicolon : constant Boolean := Ends_With (T, ";");
         begin
            Put_Line (Img (K + 1, 5) & "  " & Line);
            U.Append (Lines, Line);
            exit when (Ends_Is or else Ends_Semicolon)
              and then (Find_Word (+Lines, "with", 1) = 0
                        or else Ends_Semicolon);
         end;
      end loop;
   end Print_Profile;

   function Show_Spec (Path : String; Name : String := "";
                       All_Decls : Boolean := False) return Boolean
   is
      S     : constant Source_File := Load (Path);
      Found : Boolean := False;
   begin
      for D of Declarations (S) loop
         if (if All_Decls then not D.Is_Body and then D.Indent <= 3
             else Equal_CI (+D.Name, Name_Arg (Name)))
         then
            Found := True;
            Put_Line ("== " & Decode (Path) & ":" & Img (D.First + 1) & "-"
                      & Img (D.Last + 1) & " ("
                      & (if D.Is_Body then "body, profile only"
                         elsif D.Expr then "expression function"
                         else "spec") & ")");
            Print_Heading (S, D.First);
            if D.Is_Body then
               Print_Profile (S, D.First, D.Last);
            else
               Print_Range (S, D.First, D.Last);
               Print_Trailing (S, D.Last);
            end if;
            Put_Line ("");
         end if;
      end loop;
      return Found;
   end Show_Spec;

   --  ^\s*(overriding\s+)?(procedure|function|package|type|subtype)\s+\bName\b
   --  or ^\s*end\s+\bName\b, in any case
   function Is_Declaration_Or_End (Line, Name : WWS) return Boolean is
      L : constant WWS (1 .. Line'Length) := Line;
      P : constant Positive := Skip_Spaces (L, 1);

      function Keyword (At_Pos : Positive; Word : WWS) return Natural is
        (if Has_At (L, At_Pos, Word, Case_Insensitive => True)
            and then At_Pos + Word'Length <= L'Last
            and then Is_Space (L (At_Pos + Word'Length))
         then Skip_Spaces (L, At_Pos + Word'Length) else 0);

      function Name_At (Q : Natural) return Boolean is
        (Q /= 0 and then Boundary (L, Q)
         and then Has_At (L, Q, Name, Case_Insensitive => True)
         and then Boundary (L, Q + Name'Length));

      Q : Positive := P;
   begin
      if Name_At (Keyword (P, "end")) then
         return True;
      end if;
      if Keyword (P, "overriding") /= 0 then
         Q := Keyword (P, "overriding");
      end if;
      for Word of WWS_List'([+"procedure", +"function", +"package", +"type",
                             +"subtype"])
      loop
         if Name_At (Keyword (Q, +Word)) then
            return True;
         end if;
      end loop;
      return False;
   end Is_Declaration_Or_End;

   --  \bName\b as GNU grep -E finds it in the C locale
   function Grep_Match (Line, Name : WWS) return Boolean is
   begin
      for P in Line'First .. Line'Last - Name'Length + 1 loop
         if Line (P .. P + Name'Length - 1) = Name
           and then Boundary (Line, P, ASCII_Words => True)
           and then Boundary (Line, P + Name'Length, ASCII_Words => True)
         then
            return True;
         end if;
      end loop;
      return False;
   end Grep_Match;

   procedure Refs (Name : String; Roots : Outline.Config.Path_List) is
      use Ada.Strings.Unbounded;
      N_Name : constant WWS := Decode (Name);
      Prefix : constant String :=
        Outline.Config.Join (Outline.Config.Root, "");
      Uses   : Natural := 0;

      procedure Visit (Full : String) is
         Rel  : constant String :=
           (if Full'Length > Prefix'Length
              and then Full (Full'First .. Full'First + Prefix'Length - 1)
                       = Prefix
            then Full (Full'First + Prefix'Length .. Full'Last)
            else Full);
         Base : constant String := Ada.Directories.Simple_Name (Full);
      begin
         if Base'Length <= 4
           or else Base (Base'Last - 3 .. Base'Last) not in ".ads" | ".adb"
         then
            return;
         end if;
         declare
            Bytes : constant String := Outline.Files.Read (Full);
            First : Positive := 1;
            Line  : Positive := 1;
         begin
            --  most files do not hold the name at all
            if Ada.Strings.Fixed.Index (Bytes, Name) = 0 then
               return;
            end if;
            --  grep's lines: split at LF only
            for I in 1 .. Bytes'Length + 1 loop
               if I > Bytes'Length or else Bytes (I) = ASCII.LF then
                  if I > Bytes'Length and then First > Bytes'Length then
                     exit;
                  end if;
                  declare
                     Raw_Line : constant String := Bytes (First .. I - 1);
                  begin
                     if Ada.Strings.Fixed.Index (Raw_Line, Name) /= 0 then
                        declare
                           L : constant WWS := Decode (Raw_Line);
                        begin
                           if Grep_Match (L, N_Name)
                             and then not Is_Declaration_Or_End (L, N_Name)
                             and then not Starts_With (Strip (L), "--")
                           then
                              Uses := Uses + 1;
                              Put_Line (Decode (Rel) & ":" & Img (Line) & ": "
                                        & Head (Strip (L), 110));
                           end if;
                        end;
                     end if;
                  end;
                  First := I + 1;
                  Line := Line + 1;
               end if;
            end loop;
         end;
      exception
         when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
            null;
      end Visit;

      procedure Files_Of is new Outline.Config.Walk (Visit);
   begin
      for R of Roots loop
         declare
            Dir : constant String :=
              Outline.Config.Join (Outline.Config.Root, To_String (R));
         begin
            if Outline.Config.Is_File (Dir) then
               Visit (Dir);
            else
               Files_Of (Dir, Hidden => True);
            end if;
         end;
      end loop;
      Put_Line ("-- " & Img (Uses) & " uses of " & N_Name
                & " (declarations, end lines and comments left out)");
   end Refs;

   procedure List_Units is
      use Ada.Strings.Unbounded;
   begin
      for P of Outline.Config.All_Units loop
         declare
            S : constant Source_File := Load (To_String (P));
         begin
            Put_Line (Img (Count (S), 6) & " lines "
                      & Img (Natural (Declarations (S).Length),
                             4)
                      & " subprograms  " & Decode (To_String (P)));
         end;
      end loop;
   end List_Units;

   type Heading is record
      Level : Positive;
      Title : UStr;
      First : Natural;
      Last  : Natural;
   end record;

   package Heading_Vectors is new Ada.Containers.Vectors (Positive, Heading);

   --  The headings of a markdown file; a section ends before the next
   --  heading of the same or a higher level; fenced code is skipped.
   function Headings (S : Source_File) return Heading_Vectors.Vector is
      Result : Heading_Vectors.Vector;
      Fence  : Boolean := False;
   begin
      for I in 0 .. Count (S) - 1 loop
         declare
            L      : constant WWS := Raw (S, I);
            Hashes : Natural := 0;
         begin
            if Starts_With (L, "```") then
               Fence := not Fence;
            elsif not Fence then
               while Hashes < L'Length and then L (L'First + Hashes) = '#' loop
                  Hashes := Hashes + 1;
               end loop;
               --  ^(#{1,6})\s+(.*)$, the line with its '\n'
               if Hashes in 1 .. 6
                 and then (if Hashes < L'Length
                           then Is_Space (L (L'First + Hashes))
                           else I < Count (S) - 1 or else S.Last_Ended)
               then
                  Result.Append
                    (Heading'(Level => Hashes,
                      Title => +Strip (L (L'First + Hashes .. L'Last)),
                      First => I,
                      Last  => Count (S) - 1));
               end if;
            end if;
         end;
      end loop;
      for A in 1 .. Result.Last_Index loop
         for B in A + 1 .. Result.Last_Index loop
            if Result (B).Level <= Result (A).Level then
               Result (A).Last := Result (B).First - 1;
               exit;
            end if;
         end loop;
      end loop;
      return Result;
   end Headings;

   procedure Md_Toc (Path : String) is
      S : constant Source_File := Load (Path);
   begin
      Put_Line ("== " & Decode (Path) & Lines_Image (S));
      for H of Headings (S) loop
         Put_Line (Spaces (2 * (H.Level - 1)) & Span (H.First, H.Last) & " "
                   & Head (+H.Title, 90));
      end loop;
   end Md_Toc;

   function Md_Section (Path, Key : String) return Boolean is
      S     : constant Source_File := Load (Path);
      K     : constant WWS := Lower (Decode (Key));
      Found : Boolean := False;
   begin
      for H of Headings (S) loop
         declare
            T      : constant WWS := Strip (LStrip_Chars (Lower (+H.Title), "*"));
            Number : constant WWS :=
              (if T = "" then ""
               else Strip_Chars (RStrip_Chars (First_Word (T), "."), "*"));
         begin
            if Number = K or else Starts_With (T, K & " ") or else T = K then
               Found := True;
               Put_Line ("== " & Decode (Path) & ":" & Img (H.First + 1) & "-"
                         & Img (H.Last + 1));
               Print_Range (S, H.First, H.Last);
               Put_Line ("");
            end if;
         end;
      end loop;
      return Found;
   end Md_Section;

   procedure Md_Grep (Path, Word : String) is
      S     : constant Source_File := Load (Path);
      Heads : constant Heading_Vectors.Vector := Headings (S);
      W     : constant WWS := Decode (Word);
      N     : Natural := 0;
   begin
      for I in 0 .. Count (S) - 1 loop
         declare
            L   : constant WWS := Raw (S, I);
            Sec : UStr;
         begin
            if Index_CI (L, W) /= 0 then
               for H of Heads loop
                  if H.First <= I and then I <= H.Last then
                     Sec := +Head (+H.Title, 40);
                  end if;
               end loop;
               N := N + 1;
               Put_Line (Decode (Path) & ":" & Img (I + 1) & " [" & (+Sec)
                         & "] " & Head (Strip (L), 120));
            end if;
         end;
      end loop;
      Put_Line ("-- " & Img (N) & " lines match " & Repr (W));
   end Md_Grep;

   procedure Tokens (Path : String) is
      use Outline.Lexer;
      Source : constant String := Outline.Files.Read (Path);
      C      : Cursor := Start (Source);
      T      : Token;
   begin
      loop
         Next (Source, C, T);
         exit when T.Kind = End_Of_Input;
         Put_Line (Img (T.Line) & ":" & Img (T.Column) & " "
                   & Decode (T.Kind'Image)
                   & (if T.Kind = Delimiter then " " & Decode (T.Delim'Image)
                      else "")
                   & (if T.Malformed then " MALFORMED" else "")
                   & "  " & Decode (Source (T.First .. T.Last)));
      end loop;
   end Tokens;

end Outline.Commands;
