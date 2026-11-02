--  SPDX-License-Identifier: Apache-2.0

with Outline.Config;

package body Outline.Scan is

   use Outline.Sources;
   use type Outline.Config.Fix;

   Look_Ahead  : constant := 200;   --  lines searched for `is` or `;`
   Decl_Window : constant := 400;   --  lines searched for a declaration's end

   --  A copy of W indexed from 1, so that the matchers can count.
   function One (W : WWS) return WWS is
      R : constant WWS (1 .. W'Length) := W;
   begin
      return R;
   end One;

   function Word_Run (L : WWS; From : Positive; Dots : Boolean := False)
     return Positive
   is
      E : Positive := From;
   begin
      while E <= L'Last
        and then (Is_Word (L (E)) or else (Dots and then L (E) = '.'))
      loop
         E := E + 1;
      end loop;
      return E;
   end Word_Run;
   --  The first position after the run of \w (or [\w.]) that starts at
   --  From.

   --  Keyword at P, in any case, followed by at least one space: the
   --  position after the spaces, or 0.
   function Keyword_Space (L : WWS; P : Positive; Keyword : WWS)
     return Natural
   is
      After : constant Positive := P + Keyword'Length;
   begin
      if Has_At (L, P, Keyword, Case_Insensitive => True)
        and then After <= L'Last and then Is_Space (L (After))
      then
         return Skip_Spaces (L, After);
      end if;
      return 0;
   end Keyword_Space;

   --  START: ^(\s*)(?:overriding\s+)?(procedure|function)\s+("?[\w\.]+"?)
   function Match_Start
     (Line   : WWS;
      Indent : out Natural;
      Kind   : out UStr;
      Name   : out UStr) return Boolean
   is
      L : constant WWS := One (Line);
      P : constant Positive := Skip_Spaces (L, 1);
      Q : Positive := P;
      R : Natural := 0;
   begin
      Indent := P - 1;
      Kind := +"";
      Name := +"";
      declare
         After_Overriding : constant Natural :=
           Keyword_Space (L, P, "overriding");
      begin
         if After_Overriding /= 0 then
            Q := After_Overriding;
         end if;
      end;
      if Keyword_Space (L, Q, "procedure") /= 0 then
         R := Keyword_Space (L, Q, "procedure");
         Kind := +"procedure";
      elsif Keyword_Space (L, Q, "function") /= 0 then
         R := Keyword_Space (L, Q, "function");
         Kind := +"function";
      else
         return False;
      end if;
      if R > L'Last then
         return False;
      end if;

      if L (R) = '"' and then not Outline.Config.Compat (Outline.Config.Operators)
      then
         --  an operator symbol: "+", "and", "<="
         for K in R + 1 .. L'Last loop
            if L (K) = '"' then
               if K = R + 1 then
                  return False;
               end if;
               Name := +L (R + 1 .. K - 1);
               return True;
            end if;
         end loop;
         return False;
      end if;

      declare
         Start_Name : constant Positive := (if L (R) = '"' then R + 1 else R);
         E          : constant Positive := Word_Run (L, Start_Name, True);
         Last_G3    : Natural;
      begin
         if E = Start_Name then
            return False;
         end if;
         Last_G3 := (if E <= L'Last and then L (E) = '"' then E else E - 1);
         Name := +Strip_Chars (L (R .. Last_G3), """");
         return True;
      end;
   end Match_Start;

   --  ^ {Indent}end\s+"?Name"?\s*;  (any case)
   function Is_End_Line (Line : WWS; Indent : Natural; Name : WWS)
     return Boolean
   is
      L : constant WWS := One (Line);
      P : Natural;
   begin
      if L'Length < Indent + 3
        or else (for some I in 1 .. Indent => L (I) /= ' ')
      then
         return False;
      end if;
      P := Keyword_Space (L, Indent + 1, "end");
      if P = 0 or else P > L'Last then
         return False;
      end if;
      if L (P) = '"' then
         P := P + 1;
      end if;
      if not Has_At (L, P, Name, Case_Insensitive => True) then
         return False;
      end if;
      P := P + Name'Length;
      if P <= L'Last and then L (P) = '"' then
         P := P + 1;
      end if;
      P := Skip_Spaces (L, P);
      return P <= L'Last and then L (P) = ';';
   end Is_End_Line;

   --  \s*(\(|new\b|abstract\b|null\b|separate\b) at the start of Rest
   function Starts_Spec_Like (Rest : WWS) return Boolean is
      L : constant WWS := One (Rest);
      P : constant Positive := Skip_Spaces (L, 1);
   begin
      if P > L'Last then
         return False;
      end if;
      if L (P) = '(' then
         return True;
      end if;
      for Word of WWS_List'([+"new", +"abstract", +"null", +"separate"]) loop
         declare
            W : constant WWS := +Word;
         begin
            if Has_At (L, P, W) and then Boundary (L, P + W'Length) then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Starts_Spec_Like;

   function Declarations
     (S : Outline.Sources.Source_File) return Subprogram_Vectors.Vector
   is
      N      : constant Natural := Count (S);
      Result : Subprogram_Vectors.Vector;
   begin
      for I in 0 .. N - 1 loop
         declare
            D       : Subprogram;
            Kind    : UStr;
            Name    : UStr;
            Indent  : Natural;
            Depth   : Integer := 0;
            Known   : Boolean := False;
            Is_Body : Boolean := False;
            Expr    : Boolean := False;
            J       : Natural := I;
            Last    : Natural;
         begin
            if Match_Start (Raw (S, I), Indent, Kind, Name) then
               while J < N and then J < I + Look_Ahead and then not Known loop
                  declare
                     L : constant WWS := One (Code (S, J));
                     P : Positive := 1;
                  begin
                     while P <= L'Last loop
                        if L (P) = '(' then
                           Depth := Depth + 1;
                        elsif L (P) = ')' then
                           Depth := Depth - 1;
                        elsif L (P) = ';' and then Depth = 0 then
                           Known := True;
                           Is_Body := False;
                           exit;
                        elsif Has_At (L, P, "is") and then Boundary (L, P)
                          and then Boundary (L, P + 2)
                        then
                           if Depth = 0 then
                              declare
                                 Rest : UStr := +L (P + 2 .. L'Last);
                                 K    : Natural;
                              begin
                                 if Strip (+Rest) = "" then
                                    K := J + 1;
                                    while K < N
                                      and then Strip (No_Comment (S, K)) = ""
                                    loop
                                       K := K + 1;
                                    end loop;
                                    Rest := +(if K < N then No_Comment (S, K)
                                              else "");
                                 end if;
                                 Known := True;
                                 if Starts_Spec_Like (+Rest) then
                                    Is_Body := False;
                                    Expr := True;
                                 else
                                    Is_Body := True;
                                 end if;
                              end;
                              exit;
                           end if;
                           P := P + 1;   --  past the "is"
                        end if;
                        P := P + 1;
                     end loop;
                  end;
                  J := J + 1;
               end loop;
               Last := J - 1;

               if Known and then not Is_Body and then Expr
                 and then not Outline.Config.Compat (Outline.Config.Expr_End)
               then
                  --  an expression function ends at its ';' at depth 0
                  Depth := 0;
                  Scan_Expr :
                  for K in I .. Natural'Min (N, I + Look_Ahead) - 1 loop
                     for C of Code (S, K) loop
                        if C = '(' then
                           Depth := Depth + 1;
                        elsif C = ')' then
                           Depth := Depth - 1;
                        elsif C = ';' and then Depth = 0 then
                           Last := K;
                           exit Scan_Expr;
                        end if;
                     end loop;
                  end loop Scan_Expr;
               elsif Known and then Is_Body then
                  for K in J .. N - 1 loop
                     if Is_End_Line (Raw (S, K), Indent, +Name) then
                        Last := K;
                        exit;
                     end if;
                  end loop;
               elsif Known then
                  Last := J - 1;
               end if;

               D := (Indent  => Indent,
                     Kind    => Kind,
                     Name    => Name,
                     First   => I,
                     Last    => Last,
                     Is_Body => Known and then Is_Body,
                     Expr    => Expr);
               Result.Append (D);
            end if;
         end;
      end loop;
      return Result;
   end Declarations;

   --  The DECL pattern of outline.py:
   --  ^(\s*)(?:(type|subtype)\s+("?[\w]+"?)
   --          |([\w]+(?:\s*,\s*[\w]+)*)\s*:(?!=)
   --          |(with|use)\s+([\w\.]+(?:\s*,\s*[\w\.]+)*)\s*;)
   function Match_Decl
     (Line   : WWS;
      Indent : out Natural;
      Kind   : out UStr;
      Name   : out UStr) return Boolean
   is
      L : constant WWS := One (Line);
      P : constant Positive := Skip_Spaces (L, 1);

      --  [\w]+ (or [\w.]+) and (\s*,\s*[\w]+)* from From: the last
      --  position of the list, or 0 when there is no first word.
      function Name_List (From : Positive; Dots : Boolean) return Natural is
         E    : Positive := Word_Run (L, From, Dots);
         Last : Natural;
      begin
         if E = From then
            return 0;
         end if;
         Last := E - 1;
         loop
            declare
               Q : constant Positive := Skip_Spaces (L, E);
            begin
               exit when Q > L'Last or else L (Q) /= ',';
               declare
                  R  : constant Positive := Skip_Spaces (L, Q + 1);
                  E2 : constant Positive := Word_Run (L, R, Dots);
               begin
                  exit when E2 = R;
                  Last := E2 - 1;
                  E := E2;
               end;
            end;
         end loop;
         return Last;
      end Name_List;
   begin
      Indent := P - 1;
      Kind := +"";
      Name := +"";
      if P > L'Last then
         return False;
      end if;

      for Keyword of WWS_List'([+"type", +"subtype"]) loop
         declare
            R : constant Natural := Keyword_Space (L, P, +Keyword);
         begin
            if R /= 0 and then R <= L'Last then
               declare
                  Q : constant Positive := (if L (R) = '"' then R + 1 else R);
                  E : constant Positive := Word_Run (L, Q);
               begin
                  if E > Q then
                     Kind := Keyword;
                     Name := +Strip_Chars
                       (L (R .. (if E <= L'Last and then L (E) = '"' then E
                                 else E - 1)), """");
                     return True;
                  end if;
               end;
            end if;
         end;
      end loop;

      declare
         Last : constant Natural := Name_List (P, Dots => False);
      begin
         if Last /= 0 then
            declare
               Q : constant Positive := Skip_Spaces (L, Last + 1);
            begin
               if Q <= L'Last and then L (Q) = ':'
                 and then not (Q < L'Last and then L (Q + 1) = '=')
               then
                  Kind := +"object";
                  Name := +L (P .. Last);
                  return True;
               end if;
            end;
         end if;
      end;

      for Keyword of WWS_List'([+"with", +"use"]) loop
         declare
            R : constant Natural := Keyword_Space (L, P, +Keyword);
         begin
            if R /= 0 and then R <= L'Last then
               declare
                  Last : constant Natural := Name_List (R, Dots => True);
               begin
                  if Last /= 0 then
                     declare
                        Q : constant Positive := Skip_Spaces (L, Last + 1);
                     begin
                        if Q <= L'Last and then L (Q) = ';' then
                           Kind := Keyword;
                           Name := +L (R .. Last);
                           return True;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
      return False;
   end Match_Decl;

   --  \bis\b\s*(tagged\s+|limited\s+)*record\b or \bwith\s+record\b
   function Opens_Record (Code_Line : WWS) return Boolean is
      L : constant WWS := One (Code_Line);
   begin
      for P in L'Range loop
         if Has_At (L, P, "is") and then Boundary (L, P)
           and then Boundary (L, P + 2)
         then
            declare
               Q : Positive := Skip_Spaces (L, P + 2);
            begin
               loop
                  if Has_At (L, Q, "tagged") and then Q + 6 <= L'Last
                    and then Is_Space (L (Q + 6))
                  then
                     Q := Skip_Spaces (L, Q + 6);
                  elsif Has_At (L, Q, "limited") and then Q + 7 <= L'Last
                    and then Is_Space (L (Q + 7))
                  then
                     Q := Skip_Spaces (L, Q + 7);
                  else
                     exit;
                  end if;
               end loop;
               if Has_At (L, Q, "record") and then Boundary (L, Q + 6) then
                  return True;
               end if;
            end;
         end if;
         if Has_At (L, P, "with") and then Boundary (L, P)
           and then P + 4 <= L'Last and then Is_Space (L (P + 4))
         then
            declare
               Q : constant Positive := Skip_Spaces (L, P + 4);
            begin
               if Has_At (L, Q, "record") and then Boundary (L, Q + 6) then
                  return True;
               end if;
            end;
         end if;
      end loop;
      return False;
   end Opens_Record;

   --  ^ {Indent}end\s+record\s*;  (any case)
   function Is_End_Record (Line : WWS; Indent : Natural) return Boolean is
      L : constant WWS := One (Line);
      P : Natural;
   begin
      if L'Length < Indent + 3
        or else (for some I in 1 .. Indent => L (I) /= ' ')
      then
         return False;
      end if;
      P := Keyword_Space (L, Indent + 1, "end");
      if P = 0 or else not Has_At (L, P, "record", Case_Insensitive => True)
      then
         return False;
      end if;
      P := Skip_Spaces (L, P + 6);
      return P <= L'Last and then L (P) = ';';
   end Is_End_Record;

   function Other_Declarations
     (S : Outline.Sources.Source_File) return Other_Vectors.Vector
   is
      N      : constant Natural := Count (S);
      Bodies : Subprogram_Vectors.Vector;
      Result : Other_Vectors.Vector;
      I      : Natural := 0;

      function Inside_Body (Line : Natural) return Boolean is
        (for some D of Bodies => D.First < Line and then Line <= D.Last);
   begin
      for D of Declarations (S) loop
         if D.Is_Body then
            Bodies.Append (D);
         end if;
      end loop;
      while I < N loop
         declare
            Indent : Natural;
            Kind   : UStr;
            Name   : UStr;
         begin
            if Inside_Body (I)
              or else not Match_Decl (Raw (S, I), Indent, Kind, Name)
              or else Starts_With (Strip (Raw (S, I)), "--")
            then
               I := I + 1;
            else
               declare
                  Last   : Natural := I;
                  Depth  : Integer := 0;
                  Record_Type : Boolean := False;
               begin
                  Window :
                  for K in I .. Natural'Min (N, I + Decl_Window) - 1 loop
                     declare
                        Code_K : constant WWS := Code (S, K);
                     begin
                        if Opens_Record (Code_K) then
                           Record_Type := True;
                        end if;
                        if Record_Type then
                           if Is_End_Record (Raw (S, K), Indent) then
                              Last := K;
                              exit Window;
                           end if;
                        else
                           for C of Code_K loop
                              if C = '(' then
                                 Depth := Depth + 1;
                              elsif C = ')' then
                                 Depth := Depth - 1;
                              elsif C = ';' and then Depth = 0 then
                                 Last := K;
                                 exit Window;
                              end if;
                           end loop;
                        end if;
                     end;
                  end loop Window;
                  Result.Append (Other'(Indent => Indent,
                                         Kind   => +Lower (+Kind),
                                         Name   => Name,
                                         First  => I,
                                         Last   => Last));
                  I := Last + 1;
               end;
            end if;
         end;
      end loop;
      return Result;
   end Other_Declarations;

   Aspect_Marks : constant WWS_List :=
     [+"Global", +"Depends", +"Pre", +"Post", +"Contract_Cases",
      +"Refined_Global", +"Refined_Depends", +"Refined_Post",
      +"Refined_State", +"Abstract_State", +"Initializes", +"Convention",
      +"Import", +"Export", +"External_Name", +"Inline", +"Ghost",
      +"SPARK_Mode", +"Annotate"];

   function Aspect_At (Line : WWS; Name : out UStr) return Boolean is
      L : constant WWS := One (Line);
   begin
      Name := +"";
      for P in L'Range loop
         if Is_Word (L (P)) and then Boundary (L, P) then
            for Mark of Aspect_Marks loop
               declare
                  M : constant WWS := +Mark;
               begin
                  if Has_At (L, P, M, Case_Insensitive => True)
                    and then Has_At (L, Skip_Spaces (L, P + M'Length), "=>")
                  then
                     Name := +L (P .. P + M'Length - 1);
                     return True;
                  end if;
               end;
            end loop;
         end if;
      end loop;
      return False;
   end Aspect_At;

end Outline.Scan;
