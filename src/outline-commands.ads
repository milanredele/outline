--  SPDX-License-Identifier: Apache-2.0
--
--  The commands of outline, each printing what outline.py printed. Paths
--  are relative to the root (Outline.Config); the Boolean results say
--  whether anything was found.

with Outline.Config;

package Outline.Commands is

   procedure Outline_Unit (Path : String);
   --  Every subprogram: lines, kind, profile, aspect lines.

   procedure List_Decls (Path : String);
   --  Every other declaration: lines, kind, first line.

   function Show_Decl (Path, Name : String) return Boolean;
   --  That declaration in full, with its heading and trailing comments.

   function Show (Path, Name : String; Bodies_Only : Boolean := False)
     return Boolean;
   --  That subprogram in full.

   function Show_Spec (Path : String; Name : String := "";
                       All_Decls : Boolean := False) return Boolean;
   --  That subprogram's declaration without its body (a body cut after
   --  its profile); with All_Decls, every declaration of the file at
   --  library level that is not a body.

   procedure Refs (Name : String; Roots : Outline.Config.Path_List);
   --  The uses of Name, as file:line, declarations, end lines and comment
   --  lines left out.

   procedure List_Units;
   --  Every unit under the roots with its lines and subprograms.

   procedure Md_Toc (Path : String);
   function Md_Section (Path, Key : String) return Boolean;
   procedure Md_Grep (Path, Word : String);
   --  The headings of a markdown file, one section, the matching lines.

   procedure Tokens (Path : String);
   --  The tokens of a file (a development aid).

end Outline.Commands;
