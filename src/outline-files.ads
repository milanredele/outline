--  SPDX-License-Identifier: Apache-2.0
--
--  Source files read whole into memory, bytes as they are.

package Outline.Files is

   function Read (Path : String) return String
   with Post => Read'Result'First = 1;
   --  The bytes of the file at Path; raises Ada.IO_Exceptions.Name_Error
   --  when it cannot be opened.

end Outline.Files;
