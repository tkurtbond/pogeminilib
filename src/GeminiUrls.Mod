MODULE GeminiUrls; (* URLs: parsed, checked, resolved and written *)

(* Two views of a URL. A client's (Parse, Resolve, Write, WithQuery,
   RequestLine) is lenient, since links in a page are what their authors
   wrote: any scheme, userinfo, a fragment, and any character but a
   space or a control character, kept as written. A server's
   (CheckRequest) is strict: pogemini's GemRequest, carried over, which
   refuses what the Gemini specification says a server must, and gives
   the path decoded and normalised, ready to be looked up.

   A URL may hold non-ASCII characters as UTF-8, as an IRI (RFC 3987)
   does; malformed UTF-8 is refused. What goes on the wire is ASCII
   (the specification's "absolute-URI" is RFC 3986's): RequestLine
   percent-encodes the rest of the path and query, and gives the host
   as GeminiPunycode.ToAscii does.

   Every URL is at most MaxURL bytes, as a request's must be: a longer
   one could never be fetched. Nothing here halts: what can't be done
   gives FALSE (or a status) and the reason in why. *)

IMPORT GeminiPunycode;

CONST
  MaxURL* = 1024;      (* a URL at most, by the specification *)
  DefaultPort* = 1965;
  NoPort* = -1;        (* a URL with no port: Port gives the scheme's *)
  Ok* = 0;
  BadRequest* = 59;    (* not a URL, or one the specification forbids *)
  Refused* = 53;       (* not a gemini: URL *)

TYPE
  Text* = ARRAY MaxURL + 1 OF CHAR;

  (* A URL, as Parse or Resolve gives it: each part as written (path,
     query and fragment still percent-encoded) but the scheme and host,
     which are lower case, and the host, which is decoded, with no
     brackets round an IPv6 address and no "." at its end. *)
  URL* = RECORD
    scheme-: ARRAY 64 OF CHAR;
    hasAuthority-: BOOLEAN;     (* a "//", so a host, even an empty one *)
    hasUserinfo-: BOOLEAN;
    userinfo-: ARRAY 256 OF CHAR;
    host-: ARRAY 256 OF CHAR;
    port-: LONGINT;             (* NoPort if none was given *)
    path-: Text;                (* "" for none *)
    hasQuery-: BOOLEAN;         (* a "?", perhaps with nothing after *)
    query-: Text;
    hasFragment-: BOOLEAN;
    fragment-: Text
  END;

  (* A request, as CheckRequest gives it: a server's view. *)
  Request* = RECORD
    scheme-: ARRAY 64 OF CHAR;  (* lower case *)
    host-: ARRAY 256 OF CHAR;   (* lower case, decoded, with no
                                   final "." and an IPv6 address
                                   without its brackets *)
    port-: LONGINT;             (* DefaultPort if none was given *)
    path-: Text;                (* decoded and normalised: CheckRequest *)
    rawPath-: Text;             (* as sent, "" for none *)
    hasQuery-: BOOLEAN;         (* there was a "?", perhaps with nothing after *)
    query-: Text                (* after the "?", as sent *)
  END;

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END; RETURN n
END Length;

PROCEDURE Alpha(c: CHAR): BOOLEAN;
BEGIN RETURN (CAP(c) >= "A") & (CAP(c) <= "Z")
END Alpha;

PROCEDURE Digit(c: CHAR): BOOLEAN;
BEGIN RETURN (c >= "0") & (c <= "9")
END Digit;

(* The value of hex digit c, or -1 *)
PROCEDURE Hex(c: CHAR): INTEGER;
BEGIN
  IF Digit(c) THEN RETURN ORD(c) - ORD("0")
  ELSIF (CAP(c) >= "A") & (CAP(c) <= "F") THEN RETURN ORD(CAP(c)) - ORD("A") + 10
  ELSE RETURN -1
  END
END Hex;

PROCEDURE Lower(c: CHAR): CHAR;
BEGIN
  IF (c >= "A") & (c <= "Z") THEN RETURN CHR(ORD(c) + 32) ELSE RETURN c END
END Lower;

(* c is RFC 3986's unreserved: never encoded. *)
PROCEDURE Unreserved(c: CHAR): BOOLEAN;
BEGIN
  RETURN Alpha(c) OR Digit(c) OR (c = "-") OR (c = ".") OR (c = "_") OR (c = "~")
END Unreserved;

(* c may appear in a URL as itself: RFC 3986's unreserved, gen-delims
   and sub-delims, "%", and every byte of a non-ASCII character. *)
PROCEDURE UrlChar(c: CHAR): BOOLEAN;
BEGIN
  RETURN Unreserved(c) OR (c >= 80X)
    OR (c = ":") OR (c = "/") OR (c = "?") OR (c = "#") OR (c = "[") OR (c = "]") OR (c = "@")
    OR (c = "!") OR (c = "$") OR (c = "&") OR (c = "'") OR (c = "(") OR (c = ")")
    OR (c = "*") OR (c = "+") OR (c = ",") OR (c = ";") OR (c = "=") OR (c = "%")
END UrlChar;

(* s[0..n-1] is well-formed UTF-8 (RFC 3629): no overlong forms, no
   surrogates, nothing over U+10FFFF. *)
PROCEDURE Utf8*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
  VAR i, k: LONGINT; c: INTEGER; lo, hi: CHAR;
BEGIN
  i := 0;
  WHILE i < n DO
    c := ORD(s[i]); lo := 80X; hi := 0BFX;
    IF c < 80H THEN k := 0
    ELSIF (c >= 0C2H) & (c <= 0DFH) THEN k := 1
    ELSIF c = 0E0H THEN k := 2; lo := 0A0X
    ELSIF c = 0EDH THEN k := 2; hi := 9FX
    ELSIF (c >= 0E1H) & (c <= 0EFH) THEN k := 2
    ELSIF c = 0F0H THEN k := 3; lo := 90X
    ELSIF c = 0F4H THEN k := 3; hi := 8FX
    ELSIF (c >= 0F1H) & (c <= 0F3H) THEN k := 3
    ELSE RETURN FALSE
    END;
    INC(i);
    IF k > 0 THEN
      IF (i >= n) OR (s[i] < lo) OR (s[i] > hi) THEN RETURN FALSE END;
      INC(i); DEC(k);
      WHILE k > 0 DO
        IF (i >= n) OR (s[i] < 80X) OR (s[i] > 0BFX) THEN RETURN FALSE END;
        INC(i); DEC(k)
      END
    END
  END;
  RETURN TRUE
END Utf8;

(* Decodes s[from..to-1]'s percent-encoding into d, 0X-terminated, and
   its length into n: FALSE if a "%" isn't followed by two hex digits.
   d has room: decoding never lengthens. *)
PROCEDURE DecodePart(s-: ARRAY OF CHAR; from, to: LONGINT;
    VAR d: ARRAY OF CHAR; VAR n: LONGINT): BOOLEAN;
  VAR i: LONGINT; h, l: INTEGER;
BEGIN
  i := from; n := 0;
  WHILE i < to DO
    IF s[i] = "%" THEN
      IF i + 2 >= to THEN RETURN FALSE END;
      h := Hex(s[i + 1]); l := Hex(s[i + 2]);
      IF (h < 0) OR (l < 0) THEN RETURN FALSE END;
      d[n] := CHR(h * 16 + l); INC(i, 3)
    ELSE d[n] := s[i]; INC(i)
    END;
    INC(n)
  END;
  d[n] := 0X;
  RETURN TRUE
END DecodePart;

(* Decodes s's percent-encoding (a query's, say) into d: FALSE if a "%"
   isn't followed by two hex digits, or the result doesn't fit d. The
   result may contain any byte, 0X included, so n is its length. *)
PROCEDURE Decode*(s-: ARRAY OF CHAR; VAR d: ARRAY OF CHAR; VAR n: LONGINT): BOOLEAN;
  VAR m: LONGINT;
BEGIN
  m := Length(s);
  (* Decoding never lengthens. *)
  IF m >= LEN(d) THEN n := 0; IF LEN(d) > 0 THEN d[0] := 0X END; RETURN FALSE END;
  RETURN DecodePart(s, 0, m, d, n)
END Decode;

(* Appends c to s at s[p], moving p on: FALSE if it doesn't fit with a
   0X after it. *)
PROCEDURE Put(c: CHAR; VAR s: ARRAY OF CHAR; VAR p: LONGINT): BOOLEAN;
BEGIN
  IF p + 1 >= LEN(s) THEN RETURN FALSE END;
  s[p] := c; INC(p); RETURN TRUE
END Put;

(* Appends t, to its 0X, to s at s[p]. *)
PROCEDURE PutString(t-: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; VAR p: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(t)) & (t[i] # 0X) DO
    IF ~Put(t[i], s, p) THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END PutString;

(* The upper-case hex digit for d, 0..15. *)
PROCEDURE HexDigit(d: INTEGER): CHAR;
BEGIN
  IF d < 10 THEN RETURN CHR(ORD("0") + d) ELSE RETURN CHR(ORD("A") + d - 10) END
END HexDigit;

(* Appends c to s at s[p] as "%" and two upper-case hex digits. *)
PROCEDURE PutEscape(c: CHAR; VAR s: ARRAY OF CHAR; VAR p: LONGINT): BOOLEAN;
BEGIN
  RETURN Put("%", s, p) & Put(HexDigit(ORD(c) DIV 16), s, p) & Put(HexDigit(ORD(c) MOD 16), s, p)
END PutEscape;

(* Percent-encodes s, to its 0X, into out: every byte but RFC 3986's
   unreserved (letters, digits, "-", ".", "_", "~"), so a space is
   "%20" and a line feed "%0A", as the specification asks of an input
   answer. FALSE, out empty, if it doesn't fit out. *)
PROCEDURE Encode*(s-: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
  VAR i, p: LONGINT; ok: BOOLEAN;
BEGIN
  i := 0; p := 0; ok := TRUE;
  WHILE ok & (i < LEN(s)) & (s[i] # 0X) DO
    IF Unreserved(s[i]) THEN ok := Put(s[i], out, p) ELSE ok := PutEscape(s[i], out, p) END;
    INC(i)
  END;
  IF ok THEN out[p] := 0X ELSIF LEN(out) > 0 THEN out[0] := 0X END;
  RETURN ok
END Encode;

PROCEDURE Fail(VAR why: ARRAY OF CHAR; reason-: ARRAY OF CHAR): BOOLEAN;
BEGIN COPY(reason, why); RETURN FALSE
END Fail;

(* d := s[from..to-1]; d is large enough. *)
PROCEDURE Part(s-: ARRAY OF CHAR; from, to: LONGINT; VAR d: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE from + i < to DO d[i] := s[from + i]; INC(i) END;
  d[i] := 0X
END Part;

PROCEDURE Clear(VAR u: URL);
BEGIN
  u.scheme := ""; u.hasAuthority := FALSE; u.hasUserinfo := FALSE; u.userinfo := "";
  u.host := ""; u.port := NoPort; u.path := ""; u.hasQuery := FALSE; u.query := "";
  u.hasFragment := FALSE; u.fragment := ""
END Clear;

(* Parses the authority s[i..end-1] into u's userinfo, host and port. *)
PROCEDURE Authority(s-: ARRAY OF CHAR; i, end: LONGINT; VAR u: URL;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR j, h, m: LONGINT; d: ARRAY 256 OF CHAR; c: CHAR;
BEGIN
  (* userinfo "@", to the last "@", as browsers take it *)
  j := end - 1; WHILE (j >= i) & (s[j] # "@") DO DEC(j) END;
  IF j >= i THEN
    IF j - i >= LEN(u.userinfo) THEN RETURN Fail(why, "the userinfo is too long") END;
    u.hasUserinfo := TRUE; Part(s, i, j, u.userinfo); i := j + 1
  END;
  (* host *)
  IF (i < end) & (s[i] = "[") THEN
    (* An IPv6 address, lower case, without its brackets. *)
    j := i + 1;
    WHILE (j < end) & ((Hex(s[j]) >= 0) OR (s[j] = ":") OR (s[j] = ".")) DO INC(j) END;
    IF (j = end) OR (s[j] # "]") OR (j = i + 1) OR (j - i > LEN(u.host)) THEN
      RETURN Fail(why, "a malformed IPv6 address")
    END;
    h := 0; m := i + 1; WHILE m < j DO u.host[h] := Lower(s[m]); INC(h); INC(m) END;
    u.host[h] := 0X;
    i := j + 1
  ELSE
    j := i; WHILE (j < end) & (s[j] # ":") DO INC(j) END;
    IF j - i >= LEN(d) THEN RETURN Fail(why, "the host is too long") END;
    IF ~DecodePart(s, i, j, d, m) THEN RETURN Fail(why, "bad percent-encoding in the host") END;
    (* Nothing that would read as another part once the host is written
       again, decoded. *)
    h := 0;
    WHILE h < m DO
      c := d[h];
      IF (c <= " ") OR (c = 7FX) OR (c = "/") OR (c = "?") OR (c = "#") OR (c = "[") OR (c = "]")
          OR (c = "@") OR (c = ":") OR (c = "%") THEN
        RETURN Fail(why, "a malformed host")
      END;
      u.host[h] := Lower(c); INC(h)
    END;
    IF ~Utf8(d, m) THEN RETURN Fail(why, "the host is not UTF-8") END;
    (* "example.org." is "example.org", which SNI needs (RFC 6066) and
       the known-hosts file keeps once. *)
    IF (h > 1) & (u.host[h - 1] = ".") THEN DEC(h) END;
    u.host[h] := 0X;
    i := j
  END;
  (* ":" port, empty meaning none *)
  IF i < end THEN
    IF s[i] # ":" THEN RETURN Fail(why, "a malformed host") END;
    INC(i);
    IF i < end THEN
      u.port := 0;
      WHILE i < end DO
        IF ~Digit(s[i]) THEN RETURN Fail(why, "a malformed port") END;
        u.port := u.port * 10 + ORD(s[i]) - ORD("0");
        IF u.port > 65535 THEN RETURN Fail(why, "a malformed port") END;
        INC(i)
      END
    END
  END;
  RETURN TRUE
END Authority;

(* Splits s into u by RFC 3986's grammar (appendix B), as a URL if
   absolute, else as a reference, whose scheme may be missing. *)
PROCEDURE Split(s-: ARRAY OF CHAR; absolute: BOOLEAN; VAR u: URL;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR n, i, j: LONGINT;
BEGIN
  Clear(u);
  n := Length(s);
  IF n > MaxURL THEN RETURN Fail(why, "the URL is over 1024 bytes") END;
  IF absolute & (n = 0) THEN RETURN Fail(why, "no URL") END;
  i := 0;
  WHILE i < n DO
    IF (s[i] <= " ") OR (s[i] = 7FX) THEN RETURN Fail(why, "a space or control character in the URL") END;
    INC(i)
  END;
  IF ~Utf8(s, n) THEN RETURN Fail(why, "the URL is not UTF-8") END;

  (* scheme ":", which a reference may leave out *)
  i := 0;
  WHILE (i < n) & (Alpha(s[i]) OR (i > 0) & (Digit(s[i]) OR (s[i] = "+")
      OR (s[i] = "-") OR (s[i] = "."))) DO
    INC(i)
  END;
  IF (i > 0) & (i < n) & (s[i] = ":") THEN
    IF i >= LEN(u.scheme) THEN RETURN Fail(why, "the scheme is too long") END;
    j := 0; WHILE j < i DO u.scheme[j] := Lower(s[j]); INC(j) END;
    u.scheme[i] := 0X;
    INC(i)
  ELSIF absolute THEN RETURN Fail(why, "not an absolute URL")
  ELSE i := 0
  END;

  (* "//" authority *)
  IF (i + 1 < n) & (s[i] = "/") & (s[i + 1] = "/") THEN
    u.hasAuthority := TRUE; INC(i, 2);
    j := i; WHILE (j < n) & (s[j] # "/") & (s[j] # "?") & (s[j] # "#") DO INC(j) END;
    IF ~Authority(s, i, j, u, why) THEN RETURN FALSE END;
    i := j
  END;

  (* path, "?" query, "#" fragment *)
  j := i; WHILE (j < n) & (s[j] # "?") & (s[j] # "#") DO INC(j) END;
  Part(s, i, j, u.path); i := j;
  IF (i < n) & (s[i] = "?") THEN
    u.hasQuery := TRUE;
    j := i + 1; WHILE (j < n) & (s[j] # "#") DO INC(j) END;
    Part(s, i + 1, j, u.query); i := j
  END;
  IF i < n THEN u.hasFragment := TRUE; Part(s, i + 1, n, u.fragment) END;
  RETURN TRUE
END Split;

(* Parses s, an absolute URL with any scheme, into u: FALSE, with why,
   if it is over MaxURL bytes, has no scheme, has a space or control
   character or malformed UTF-8, or its host or port is malformed.
   Nothing else is checked: Gemini's rules are RequestLine's. *)
PROCEDURE Parse*(s-: ARRAY OF CHAR; VAR u: URL; VAR why: ARRAY OF CHAR): BOOLEAN;
BEGIN
  why[0] := 0X;
  IF Split(s, TRUE, u, why) THEN RETURN TRUE END;
  Clear(u); RETURN FALSE
END Parse;

(* u's port, or the scheme's if it has none: 1965 for gemini, else
   NoPort. *)
PROCEDURE Port*(VAR u: URL): LONGINT;
BEGIN
  IF u.port # NoPort THEN RETURN u.port
  ELSIF u.scheme = "gemini" THEN RETURN DefaultPort
  ELSE RETURN NoPort
  END
END Port;

(* Appends the port n to s at s[p]. *)
PROCEDURE PutPort(n: LONGINT; VAR s: ARRAY OF CHAR; VAR p: LONGINT): BOOLEAN;
  VAR d: ARRAY 8 OF CHAR; i: INTEGER; ok: BOOLEAN;
BEGIN
  i := 0; REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  ok := Put(":", s, p);
  WHILE ok & (i > 0) DO DEC(i); ok := Put(d[i], s, p) END;
  RETURN ok
END PutPort;

(* An IPv6 address, the only host with a ":". *)
PROCEDURE IPv6(host-: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE (i < LEN(host)) & (host[i] # 0X) & (host[i] # ":") DO INC(i) END;
  RETURN (i < LEN(host)) & (host[i] = ":")
END IPv6;

(* Writes u back as text, by RFC 3986 section 5.3, into s: FALSE, s
   empty, if it doesn't fit. The host is written as Parse keeps it (so
   not as punycode: RequestLine does that). *)
PROCEDURE Write*(VAR u: URL; VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR p: LONGINT; ok: BOOLEAN;
BEGIN
  p := 0; ok := TRUE;
  IF u.scheme # "" THEN ok := PutString(u.scheme, s, p) & Put(":", s, p) END;
  IF ok & u.hasAuthority THEN
    ok := Put("/", s, p) & Put("/", s, p);
    IF ok & u.hasUserinfo THEN ok := PutString(u.userinfo, s, p) & Put("@", s, p) END;
    IF ok & IPv6(u.host) THEN ok := Put("[", s, p) & PutString(u.host, s, p) & Put("]", s, p)
    ELSIF ok THEN ok := PutString(u.host, s, p)
    END;
    IF ok & (u.port # NoPort) THEN ok := PutPort(u.port, s, p) END
  END;
  ok := ok & PutString(u.path, s, p);
  IF ok & u.hasQuery THEN ok := Put("?", s, p) & PutString(u.query, s, p) END;
  IF ok & u.hasFragment THEN ok := Put("#", s, p) & PutString(u.fragment, s, p) END;
  IF ok THEN s[p] := 0X ELSIF LEN(s) > 0 THEN s[0] := 0X END;
  RETURN ok
END Write;

(* RFC 3986 section 5.2.4: path with its "." and ".." segments removed.
   A ".." at the root is dropped, so a path never climbs above it (the
   client's way; CheckRequest refuses one instead). *)
PROCEDURE RemoveDots(VAR path: Text);
  VAR in: Text; n, i, j, o: LONGINT;
  PROCEDURE At(k: LONGINT; c: CHAR): BOOLEAN;
  BEGIN RETURN (k < n) & (in[k] = c)
  END At;
  PROCEDURE DropLast;
  BEGIN
    WHILE (o > 0) & (path[o - 1] # "/") DO DEC(o) END;
    IF o > 0 THEN DEC(o) END
  END DropLast;
BEGIN
  in := path; n := Length(in); i := 0; o := 0;
  WHILE i < n DO
    IF At(i, ".") & At(i + 1, ".") & At(i + 2, "/") THEN INC(i, 3)          (* A *)
    ELSIF At(i, ".") & At(i + 1, "/") THEN INC(i, 2)
    ELSIF At(i, "/") & At(i + 1, ".") & At(i + 2, "/") THEN INC(i, 2)      (* B *)
    ELSIF At(i, "/") & At(i + 1, ".") & (i + 2 = n) THEN INC(i); in[i] := "/"
    ELSIF At(i, "/") & At(i + 1, ".") & At(i + 2, ".") & At(i + 3, "/") THEN  (* C *)
      INC(i, 3); DropLast
    ELSIF At(i, "/") & At(i + 1, ".") & At(i + 2, ".") & (i + 3 = n) THEN
      INC(i, 2); in[i] := "/"; DropLast
    ELSIF At(i, ".") & (i + 1 = n) THEN i := n                              (* D *)
    ELSIF At(i, ".") & At(i + 1, ".") & (i + 2 = n) THEN i := n
    ELSE                                                                     (* E *)
      j := i; IF in[j] = "/" THEN INC(j) END;
      WHILE (j < n) & (in[j] # "/") DO INC(j) END;
      WHILE i < j DO path[o] := in[i]; INC(o); INC(i) END
    END
  END;
  path[o] := 0X
END RemoveDots;

(* Resolves ref, a URL or a relative reference, against base, by RFC
   3986 section 5.2.2, into u (which may be base itself): FALSE, with
   why, u empty, if ref is malformed or the result is over MaxURL bytes.
   ".." never climbs above the root. *)
PROCEDURE Resolve*(VAR base: URL; ref-: ARRAY OF CHAR; VAR u: URL;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR r, t: POINTER TO URL; s: Text; i, j, k: LONGINT; dots: BOOLEAN;
BEGIN
  why[0] := 0X;
  NEW(r); NEW(t);
  IF ~Split(ref, FALSE, r^, why) THEN Clear(u); RETURN FALSE END;
  t^ := r^; dots := TRUE;
  IF r.scheme = "" THEN
    t.scheme := base.scheme;
    IF ~r.hasAuthority THEN
      t.hasAuthority := base.hasAuthority; t.hasUserinfo := base.hasUserinfo;
      t.userinfo := base.userinfo; t.host := base.host; t.port := base.port;
      IF r.path = "" THEN
        t.path := base.path; dots := FALSE;  (* as base has it, by 5.2.2 *)
        IF ~r.hasQuery THEN t.hasQuery := base.hasQuery; t.query := base.query END
      ELSIF r.path[0] # "/" THEN
        (* Section 5.2.3: merged with base's path. *)
        IF base.hasAuthority & (base.path = "") THEN t.path := "/"; k := 1
        ELSE
          k := Length(base.path); WHILE (k > 0) & (base.path[k - 1] # "/") DO DEC(k) END;
          Part(base.path, 0, k, t.path)
        END;
        i := 0; j := Length(r.path);
        IF k + j > MaxURL THEN Clear(u); RETURN Fail(why, "the URL is over 1024 bytes") END;
        WHILE i < j DO t.path[k] := r.path[i]; INC(k); INC(i) END;
        t.path[k] := 0X
      END
    END
  END;
  IF dots THEN RemoveDots(t.path) END;
  IF ~Write(t^, s) THEN Clear(u); RETURN Fail(why, "the URL is over 1024 bytes") END;
  u := t^;
  RETURN TRUE
END Resolve;

(* Sets u's query to answer, percent-encoded as Encode does, for the
   answer to an input prompt (status 10 or 11), and drops u's fragment,
   which named a place in the prompt's page, not the answer's. FALSE, u
   unchanged, if the encoded answer won't fit. *)
PROCEDURE WithQuery*(VAR u: URL; answer-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR q: Text;
BEGIN
  why[0] := 0X;
  IF ~Encode(answer, q) THEN RETURN Fail(why, "the answer is too long") END;
  u.hasQuery := TRUE; u.query := q; u.hasFragment := FALSE; u.fragment := "";
  RETURN TRUE
END WithQuery;

(* Appends the path or query s to line at line[p], encoding what may not
   be sent as it is: non-ASCII, and ASCII that RFC 3986 doesn't allow
   there. "%" is left, taken as an escape already. *)
PROCEDURE PutEncoded(s-: ARRAY OF CHAR; VAR line: ARRAY OF CHAR; VAR p: LONGINT): BOOLEAN;
  VAR i: LONGINT; c: CHAR; ok: BOOLEAN;
BEGIN
  i := 0; ok := TRUE;
  WHILE ok & (i < LEN(s)) & (s[i] # 0X) DO
    c := s[i];
    IF (c < 80X) & UrlChar(c) & (c # "#") & (c # "[") & (c # "]") THEN ok := Put(c, line, p)
    ELSE ok := PutEscape(c, line, p)
    END;
    INC(i)
  END;
  RETURN ok
END PutEncoded;

PROCEDURE RequestLineOf(VAR u: URL; VAR line: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR t: Text; host: ARRAY 256 OF CHAR; p: LONGINT; reason: ARRAY 128 OF CHAR;
BEGIN
  IF ~u.hasAuthority OR (u.host = "") THEN RETURN Fail(why, "no host") END;
  IF u.hasUserinfo THEN RETURN Fail(why, "userinfo in the URL") END;
  IF IPv6(u.host) THEN COPY(u.host, host)
  ELSIF ~GeminiPunycode.ToAscii(u.host, host, reason) THEN
    (* "the host: " and ToAscii's reason, cut short if why is. *)
    p := 0;
    IF PutString("the host: ", why, p) & PutString(reason, why, p) THEN END;
    IF p < LEN(why) THEN why[p] := 0X END;
    RETURN FALSE
  END;
  p := 0;
  IF ~(PutString(u.scheme, t, p) & Put(":", t, p) & Put("/", t, p) & Put("/", t, p)) THEN
    RETURN Fail(why, "the URL is over 1024 bytes")
  END;
  IF IPv6(host) THEN
    IF ~(Put("[", t, p) & PutString(host, t, p) & Put("]", t, p)) THEN
      RETURN Fail(why, "the URL is over 1024 bytes")
    END
  ELSIF ~PutString(host, t, p) THEN RETURN Fail(why, "the URL is over 1024 bytes")
  END;
  IF (u.port # NoPort) & ~PutPort(u.port, t, p) THEN RETURN Fail(why, "the URL is over 1024 bytes") END;
  IF u.path = "" THEN
    IF ~Put("/", t, p) THEN RETURN Fail(why, "the URL is over 1024 bytes") END
  ELSIF ~PutEncoded(u.path, t, p) THEN RETURN Fail(why, "the URL is over 1024 bytes")
  END;
  IF u.hasQuery & ~(Put("?", t, p) & PutEncoded(u.query, t, p)) THEN
    RETURN Fail(why, "the URL is over 1024 bytes")
  END;
  t[p] := 0X;
  IF p >= LEN(line) THEN RETURN Fail(why, "too long for the buffer") END;
  COPY(t, line);
  RETURN TRUE
END RequestLineOf;

(* The request for u, in line, without its CR LF: u as an absolute URI
   in ASCII, at most MaxURL bytes, with no fragment, as the
   specification's "Requests" says: the host as GeminiPunycode.ToAscii
   gives it, an empty path as "/", and the path and query with non-ASCII
   and what RFC 3986 doesn't allow percent-encoded. FALSE, with why,
   line empty, if u has no host or has userinfo (which Gemini forbids),
   its host can't be converted, or the result is over MaxURL bytes or
   doesn't fit line. *)
PROCEDURE RequestLine*(VAR u: URL; VAR line: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
BEGIN
  why[0] := 0X;
  IF RequestLineOf(u, line, why) THEN RETURN TRUE END;
  IF LEN(line) > 0 THEN line[0] := 0X END;
  RETURN FALSE
END RequestLine;

(* The server's check. *)

PROCEDURE Refuse(VAR why: ARRAY OF CHAR; reason-: ARRAY OF CHAR): INTEGER;
BEGIN COPY(reason, why); RETURN BadRequest
END Refuse;

(* Normalises url[from..to-1], the raw path, into r.path: FALSE, with
   why, if it can't be. *)
PROCEDURE Path(url-: ARRAY OF CHAR; from, to: LONGINT; VAR r: Request;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR seg: Text; i, j, k, n, p: LONGINT; dir: BOOLEAN;
BEGIN
  (* r.path holds "/" and the segments so far, each after a "/"; p is
     its length. dir: the last segment named a directory. *)
  r.path[0] := "/"; p := 1; dir := FALSE;
  i := from;
  IF (i < to) & (url[i] = "/") THEN INC(i) END;
  WHILE i < to DO
    j := i; WHILE (j < to) & (url[j] # "/") DO INC(j) END;
    IF ~DecodePart(url, i, j, seg, n) THEN COPY("bad percent-encoding in the path", why); RETURN FALSE END;
    k := 0;
    WHILE k < n DO
      IF seg[k] = "/" THEN COPY("an encoded / in the path", why); RETURN FALSE
      ELSIF (seg[k] < " ") OR (seg[k] = 7FX) THEN
        COPY("a control character in the path", why); RETURN FALSE
      END;
      INC(k)
    END;
    IF ~Utf8(seg, n) THEN COPY("the path is not UTF-8", why); RETURN FALSE END;
    IF (n = 0) OR (seg = ".") THEN dir := TRUE
    ELSIF seg = ".." THEN
      IF p = 1 THEN COPY("the path climbs above /", why); RETURN FALSE END;
      (* Drop the last segment and its "/". *)
      DEC(p); WHILE r.path[p - 1] # "/" DO DEC(p) END;
      dir := TRUE
    ELSE
      IF p > 1 THEN r.path[p - 1] := "/" END;
      k := 0; WHILE k < n DO r.path[p] := seg[k]; INC(p); INC(k) END;
      INC(p); r.path[p - 1] := "/";  (* the separator, if another segment comes *)
      dir := FALSE
    END;
    i := j + 1;
    (* A path ending in "/" names a directory. *)
    IF j = to - 1 THEN dir := TRUE END
  END;
  (* r.path[0..p-1] ends with "/" whenever it has a segment; keep it
     only for a directory. *)
  IF (p > 1) & ~dir THEN DEC(p) END;
  r.path[p] := 0X;
  RETURN TRUE
END Path;

(* Checks url, a request line without its CR LF, as a server must
   (pogemini's GemRequest): Ok, with r filled in, or BadRequest or
   Refused, with the reason in why, for the response's meta.

   A request is an absolute URI, at most 1024 bytes (the specification,
   "Requests"). Refused with BadRequest (59): what the specification
   says a server must reject (a URL over 1024 bytes, userinfo, a
   fragment) and what is not a URL at all; with Refused (53), a scheme
   other than gemini. Whether the host and port are this server's is
   the caller's to say. Besides RFC 3986's characters, non-ASCII as
   UTF-8 is taken, as an IRI's, since some clients send it.

   r.path is decoded and normalised, ready to be looked up: each
   segment percent-decoded, "." and ".." resolved after decoding (so
   "%2E%2E" is ".." too), empty segments dropped, always beginning with
   "/" (an empty path is "/"). A ".." that would climb above "/", or a
   segment that decodes to "/", a control character or malformed UTF-8,
   is refused (59): none names a file a server should serve, and
   refusing them here means no later code has to remember to. A
   trailing "/" is kept: the client asked for a directory. The query is
   left as sent: Decode decodes it. *)
PROCEDURE CheckRequest*(url-: ARRAY OF CHAR; VAR r: Request; VAR why: ARRAY OF CHAR): INTEGER;
  VAR n, i, j, h, end, m: LONGINT; d: Text;
BEGIN
  why[0] := 0X;
  r.scheme := ""; r.host := ""; r.port := DefaultPort; r.path := "/"; r.rawPath := "";
  r.hasQuery := FALSE; r.query := "";
  n := Length(url);
  IF n > MaxURL THEN RETURN Refuse(why, "the URL is over 1024 bytes") END;
  IF n = 0 THEN RETURN Refuse(why, "no URL") END;
  i := 0;
  WHILE i < n DO
    IF ~UrlChar(url[i]) THEN RETURN Refuse(why, "a character not allowed in a URL") END;
    IF url[i] = "#" THEN RETURN Refuse(why, "a fragment") END;
    INC(i)
  END;
  IF ~Utf8(url, n) THEN RETURN Refuse(why, "the URL is not UTF-8") END;

  (* scheme ":" *)
  i := 0;
  WHILE (i < n) & (Alpha(url[i]) OR (i > 0) & (Digit(url[i]) OR (url[i] = "+")
      OR (url[i] = "-") OR (url[i] = "."))) DO
    INC(i)
  END;
  IF (i = 0) OR (i = n) OR (url[i] # ":") THEN RETURN Refuse(why, "not an absolute URL") END;
  IF i >= LEN(r.scheme) THEN RETURN Refuse(why, "the scheme is too long") END;
  j := 0; WHILE j < i DO r.scheme[j] := Lower(url[j]); INC(j) END;
  r.scheme[i] := 0X;
  IF r.scheme # "gemini" THEN
    COPY("only gemini: URLs are served here", why); RETURN Refused
  END;

  (* "//" authority *)
  INC(i);
  IF (i + 1 >= n) OR (url[i] # "/") OR (url[i + 1] # "/") THEN RETURN Refuse(why, "no host") END;
  INC(i, 2);
  end := i; WHILE (end < n) & (url[end] # "/") & (url[end] # "?") DO INC(end) END;
  j := i; WHILE (j < end) & (url[j] # "@") DO INC(j) END;
  IF j < end THEN RETURN Refuse(why, "userinfo in the URL") END;

  (* host *)
  IF (i < end) & (url[i] = "[") THEN
    (* An IP literal: an IPv6 address, kept as written, lower case. *)
    j := i + 1;
    WHILE (j < end) & ((Hex(url[j]) >= 0) OR (url[j] = ":") OR (url[j] = ".")) DO INC(j) END;
    IF (j = end) OR (url[j] # "]") OR (j = i + 1) OR (j - i > LEN(r.host)) THEN
      RETURN Refuse(why, "a malformed IPv6 address")
    END;
    h := 0; m := i + 1; WHILE m < j DO r.host[h] := Lower(url[m]); INC(h); INC(m) END;
    r.host[h] := 0X;
    i := j + 1
  ELSE
    j := i;
    WHILE (j < end) & (url[j] # ":") DO
      IF (url[j] = "[") OR (url[j] = "]") THEN RETURN Refuse(why, "a malformed host") END;
      INC(j)
    END;
    IF j - i >= LEN(r.host) THEN RETURN Refuse(why, "the host is too long") END;
    IF ~DecodePart(url, i, j, d, m) THEN RETURN Refuse(why, "bad percent-encoding in the host") END;
    h := 0;
    WHILE h < m DO
      IF (d[h] <= " ") OR (d[h] = 7FX) OR (d[h] = "/") THEN RETURN Refuse(why, "a malformed host") END;
      r.host[h] := Lower(d[h]); INC(h)
    END;
    IF ~Utf8(d, m) THEN RETURN Refuse(why, "the host is not UTF-8") END;
    (* "example.org." is "example.org" *)
    IF (h > 1) & (r.host[h - 1] = ".") THEN DEC(h) END;
    r.host[h] := 0X;
    i := j
  END;
  IF r.host = "" THEN RETURN Refuse(why, "no host") END;

  (* ":" port, empty meaning the default *)
  IF i < end THEN
    IF url[i] # ":" THEN RETURN Refuse(why, "a malformed host") END;
    INC(i);
    IF i < end THEN
      r.port := 0;
      WHILE i < end DO
        IF ~Digit(url[i]) THEN RETURN Refuse(why, "a malformed port") END;
        r.port := r.port * 10 + ORD(url[i]) - ORD("0");
        IF r.port > 65535 THEN RETURN Refuse(why, "a malformed port") END;
        INC(i)
      END
    END
  END;

  (* path, then "?" query *)
  end := i; WHILE (end < n) & (url[end] # "?") DO INC(end) END;
  Part(url, i, end, r.rawPath);
  IF ~Path(url, i, end, r, why) THEN RETURN BadRequest END;
  IF end < n THEN
    r.hasQuery := TRUE;
    Part(url, end + 1, n, r.query);
    IF ~Decode(r.query, d, m) THEN RETURN Refuse(why, "bad percent-encoding in the query") END
  END;
  RETURN Ok
END CheckRequest;

END GeminiUrls.
