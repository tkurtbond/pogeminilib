MODULE GeminiHeaders; (* a response's header: read, and written *)

(* A response header (protocol specification, 0.24.1, "Responses"):
   two digits, the status; a space and the meta, which input (1x),
   success (2x) and redirects (3x) must have and failures (4x..6x) may
   leave out; CR LF. The header is UTF-8, with no byte order mark and
   no control character. The specification sets no limit on its
   length; ours is pogemini's, a meta of at most 1024 bytes, so a header
   is at most 1029.

   Parse refuses (FALSE, and why) what the specification forbids, and
   never halts on what a server sends. It is lenient in two ways, each
   what servers send: a success with no MIME type ("20" or "20 "),
   which 0.24.1 forbids but earlier versions took as
   "text/gemini; charset=utf-8", as ParseMime does; and a space after
   a failure's status with no message after it.

   WriteHeader is a server's, and halts on what it may not send: those
   are the program's mistakes (PLAN.md, "Halt codes"). *)

IMPORT GeminiStatus, GeminiUrls;

CONST
  MaxMeta* = 1024;               (* a meta at most, as pogemini's *)
  MaxHeader* = MaxMeta + 5;      (* a header at most: status, space, meta, CR LF *)
  MaxName* = 127;                (* a MIME type or subtype at most (RFC 6838) *)

  BadStatus = 124;    (* WriteHeader: a status the specification doesn't name *)
  BadMeta = 125;      (* WriteHeader: a meta too long, not UTF-8, with a control
                         character, or empty where the status needs one *)
  BadRange = 126;     (* Ended or Parse: a length past the array *)

  CR = 0DX; LF = 0AX; Tab = 09X;

TYPE
  (* A header, as Parse gives it: meta is "" when it had none. *)
  Header* = RECORD
    status-: INTEGER;
    meta-: ARRAY MaxMeta + 1 OF CHAR
  END;

  (* A header as WriteHeader writes it, 0X after. *)
  Line* = ARRAY MaxHeader + 1 OF CHAR;

  Chars* = POINTER TO ARRAY OF CHAR;

  (* A MIME parameter: its name in lower case, its value as written
     (unquoted, if it was quoted). *)
  Parameter* = RECORD
    name-, value-: Chars
  END;

  Parameters* = POINTER TO ARRAY OF Parameter;

  (* A MIME type, as ParseMime gives it: type and subtype in lower
     case, params[0..count-1] in order. assumed: the meta was empty, so
     it is "text/gemini; charset=utf-8". skipped: something after the
     subtype wasn't a parameter, and was left out, as the specification
     says to leave out parameters not understood. *)
  Mime* = RECORD
    type-, subtype-: ARRAY MaxName + 1 OF CHAR;
    params-: Parameters;
    count-: INTEGER;
    assumed-, skipped-: BOOLEAN
  END;

PROCEDURE Fail(VAR why: ARRAY OF CHAR; reason-: ARRAY OF CHAR): BOOLEAN;
BEGIN COPY(reason, why); RETURN FALSE
END Fail;

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
  RETURN n
END Length;

PROCEDURE Digit(c: CHAR): BOOLEAN;
BEGIN RETURN (c >= "0") & (c <= "9")
END Digit;

PROCEDURE Space(c: CHAR): BOOLEAN;
BEGIN RETURN (c = " ") OR (c = Tab)
END Space;

PROCEDURE Lower(c: CHAR): CHAR;
BEGIN
  IF (c >= "A") & (c <= "Z") THEN c := CHR(ORD(c) + 32) END;
  RETURN c
END Lower;

(* Whether s[0..n-1], UTF-8, holds a control character: C0, DEL, or
   C1 (U+0080..U+009F, C2 80..C2 9F in UTF-8). *)
PROCEDURE Controls(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < n) & (s[i] >= " ") & (s[i] # 7FX)
      & ~((s[i] = 0C2X) & (i + 1 < n) & (s[i + 1] >= 80X) & (s[i + 1] <= 9FX)) DO
    INC(i)
  END;
  RETURN i < n
END Controls;

(* Whether buf[0..len-1] holds as much as Parse needs: a header's end
   within MaxHeader bytes, n the bytes up to and including its LF; or
   MaxHeader bytes without one, n MaxHeader, which Parse refuses. A
   client reads until it gives TRUE, then gives buf[0..n-1] to Parse;
   the body begins at n. *)
PROCEDURE Ended*(buf-: ARRAY OF CHAR; len: LONGINT; VAR n: LONGINT): BOOLEAN;
  VAR i: LONGINT; ended: BOOLEAN;
BEGIN
  ASSERT((len >= 0) & (len <= LEN(buf)), BadRange);
  i := 0; WHILE (i < len) & (i < MaxHeader) & (buf[i] # LF) DO INC(i) END;
  IF (i < len) & (i < MaxHeader) THEN n := i + 1; ended := TRUE
  ELSIF i = MaxHeader THEN n := MaxHeader; ended := TRUE
  ELSE n := 0; ended := FALSE
  END;
  RETURN ended
END Ended;

(* The header line[0..len-1], CR LF and all: its status and meta in h,
   or FALSE and why, h's status 0. *)
PROCEDURE Parse*(line-: ARRAY OF CHAR; len: LONGINT; VAR h: Header;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR e, m, k: LONGINT; s: INTEGER; ok: BOOLEAN;
BEGIN
  ASSERT((len >= 0) & (len <= LEN(line)), BadRange);
  h.status := 0; h.meta[0] := 0X;
  e := 0; WHILE (e < len) & (line[e] # LF) DO INC(e) END;
  IF (len >= 3) & (line[0] = 0EFX) & (line[1] = 0BBX) & (line[2] = 0BFX) THEN
    ok := Fail(why, "a byte order mark")
  ELSIF (e = len) & (len >= MaxHeader) THEN
    ok := Fail(why, "no line end within the header's 1029 bytes")
  ELSIF e = len THEN ok := Fail(why, "no line end")
  ELSIF (e = 0) OR (line[e - 1] # CR) THEN ok := Fail(why, "a line end without CR")
  ELSIF e + 1 < len THEN ok := Fail(why, "more than the header")
  ELSIF (e < 3) OR ~Digit(line[0]) OR ~Digit(line[1]) THEN ok := Fail(why, "no status")
  ELSIF (e > 3) & Digit(line[2]) THEN ok := Fail(why, "a status of more than two digits")
  ELSE
    (* the status in line[0..1], the meta, if any, in line[3..e-2] *)
    s := (ORD(line[0]) - ORD("0")) * 10 + ORD(line[1]) - ORD("0");
    IF e > 3 THEN m := e - 4 ELSE m := 0 END;
    IF ~GeminiStatus.Valid(s) THEN ok := Fail(why, "a status outside 10..69")
    ELSIF (e > 3) & (line[2] # " ") THEN ok := Fail(why, "no space after the status")
    ELSIF m > MaxMeta THEN ok := Fail(why, "a meta of more than 1024 bytes")
    ELSE
      k := 0; WHILE k < m DO h.meta[k] := line[3 + k]; INC(k) END;
      h.meta[m] := 0X;
      IF ~GeminiUrls.Utf8(h.meta, m) THEN ok := Fail(why, "a meta that isn't UTF-8")
      ELSIF Controls(h.meta, m) THEN ok := Fail(why, "a control character in the meta")
      ELSIF (m = 0) & (s DIV 10 = GeminiStatus.InputClass) THEN
        ok := Fail(why, "input with no prompt")
      ELSIF (m = 0) & (s DIV 10 = GeminiStatus.RedirectClass) THEN
        ok := Fail(why, "a redirect with no URL")
      ELSE ok := TRUE; h.status := s
      END;
      IF ~ok THEN h.meta[0] := 0X END
    END
  END;
  RETURN ok
END Parse;

(* The header for status and meta ("" for none) in line[0..len-1], 0X
   after. Halts on a status the specification doesn't name (servers
   MUST NOT send one), and on a meta the specification forbids: longer
   than MaxMeta, not UTF-8, with a control character, or empty after
   a status of input, success or a redirect. *)
PROCEDURE WriteHeader*(status: INTEGER; meta-: ARRAY OF CHAR; VAR line: Line;
    VAR len: LONGINT);
  VAR n, i: LONGINT;
BEGIN
  ASSERT(GeminiStatus.Known(status), BadStatus);
  n := Length(meta);
  ASSERT(n <= MaxMeta, BadMeta);
  ASSERT(GeminiUrls.Utf8(meta, n) & ~Controls(meta, n), BadMeta);
  ASSERT((n > 0) OR (status >= GeminiStatus.TemporaryFailure), BadMeta);
  line[0] := CHR(ORD("0") + status DIV 10); line[1] := CHR(ORD("0") + status MOD 10);
  len := 2;
  IF n > 0 THEN
    line[2] := " "; len := 3;
    i := 0; WHILE i < n DO line[len] := meta[i]; INC(len); INC(i) END
  END;
  line[len] := CR; line[len + 1] := LF; INC(len, 2); line[len] := 0X
END WriteHeader;

(* RFC 2045's token: any printable ASCII but a space and its tspecials. *)
PROCEDURE TokenChar(c: CHAR): BOOLEAN;
BEGIN
  RETURN (c > " ") & (c < 7FX) & (c # "(") & (c # ")") & (c # "<") & (c # ">")
    & (c # "@") & (c # ",") & (c # ";") & (c # ":") & (c # "\") & (c # 22X)
    & (c # "/") & (c # "[") & (c # "]") & (c # "?") & (c # "=")
END TokenChar;

PROCEDURE SkipSpace(s-: ARRAY OF CHAR; VAR i: LONGINT; n: LONGINT);
BEGIN WHILE (i < n) & Space(s[i]) DO INC(i) END
END SkipSpace;

(* A token at s[i..], lower case, into t: FALSE if empty or too long. *)
PROCEDURE Name(s-: ARRAY OF CHAR; VAR i: LONGINT; n: LONGINT; VAR t: ARRAY OF CHAR): BOOLEAN;
  VAR k: LONGINT;
BEGIN
  k := 0;
  WHILE (i < n) & TokenChar(s[i]) DO
    IF k < LEN(t) - 1 THEN t[k] := Lower(s[i]) END;
    INC(k); INC(i)
  END;
  IF k < LEN(t) THEN t[k] := 0X ELSE t[LEN(t) - 1] := 0X END;
  RETURN (k > 0) & (k < LEN(t))
END Name;

(* Past the next ";" not inside quotes, or to n. *)
PROCEDURE SkipParam(s-: ARRAY OF CHAR; VAR i: LONGINT; n: LONGINT);
  VAR quoted: BOOLEAN;
BEGIN
  quoted := FALSE;
  WHILE (i < n) & (quoted OR (s[i] # ";")) DO
    IF s[i] = 22X THEN quoted := ~quoted
    ELSIF quoted & (s[i] = "\") & (i + 1 < n) THEN INC(i)
    END;
    INC(i)
  END
END SkipParam;

(* A parameter at s[i..] (after a ";" and any whitespace), added to m
   if it is one; i is left at the next ";", or n. *)
PROCEDURE ParseParam(s-: ARRAY OF CHAR; VAR i: LONGINT; n: LONGINT; VAR m: Mime);
  VAR ns, ne, k: LONGINT; good: BOOLEAN; v: Chars;
BEGIN
  ns := i; WHILE (i < n) & TokenChar(s[i]) DO INC(i) END; ne := i;
  SkipSpace(s, i, n);  (* RFC 822's tokens, which RFC 2045's are, may be spaced *)
  good := (ne > ns) & (i < n) & (s[i] = "=");
  IF good THEN
    INC(i); SkipSpace(s, i, n); NEW(v, n - i + 1); k := 0;
    IF (i < n) & (s[i] = 22X) THEN
      INC(i);
      WHILE (i < n) & (s[i] # 22X) DO
        IF (s[i] = "\") & (i + 1 < n) THEN INC(i) END;
        v[k] := s[i]; INC(k); INC(i)
      END;
      good := i < n;
      IF good THEN INC(i) END
    ELSE
      WHILE (i < n) & TokenChar(s[i]) DO v[k] := s[i]; INC(k); INC(i) END;
      good := k > 0
    END;
    v[k] := 0X;
    SkipSpace(s, i, n);
    good := good & ((i = n) OR (s[i] = ";"))
  END;
  IF good THEN
    NEW(m.params[m.count].name, ne - ns + 1);
    k := 0; WHILE ns + k < ne DO m.params[m.count].name[k] := Lower(s[ns + k]); INC(k) END;
    m.params[m.count].name[k] := 0X;
    NEW(m.params[m.count].value, Length(v^) + 1); COPY(v^, m.params[m.count].value^);
    INC(m.count)
  ELSE m.skipped := TRUE; SkipParam(s, i, n)
  END
END ParseParam;

(* meta as a MIME type (RFC 2045, "type/subtype; name=value; ..."), as
   a success's header gives it: FALSE, and why, if it has no type and
   subtype. An empty meta is "text/gemini; charset=utf-8" (assumed). *)
PROCEDURE ParseMime*(meta-: ARRAY OF CHAR; VAR m: Mime; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR i, n, k, semis: LONGINT; ok: BOOLEAN;
BEGIN
  m.type[0] := 0X; m.subtype[0] := 0X; m.params := NIL; m.count := 0;
  m.assumed := FALSE; m.skipped := FALSE;
  n := Length(meta);
  WHILE (n > 0) & Space(meta[n - 1]) DO DEC(n) END;
  i := 0; SkipSpace(meta, i, n);
  IF i = n THEN
    m.assumed := TRUE; m.type := "text"; m.subtype := "gemini";
    NEW(m.params, 1); m.count := 1;
    NEW(m.params[0].name, 8); COPY("charset", m.params[0].name^);
    NEW(m.params[0].value, 6); COPY("utf-8", m.params[0].value^);
    ok := TRUE
  ELSIF ~TokenChar(meta[i]) THEN ok := Fail(why, "no MIME type")
  ELSIF ~Name(meta, i, n, m.type) THEN ok := Fail(why, "a MIME type of more than 127 bytes")
  ELSIF (i = n) OR (meta[i] # "/") THEN ok := Fail(why, "no MIME subtype")
  ELSE
    INC(i);
    IF (i = n) OR ~TokenChar(meta[i]) THEN ok := Fail(why, "no MIME subtype")
    ELSIF ~Name(meta, i, n, m.subtype) THEN ok := Fail(why, "a MIME subtype of more than 127 bytes")
    ELSE
      ok := TRUE;
      (* a parameter follows a ";", so there are at most as many *)
      semis := 0; k := i;
      WHILE k < n DO IF meta[k] = ";" THEN INC(semis) END; INC(k) END;
      NEW(m.params, semis + 1);
      SkipSpace(meta, i, n);
      WHILE i < n DO
        IF meta[i] = ";" THEN
          INC(i); SkipSpace(meta, i, n);
          IF (i < n) & (meta[i] # ";") THEN ParseParam(meta, i, n, m) END
        ELSE m.skipped := TRUE; SkipParam(meta, i, n)
        END
      END
    END
  END;
  IF ~ok THEN m.type[0] := 0X; m.subtype[0] := 0X END;
  RETURN ok
END ParseMime;

(* Whether a and b are the same, ASCII letters' case aside. *)
PROCEDURE Same(a-, b-: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(a)) & (i < LEN(b)) & (a[i] # 0X) & (Lower(a[i]) = Lower(b[i])) DO INC(i) END;
  RETURN ((i = LEN(a)) OR (a[i] = 0X)) & ((i = LEN(b)) OR (b[i] = 0X))
END Same;

(* Whether m is type/subtype, case aside: Is(m, "text", "gemini"). *)
PROCEDURE Is*(m-: Mime; type-, subtype-: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Same(m.type, type) & Same(m.subtype, subtype)
END Is;

(* The value of m's first parameter called name (case aside), cut to
   fit value, or FALSE if it has none. *)
PROCEDURE Param*(m-: Mime; name-: ARRAY OF CHAR; VAR value: ARRAY OF CHAR): BOOLEAN;
  VAR i: INTEGER;
BEGIN
  i := 0; WHILE (i < m.count) & ~Same(m.params[i].name^, name) DO INC(i) END;
  IF i < m.count THEN COPY(m.params[i].value^, value) ELSE value[0] := 0X END;
  RETURN i < m.count
END Param;

(* m's charset, in lower case: its parameter's, or "utf-8" for a text
   type without one, as the specification says ("Success"); "" for
   any other type without one. *)
PROCEDURE Charset*(m-: Mime; VAR cs: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  IF ~Param(m, "charset", cs) & (m.type = "text") THEN COPY("utf-8", cs) END;
  i := 0; WHILE (i < LEN(cs)) & (cs[i] # 0X) DO cs[i] := Lower(cs[i]); INC(i) END
END Charset;

END GeminiHeaders.
