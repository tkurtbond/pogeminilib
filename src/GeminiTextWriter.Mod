MODULE GeminiTextWriter; (* gemtext, written *)

(* Writes gemtext a line at a time, each ended by LF, to a file
   (FileWriter) or to anything a Writer's extension writes to, as a
   server's exchange will.

   Gemtext has no escape, so what would read back as something else is
   refused (FALSE, and why), not written, and the program chooses what
   to do instead: a text line that another kind would claim (one that
   begins "=>", "#", "* ", ">" or three backticks), a line end in any
   line, a line of the wrong kind for where it is (preformatted text
   outside a block, any other inside one), whitespace that a reader
   drops (before a heading's text or a link's label, or a byte order
   mark beginning the page), and a link whose URL is empty or holds a
   space or a control character.

   What is written reads back through GeminiText as the same lines. *)

IMPORT Files, GeminiUrls;

CONST
  Abstract = 122;     (* Writer.Put not overridden *)
  BadLevel = 123;     (* Heading: a level not 1..3 *)

  CR = 0DX; LF = 0AX; Tab = 09X;

TYPE
  (* Writes gemtext. An extension overrides Put; pre is whether a
     preformatted block is open. *)
  Writer* = POINTER TO WriterDesc;
  WriterDesc* = RECORD
    pre-: BOOLEAN;
    begun: BOOLEAN    (* a line written: a BOM now would be text *)
  END;

  (* Writes to r, which is left after the last byte written. *)
  FileWriter* = POINTER TO FileWriterDesc;
  FileWriterDesc* = RECORD (WriterDesc)
    r*: Files.Rider
  END;

(* Writes s[0..n-1]: FALSE if it couldn't. An extension's own; this
   one halts. (w is never NIL here: poc refuses an ASSERT that is
   always FALSE, and HALT would exit with another status than every
   other halt here.) *)
PROCEDURE (w: Writer) Put*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
BEGIN ASSERT(w = NIL, Abstract); RETURN FALSE
END Put;

PROCEDURE (w: FileWriter) Put*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < n) & (w.r.res = 0) DO Files.Write(w.r, s[i]); INC(i) END;
  RETURN w.r.res = 0
END Put;

(* Makes w a writer at the start of a page. *)
PROCEDURE Init*(w: Writer);
BEGIN w.pre := FALSE; w.begun := FALSE
END Init;

(* A writer to r, which it copies: the rider w.r then goes on. *)
PROCEDURE NewFile*(VAR r: Files.Rider): FileWriter;
  VAR w: FileWriter;
BEGIN
  NEW(w); Init(w); w.r := r;
  RETURN w
END NewFile;

PROCEDURE Fail(VAR why: ARRAY OF CHAR; reason-: ARRAY OF CHAR): BOOLEAN;
BEGIN COPY(reason, why); RETURN FALSE
END Fail;

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
  RETURN n
END Length;

