MODULE GeminiText; (* gemtext, parsed: a line at a time, or a whole page *)

(* Gemtext (text/gemini) as the gemtext specification defines it: each
   line's type from its first three bytes and whether a preformatted
   block is open.

   A Parser takes a page's bytes as they come and gives its lines, in
   memory fixed when it is made: a line longer than its buffer comes out
   in pieces, as much as fits each time, so no line is too long and no
   page too large. A piece never ends inside a UTF-8 character unless
   the bytes there aren't UTF-8. Parse gives a whole page's lines,
   joined, for a program that has the page in memory.

   Nothing here halts on what a page holds: bytes that aren't UTF-8 are
   kept, and flagged; a link with no URL is flagged. A link's URL is
   kept as written, for the program to resolve (GeminiUrls.Resolve).
   Halts are for a program's mistakes (PLAN.md, "Halt codes"). *)

CONST
  (* The kinds of line *)
  Text* = 0;          (* any line no other kind claims; an empty one too *)
  Link* = 1;          (* "=>", a URL, perhaps a label *)
  Heading* = 2;       (* "#", "##" or "###" *)
  ListItem* = 3;      (* "* " *)
  Quote* = 4;         (* ">" *)
  Toggle* = 5;        (* three backticks: opens or closes a block *)
  Preformatted* = 6;  (* a line inside a block *)

  (* The smallest buffer a parser takes. A piece holds a byte less than
     the buffer (its 0X) and may stop up to three bytes short of that,
     so as not to split a character: eight leaves room for a
     four-byte character after a cut, so every piece makes progress. *)
  MinBuffer* = 8;
  (* The longest URL kept: a request is at most 1024 bytes
     (GeminiUrls.MaxURL), so a longer URL can never be fetched. *)
  MaxURL* = 1024;

  BadBuffer = 120;    (* New: a buffer under MinBuffer *)
  BadRange = 121;     (* Feed, Parse: bytes past the array's end *)

  CR = 0DX; LF = 0AX; Tab = 09X;

  (* Where a line is: Head collects its first bytes, to tell its kind;
     Keep keeps the rest; a link skips to its URL, takes it, and skips
     to its label; a heading skips to its text; a closing toggle drops
     the rest. *)
  Head = 0; Keep = 1; SkipToUrl = 2; InUrl = 3; SkipToLabel = 4;
  SkipToText = 5; Drop = 6;

TYPE
  Chars* = POINTER TO ARRAY OF CHAR;

  (* A line, or a piece of one. text[0..len-1] is its text, 0X after:
     a heading's without its "#"s and the spaces or tabs after them; a
     list item's without "* "; a quote's without ">", any whitespace
     after it kept; a link's label, without the whitespace before it; an
     opening toggle's alt text, without the backticks; empty for a
     closing toggle. A page's bytes may hold 0X, so len, not the 0X, is
     the length.

     A line longer than a parser's buffer comes in pieces: first is set
     in the first, last in the last (both in a line of one piece). kind
     and level (1..3 for a heading, else 0) hold for every piece; url,
     noUrl and urlTooLong are a link's first piece's.

     malformed: the piece's text, or a link's URL, holds bytes that
     aren't UTF-8, kept as they came. noUrl: "=>" and nothing more but
     whitespace, a link to show as text or leave out, never to fetch.
     urlTooLong: the URL was longer than MaxURL bytes and url has its
     first MaxURL. *)
  Line* = RECORD
    kind-, level-: INTEGER;
    first-, last-: BOOLEAN;
    malformed-, noUrl-, urlTooLong-: BOOLEAN;
    text-: Chars;
    len-: LONGINT;
    url-: Chars;
    urlLen-: LONGINT
  END;

  Parser* = POINTER TO ParserDesc;
  ParserDesc = RECORD
    out: Chars;                       (* the piece being made *)
    olen, cap: LONGINT;               (* its bytes; at most cap *)
    url: ARRAY MaxURL + 1 OF CHAR;
    ulen: LONGINT;
    urlTooLong: BOOLEAN;
    head: ARRAY 3 OF CHAR;            (* a line's first bytes *)
    hlen: INTEGER;
    phase, kind, level: INTEGER;
    first: BOOLEAN;                   (* the next piece is a line's first *)
    inLine: BOOLEAN;                  (* a line begun and not ended *)
    pre: BOOLEAN;                     (* in a preformatted block *)
    start: BOOLEAN;                   (* at the page's start: a BOM? *)
    cr: BOOLEAN;                      (* a CR held, to see if LF follows *)
    got: BOOLEAN                      (* a piece given this call *)
  END;

  Lines* = POINTER TO ARRAY OF Line;

  (* A page: lines[0..count-1], each whole (first and last both set).
     title is the index of the first heading, -1 if none. *)
  Document* = POINTER TO DocumentDesc;
  DocumentDesc* = RECORD
    lines-: Lines;
    count-: LONGINT;
    title-: LONGINT
  END;

(* Whether s[0..n-1] is UTF-8, by RFC 3629: no overlong form, no
   surrogate, nothing past U+10FFFF. GeminiUrls.Utf8's, so this module
   needs no other. *)
PROCEDURE Utf8(VAR s: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
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

PROCEDURE Reset(p: Parser);
BEGIN
  p.olen := 0; p.ulen := 0; p.urlTooLong := FALSE; p.hlen := 0;
  p.phase := Head; p.kind := Text; p.level := 0; p.first := TRUE;
  p.inLine := FALSE; p.pre := FALSE; p.start := TRUE; p.cr := FALSE;
  p.got := FALSE
END Reset;

(* A parser whose pieces are at most size - 1 bytes; size at least
   MinBuffer, or it halts. *)
PROCEDURE New*(size: LONGINT): Parser;
  VAR p: Parser;
BEGIN
  ASSERT(size >= MinBuffer, BadBuffer);
  NEW(p); NEW(p.out, size); p.cap := size - 1;
  Reset(p);
  RETURN p
END New;

(* How many bytes a character has, from its first byte; 1 for a byte
   that can't begin one, which Utf8 then refuses. *)
PROCEDURE Length(c: CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN
  IF (c >= 0C0X) & (c <= 0DFX) THEN n := 2
  ELSIF (c >= 0E0X) & (c <= 0EFX) THEN n := 3
  ELSIF (c >= 0F0X) & (c <= 0F7X) THEN n := 4
  ELSE n := 1
  END;
  RETURN n
END Length;

(* Where to end a full piece of n bytes: before a character it holds
   only part of. That character's first byte is at most three back, past
   continuation bytes (10xxxxxx); if none is, the bytes aren't UTF-8, or
   end a whole four-byte character, and the piece ends at n. *)
PROCEDURE Cut(VAR s: ARRAY OF CHAR; n: LONGINT): LONGINT;
  VAR j: LONGINT;
BEGIN
  j := n - 1;
  WHILE (j >= n - 3) & (ORD(s[j]) DIV 64 = 2) DO DEC(j) END;
  IF (j >= n - 3) & (Length(s[j]) > n - j) THEN n := j END;
  RETURN n
END Cut;

(* Gives out[0..n-1] as a piece in l, the last of its line if last. *)
PROCEDURE Emit(p: Parser; VAR l: Line; n: LONGINT; last: BOOLEAN);
  VAR i: LONGINT;
BEGIN
  IF (l.text = NIL) OR (LEN(l.text^) < p.cap + 1) THEN NEW(l.text, p.cap + 1) END;
  IF (l.url = NIL) OR (LEN(l.url^) < MaxURL + 1) THEN NEW(l.url, MaxURL + 1) END;
  FOR i := 0 TO n - 1 DO l.text[i] := p.out[i] END;
  l.text[n] := 0X; l.len := n;
  l.kind := p.kind; l.level := p.level; l.first := p.first; l.last := last;
  l.malformed := ~Utf8(l.text^, n);
  IF p.first & (p.kind = Link) THEN
    FOR i := 0 TO p.ulen - 1 DO l.url[i] := p.url[i] END;
    l.url[p.ulen] := 0X; l.urlLen := p.ulen;
    l.noUrl := p.ulen = 0; l.urlTooLong := p.urlTooLong;
    IF ~Utf8(p.url, p.ulen) THEN l.malformed := TRUE END
  ELSE
    l.url[0] := 0X; l.urlLen := 0; l.noUrl := FALSE; l.urlTooLong := FALSE
  END;
  p.first := FALSE; p.got := TRUE
END Emit;

(* Adds c to the piece; a full piece is given first, and the part of a
   character at its end begins the next. *)
PROCEDURE Append(p: Parser; c: CHAR; VAR l: Line);
  VAR k, i: LONGINT;
BEGIN
  IF p.olen = p.cap THEN
    k := Cut(p.out^, p.olen);
    Emit(p, l, k, FALSE);
    i := 0; WHILE k + i < p.olen DO p.out[i] := p.out[k + i]; INC(i) END;
    p.olen := i
  END;
  p.out[p.olen] := c; INC(p.olen)
END Append;

PROCEDURE Space(c: CHAR): BOOLEAN;
BEGIN RETURN (c = " ") OR (c = Tab)
END Space;

(* c, after a line's kind is known. *)
PROCEDURE Rest(p: Parser; c: CHAR; VAR l: Line);
BEGIN
  CASE p.phase OF
    Keep: Append(p, c, l)
  | SkipToUrl:
      IF ~Space(c) THEN p.phase := InUrl; Rest(p, c, l) END
  | InUrl:
      IF Space(c) THEN p.phase := SkipToLabel
      ELSIF p.ulen < MaxURL THEN p.url[p.ulen] := c; INC(p.ulen)
      ELSE p.urlTooLong := TRUE
      END
  | SkipToLabel, SkipToText:
      IF ~Space(c) THEN p.phase := Keep; Append(p, c, l) END
  | Drop:
  END
END Rest;

(* The line's kind, from head[0..hlen-1] (all its bytes, if fewer than
   three), and those bytes after its marker given to Rest. *)
PROCEDURE Classify(p: Parser; VAR l: Line);
  VAR n, i: INTEGER; h: ARRAY 3 OF CHAR;
BEGIN
  n := p.hlen; h := p.head; p.hlen := 0; p.start := FALSE;
  i := 0; p.level := 0; p.phase := Keep;
  IF (n = 3) & (h[0] = "`") & (h[1] = "`") & (h[2] = "`") THEN
    p.kind := Toggle; i := 3;
    IF p.pre THEN p.phase := Drop END;
    p.pre := ~p.pre
  ELSIF p.pre THEN p.kind := Preformatted
  ELSIF (n >= 2) & (h[0] = "=") & (h[1] = ">") THEN
    p.kind := Link; i := 2; p.phase := SkipToUrl; p.ulen := 0; p.urlTooLong := FALSE
  ELSIF (n >= 1) & (h[0] = "#") THEN
    p.kind := Heading; p.phase := SkipToText;
    WHILE (i < n) & (h[i] = "#") DO INC(i) END;
    p.level := i
  ELSIF (n >= 2) & (h[0] = "*") & (h[1] = " ") THEN p.kind := ListItem; i := 2
  ELSIF (n >= 1) & (h[0] = ">") THEN p.kind := Quote; i := 1
  ELSE p.kind := Text
  END;
  WHILE i < n DO Rest(p, h[i], l); INC(i) END
END Classify;

(* c, a byte of a line (not its end). *)
PROCEDURE Content(p: Parser; c: CHAR; VAR l: Line);
BEGIN
  p.inLine := TRUE;
  IF p.phase = Head THEN
    p.head[p.hlen] := c; INC(p.hlen);
    IF p.hlen = 3 THEN
      IF p.start & (p.head[0] = 0EFX) & (p.head[1] = 0BBX) & (p.head[2] = 0BFX) THEN
        (* a byte order mark, skipped (PLAN.md, "Gemtext") *)
        p.hlen := 0; p.start := FALSE; p.inLine := FALSE
      ELSE Classify(p, l)
      END
    END
  ELSE Rest(p, c, l)
  END
END Content;

(* The line ends: its last piece is given. *)
PROCEDURE EndLine(p: Parser; VAR l: Line);
BEGIN
  IF p.phase = Head THEN Classify(p, l) END;
  Emit(p, l, p.olen, TRUE);
  p.olen := 0; p.phase := Head; p.hlen := 0; p.first := TRUE;
  p.inLine := FALSE; p.start := FALSE
END EndLine;

(* Takes bytes from buf[pos..end-1], advancing pos, until a piece is
   ready, which it gives in l (TRUE), or the bytes are used up (FALSE).
   Call it again, with the same bytes and pos, until it gives FALSE,
   then with the next bytes; then Finish. Every byte is used, so the
   parser keeps none of the caller's. l's text and url are made once,
   and given again: copy a piece to keep it. *)
PROCEDURE Feed*(p: Parser; buf-: ARRAY OF CHAR; VAR pos: LONGINT; end: LONGINT;
    VAR l: Line): BOOLEAN;
  VAR c: CHAR;
BEGIN
  ASSERT((pos >= 0) & (end <= LEN(buf)), BadRange);
  p.got := FALSE;
  WHILE ~p.got & (pos < end) DO
    c := buf[pos]; INC(pos);
    IF p.cr THEN
      (* CR LF ends a line; any other CR is a byte of it *)
      p.cr := FALSE;
      IF c = LF THEN EndLine(p, l)
      ELSE
        Content(p, CR, l);
        IF c = CR THEN p.cr := TRUE ELSE Content(p, c, l) END
      END
    ELSIF c = LF THEN EndLine(p, l)
    ELSIF c = CR THEN p.cr := TRUE; p.inLine := TRUE
    ELSE Content(p, c, l)
    END
  END;
  RETURN p.got
END Feed;

(* At the page's end: gives any piece still to come (TRUE), and is
   called until it gives FALSE. A last line need not end in LF, and a
   preformatted block need not be closed. The parser is then ready for
   another page. *)
PROCEDURE Finish*(p: Parser; VAR l: Line): BOOLEAN;
BEGIN
  p.got := FALSE;
  IF p.cr THEN p.cr := FALSE; Content(p, CR, l) END;
  IF ~p.got & p.inLine THEN EndLine(p, l)
  ELSIF ~p.got THEN Reset(p)
  END;
  RETURN p.got
END Finish;

(* A copy of s[0..n-1] in an array of room bytes, 0X after. *)
PROCEDURE Copy(VAR s: ARRAY OF CHAR; n, room: LONGINT): Chars;
  VAR c: Chars; i: LONGINT;
BEGIN
  NEW(c, room);
  FOR i := 0 TO n - 1 DO c[i] := s[i] END;
  c[n] := 0X;
  RETURN c
END Copy;

(* Adds a piece to d: a new line if it is a first, else joined to the
   last. A line's text grows by doubling, so a long line costs no more
   than twice its length to join. *)
PROCEDURE Add(d: Document; VAR l: Line);
  VAR more: Lines; t: Chars; i, room: LONGINT;
BEGIN
  IF l.first THEN
    IF d.count = LEN(d.lines^) THEN
      NEW(more, 2 * d.count);
      FOR i := 0 TO d.count - 1 DO more[i] := d.lines[i] END;
      d.lines := more
    END;
    (* field by field: copying l whole would carry its padding, never
       written, into the heap, where the collector reads every word
       (memcheck reports it) *)
    i := d.count;
    d.lines[i].kind := l.kind; d.lines[i].level := l.level;
    d.lines[i].malformed := l.malformed; d.lines[i].noUrl := l.noUrl;
    d.lines[i].urlTooLong := l.urlTooLong;
    d.lines[i].text := Copy(l.text^, l.len, l.len + 1); d.lines[i].len := l.len;
    d.lines[i].url := Copy(l.url^, l.urlLen, l.urlLen + 1); d.lines[i].urlLen := l.urlLen;
    IF (l.kind = Heading) & (d.title < 0) THEN d.title := d.count END;
    INC(d.count)
  ELSE
    i := d.count - 1;
    IF d.lines[i].len + l.len + 1 > LEN(d.lines[i].text^) THEN
      room := 2 * LEN(d.lines[i].text^);
      IF room < d.lines[i].len + l.len + 1 THEN room := d.lines[i].len + l.len + 1 END;
      t := Copy(d.lines[i].text^, d.lines[i].len, room);
      d.lines[i].text := t
    END;
    t := d.lines[i].text;
    FOR room := 0 TO l.len - 1 DO t[d.lines[i].len + room] := l.text[room] END;
    INC(d.lines[i].len, l.len); t[d.lines[i].len] := 0X;
    IF l.malformed THEN d.lines[i].malformed := TRUE END
  END;
  d.lines[d.count - 1].first := TRUE;
  d.lines[d.count - 1].last := TRUE
END Add;

(* The page text[0..len-1], its lines whole. *)
PROCEDURE Parse*(text-: ARRAY OF CHAR; len: LONGINT): Document;
  VAR d: Document; p: Parser; l: Line; pos: LONGINT;
BEGIN
  ASSERT((len >= 0) & (len <= LEN(text)), BadRange);
  NEW(d); NEW(d.lines, 16); d.count := 0; d.title := -1;
  p := New(4096); pos := 0;
  WHILE Feed(p, text, pos, len, l) DO Add(d, l) END;
  WHILE Finish(p, l) DO Add(d, l) END;
  RETURN d
END Parse;

(* The index of the first link after line i, -1 if none: NextLink(d, -1)
   gives the first. *)
PROCEDURE NextLink*(d: Document; i: LONGINT): LONGINT;
BEGIN
  INC(i);
  WHILE (i < d.count) & (d.lines[i].kind # Link) DO INC(i) END;
  IF i >= d.count THEN i := -1 END;
  RETURN i
END NextLink;

END GeminiText.
