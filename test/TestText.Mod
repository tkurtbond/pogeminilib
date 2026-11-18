MODULE TestText; (* GeminiText and GeminiTextWriter: gemtext read and written *)

(* Each kind of line, read by Parse; a page's lines given by a Parser in
   pieces, joined, equal to Parse's, whatever the buffer and however the
   page is cut into the bytes fed; a piece's flags and sizes; lines many
   times a buffer; characters at a piece's end; a URL past MaxURL; bytes
   that aren't UTF-8, kept and flagged; then the writer: each kind
   written, to a file and to a Writer of the test's own, and read back,
   and what it refuses. *)

IMPORT Out, Files, Platform, C := Check, T := GeminiText, W := GeminiTextWriter,
  GeminiUrls;

CONST
  BOM = "﻿";
  File = "../build/test-text/page.gmi";

TYPE
  Bytes = POINTER TO ARRAY OF CHAR;

  (* A line joined from a parser's pieces. *)
  Joined = RECORD
    kind, level: INTEGER;
    text, url: Bytes;
    len, urlLen: LONGINT;
    malformed, noUrl, urlTooLong: BOOLEAN
  END;
  Joins = POINTER TO ARRAY OF Joined;

  (* A Writer of the test's own: to page. *)
  PageWriter = POINTER TO RECORD (W.WriterDesc) END;

VAR
  page: Bytes; plen: LONGINT;      (* the page being made *)
  d: T.Document;
  why: ARRAY 128 OF CHAR;
  joins: Joins; jcount: LONGINT;   (* Stream's result *)
  fault: ARRAY 200 OF CHAR;        (* why Stream's pieces were wrong, or "" *)
  mix: LONGINT;                    (* the next of Mixed's characters *)

(* The page *)

PROCEDURE Clear;
BEGIN plen := 0; mix := 0
END Clear;

PROCEDURE PutC(c: CHAR);
  VAR more: Bytes; i: LONGINT;
BEGIN
  IF plen = LEN(page^) THEN
    NEW(more, 2 * plen);
    FOR i := 0 TO plen - 1 DO more[i] := page[i] END;
    page := more
  END;
  page[plen] := c; INC(plen)
END PutC;

PROCEDURE Put(s: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO PutC(s[i]); INC(i) END
END Put;

PROCEDURE PutLn(s: ARRAY OF CHAR);
BEGIN Put(s); PutC(0AX)
END PutLn;

PROCEDURE PutN(c: CHAR; n: LONGINT);
BEGIN WHILE n > 0 DO PutC(c); DEC(n) END
END PutN;

(* n bytes or a little more of characters of one, two, three and four
   bytes in turn, so that pieces end at every place in a character. *)
PROCEDURE Mixed(n: LONGINT);
  VAR start: LONGINT;
BEGIN
  start := plen;
  WHILE plen - start < n DO
    CASE mix MOD 5 OF
      0: Put("a")
    | 1: Put("é")
    | 2: Put("€")
    | 3: Put("😀")
    | 4: Put("bc")
    END;
    INC(mix)
  END
END Mixed;

(* Parse's lines *)

PROCEDURE Equal(VAR a: ARRAY OF CHAR; alen: LONGINT; b: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE (i < alen) & (i < LEN(b)) & (a[i] = b[i]) DO INC(i) END;
  RETURN (i = alen) & (i < LEN(b)) & (b[i] = 0X)
END Equal;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE t[j] # 0X DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

(* Line i of d is of kind and level, with text, and, if url isn't "-",
   that URL. *)
PROCEDURE Is(i: LONGINT; kind, level: INTEGER; text, url: ARRAY OF CHAR; label: ARRAY OF CHAR);
  VAR ok: BOOLEAN;
BEGIN
  ok := (i < d.count);
  IF ok THEN
    ok := (d.lines[i].kind = kind) & (d.lines[i].level = level)
      & Equal(d.lines[i].text^, d.lines[i].len, text)
      & d.lines[i].first & d.lines[i].last;
    IF url # "-" THEN ok := ok & Equal(d.lines[i].url^, d.lines[i].urlLen, url) END
  END;
  C.Check(ok, label);
  IF ~ok & (i < d.count) THEN
    Out.String("  kind "); Out.Int(d.lines[i].kind, 0); Out.String(" level "); Out.Int(d.lines[i].level, 0);
    Out.String(" text ["); Out.String(d.lines[i].text^); Out.String("] url [");
    Out.String(d.lines[i].url^); Out.String("]"); Out.Ln
  ELSIF ~ok THEN Out.String("  only "); Out.Int(d.count, 0); Out.String(" lines"); Out.Ln
  END
END Is;

PROCEDURE Kinds;
  VAR i: LONGINT; ok: BOOLEAN; w: ARRAY 64 OF CHAR;
BEGIN
  Clear;
  Put(BOM); PutLn("# Title");
  PutLn("plain text");
  PutLn("");
  PutLn("=> gemini://example.org/a?b Its label");
  PutLn("=>/relative");
  Put("=>"); PutC(09X); Put(" gemini://h/"); PutC(09X); Put("  label with  inner  spaces  ");
  PutC(0DX); PutC(0AX);
  PutLn("=>");
  Put("=> "); PutC(09X); PutLn(" ");
  PutLn("#");
  Put("##"); PutC(09X); PutLn(" Two");
  PutLn("###Three");
  PutLn("####x");
  PutLn("* item");
  PutLn("*x");
  PutLn("*");
  PutLn(">quote");
  PutLn(">  spaced quote");
  PutLn("``` alt text");
  PutLn("# not a heading");
  PutLn("=> not a link");
  PutLn("```` closing, all ignored");
  PutLn("=> gemini://h/ after");
  Put(BOM); PutLn("a BOM not at the start");
  Put("a"); PutC(0DX); PutLn("b");
  PutC(0DX); PutC(0DX); PutC(0AX);
  Put("```"); PutC(0AX);
  Put("unclosed, unended");
  d := T.Parse(page^, plen);
  i := 0;
  Is(i, T.Heading, 1, "Title", "", "a BOM at the start is skipped; # Title"); INC(i);
  Is(i, T.Text, 0, "plain text", "", "text"); INC(i);
  Is(i, T.Text, 0, "", "", "an empty line is text"); INC(i);
  Is(i, T.Link, 0, "Its label", "gemini://example.org/a?b", "a link with a label"); INC(i);
  Is(i, T.Link, 0, "", "/relative", "=>/relative: no space needed, no label"); INC(i);
  Is(i, T.Link, 0, "label with  inner  spaces  ", "gemini://h/",
    "tabs and spaces skipped round the URL; the label's own kept; CR LF ends"); INC(i);
  ok := d.lines[3].noUrl = FALSE;
  Is(i, T.Link, 0, "", "", "=> alone: a link"); ok := ok & d.lines[i].noUrl; INC(i);
  Is(i, T.Link, 0, "", "", "=> and whitespace: a link"); ok := ok & d.lines[i].noUrl; INC(i);
  C.Check(ok, "noUrl set for those two, not for a link with a URL");
  Is(i, T.Heading, 1, "", "", "# alone: an empty heading"); INC(i);
  Is(i, T.Heading, 2, "Two", "", "## and whitespace"); INC(i);
  Is(i, T.Heading, 3, "Three", "", "###Three: no space needed"); INC(i);
  Is(i, T.Heading, 3, "#x", "", "####x: level 3, text #x"); INC(i);
  Is(i, T.ListItem, 0, "item", "", "* item"); INC(i);
  Is(i, T.Text, 0, "*x", "", "*x is text"); INC(i);
  Is(i, T.Text, 0, "*", "", "* alone is text"); INC(i);
  Is(i, T.Quote, 0, "quote", "", ">quote"); INC(i);
  Is(i, T.Quote, 0, "  spaced quote", "", "a quote keeps the whitespace after >"); INC(i);
  Is(i, T.Toggle, 0, " alt text", "", "an opening toggle's alt text, as written"); INC(i);
  Is(i, T.Preformatted, 0, "# not a heading", "", "inside a block, # is preformatted"); INC(i);
  Is(i, T.Preformatted, 0, "=> not a link", "", "inside a block, => is preformatted"); INC(i);
  Is(i, T.Toggle, 0, "", "", "a closing toggle: the rest ignored"); INC(i);
  Is(i, T.Link, 0, "after", "gemini://h/", "after the block, a link again"); INC(i);
  w := BOM; Append(w, "a BOM not at the start");
  Is(i, T.Text, 0, w, "", "a BOM elsewhere is text"); INC(i);
  w := "a?b"; w[1] := 0DX;
  Is(i, T.Text, 0, w, "", "a lone CR is text"); INC(i);
  w[0] := 0DX; w[1] := 0X;
  Is(i, T.Text, 0, w, "", "CR CR LF: a line of one CR"); INC(i);
  Is(i, T.Toggle, 0, "", "", "a block opened"); INC(i);
  Is(i, T.Preformatted, 0, "unclosed, unended", "", "never closed, no LF: still a line"); INC(i);
  C.Check(d.count = i, "no more lines than those");
  C.Check(d.title = 0, "the title is the first heading");
  i := T.NextLink(d, -1); ok := i = 3;
  i := T.NextLink(d, i); ok := ok & (i = 4);
  i := T.NextLink(d, 7); ok := ok & (i = 21);
  i := T.NextLink(d, i); ok := ok & (i = -1);
  C.Check(ok, "NextLink: each link in turn, then -1");

  Clear; d := T.Parse(page^, 0);
  C.Check((d.count = 0) & (d.title = -1), "an empty page: no lines, no title");
  Clear; Put(BOM); d := T.Parse(page^, plen);
  C.Check(d.count = 0, "a page of only a BOM: no lines");
  Clear; PutC(0AX); d := T.Parse(page^, plen);
  C.Check(d.count = 1, "a page of one LF: one empty line");
  Clear; Put("a"); PutC(0X); Put("b"); d := T.Parse(page^, plen);
  C.Check((d.count = 1) & (d.lines[0].len = 3) & (d.lines[0].text[1] = 0X)
    & (d.lines[0].text[2] = "b") & ~d.lines[0].malformed, "a 0X byte kept, len counting past it");
  Clear; Put("ab"); d := T.Parse(page^, plen);
  C.Check((d.count = 1) & (d.lines[0].kind = T.Text), "a line of two bytes, no LF")
END Kinds;

(* Malformed bytes *)

PROCEDURE Malformed;
  VAR ok: BOOLEAN;
BEGIN
  Clear;
  Put("a"); PutC(0FFX); PutLn("b");
  PutC(0C0X); PutC(80X); PutC(0AX);
  Put("ends in part of €"); PutC(0E2X); PutC(82X); PutC(0AX);
  Put("=> gemini://h/"); PutC(0E9X); PutLn(" label");
  PutLn("good: é € 😀");
  Put("a surrogate "); PutC(0EDX); PutC(0A0X); PutC(80X); PutC(0AX);
  d := T.Parse(page^, plen);
  ok := (d.count = 6) & d.lines[0].malformed & (d.lines[0].len = 3) & (d.lines[0].text[1] = 0FFX);
  C.Check(ok, "a byte that isn't UTF-8: kept and flagged");
  C.Check((d.count = 6) & d.lines[1].malformed & (d.lines[1].len = 2), "an overlong form: kept and flagged");
  C.Check((d.count = 6) & d.lines[2].malformed & (d.lines[2].len = 21), "a line ending in part of a character");
  C.Check((d.count = 6) & d.lines[3].malformed & (d.lines[3].kind = T.Link) & (d.lines[3].urlLen = 12),
    "a link whose URL isn't UTF-8: flagged, kept");
  C.Check((d.count = 6) & ~d.lines[4].malformed, "UTF-8 of 2, 3 and 4 bytes is not flagged");
  C.Check((d.count = 6) & d.lines[5].malformed, "a surrogate is flagged")
END Malformed;

(* Streaming *)

PROCEDURE CopyOf(VAR s: ARRAY OF CHAR; n, room: LONGINT): Bytes;
  VAR b: Bytes; i: LONGINT;
BEGIN
  NEW(b, room); FOR i := 0 TO n - 1 DO b[i] := s[i] END; b[n] := 0X;
  RETURN b
END CopyOf;

PROCEDURE Fault(s: ARRAY OF CHAR);
BEGIN IF fault = "" THEN COPY(s, fault) END
END Fault;

(* Takes piece l into joins, checking it against the one before. *)
PROCEDURE Take(VAR l: T.Line; size: LONGINT; VAR open: BOOLEAN; VAR anyBad: BOOLEAN);
  VAR more: Joins; i: LONGINT; b: Bytes;
BEGIN
  IF l.len > size - 1 THEN Fault("a piece longer than the buffer allows") END;
  IF l.first = open THEN Fault("first set wrongly") END;
  IF ~l.last & (l.len < size - 4) THEN Fault("a piece not the last, but shorter than it need be") END;
  IF l.first THEN
    IF jcount = LEN(joins^) THEN
      NEW(more, 2 * jcount); FOR i := 0 TO jcount - 1 DO more[i] := joins[i] END; joins := more
    END;
    (* field by field: a whole record's copy would carry its padding,
       never written, into the heap, where the collector reads it *)
    i := jcount;
    joins[i].kind := l.kind; joins[i].level := l.level;
    joins[i].text := CopyOf(l.text^, l.len, l.len + 1); joins[i].len := l.len;
    joins[i].url := CopyOf(l.url^, l.urlLen, l.urlLen + 1); joins[i].urlLen := l.urlLen;
    joins[i].malformed := l.malformed; joins[i].noUrl := l.noUrl;
    joins[i].urlTooLong := l.urlTooLong;
    INC(jcount);
    anyBad := l.malformed
  ELSE
    i := jcount - 1;
    IF (l.kind # joins[i].kind) OR (l.level # joins[i].level) THEN Fault("a later piece of another kind") END;
    IF l.noUrl OR l.urlTooLong OR (l.urlLen # 0) THEN Fault("a later piece with a URL's flags") END;
    b := CopyOf(joins[i].text^, joins[i].len, joins[i].len + l.len + 1);
    FOR size := 0 TO l.len - 1 DO b[joins[i].len + size] := l.text[size] END;
    INC(joins[i].len, l.len); b[joins[i].len] := 0X; joins[i].text := b;
    IF l.malformed THEN joins[i].malformed := TRUE; anyBad := TRUE END
  END;
  open := ~l.last;
  IF l.last THEN
    (* a piece is flagged only for bytes that aren't UTF-8 in the line: a
       cut never splits a character *)
    i := jcount - 1;
    IF anyBad # ~(GeminiUrls.Utf8(joins[i].text^, joins[i].len)
        & GeminiUrls.Utf8(joins[i].url^, joins[i].urlLen)) THEN
      Fault("a piece flagged malformed for a cut, not for its bytes")
    END
  END
END Take;

(* Parses page with a buffer of size, fed in chunks of chunk bytes, or,
   if split >= 0, in two: before split and from it. *)
PROCEDURE Stream(p: T.Parser; size, chunk, split: LONGINT);
  VAR l: T.Line; pos, end: LONGINT; open, anyBad: BOOLEAN;
BEGIN
  jcount := 0; fault := ""; open := FALSE; anyBad := FALSE; pos := 0;
  WHILE pos < plen DO
    IF split >= 0 THEN
      IF pos < split THEN end := split ELSE end := plen END
    ELSE end := pos + chunk; IF end > plen THEN end := plen END
    END;
    WHILE T.Feed(p, page^, pos, end, l) DO Take(l, size, open, anyBad) END;
    IF pos # end THEN Fault("Feed left bytes unused") END
  END;
  WHILE T.Finish(p, l) DO Take(l, size, open, anyBad) END;
  IF open THEN Fault("the last piece never came") END
END Stream;

(* Whether joins equal d's lines; why not in fault. *)
PROCEDURE Same(): BOOLEAN;
  VAR i, k: LONGINT; a: Joined; ok: BOOLEAN;
BEGIN
  IF fault # "" THEN RETURN FALSE END;
  IF jcount # d.count THEN Fault("another number of lines"); RETURN FALSE END;
  ok := TRUE; i := 0;
  WHILE ok & (i < jcount) DO
    a := joins[i];
    ok := (a.kind = d.lines[i].kind) & (a.level = d.lines[i].level) & (a.len = d.lines[i].len)
      & (a.urlLen = d.lines[i].urlLen) & (a.malformed = d.lines[i].malformed)
      & (a.noUrl = d.lines[i].noUrl) & (a.urlTooLong = d.lines[i].urlTooLong);
    k := 0; WHILE ok & (k < a.len) DO ok := a.text[k] = d.lines[i].text[k]; INC(k) END;
    k := 0; WHILE ok & (k < a.urlLen) DO ok := a.url[k] = d.lines[i].url[k]; INC(k) END;
    INC(i)
  END;
  IF ~ok THEN Fault("a line unlike Parse's") END;
  RETURN ok
END Same;

(* A page with every kind of line, long lines, characters of every
   length, bytes that aren't UTF-8, and every line end. *)
PROCEDURE BigPage;
BEGIN
  Clear;
  Put(BOM); Put("# Title "); Mixed(40); PutC(0AX);
  Mixed(150); PutC(0AX);
  PutC(0AX);
  Put("=> gemini://example.org/ü "); Mixed(500); PutC(0AX);
  Put("=>"); PutN(" ", 100); Put("gemini://h/path"); PutN(09X, 50); Put("label"); PutC(0AX);
  Put("=>"); PutN(" ", 3000); PutC(0AX);
  Put("=> "); PutN("u", 1100); Put(" lbl "); Mixed(30); PutC(0AX);
  Put("=> "); PutN("v", 1024); PutC(0AX);
  Put("##"); PutN(" ", 2500); Mixed(3000); PutC(0DX); PutC(0AX);
  Put("####"); Mixed(20); PutC(0AX);
  Put("* "); Mixed(60); PutC(0AX);
  PutLn("*x");
  Put(">  "); Mixed(70); PutC(0AX);
  Put("```"); Mixed(5000); PutC(0AX);
  PutLn("# preformatted");
  Mixed(9000); PutC(0AX);
  Put("```"); PutN("x", 4000); PutC(0AX);
  PutN(80X, 20); PutC(0AX);
  Put("x"); PutC(0FFX); PutLn("y");
  Put("abc"); PutC(0E2X); PutC(82X); PutC(0AX);
  Put("cut"); PutC(0F0X); PutC(9FX); PutC(98X); PutC(0DX); PutC(0AX);
  Put("lone"); PutC(0DX); Put("CR"); PutC(0DX); PutC(0DX); PutC(0AX);
  PutN("-", 3); PutC(0DX); PutC(0AX);
  Mixed(20000); PutC(0AX);
  Put("```"); PutC(0AX); Put("unclosed"); PutC(0DX)
END BigPage;

PROCEDURE Streaming;
  CONST NC = 8;
  VAR p: T.Parser; size, k, n, split: LONGINT; ok: BOOLEAN;
    chunks: ARRAY NC OF LONGINT; label: ARRAY 100 OF CHAR;

  PROCEDURE Report(what: ARRAY OF CHAR; size, how: LONGINT);
  BEGIN
    Out.String("  "); Out.String(fault); Out.String(", buffer "); Out.Int(size, 0);
    Out.String(", "); Out.String(what); Out.String(" "); Out.Int(how, 0); Out.Ln
  END Report;

  PROCEDURE Sizes(VAR label: ARRAY OF CHAR);
  BEGIN
    ok := TRUE; size := T.MinBuffer;
    WHILE ok & (size <= 6000) DO
      p := T.New(size); k := 0;
      WHILE ok & (k < NC) DO
        n := chunks[k]; IF n = 0 THEN n := plen END;
        Stream(p, size, n, -1); ok := Same();
        IF ~ok THEN Report("chunks of", size, n) END;
        INC(k)
      END;
      IF size < 24 THEN INC(size) ELSE size := size * 2 + 1 END
    END;
    C.Check(ok, label)
  END Sizes;

BEGIN
  chunks[0] := 1; chunks[1] := 2; chunks[2] := 3; chunks[3] := 5; chunks[4] := 7;
  chunks[5] := 64; chunks[6] := 1000; chunks[7] := 0;
  BigPage; d := T.Parse(page^, plen);
  C.Check(d.count = 26, "the big page: 26 lines");
  C.Check((d.count = 26) & d.lines[5].noUrl & ~d.lines[5].urlTooLong,
    "=> and 3000 spaces: no URL");
  C.Check((d.count = 26) & d.lines[6].urlTooLong & (d.lines[6].urlLen = T.MaxURL)
    & (d.lines[6].text[0] = "l") & ~d.lines[6].noUrl,
    "a URL of 1100 bytes: its first 1024 kept, flagged, the label after it");
  C.Check((d.count = 26) & ~d.lines[7].urlTooLong & (d.lines[7].urlLen = T.MaxURL),
    "a URL of 1024 bytes: whole, not flagged");
  C.Check((d.count = 26) & (d.lines[23].len >= 20000) & ~d.lines[23].malformed,
    "a line of 20000 bytes of UTF-8: whole, not flagged");
  label := "a page with every kind of line: pieces joined equal Parse's, buffers 8..6000, every chunking";
  Sizes(label);

  (* every cut of a short page into two, at the smallest buffer and a large one *)
  Clear;
  Put(BOM); PutLn("# é€😀"); Put("=> gemini://h/€ "); Mixed(20); PutC(0AX);
  Mixed(30); PutC(0DX); PutC(0AX); PutLn("```"); Mixed(15); PutC(0AX);
  PutC(0F0X); PutC(9FX); PutC(0DX); PutLn("```x");
  Put("* "); Mixed(12);
  d := T.Parse(page^, plen);
  ok := TRUE;
  FOR size := T.MinBuffer TO T.MinBuffer + 4 DO
    p := T.New(size); split := 0;
    WHILE ok & (split <= plen) DO
      Stream(p, size, 0, split); ok := Same();
      IF ~ok THEN Report("cut at", size, split) END;
      INC(split)
    END
  END;
  p := T.New(4096); split := 0;
  WHILE ok & (split <= plen) DO
    Stream(p, 4096, 0, split); ok := Same();
    IF ~ok THEN Report("cut at", 4096, split) END;
    INC(split)
  END;
  C.Check(ok, "a short page cut in two at every byte: the same lines");

  (* a parser goes on to another page after Finish *)
  p := T.New(64);
  Clear; PutLn("```"); Put("inside"); Stream(p, 64, plen, -1);
  Clear; PutLn("# h"); Stream(p, 64, plen, -1);
  C.Check((fault = "") & (jcount = 1) & (joins[0].kind = T.Heading),
    "after Finish, a new page starts outside a block")
END Streaming;

(* Pieces *)

(* Feeds page to a parser of size and checks the pieces' lengths, given
   as a string of digits and letters ("a" 10, ...), and their texts
   joined. *)
PROCEDURE Pieces(size: LONGINT; lengths, label: ARRAY OF CHAR);
  VAR p: T.Parser; l: T.Line; pos, i, n: LONGINT; ok: BOOLEAN; c: CHAR;
BEGIN
  p := T.New(size); pos := 0; i := 0; ok := TRUE;
  LOOP
    IF ~T.Feed(p, page^, pos, plen, l) & ~T.Finish(p, l) THEN EXIT END;
    c := lengths[i];
    IF (c >= "0") & (c <= "9") THEN n := ORD(c) - ORD("0") ELSE n := ORD(c) - ORD("a") + 10 END;
    ok := ok & (c # 0X) & (l.len = n);
    IF c # 0X THEN INC(i) END
  END;
  C.Check(ok & (lengths[i] = 0X), label)
END Pieces;

PROCEDURE Pieced;
  VAR p: T.Parser; l: T.Line; pos, i: LONGINT; ok: BOOLEAN;
BEGIN
  Clear; Put("abcde€");
  Pieces(8, "53", "abcde€ in a buffer of 8: 5 bytes, then the 3 of €");
  Clear; Put("abcdef😀");
  Pieces(8, "64", "abcdef😀: 6, then the 4 of 😀");
  Clear; Put("abcd€x");
  Pieces(8, "71", "abcd€x: € ends the first piece whole");
  Clear; Put("abc😀x");
  Pieces(8, "71", "abc😀x: 😀 ends the first piece whole");
  Clear; PutN(80X, 20);
  Pieces(8, "776", "continuation bytes alone: cut where the buffer ends");
  Clear; Put("=> "); PutN("u", 30); Put(" label");
  Pieces(8, "5", "a link: its URL kept apart, the label the piece");
  Clear; Put("=> "); PutN("u", 30); Put(" labels and more");
  Pieces(8, "771", "a link's label in pieces");

  (* a line many times the buffer *)
  Clear; PutN("z", 100000); d := T.Parse(page^, plen);
  C.Check((d.count = 1) & (d.lines[0].len = 100000), "Parse: a line of 100000 bytes, whole");
  Clear; PutN("z", 7 * 1000); PutC(0AX);
  p := T.New(8); pos := 0; i := 0; ok := TRUE;
  WHILE T.Feed(p, page^, pos, plen, l) DO
    ok := ok & (l.len = 7) & (l.first = (i = 0)) & (l.last = (i = 999)); INC(i)
  END;
  C.Check(ok & (i = 1000) & ~T.Finish(p, l), "a line of 7000 bytes in a buffer of 8: 1000 pieces of 7")
END Pieced;

(* The writer *)

PROCEDURE (w: PageWriter) Put*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  FOR i := 0 TO n - 1 DO PutC(s[i]) END;
  RETURN TRUE
END Put;

(* Writes each kind of line through w, the page empty to begin with. *)
PROCEDURE WriteAll(w: W.Writer): BOOLEAN;
BEGIN
  RETURN W.Heading(w, 1, "Title", why) & W.Text(w, "plain", why) & W.Text(w, "", why)
    & W.Text(w, "*x", why) & W.Link(w, "gemini://h/a?b", "a label", why)
    & W.Link(w, "/x", "", why) & W.NameLink(w, "a b:c?é", "name", why)
    & W.Heading(w, 2, "#two", why) & W.Heading(w, 3, "", why)
    & W.ListItem(w, "item", why) & W.Quote(w, "  q", why)
    & W.Open(w, "alt", why) & W.Preformatted(w, "# pre", why)
    & W.Preformatted(w, "=> x", why) & W.Preformatted(w, "", why) & W.Close(w, why)
    & W.Text(w, "end", why)
END WriteAll;

PROCEDURE ReadAll(what: ARRAY OF CHAR);
  VAR label: ARRAY 100 OF CHAR;

  PROCEDURE L(i: LONGINT; kind, level: INTEGER; text, url, name: ARRAY OF CHAR);
  BEGIN
    COPY(what, label); Append(label, ": "); Append(label, name);
    Is(i, kind, level, text, url, label)
  END L;

BEGIN
  d := T.Parse(page^, plen);
  L(0, T.Heading, 1, "Title", "-", "a heading");
  L(1, T.Text, 0, "plain", "-", "text");
  L(2, T.Text, 0, "", "-", "an empty line");
  L(3, T.Text, 0, "*x", "-", "*x, text");
  L(4, T.Link, 0, "a label", "gemini://h/a?b", "a link, its URL as given");
  L(5, T.Link, 0, "", "/x", "a link with no label");
  L(6, T.Link, 0, "name", "a%20b%3Ac%3F%C3%A9", "NameLink: all but unreserved encoded");
  L(7, T.Heading, 2, "#two", "-", "a heading whose text begins with #");
  L(8, T.Heading, 3, "", "-", "an empty heading");
  L(9, T.ListItem, 0, "item", "-", "a list item");
  L(10, T.Quote, 0, "  q", "-", "a quote, its whitespace kept");
  L(11, T.Toggle, 0, "alt", "-", "a block opened, with alt text");
  L(12, T.Preformatted, 0, "# pre", "-", "preformatted # pre");
  L(13, T.Preformatted, 0, "=> x", "-", "preformatted => x");
  L(14, T.Preformatted, 0, "", "-", "an empty preformatted line");
  L(15, T.Toggle, 0, "", "-", "the block closed");
  L(16, T.Text, 0, "end", "-", "text after it");
  COPY(what, label); Append(label, ": no more lines");
  C.Check(d.count = 17, label)
END ReadAll;

(* ok is FALSE, why is reason, and nothing was written. *)
PROCEDURE Refused(ok: BOOLEAN; reason, label: ARRAY OF CHAR);
  VAR good: BOOLEAN;
BEGIN
  good := ~ok & (why = reason) & (plen = 0);
  C.Check(good, label);
  IF ~good THEN
    Out.String("  why: "); Out.String(why); Out.String(", "); Out.Int(plen, 0);
    Out.String(" bytes written"); Out.Ln
  END
END Refused;

PROCEDURE Writing;
  VAR pw: PageWriter; fw: W.FileWriter; f: Files.File; r: Files.Rider;
    ok: BOOLEAN; s: ARRAY 64 OF CHAR; status: INTEGER;
BEGIN
  Clear; NEW(pw); W.Init(pw);
  ok := WriteAll(pw);
  C.Check(ok, "a Writer of the program's own: every kind written");
  ReadAll("read back");

  Clear; W.Init(pw); Refused(W.Text(pw, "=> x", why), "another kind of line begins so", "text =>, refused");
  Refused(W.Text(pw, "#x", why), "another kind of line begins so", "text #, refused");
  Refused(W.Text(pw, "* x", why), "another kind of line begins so", "text *space, refused");
  Refused(W.Text(pw, ">x", why), "another kind of line begins so", "text >, refused");
  Refused(W.Text(pw, "```x", why), "another kind of line begins so", "text ```, refused");
  s := "a?b"; s[1] := 0AX;
  Refused(W.Text(pw, s, why), "a line end in a line", "a LF in text, refused");
  s[1] := 0DX;
  Refused(W.Quote(pw, s, why), "a line end in a line", "a CR in a quote, refused");
  Refused(W.Link(pw, "", "x", why), "no URL", "a link with no URL, refused");
  Refused(W.Link(pw, "a b", "x", why), "a space or a control character in the URL",
    "a space in a URL, refused");
  s := "a?b"; s[1] := 09X;
  Refused(W.Link(pw, s, "x", why), "a space or a control character in the URL",
    "a tab in a URL, refused");
  Refused(W.Link(pw, "/x", " x", why), "whitespace before the label",
    "whitespace before a label, refused");
  s := "a?b"; s[1] := 0AX;
  Refused(W.Link(pw, "/x", s, why), "a line end in a line", "a LF in a label, refused");
  Refused(W.Heading(pw, 1, " x", why), "whitespace before the heading's text",
    "whitespace before a heading's text, refused");
  Refused(W.Preformatted(pw, "x", why), "outside a preformatted block",
    "preformatted text outside a block, refused");
  Refused(W.Close(pw, why), "outside a preformatted block", "closing no block, refused");
  s := BOM; Append(s, "x");
  Refused(W.Text(pw, s, why), "a byte order mark at the page's start, which a reader skips",
    "a BOM beginning the page, refused");
  ok := W.Open(pw, "", why) & pw.pre; Clear;
  C.Check(ok, "a block opened: pre set");
  Refused(W.Text(pw, "x", why), "inside a preformatted block", "text inside a block, refused");
  Refused(W.Link(pw, "/x", "", why), "inside a preformatted block", "a link inside a block, refused");
  Refused(W.Heading(pw, 1, "x", why), "inside a preformatted block", "a heading inside a block, refused");
  Refused(W.Preformatted(pw, "```", why), "three backticks would close the block",
    "``` as preformatted text, refused");
  ok := W.Close(pw, why) & ~pw.pre & W.Text(pw, s, why);
  C.Check(ok, "closed; a BOM in a later line is written");

  (* to a file *)
  status := Platform.System("rm -rf ../build/test-text && mkdir -p ../build/test-text");
  IF status # 0 THEN C.Check(FALSE, "make ../build/test-text"); RETURN END;
  f := Files.New(File); Files.Set(r, f, 0);
  fw := W.NewFile(r);
  ok := WriteAll(fw);
  Files.Register(f); Files.Close(f);
  C.Check(ok & (fw.r.res = 0), "a FileWriter: every kind written");
  f := Files.Old(File);
  ok := f # NIL;
  IF ok THEN
    Clear; plen := Files.Length(f);
    IF plen > LEN(page^) THEN NEW(page, plen) END;
    Files.Set(r, f, 0); Files.ReadBytes(r, page^, plen); Files.Close(f);
    ok := r.res = 0
  END;
  C.Check(ok, "the file read");
  IF ok THEN ReadAll("the file read back") END;
  status := Platform.System("rm -rf ../build/test-text");
  C.Check(status = 0, "../build/test-text removed")
END Writing;

BEGIN
  NEW(page, 1024); NEW(joins, 16);
  Kinds;
  Malformed;
  Streaming;
  Pieced;
  Writing;
  C.Summary
END TestText.
