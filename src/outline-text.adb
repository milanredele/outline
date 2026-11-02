--  SPDX-License-Identifier: Apache-2.0

with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Ada.Wide_Wide_Characters.Handling;

package body Outline.Text is

   package WCH renames Ada.Wide_Wide_Characters.Handling;

   Replacement : constant WWC := WWC'Val (16#FFFD#);

   function Decode (S : String) return WWS is
      Result : WWS (1 .. S'Length);
      N      : Natural := 0;
      I      : Integer := S'First;

      function B (K : Integer) return Natural is
        (if K <= S'Last then Character'Pos (S (K)) else 256);

      function Cont (K : Integer; Lo : Natural := 16#80#;
                     Hi : Natural := 16#BF#) return Boolean is
        (B (K) in Lo .. Hi);

      procedure Emit (Code : Natural) is
      begin
         N := N + 1;
         Result (N) := WWC'Val (Code);
      end Emit;
   begin
      while I <= S'Last loop
         declare
            Lead : constant Natural := B (I);
         begin
            if Lead < 16#80# then
               Emit (Lead);
               I := I + 1;
            elsif Lead in 16#C2# .. 16#DF# then
               if Cont (I + 1) then
                  Emit ((Lead - 16#C0#) * 64 + (B (I + 1) - 16#80#));
                  I := I + 2;
               else
                  Emit (16#FFFD#);
                  I := I + 1;
               end if;
            elsif Lead in 16#E0# .. 16#EF# then
               declare
                  Lo : constant Natural :=
                    (if Lead = 16#E0# then 16#A0# else 16#80#);
                  Hi : constant Natural :=
                    (if Lead = 16#ED# then 16#9F# else 16#BF#);
               begin
                  if Cont (I + 1, Lo, Hi) and then Cont (I + 2) then
                     Emit ((Lead - 16#E0#) * 4096 + (B (I + 1) - 16#80#) * 64
                           + (B (I + 2) - 16#80#));
                     I := I + 3;
                  elsif Cont (I + 1, Lo, Hi) then
                     Emit (16#FFFD#);
                     I := I + 2;
                  else
                     Emit (16#FFFD#);
                     I := I + 1;
                  end if;
               end;
            elsif Lead in 16#F0# .. 16#F4# then
               declare
                  Lo : constant Natural :=
                    (if Lead = 16#F0# then 16#90# else 16#80#);
                  Hi : constant Natural :=
                    (if Lead = 16#F4# then 16#8F# else 16#BF#);
               begin
                  if Cont (I + 1, Lo, Hi) and then Cont (I + 2)
                    and then Cont (I + 3)
                  then
                     Emit ((Lead - 16#F0#) * 262_144
                           + (B (I + 1) - 16#80#) * 4096
                           + (B (I + 2) - 16#80#) * 64
                           + (B (I + 3) - 16#80#));
                     I := I + 4;
                  elsif Cont (I + 1, Lo, Hi) and then Cont (I + 2) then
                     Emit (16#FFFD#);
                     I := I + 3;
                  elsif Cont (I + 1, Lo, Hi) then
                     Emit (16#FFFD#);
                     I := I + 2;
                  else
                     Emit (16#FFFD#);
                     I := I + 1;
                  end if;
               end;
            else
               Emit (16#FFFD#);
               I := I + 1;
            end if;
         end;
      end loop;
      return Result (1 .. N);
   end Decode;

   function Encode (W : WWS) return String is
      Result : String (1 .. 4 * W'Length);
      N      : Natural := 0;

      procedure Emit (Code : Natural) is
      begin
         N := N + 1;
         Result (N) := Character'Val (Code);
      end Emit;
   begin
      for C of W loop
         declare
            Code : constant Natural := WWC'Pos (C);
         begin
            if Code < 16#80# then
               Emit (Code);
            elsif Code < 16#800# then
               Emit (16#C0# + Code / 64);
               Emit (16#80# + Code mod 64);
            elsif Code < 16#1_0000# then
               Emit (16#E0# + Code / 4096);
               Emit (16#80# + Code / 64 mod 64);
               Emit (16#80# + Code mod 64);
            elsif Code < 16#11_0000# then
               Emit (16#F0# + Code / 262_144);
               Emit (16#80# + Code / 4096 mod 64);
               Emit (16#80# + Code / 64 mod 64);
               Emit (16#80# + Code mod 64);
            else
               Emit (16#EF#);
               Emit (16#BF#);
               Emit (16#BD#);
            end if;
         end;
      end loop;
      return Result (1 .. N);
   end Encode;

   function Is_Space (C : WWC) return Boolean is
     (case WWC'Pos (C) is
         when 16#09# .. 16#0D# | 16#1C# .. 16#20# | 16#85# | 16#A0#
            | 16#1680# | 16#2000# .. 16#200A# | 16#2028# | 16#2029#
            | 16#202F# | 16#205F# | 16#3000# => True,
         when others => False);

   function Is_Word (C : WWC) return Boolean is
   begin
      if WWC'Pos (C) < 128 then
         return Is_ASCII_Word (C);
      end if;
      return C /= Replacement
        and then (WCH.Is_Letter (C) or else WCH.Is_Digit (C)
                  or else WWC'Pos (C) in 16#B2# | 16#B3# | 16#B9#
                                       | 16#BC# .. 16#BE#);
   end Is_Word;

   function Lower_Char (C : WWC) return WWC is
     (if C in 'A' .. 'Z' then WWC'Val (WWC'Pos (C) + 32)
      elsif WWC'Pos (C) < 128 then C
      else WCH.To_Lower (C));

   function Lower (W : WWS) return WWS is
      Result : WWS (W'Range);
   begin
      for I in W'Range loop
         Result (I) := Lower_Char (W (I));
      end loop;
      return Result;
   end Lower;

   function LStrip (W : WWS) return WWS is
   begin
      for I in W'Range loop
         if not Is_Space (W (I)) then
            return W (I .. W'Last);
         end if;
      end loop;
      return "";
   end LStrip;

   function RStrip (W : WWS) return WWS is
   begin
      for I in reverse W'Range loop
         if not Is_Space (W (I)) then
            return W (W'First .. I);
         end if;
      end loop;
      return "";
   end RStrip;

   function Strip (W : WWS) return WWS is (RStrip (LStrip (W)));

   function In_Set (C : WWC; Chars : WWS) return Boolean is
     (for some X of Chars => X = C);

   function LStrip_Chars (W : WWS; Chars : WWS) return WWS is
   begin
      for I in W'Range loop
         if not In_Set (W (I), Chars) then
            return W (I .. W'Last);
         end if;
      end loop;
      return "";
   end LStrip_Chars;

   function RStrip_Chars (W : WWS; Chars : WWS) return WWS is
   begin
      for I in reverse W'Range loop
         if not In_Set (W (I), Chars) then
            return W (W'First .. I);
         end if;
      end loop;
      return "";
   end RStrip_Chars;

   function Strip_Chars (W : WWS; Chars : WWS) return WWS is
     (RStrip_Chars (LStrip_Chars (W, Chars), Chars));

   function Collapse (W : WWS) return WWS is
      Result : WWS (1 .. W'Length);
      N      : Natural := 0;
      In_Run : Boolean := False;
   begin
      for C of W loop
         if Is_Space (C) then
            if not In_Run then
               N := N + 1;
               Result (N) := ' ';
               In_Run := True;
            end if;
         else
            N := N + 1;
            Result (N) := C;
            In_Run := False;
         end if;
      end loop;
      return Result (1 .. N);
   end Collapse;

   function Head (W : WWS; N : Natural) return WWS is
     (if W'Length <= N then W else W (W'First .. W'First + N - 1));

   function Starts_With (W, Prefix : WWS) return Boolean is
     (W'Length >= Prefix'Length
      and then W (W'First .. W'First + Prefix'Length - 1) = Prefix);

   function Ends_With (W, Suffix : WWS) return Boolean is
     (W'Length >= Suffix'Length
      and then W (W'Last - Suffix'Length + 1 .. W'Last) = Suffix);

   function Equal_CI (A, B : WWS) return Boolean is
     (A'Length = B'Length
      and then (for all I in 0 .. A'Length - 1 =>
                  Lower_Char (A (A'First + I)) = Lower_Char (B (B'First + I))));

   function Has_At (W : WWS; Pos : Positive; Pat : WWS;
                    Case_Insensitive : Boolean := False) return Boolean is
   begin
      if Pos < W'First or else Pos - 1 > W'Last - Pat'Length then
         return False;
      end if;
      if Case_Insensitive then
         for I in 0 .. Pat'Length - 1 loop
            if Lower_Char (W (Pos + I)) /= Lower_Char (Pat (Pat'First + I)) then
               return False;
            end if;
         end loop;
         return True;
      end if;
      return W (Pos .. Pos + Pat'Length - 1) = Pat;
   end Has_At;

   function Boundary (W : WWS; Pos : Positive;
                      ASCII_Words : Boolean := False) return Boolean
   is
      function Word (C : WWC) return Boolean is
        (if ASCII_Words then Is_ASCII_Word (C) else Is_Word (C));
      Before : constant Boolean := Pos > W'First and then Pos - 1 <= W'Last
                                   and then Word (W (Pos - 1));
      After  : constant Boolean := Pos >= W'First and then Pos <= W'Last
                                   and then Word (W (Pos));
   begin
      return Before /= After;
   end Boundary;

   function Find_Word (W : WWS; Word : WWS; From : Positive;
                       Case_Insensitive : Boolean := False) return Natural is
   begin
      for P in From .. W'Last - Word'Length + 1 loop
         if Has_At (W, P, Word, Case_Insensitive)
           and then Boundary (W, P)
           and then Boundary (W, P + Word'Length)
         then
            return P;
         end if;
      end loop;
      return 0;
   end Find_Word;

   function Skip_Spaces (W : WWS; Pos : Positive) return Positive is
      P : Positive := Pos;
   begin
      while P <= W'Last and then Is_Space (W (P)) loop
         P := P + 1;
      end loop;
      return P;
   end Skip_Spaces;

   function Index_CI (W, Pat : WWS) return Natural is
   begin
      if Pat'Length = 0 then
         return W'First;
      end if;
      declare
         LW : constant WWS := Lower (W);
         LP : constant WWS := Lower (Pat);
      begin
         for P in LW'First .. LW'Last - LP'Length + 1 loop
            if LW (P .. P + LP'Length - 1) = LP then
               return P;
            end if;
         end loop;
      end;
      return 0;
   end Index_CI;

   function First_Word (W : WWS) return WWS is
      P : constant Positive := Skip_Spaces (W, W'First);
      Q : Positive := P;
   begin
      while Q <= W'Last and then not Is_Space (W (Q)) loop
         Q := Q + 1;
      end loop;
      return W (P .. Q - 1);
   end First_Word;

   function Img (N : Integer; Width : Natural := 0) return WWS is
      S : constant String := Integer'Image (N);
      T : constant WWS :=
        To_WWS (if N < 0 then S else S (S'First + 1 .. S'Last));
   begin
      return (if T'Length >= Width then T
              else [1 .. Width - T'Length => ' '] & T);
   end Img;

   function Pad (W : WWS; Width : Natural) return WWS is
     (if W'Length >= Width then W else W & [1 .. Width - W'Length => ' ']);

   function Zfill (W : WWS; Width : Natural) return WWS is
   begin
      if W'Length >= Width then
         return W;
      elsif W'Length > 0 and then W (W'First) in '+' | '-' then
         return W (W'First) & [1 .. Width - W'Length => '0']
                & W (W'First + 1 .. W'Last);
      else
         return [1 .. Width - W'Length => '0'] & W;
      end if;
   end Zfill;

   function Repr (W : WWS) return WWS is
      Quote  : constant WWC :=
        (if (for some C of W => C = ''')
           and then not (for some C of W => C = '"') then '"' else ''');
      Result : UStr;

      function Hex (Code : Natural; Digits_Count : Positive) return WWS is
         Map : constant WWS := "0123456789abcdef";
         R   : WWS (1 .. Digits_Count);
         V   : Natural := Code;
      begin
         for I in reverse R'Range loop
            R (I) := Map (V mod 16 + 1);
            V := V / 16;
         end loop;
         return R;
      end Hex;

      function Printable (Code : Natural) return Boolean is
        (case Code is
            when 0 .. 16#1F# | 16#7F# .. 16#A0# | 16#AD# => False,
            when 16#1680# | 16#2000# .. 16#200F# | 16#2028# .. 16#202F#
               | 16#205F# .. 16#206F# | 16#3000# | 16#D800# .. 16#DFFF#
               | 16#FEFF# | 16#FFF9# .. 16#FFFB# => False,
            when others => True);
   begin
      U.Append (Result, Quote);
      for C of W loop
         declare
            Code : constant Natural := WWC'Pos (C);
         begin
            if C = '\' then
               U.Append (Result, "\\");
            elsif C = Quote then
               U.Append (Result, "\" & Quote);
            elsif Code = 9 then
               U.Append (Result, "\t");
            elsif Code = 10 then
               U.Append (Result, "\n");
            elsif Code = 13 then
               U.Append (Result, "\r");
            elsif Printable (Code) then
               U.Append (Result, C);
            elsif Code < 256 then
               U.Append (Result, "\x" & Hex (Code, 2));
            elsif Code < 16#1_0000# then
               U.Append (Result, "\u" & Hex (Code, 4));
            else
               U.Append (Result, "\U" & Hex (Code, 8));
            end if;
         end;
      end loop;
      U.Append (Result, Quote);
      return +Result;
   end Repr;

   Out_Stream : constant Ada.Text_IO.Text_Streams.Stream_Access :=
     Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Standard_Output);
   Err_Stream : constant Ada.Text_IO.Text_Streams.Stream_Access :=
     Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Standard_Error);

   procedure Put_Line (W : WWS) is
   begin
      String'Write (Out_Stream, Encode (W) & ASCII.LF);
   end Put_Line;

   procedure Put_Error (W : WWS) is
   begin
      String'Write (Err_Stream, Encode (W) & ASCII.LF);
   end Put_Error;

end Outline.Text;