(* Whether s holds a line end, which would end the line early. *)
PROCEDURE Breaks(s-: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) & (s[i] # CR) & (s[i] # LF) DO INC(i) END;
  RETURN (i < LEN(s)) & (s[i] # 0X)
END Breaks;

PROCEDURE Space(c: CHAR): BOOLEAN;
BEGIN RETURN (c = " ") OR (c = Tab)
END Space;

PROCEDURE Ticks(s-: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN (Length(s) >= 3) & (s[0] = "`") & (s[1] = "`") & (s[2] = "`")
END Ticks;

(* marker, then s, then LF, if s may be written in a line outside a
   block (inside one if pre). *)
PROCEDURE Line(w: Writer; marker-, s-: ARRAY OF CHAR; pre: BOOLEAN;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR ok: BOOLEAN;
BEGIN
  IF Breaks(s) THEN ok := Fail(why, "a line end in a line")
  ELSIF ~w.begun & (marker[0] = 0X) & (Length(s) >= 3)
      & (s[0] = 0EFX) & (s[1] = 0BBX) & (s[2] = 0BFX) THEN
    ok := Fail(why, "a byte order mark at the page's start, which a reader skips")
  ELSIF w.pre & ~pre THEN ok := Fail(why, "inside a preformatted block")
  ELSIF ~w.pre & pre THEN ok := Fail(why, "outside a preformatted block")
  ELSIF ~(w.Put(marker, Length(marker)) & w.Put(s, Length(s)) & w.Put(0AX, 1)) THEN
    ok := Fail(why, "the write failed")
  ELSE ok := TRUE; w.begun := TRUE
  END;
  RETURN ok
END Line;

(* A text line: refused if another kind would claim it. *)
PROCEDURE Text*(w: Writer; s-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR n: LONGINT; ok: BOOLEAN;
BEGIN
  n := Length(s);
  IF (n >= 2) & (s[0] = "=") & (s[1] = ">") OR (n >= 1) & ((s[0] = "#") OR (s[0] = ">"))
    OR (n >= 2) & (s[0] = "*") & (s[1] = " ") OR Ticks(s) THEN
    ok := Fail(why, "another kind of line begins so")
  ELSE ok := Line(w, "", s, FALSE, why)
  END;
  RETURN ok
END Text;

(* A link to url, as written, with label (or none, if ""). *)
PROCEDURE Link*(w: Writer; url-, label-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT; ok: BOOLEAN;
BEGIN
  i := 0; WHILE (i < LEN(url)) & (url[i] > " ") & (url[i] # 7FX) DO INC(i) END;
  IF i = 0 THEN ok := Fail(why, "no URL")
  ELSIF (i < LEN(url)) & (url[i] # 0X) THEN ok := Fail(why, "a space or a control character in the URL")
  ELSIF Space(label[0]) THEN ok := Fail(why, "whitespace before the label")
  ELSIF Breaks(label) THEN ok := Fail(why, "a line end in a line")
  ELSIF w.pre THEN ok := Fail(why, "inside a preformatted block")
  ELSIF ~(w.Put("=> ", 3) & w.Put(url, i)) THEN ok := Fail(why, "the write failed")
  ELSIF label[0] = 0X THEN ok := Line(w, "", "", FALSE, why)
  ELSE ok := Line(w, " ", label, FALSE, why)
  END;
  RETURN ok
END Link;

(* A link to name, a relative path of one segment, every byte of it
   percent-encoded but RFC 3986's unreserved (letters, digits, "-._~"),
   as pogemini's listings write them: so "a:b" is a name, not a scheme,
   and "a?b" not a query. *)
PROCEDURE NameLink*(w: Writer; name-, label-: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR url: POINTER TO ARRAY OF CHAR; ok: BOOLEAN;
BEGIN
  NEW(url, 3 * Length(name) + 1);
  IF ~GeminiUrls.Encode(name, url^) THEN ok := Fail(why, "no room for the URL")
  ELSE ok := Link(w, url^, label, why)
  END;
  RETURN ok
END NameLink;

(* A heading of level 1..3; any other level halts. *)
PROCEDURE Heading*(w: Writer; level: INTEGER; s-: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR ok: BOOLEAN;
BEGIN
  ASSERT((level >= 1) & (level <= 3), BadLevel);
  IF Space(s[0]) THEN ok := Fail(why, "whitespace before the heading's text")
  ELSIF level = 1 THEN ok := Line(w, "# ", s, FALSE, why)
  ELSIF level = 2 THEN ok := Line(w, "## ", s, FALSE, why)
  ELSE ok := Line(w, "### ", s, FALSE, why)
  END;
  RETURN ok
END Heading;

PROCEDURE ListItem*(w: Writer; s-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Line(w, "* ", s, FALSE, why)
END ListItem;

(* A quote; whitespace at the start of s is kept, as a reader keeps it. *)
PROCEDURE Quote*(w: Writer; s-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Line(w, ">", s, FALSE, why)
END Quote;

(* Opens a preformatted block, with alt text (or none, if ""). *)
PROCEDURE Open*(w: Writer; alt-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR ok: BOOLEAN;
BEGIN
  ok := Line(w, "```", alt, FALSE, why);
  IF ok THEN w.pre := TRUE END;
  RETURN ok
END Open;

PROCEDURE Close*(w: Writer; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR ok: BOOLEAN;
BEGIN
  ok := Line(w, "```", "", TRUE, why);
  IF ok THEN w.pre := FALSE END;
  RETURN ok
END Close;

(* A line inside a block, as it is: refused if it would close it. *)
PROCEDURE Preformatted*(w: Writer; s-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR ok: BOOLEAN;
BEGIN
  IF Ticks(s) THEN ok := Fail(why, "three backticks would close the block")
  ELSE ok := Line(w, "", s, TRUE, why)
  END;
  RETURN ok
END Preformatted;

END GeminiTextWriter.
