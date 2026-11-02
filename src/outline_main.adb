--  SPDX-License-Identifier: Apache-2.0
--
--  The command line of outline (see Help below and README.md).

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Outline.Commands;
with Outline.Config;
with Outline.Text;

procedure Outline_Main is
   use Ada.Strings.Unbounded;
   use Outline.Text;
   package CL renames Ada.Command_Line;
   package Cmd renames Outline.Commands;

   Version : constant String := "0.1.0-dev";

   Help : constant WWS_List :=
     [+"outline: read Ada units piecewise, instead of whole.",
      +"",
      +"Ada units (a unit is given by file name or Ada name: fc_session, Fc_Core.Links,",
      +"fc_core-links, core/src/fc_store.ads; the search roots are listed below):",
      +"",
      +"  outline fc_session                  every subprogram of spec and body: lines,",
      +"                                      profile, the first line of each aspect",
      +"  outline fc_session --spec           the digest of the spec: every declaration",
      +"                                      in full (contract and heading comment), no bodies;",
      +"                                      what a caller or an integrator needs",
      +"  outline fc_session --spec Receive   one declaration with its contract and heading",
      +"                                      (a private subprogram: the profile of its body)",
      +"  outline fc_session Receive          that subprogram in full: declaration and body",
      +"  outline fc_session --body Receive   the body only",
      +"  outline fc_store --decl             every other declaration (types, subtypes,",
      +"                                      constants, objects, with/use clauses)",
      +"  outline fc_store --decl Slot_Record that declaration in full (a record to its end)",
      +"  outline --refs Within_Bounds        every use outside its declaration, as file:line",
      +"  outline --refs Valid --in core/src  limit the search to a directory",
      +"  outline --units                     every unit under the roots, with its line counts",
      +"",
      +"Markdown (a file is given by its path, or by its number in the spec directory: 03):",
      +"",
      +"  outline --md 03                     the headings of spec/03-*.md with their lines",
      +"  outline --md 03 7.5                 that section (to the next heading of the same or a",
      +"                                      higher level), with line numbers",
      +"  outline --md 03 --grep stamp        the lines matching, with their section",
      +"  outline --md PLAN.md 3a             any markdown file: the section whose heading",
      +"                                      starts with the given number or words",
      +"",
      +"Every listing shows first and last line, so that a following `sed -n A,Bp` is exact.",
      +"",
      +"Where: the root is $OUTLINE_ROOT, else the nearest directory upwards holding .outline",
      +"or .git; the search roots are $OUTLINE_ROOTS (colon-separated), else the lines of",
      +"<root>/.outline (`spec: <dir>` names the markdown directory, default spec), else the",
      +"Source_Dirs of <root>/*.gpr, else the root.",
      +"",
      +"  outline --where                     the root and the search roots in use",
      +"  outline --version"];

   function Arg (I : Positive) return String renames CL.Argument;
   Argc : constant Natural := CL.Argument_Count;

   function Has_Arg (Text : String) return Natural is
   begin
      for I in 1 .. Argc loop
         if Arg (I) = Text then
            return I;
         end if;
      end loop;
      return 0;
   end Has_Arg;

   function Args_From (First : Positive) return String is
      R : Unbounded_String;
   begin
      for I in First .. Argc loop
         if I > First then
            Append (R, " ");
         end if;
         Append (R, Arg (I));
      end loop;
      return To_String (R);
   end Args_From;

   --  repr of argv[First:], a Python list of strings
   function Args_Repr (First : Positive) return WWS is
      R : UStr := +"[";
   begin
      for I in First .. Argc loop
         if I > First then
            U.Append (R, ", ");
         end if;
         U.Append (R, Repr (Decode (Arg (I))));
      end loop;
      U.Append (R, "]");
      return +R;
   end Args_Repr;

   procedure Fail (Message : String) is
   begin
      Put_Error (Decode ("outline: " & Message));
      CL.Set_Exit_Status (CL.Failure);
   end Fail;

   procedure Run is
   begin
      if Argc = 0 or else Arg (1) in "-h" | "--help" then
         for Line of Help loop
            Put_Line (+Line);
         end loop;
         return;
      end if;
      if Arg (1) = "--version" then
         Put_Line (Decode ("outline " & Version));
         return;
      end if;

      Outline.Config.Initialize;

      if Arg (1) = "--where" then
         Put_Line (Decode ("root: " & Outline.Config.Root));
         Put_Line (Decode ("search roots: "
                           & Outline.Config.Joined (Outline.Config.Roots)));
         Put_Line (Decode ("spec directory: " & Outline.Config.Spec_Dir));
         return;
      end if;
      if Arg (1) = "--tokens" then
         if Argc < 2 then
            Fail ("--tokens needs a file");
         else
            Cmd.Tokens (Arg (2));
         end if;
         return;
      end if;
      if Arg (1) = "--units" then
         Cmd.List_Units;
         return;
      end if;

      if Arg (1) = "--refs" then
         declare
            In_At : constant Natural := Has_Arg ("--in");
            Roots : Outline.Config.Path_List := Outline.Config.Roots;
         begin
            if Argc < 2 then
               Fail ("--refs needs a name");
               return;
            end if;
            if In_At /= 0 then
               if In_At = Argc then
                  Fail ("--in needs a directory");
                  return;
               end if;
               Roots.Clear;
               Roots.Append (To_Unbounded_String (Arg (In_At + 1)));
            end if;
            Cmd.Refs (Arg (2), Roots);
         end;
         return;
      end if;

      if Arg (1) = "--md" then
         if Argc < 2 then
            Fail ("--md needs a specification number or a markdown path");
            return;
         end if;
         declare
            Path : constant String := Outline.Config.Md_File (Arg (2));
         begin
            if Path = "" then
               Fail ("no specification file " & Arg (2));
            elsif Argc = 2 then
               Cmd.Md_Toc (Path);
            elsif Arg (3) = "--grep" then
               Cmd.Md_Grep (Path, Args_From (4));
            elsif not Cmd.Md_Section (Path, Args_From (3)) then
               Fail ("no section " & Args_From (3) & " in " & Path);
            end if;
         end;
         return;
      end if;

      declare
         Files : constant Outline.Config.Path_List :=
           Outline.Config.Unit_Files (Arg (1));
         In_Files : constant String := Outline.Config.Joined (Files);
         Found : Boolean := False;
      begin
         if Files.Is_Empty then
            Fail ("no unit " & Arg (1) & " under "
                  & Outline.Config.Joined (Outline.Config.Roots));
            return;
         end if;

         if Argc >= 2 and then Arg (2) = "--decl" then
            if Argc = 2 then
               for F of Files loop
                  Cmd.List_Decls (To_String (F));
               end loop;
            else
               for F of Files loop
                  Found := Cmd.Show_Decl (To_String (F), Arg (3)) or Found;
               end loop;
               if not Found then
                  Fail ("no declaration " & Arg (3) & " in " & In_Files);
               end if;
            end if;

         elsif Argc >= 2 and then Arg (2) = "--spec" then
            if Argc = 2 then
               declare
                  Specs : Outline.Config.Path_List;
               begin
                  for F of Files loop
                     if Slice (F, Length (F) - 3, Length (F)) = ".ads" then
                        Specs.Append (F);
                     end if;
                  end loop;
                  if Specs.Is_Empty then
                     Specs := Files;
                  end if;
                  for F of Specs loop
                     Found := Cmd.Show_Spec (To_String (F), All_Decls => True)
                              or Found;
                  end loop;
               end;
            else
               for F of Files loop
                  Found := Cmd.Show_Spec (To_String (F), Arg (3));
                  exit when Found;
               end loop;
            end if;
            if not Found then
               Put_Error ("outline: no subprogram " & Args_Repr (3) & " in "
                          & Decode (In_Files));
               CL.Set_Exit_Status (CL.Failure);
            end if;

         elsif Argc >= 2 and then Arg (2) = "--body" then
            if Argc = 2 then
               Fail ("--body needs a subprogram name");
               return;
            end if;
            for F of Files loop
               if Slice (F, Length (F) - 3, Length (F)) = ".adb" then
                  Found := Cmd.Show (To_String (F), Arg (3), Bodies_Only => True)
                           or Found;
               end if;
            end loop;
            if not Found then
               Fail ("no body " & Arg (3) & " in " & In_Files);
            end if;

         elsif Argc >= 2 then
            for F of Files loop
               Found := Cmd.Show (To_String (F), Arg (2)) or Found;
            end loop;
            if not Found then
               Fail ("no subprogram " & Arg (2) & " in " & In_Files);
            end if;

         else
            for F of Files loop
               Cmd.Outline_Unit (To_String (F));
            end loop;
         end if;
      end;
   end Run;

begin
   Run;
end Outline_Main;
