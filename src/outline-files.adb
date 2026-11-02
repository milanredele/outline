--  SPDX-License-Identifier: Apache-2.0

with Ada.Directories;
with Ada.Streams.Stream_IO;

package body Outline.Files is

   function Read (Path : String) return String is
      use Ada.Streams.Stream_IO;
      Size : constant Natural := Natural (Ada.Directories.Size (Path));
      File : File_Type;
   begin
      return Result : String (1 .. Size) do
         Open (File, In_File, Path);
         String'Read (Stream (File), Result);
         Close (File);
      end return;
   end Read;

end Outline.Files;
