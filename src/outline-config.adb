--  SPDX-License-Identifier: Apache-2.0

with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Outline.Files;
with Outline.Lexer;
with Outline.Text;

package body Outline.Config is

   package Dirs renames Ada.Directories;
   package Env renames Ada.Environment_Variables;
   use type Dirs.File_Kind;

   package Sorting is new Path_Vectors.Generic_Sorting;

   The_Root    : Unbounded_String;
   The_Roots   : Path_List;
   The_Spec    : Unbounded_String := To_Unbounded_String ("spec");
   Compat_Set  : array (Fix) of Boolean := [others => False];
   Skip_Builds : Boolean := False;   --  the fallback: the root itself

   Build_Dirs : constant array (1 .. 4) of Unbounded_String :=
     [To_Unbounded_String ("obj"), To_Unbounded_String ("bin"),
      To_Unbounded_String ("lib"), To_Unbounded_String ("alire")];

   function Compat (F : Fix) return Boolean is (Compat_Set (F));
   function Root return String is (To_String (The_Root));
   function Roots return Path_List is (The_Roots);
   function Spec_Dir return String is (To_String (The_Spec));

   function Get (Name : String) return String is
     (if Env.Exists (Name) then Env.Value (Name) else "");

   function Join (Dir, Path : String) return String is
     (if Path'Length > 0 and then Path (Path'First) = '/' then Path
      elsif Dir'Length > 0 and then Dir (Dir'Last) = '/' then Dir & Path
      else Dir & "/" & Path);

   function Is_File (Path : String) return Boolean is
     (Path'Length > 0 and then Dirs.Exists (Path)
      and then Dirs.Kind (Path) = Dirs.Ordinary_File);

   function Is_Dir (Path : String) return Boolean is
     (Path'Length > 0 and then Dirs.Exists (Path)
      and then Dirs.Kind (Path) = Dirs.Directory);

   function Split (S : String; Sep : Character) return Path_List is
      Result : Path_List;
      First  : Positive := S'First;
   begin
      for I in S'Range loop
         if S (I) = Sep then
            Result.Append (To_Unbounded_String (S (First .. I - 1)));
            First := I + 1;
         end if;
      end loop;
      Result.Append (To_Unbounded_String (S (First .. S'Last)));
      return Result;
   end Split;

   --  os.path.abspath: absolute, with ".", ".." and doubled slashes
   --  resolved by name.
   function Abs_Path (Path : String) return String is
      Full  : constant String :=
        (if Path'Length > 0 and then Path (Path'First) = '/' then Path
         else Join (Dirs.Current_Directory, Path));
      Parts : constant Path_List := Split (Full, '/');
      Kept  : Path_List;
      R     : Unbounded_String;
   begin
      for P of Parts loop
         if P = "" or else P = "." then
            null;
         elsif P = ".." then
            if not Kept.Is_Empty then
               Kept.Delete_Last;
            end if;
         else
            Kept.Append (P);
         end if;
      end loop;
      for P of Kept loop
         Append (R, "/" & P);
      end loop;
      return (if R = "" then "/" else To_String (R));
   end Abs_Path;

   function Rel_Path (Path : String; Start : String) return String is
      A      : constant Path_List := Split (Abs_Path (Path), '/');
      B      : constant Path_List := Split (Abs_Path (Start), '/');
      Common : Natural := 0;
      R      : Unbounded_String;

      procedure Add (Part : String) is
      begin
         if R /= "" then
            Append (R, "/");
         end if;
         Append (R, Part);
      end Add;
   begin
      --  both start with an empty element (the leading slash); "/" alone
      --  splits into two empty ones
      while Common < Natural (A.Length) and then Common < Natural (B.Length)
        and then A (Common + 1) = B (Common + 1)
      loop
         Common := Common + 1;
      end loop;
      for I in Common + 1 .. Natural (B.Length) loop
         if B (I) /= "" then
            Add ("..");
         end if;
      end loop;
      for I in Common + 1 .. Natural (A.Length) loop
         if A (I) /= "" then
            Add (To_String (A (I)));
         end if;
      end loop;
      return (if R = "" then "." else To_String (R));
   end Rel_Path;

   procedure Walk (Dir : String; Hidden : Boolean) is

      procedure Walk_Dir (Dir : String; Top : Boolean) is
         Names : Path_List;
         S     : Dirs.Search_Type;
         E     : Dirs.Directory_Entry_Type;
      begin
         if not Is_Dir (Dir) then
            return;
         end if;
         Dirs.Start_Search
           (S, Dir, "", [Dirs.Directory | Dirs.Ordinary_File => True,
                         others => False]);
         while Dirs.More_Entries (S) loop
            Dirs.Get_Next_Entry (S, E);
            declare
               Name   : constant String := Dirs.Simple_Name (E);
               Is_Sub : constant Boolean := Dirs.Kind (E) = Dirs.Directory;
            begin
               if Name /= "." and then Name /= ".."
                 and then (Hidden or else Name (Name'First) /= '.')
                 and then not (Skip_Builds and then Top and then Is_Sub
                               and then (for some B of Build_Dirs => B = Name))
               then
                  --  sorted by name; the kind rides after a NUL
                  Names.Append (To_Unbounded_String
                    (Name & ASCII.NUL & (if Is_Sub then "d" else "f")));
               end if;
            end;
         end loop;
         Dirs.End_Search (S);
         Sorting.Sort (Names);
         for N of Names loop
            declare
               Item : constant String := To_String (N);
               Name : constant String := Item (Item'First .. Item'Last - 2);
               Full : constant String := Join (Dir, Name);
            begin
               if Item (Item'Last) = 'd' then
                  Walk_Dir (Full, Top => False);
               else
                  Visit (Full);
               end if;
            end;
         end loop;
      end Walk_Dir;

   begin
      Walk_Dir (Dir, Top => True);
   end Walk;

   function Is_Ada_File (Path : String) return Boolean is
     (Path'Length > 4
      and then Path (Path'Last - 3 .. Path'Last) in ".ads" | ".adb");

   function All_Units return Path_List is
      Result : Path_List;

      procedure Visit (Path : String) is
         Base : constant String := Dirs.Simple_Name (Path);
      begin
         if Is_Ada_File (Path) and then Base (Base'First) /= '.' then
            Result.Append (To_Unbounded_String (Rel_Path (Path, Root)));
         end if;
      end Visit;

      procedure Units is new Walk (Visit);
   begin
      for R of The_Roots loop
         Units (Join (Root, To_String (R)), Hidden => False);
      end loop;
      Sorting.Sort (Result);
      return Result;
   end All_Units;

   function Unit_Files (Name : String) return Path_List is
      use Outline.Text;
      Result : Path_List;
      Specs  : Path_List;
      Bodies : Path_List;
   begin
      if Is_File (Name) then
         Result.Append (To_Unbounded_String (Rel_Path (Name, Root)));
         return Result;
      end if;
      if Is_File (Join (Root, Name)) then
         Result.Append (To_Unbounded_String (Name));
         return Result;
      end if;
      declare
         Lowered : constant String := Encode (Lower (Decode (Name)));
         No_Ext  : constant String :=
           (if Lowered'Length >= 4
              and then Lowered (Lowered'Last - 3 .. Lowered'Last)
                       in ".ads" | ".adb"
            then Lowered (Lowered'First .. Lowered'Last - 4) else Lowered);
         Base    : String := No_Ext;
      begin
         for C of Base loop
            if C = '.' then
               C := '-';
            end if;
         end loop;
         for P of All_Units loop
            declare
               File : constant String := Dirs.Simple_Name (To_String (P));
            begin
               if Is_Ada_File (File)
                 and then File (File'First .. File'Last - 4) = Base
               then
                  if File (File'Last - 3 .. File'Last) = ".ads" then
                     Specs.Append (P);
                  else
                     Bodies.Append (P);
                  end if;
               end if;
            end;
         end loop;
      end;
      Result := Specs;
      Result.Append_Vector (Bodies);
      return Result;
   end Unit_Files;

   function Md_File (Name : String) return String is
      use Outline.Text;
   begin
      if Is_File (Join (Root, Name)) then
         return Name;
      elsif Is_File (Name) then
         return Rel_Path (Name, Root);
      end if;
      declare
         Prefix : constant String := Encode (Zfill (Decode (Name), 2)) & "-";
         Dir    : constant String := Join (Root, Spec_Dir);
         Hits   : Path_List;
         S      : Dirs.Search_Type;
         E      : Dirs.Directory_Entry_Type;
      begin
         if not Is_Dir (Dir) then
            return "";
         end if;
         Dirs.Start_Search (S, Dir, "", [Dirs.Ordinary_File => True,
                                         others => False]);
         while Dirs.More_Entries (S) loop
            Dirs.Get_Next_Entry (S, E);
            declare
               F : constant String := Dirs.Simple_Name (E);
            begin
               if F'Length >= Prefix'Length + 3
                 and then F (F'First .. F'First + Prefix'Length - 1) = Prefix
                 and then F (F'Last - 2 .. F'Last) = ".md"
               then
                  Hits.Append (To_Unbounded_String (F));
               end if;
            end;
         end loop;
         Dirs.End_Search (S);
         if Hits.Is_Empty then
            return "";
         end if;
         Sorting.Sort (Hits);
         return Rel_Path (Join (Dir, To_String (Hits.First_Element)), Root);
      end;
   end Md_File;

   function Joined (List : Path_List) return String is
      R : Unbounded_String;
   begin
      for P of List loop
         if R /= "" then
            Append (R, ", ");
         end if;
         Append (R, P);
      end loop;
      return To_String (R);
   end Joined;

   --  The Source_Dirs of the project files at the root.
   function Project_Source_Dirs return Path_List is
      use Outline.Lexer;
      Result : Path_List;
      Gprs   : Path_List;
      S      : Dirs.Search_Type;
      E      : Dirs.Directory_Entry_Type;
   begin
      Dirs.Start_Search (S, Root, "*.gpr", [Dirs.Ordinary_File => True,
                                            others => False]);
      while Dirs.More_Entries (S) loop
         Dirs.Get_Next_Entry (S, E);
         Gprs.Append (To_Unbounded_String (Dirs.Full_Name (E)));
      end loop;
      Dirs.End_Search (S);
      Sorting.Sort (Gprs);
      for G of Gprs loop
         declare
            Source : constant String := Outline.Files.Read (To_String (G));
            C      : Cursor := Start (Source);
            T      : Token;
            State  : Natural := 0;   --  for, Source_Dirs, use, (
            Found  : Boolean := False;

            function Is_Ident (Text : String) return Boolean is
              (T.Kind = Identifier
               and then Ada.Characters.Handling.To_Lower
                          (Source (T.First .. T.Last)) = Text);
         begin
            loop
               Next (Source, C, T);
               exit when T.Kind = End_Of_Input;
               if T.Kind = Comment then
                  null;
               elsif State = 4 then
                  if T.Kind = Delimiter and then T.Delim = Right_Paren then
                     State := 0;
                  elsif T.Kind = String_Literal and then not T.Malformed then
                     declare
                        Lit : constant String :=
                          Source (T.First + 1 .. T.Last - 1);
                        Dir : constant String :=
                          (if Lit'Length >= 3
                             and then Lit (Lit'Last - 2 .. Lit'Last) = "/**"
                           then Lit (Lit'First .. Lit'Last - 3)
                           elsif Lit = "**" then "." else Lit);
                        Rel : constant String :=
                          Rel_Path (Join (Dirs.Containing_Directory
                                            (To_String (G)), Dir), Root);
                     begin
                        if not Result.Contains (To_Unbounded_String (Rel))
                        then
                           Result.Append (To_Unbounded_String (Rel));
                        end if;
                     end;
                  end if;
               elsif State = 0 and then T.Kind = Reserved_Word
                 and then T.Word = W_For
               then
                  State := 1;
               elsif State = 1 and then Is_Ident ("source_dirs") then
                  State := 2;
               elsif State = 2 and then T.Kind = Reserved_Word
                 and then T.Word = W_Use
               then
                  State := 3;
               elsif State = 3 and then T.Kind = Delimiter
                 and then T.Delim = Left_Paren
               then
                  State := 4;
                  Found := True;
               else
                  State := 0;
               end if;
            end loop;
            if not Found and then not Result.Contains
              (To_Unbounded_String ("."))
            then
               Result.Append (To_Unbounded_String ("."));
            end if;
         end;
      end loop;
      --  the roots are searched recursively: a root inside another one
      --  would list its units twice
      declare
         Outer : Path_List;

         function Inside (R, S : String) return Boolean is
           (R /= S and then (S = "."
                             or else (R'Length > S'Length
                                      and then R (R'First .. R'First + S'Length)
                                               = S & "/")));
      begin
         for R of Result loop
            if not (for some S of Result =>
                      Inside (To_String (R), To_String (S)))
            then
               Outer.Append (R);
            end if;
         end loop;
         return Outer;
      end;
   end Project_Source_Dirs;

   procedure Initialize is
   begin
      declare
         Value : constant String :=
           Ada.Characters.Handling.To_Lower (Get ("OUTLINE_PY_COMPAT"));
      begin
         if Value in "1" | "all" then
            Compat_Set := [others => True];
         else
            for Item of Split (Value, ',') loop
               for F in Fix loop
                  if To_String (Item) =
                    Ada.Characters.Handling.To_Lower (F'Image)
                  then
                     Compat_Set (F) := True;
                  end if;
               end loop;
            end loop;
         end if;
      end;
      if Get ("OUTLINE_ROOT") /= "" then
         The_Root := To_Unbounded_String (Get ("OUTLINE_ROOT"));
      else
         declare
            Dir : Unbounded_String :=
              To_Unbounded_String (Dirs.Current_Directory);
         begin
            The_Root := Dir;
            loop
               declare
                  D : constant String := To_String (Dir);
               begin
                  if Dirs.Exists (Join (D, ".outline"))
                    or else Dirs.Exists (Join (D, ".git"))
                  then
                     The_Root := Dir;
                     exit;
                  end if;
                  exit when D = "/" or else D = "";
                  Dir := To_Unbounded_String (Dirs.Containing_Directory (D));
               end;
            end loop;
         exception
            when others =>
               null;
         end;
      end if;

      if Get ("OUTLINE_ROOTS") /= "" then
         The_Roots := Split (Get ("OUTLINE_ROOTS"), ':');
      elsif Is_File (Join (Root, ".outline")) then
         for Raw_Line of Split (Outline.Files.Read (Join (Root, ".outline")),
                                ASCII.LF)
         loop
            declare
               L : constant String :=
                 Outline.Text.Encode (Outline.Text.Strip
                   (Outline.Text.Decode (To_String (Raw_Line))));
            begin
               if L = "" or else L (L'First) = '#' then
                  null;
               elsif L'Length > 5 and then L (L'First .. L'First + 4) = "spec:"
               then
                  The_Spec := To_Unbounded_String
                    (Outline.Text.Encode (Outline.Text.Strip
                       (Outline.Text.Decode (L (L'First + 5 .. L'Last)))));
               else
                  The_Roots.Append (To_Unbounded_String (L));
               end if;
            end;
         end loop;
      else
         The_Roots := Project_Source_Dirs;
      end if;
      if The_Roots.Is_Empty then
         The_Roots.Append (To_Unbounded_String ("."));
         Skip_Builds := True;
      end if;
   end Initialize;

end Outline.Config;
