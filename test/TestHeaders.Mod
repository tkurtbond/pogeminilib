MODULE TestHeaders; (* GeminiStatus and GeminiHeaders: statuses, headers, MIME types *)

(* Every status the specification names, and the class, the effective
   status and the name of ones it doesn't; headers parsed, good and
   refused (each refusal of the specification's, and the two
   leniencies); Ended on a header as it arrives; MIME types and their
   parameters; WriteHeader's headers read back. Its halts are the halt
   tests HaltStatusClass and HaltHeader*. *)

IMPORT Out, C := Check, S := GeminiStatus, H := GeminiHeaders;

CONST CR = 0DX; LF = 0AX; Tab = 09X;

VAR
  buf: ARRAY 2200 OF CHAR; len: LONGINT;
  h: H.Header; m: H.Mime; line: H.Line;
  why: ARRAY 128 OF CHAR; text: ARRAY 1100 OF CHAR;

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END; RETURN n
END Length;

(* Building a header in buf[0..len-1] *)

PROCEDURE Start;
BEGIN len := 0
END Start;

PROCEDURE AddC(c: CHAR);
BEGIN buf[len] := c; INC(len)
END AddC;

PROCEDURE Add(s-: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN i := 0; WHILE s[i] # 0X DO AddC(s[i]); INC(i) END
END Add;

PROCEDURE AddN(c: CHAR; n: LONGINT);
BEGIN WHILE n > 0 DO AddC(c); DEC(n) END
END AddN;

PROCEDURE End;
BEGIN AddC(CR); AddC(LF)
END End;

(* s with CR LF after it *)
PROCEDURE Set(s-: ARRAY OF CHAR);
BEGIN Start; Add(s); End
END Set;

(* Statuses *)

PROCEDURE Named(s: INTEGER; name: ARRAY OF CHAR);
  VAR n: ARRAY 64 OF CHAR; label: ARRAY 80 OF CHAR;
BEGIN
  S.Name(s, n);
  COPY(name, label);
  C.Check(S.Valid(s) & S.Known(s) & (S.Effective(s) = s) & (S.Class(s) = s DIV 10)
    & (n = name), label)
END Named;

PROCEDURE Unknown(s, effective: INTEGER; name: ARRAY OF CHAR);
  VAR n: ARRAY 64 OF CHAR; label: ARRAY 80 OF CHAR;
BEGIN
  S.Name(s, n);
  label := "unknown status, as its class: "; label[28] := CHR(ORD("0") + s DIV 10);
  label[29] := CHR(ORD("0") + s MOD 10); label[30] := 0X;
  C.Check(S.Valid(s) & ~S.Known(s) & (S.Effective(s) = effective)
    & (S.Class(s) = s DIV 10) & (n = name), label)
END Unknown;

PROCEDURE Statuses;
  VAR s, known: INTEGER; ok: BOOLEAN;
BEGIN
  Named(S.Input, "input");
  Named(S.SensitiveInput, "sensitive input");
  Named(S.Success, "success");
  Named(S.TemporaryRedirect, "temporary redirection");
  Named(S.PermanentRedirect, "permanent redirection");
  Named(S.TemporaryFailure, "temporary failure");
  Named(S.ServerUnavailable, "server unavailable");
  Named(S.CgiError, "CGI error");
  Named(S.ProxyError, "proxy error");
  Named(S.SlowDown, "slow down");
  Named(S.PermanentFailure, "permanent failure");
  Named(S.NotFound, "not found");
  Named(S.Gone, "gone");
  Named(S.ProxyRequestRefused, "proxy request refused");
  Named(S.BadRequest, "bad request");
  Named(S.CertificateRequired, "client certificate required");
  Named(S.CertificateNotAuthorized, "certificate not authorized");
  Named(S.CertificateNotValid, "certificate not valid");
  C.Check((S.Input = 10) & (S.SensitiveInput = 11) & (S.Success = 20)
    & (S.TemporaryRedirect = 30) & (S.PermanentRedirect = 31)
    & (S.TemporaryFailure = 40) & (S.ServerUnavailable = 41) & (S.CgiError = 42)
    & (S.ProxyError = 43) & (S.SlowDown = 44) & (S.PermanentFailure = 50)
    & (S.NotFound = 51) & (S.Gone = 52) & (S.ProxyRequestRefused = 53)
    & (S.BadRequest = 59) & (S.CertificateRequired = 60)
    & (S.CertificateNotAuthorized = 61) & (S.CertificateNotValid = 62),
    "the statuses' numbers are the specification's");
  (* the specification's own examples: 14 as 10, 22 as 20 *)
  Unknown(14, 10, "input");
  Unknown(22, 20, "success");
  Unknown(39, 30, "temporary redirection");
  Unknown(45, 40, "temporary failure");
  Unknown(58, 50, "permanent failure");
  Unknown(69, 60, "client certificate required");
  known := 0; ok := TRUE;
  FOR s := -1 TO 100 DO
    IF S.Known(s) THEN INC(known); ok := ok & S.Valid(s) END;
    ok := ok & (S.Valid(s) = (s >= 10) & (s <= 69))
  END;
  C.Check(ok & (known = 18), "18 statuses known, all in 10..69, which alone are valid");
  C.Check((S.Class(10) = S.InputClass) & (S.Class(29) = S.SuccessClass)
    & (S.Class(30) = S.RedirectClass) & (S.Class(44) = S.TemporaryClass)
    & (S.Class(59) = S.PermanentClass) & (S.Class(62) = S.CertificateClass),
    "the classes")
END Statuses;

(* Headers *)

(* buf[0..len-1] parses to status and meta. *)
PROCEDURE GoodBuf(label: ARRAY OF CHAR; status: INTEGER; meta: ARRAY OF CHAR);
  VAR ok: BOOLEAN;
BEGIN
  ok := H.Parse(buf, len, h, why);
  ok := ok & (h.status = status) & (h.meta = meta);
  C.Check(ok, label);
  IF ~ok THEN
    Out.String("  "); Out.String(why); Out.String(", status "); Out.Int(h.status, 0);
    Out.String(", meta "); Out.String(h.meta); Out.Ln
  END
END GoodBuf;

PROCEDURE Good(s: ARRAY OF CHAR; status: INTEGER; meta: ARRAY OF CHAR);
BEGIN Set(s); GoodBuf(s, status, meta)
END Good;

(* buf[0..len-1] is refused for reason, h left empty. *)
PROCEDURE BadBuf(label, reason: ARRAY OF CHAR);
  VAR ok, parsed: BOOLEAN;
BEGIN
  parsed := H.Parse(buf, len, h, why);
  ok := ~parsed & (why = reason) & (h.status = 0) & (h.meta = "");
  C.Check(ok, label);
  IF ~ok THEN
    Out.String("  parsed "); IF parsed THEN Out.String("yes") ELSE Out.String("no") END;
    Out.String(", why "); Out.String(why); Out.String(", status "); Out.Int(h.status, 0); Out.Ln
  END
END BadBuf;

PROCEDURE Bad(s, reason: ARRAY OF CHAR);
BEGIN Set(s); BadBuf(s, reason)
END Bad;

PROCEDURE Headers;
  VAR i: LONGINT;
BEGIN
  Good("20 text/gemini", 20, "text/gemini");
  Good("20 text/gemini; charset=utf-8; lang=en", 20, "text/gemini; charset=utf-8; lang=en");
  Good("20 application/octet-stream", 20, "application/octet-stream");
  Good("10 What is your name?", 10, "What is your name?");
  Good("11 Password", 11, "Password");
  Good("10  ", 10, " ");                     (* a prompt of one space: 1*(SP / VCHAR) *)
  Good("30 /elsewhere", 30, "/elsewhere");
  Good("31 gemini://example.org/", 31, "gemini://example.org/");
  Good("40", 40, "");
  Good("44 30", 44, "30");
  Good("50", 50, "");                        (* the specification's own example *)
  Good("51 Not here", 51, "Not here");
  Good("59 bad request", 59, "bad request");
  Good("60", 60, "");
  Good("62 Expired", 62, "Expired");
  Good("14 Unknown, so input", 14, "Unknown, so input");
  Good("45", 45, "");
  Good("51 Ünïcode € 😀", 51, "Ünïcode € 😀");
  Good("51 a ﻿ in the middle", 51, "a ﻿ in the middle");  (* U+FEFF: only a leading BOM is refused *)
  (* the leniencies: a success with no MIME type, a failure's space with no message *)
  Good("20", 20, "");
  Good("20 ", 20, "");
  Good("51 ", 51, "");
  Good("60 ", 60, "");

  Start; Add("20 "); AddN("x", H.MaxMeta); End;
  C.Check(len = H.MaxHeader, "a header of the most bytes is MaxHeader long");
  text[0] := 0X; FOR i := 0 TO H.MaxMeta - 1 DO text[i] := "x" END; text[H.MaxMeta] := 0X;
  GoodBuf("a meta of 1024 bytes", 20, text);
  Start; Add("20 "); AddN("x", H.MaxMeta + 1); End;
  BadBuf("a meta of 1025 bytes", "a meta of more than 1024 bytes");

  Start; AddC(0EFX); AddC(0BBX); AddC(0BFX); Add("20 text/gemini"); End;
  BadBuf("a byte order mark", "a byte order mark");
  Start; Add("20 text/gemini");
  BadBuf("no CR LF", "no line end");
  Start; BadBuf("nothing", "no line end");
  Start; Add("20 text/gemini"); AddC(CR);
  BadBuf("CR, no LF", "no line end");
  Start; Add("20 "); AddN("x", H.MaxMeta + 3);
  BadBuf("1029 bytes and no line end", "no line end within the header's 1029 bytes");
  Start; Add("20 text/gemini"); AddC(LF);
  BadBuf("LF without CR", "a line end without CR");
  Start; AddC(LF);
  BadBuf("LF alone", "a line end without CR");
  Start; Add("20 text/gemini"); End; Add("# A page");
  BadBuf("a body after the header", "more than the header");
  Bad("", "no status");
  Bad("2", "no status");
  Bad("2x text/gemini", "no status");
  Bad("x0 text/gemini", "no status");
  Bad(" 20 text/gemini", "no status");
  Bad("200 text/gemini", "a status of more than two digits");
  Bad("200", "a status of more than two digits");
  Bad("09 x", "a status outside 10..69");
  Bad("00", "a status outside 10..69");
  Bad("70 x", "a status outside 10..69");
  Bad("99", "a status outside 10..69");
  Bad("20text/gemini", "no space after the status");
  Start; Add("20"); AddC(Tab); Add("text/gemini"); End;
  BadBuf("a tab after the status", "no space after the status");
  Start; Add("51 "); AddC(0FFX); End;
  BadBuf("a meta that isn't UTF-8", "a meta that isn't UTF-8");
  Start; Add("51 "); AddC(0C0X); AddC(80X); End;
  BadBuf("a meta with an overlong form", "a meta that isn't UTF-8");
  Start; Add("51 "); AddC(0EDX); AddC(0A0X); AddC(80X); End;
  BadBuf("a meta with a surrogate", "a meta that isn't UTF-8");
  Start; Add("51 a"); AddC(Tab); Add("b"); End;
  BadBuf("a tab in the meta", "a control character in the meta");
  Start; Add("51 a"); AddC(CR); Add("b"); End;
  BadBuf("a CR in the meta", "a control character in the meta");
  Start; Add("51 a"); AddC(1BX); Add("[31mb"); End;
  BadBuf("an escape in the meta", "a control character in the meta");
  Start; Add("51 a"); AddC(0X); Add("b"); End;
  BadBuf("a 0X in the meta", "a control character in the meta");
  Start; Add("51 a"); AddC(7FX); End;
  BadBuf("a DEL in the meta", "a control character in the meta");
  Start; Add("51 a"); AddC(0C2X); AddC(85X); End;
  BadBuf("a C1 (NEL) in the meta", "a control character in the meta");
  Start; Add("51 a"); AddC(0C2X); AddC(0A0X); End;
  text := "a"; text[1] := 0C2X; text[2] := 0A0X; text[3] := 0X;
  GoodBuf("U+00A0, just after C1, is no control", 51, text);
  Bad("10", "input with no prompt");
  Bad("10 ", "input with no prompt");
  Bad("11 ", "input with no prompt");
  Bad("30", "a redirect with no URL");
  Bad("31 ", "a redirect with no URL")
END Headers;

(* Ended *)

PROCEDURE Ends;
  VAR n, i, first: LONGINT; ok: BOOLEAN;
BEGIN
  Set("20 text/gemini"); Add("# A page"); AddC(LF);
  C.Check(H.Ended(buf, len, n) & (n = 16), "ended: a header and a body");
  C.Check(H.Parse(buf, n, h, why) & (h.status = 20), "and the header parses");
  (* as it arrives: not ended until the LF has come *)
  ok := TRUE; first := -1;
  FOR i := 0 TO len DO
    IF H.Ended(buf, i, n) THEN
      IF first < 0 THEN first := i END;
      ok := ok & (n = 16)
    ELSE ok := ok & (n = 0)
    END
  END;
  C.Check(ok & (first = 16), "ended only once its LF is in");
  Start;
  C.Check(~H.Ended(buf, 0, n), "not ended: nothing yet");
  Start; AddN("x", H.MaxHeader - 1);
  C.Check(~H.Ended(buf, len, n), "not ended: 1028 bytes, no LF");
  AddC("x");
  C.Check(H.Ended(buf, len, n) & (n = H.MaxHeader), "ended: 1029 bytes, no LF");
  AddN("x", 500); AddC(LF);
  C.Check(H.Ended(buf, len, n) & (n = H.MaxHeader), "ended at 1029 bytes, a LF after");
  Start; Add("20 "); AddN("x", H.MaxMeta); End; Add("body");
  C.Check(H.Ended(buf, len, n) & (n = H.MaxHeader) & H.Parse(buf, n, h, why),
    "ended: the longest header, its LF its 1029th byte");
  Start; Add("20 "); AddN("x", H.MaxMeta + 1); End;
  C.Check(H.Ended(buf, len, n) & (n = H.MaxHeader) & ~H.Parse(buf, n, h, why)
    & (why = "no line end within the header's 1029 bytes"),
    "a header a byte too long: no line end within 1029 bytes")
END Ends;

(* MIME types *)

(* meta parses as type/subtype with count parameters, skipped as given. *)
PROCEDURE Mime(meta, type, subtype: ARRAY OF CHAR; count: INTEGER; skipped: BOOLEAN);
  VAR ok: BOOLEAN;
BEGIN
  why := "";
  ok := H.ParseMime(meta, m, why) & (m.type = type) & (m.subtype = subtype)
    & (m.count = count) & (m.skipped = skipped) & ~m.assumed;
  C.Check(ok, meta);
  IF ~ok THEN
    Out.String("  "); Out.String(why); Out.String(", "); Out.String(m.type);
    Out.String("/"); Out.String(m.subtype); Out.String(", count "); Out.Int(m.count, 0); Out.Ln
  END
END Mime;

(* m's parameter name is value. *)
PROCEDURE Value(name, value: ARRAY OF CHAR);
  VAR v: ARRAY 200 OF CHAR; label: ARRAY 200 OF CHAR; i, k: LONGINT;
BEGIN
  label := "  its parameter "; i := 0; WHILE label[i] # 0X DO INC(i) END;
  k := 0; WHILE name[k] # 0X DO label[i] := name[k]; INC(i); INC(k) END;
  label[i] := 0X;
  C.Check(H.Param(m, name, v) & (v = value), label);
  IF v # value THEN Out.String("  got "); Out.String(v); Out.Ln END
END Value;

PROCEDURE BadMime(meta, reason: ARRAY OF CHAR);
  VAR ok: BOOLEAN;
BEGIN
  ok := ~H.ParseMime(meta, m, why) & (why = reason) & (m.type = "") & (m.subtype = "");
  C.Check(ok, meta);
  IF ~ok THEN Out.String("  "); Out.String(why); Out.Ln END
END BadMime;

PROCEDURE Mimes;
  VAR cs: ARRAY 32 OF CHAR; v: ARRAY 4 OF CHAR; i: LONGINT;
BEGIN
  C.Check(H.ParseMime("", m, why) & m.assumed & (m.type = "text") & (m.subtype = "gemini")
    & (m.count = 1) & (m.params[0].name^ = "charset") & (m.params[0].value^ = "utf-8")
    & ~m.skipped, "an empty meta: text/gemini; charset=utf-8, assumed");
  C.Check(H.ParseMime("  ", m, why) & m.assumed, "a meta of spaces, likewise");
  Mime("text/gemini", "text", "gemini", 0, FALSE);
  H.Charset(m, cs); C.Check(cs = "utf-8", "  a text type's charset is UTF-8 by default");
  C.Check(H.Is(m, "TEXT", "Gemini") & ~H.Is(m, "text", "plain") & ~H.Is(m, "text", "gemin"),
    "  Is, case aside");
  C.Check(~H.Param(m, "lang", cs) & (cs = ""), "  no lang: Param FALSE, and empty");
  Mime("Text/Gemini; Charset=UTF-8; LANG=en", "text", "gemini", 2, FALSE);
  Value("charset", "UTF-8"); Value("Lang", "en");
  H.Charset(m, cs); C.Check(cs = "utf-8", "  Charset in lower case");
  Mime('text/gemini; lang="en,fr"', "text", "gemini", 1, FALSE);
  Value("lang", "en,fr");
  Mime('text/gemini; title="a \"quoted\" \\ name"; lang=de', "text", "gemini", 2, FALSE);
  Value("title", 'a "quoted" \ name'); Value("lang", "de");
  Mime("text/plain;charset=us-ascii", "text", "plain", 1, FALSE);
  H.Charset(m, cs); C.Check(cs = "us-ascii", "  its charset");
  Mime("text/gemini ; lang = en ", "text", "gemini", 1, FALSE);
  Value("lang", "en");
  Mime("  text/gemini", "text", "gemini", 0, FALSE);
  Mime("text/gemini;", "text", "gemini", 0, FALSE);
  Mime("text/gemini;;; lang=en;", "text", "gemini", 1, FALSE);
  Mime("text/gemini; lang=en; lang=fr", "text", "gemini", 2, FALSE);
  Value("lang", "en");
  Mime("image/png", "image", "png", 0, FALSE);
  H.Charset(m, cs); C.Check(cs = "", "  no charset for an image");
  Mime("application/vnd.example+json", "application", "vnd.example+json", 0, FALSE);
  (* what isn't a parameter is skipped, flagged, and the rest kept *)
  Mime("text/gemini; utf-8", "text", "gemini", 0, TRUE);
  Mime("text/gemini; foo; lang=en", "text", "gemini", 1, TRUE);
  Value("lang", "en");
  Mime("text/gemini junk; lang=en", "text", "gemini", 1, TRUE);
  Value("lang", "en");
  Mime("text/gemini; a=; b=c", "text", "gemini", 1, TRUE);
  Value("b", "c");
  Mime("text/gemini; a=b c; d=e", "text", "gemini", 1, TRUE);
  Value("d", "e");
  Mime('text/gemini; a="b;c" d; e=f', "text", "gemini", 1, TRUE);
  Value("e", "f");
  Mime('text/gemini; a="unclosed; lang=en', "text", "gemini", 0, TRUE);
  Mime('text/gemini; a b="x; c=d; "', "text", "gemini", 0, TRUE);  (* a ";" quoted in what is skipped *)
  Mime('text/gemini; a b="x\"; c=d; "', "text", "gemini", 0, TRUE);  (* and an escaped quote *)
  Mime("text/gemini; =en", "text", "gemini", 0, TRUE);
  Mime("text/gemini; lang=ü", "text", "gemini", 0, TRUE);
  Mime('text/gemini; lang="ü"', "text", "gemini", 1, FALSE);
  Value("lang", "ü");
  Mime("text/gemini; charset=a-very-long-name", "text", "gemini", 1, FALSE);
  C.Check(H.Param(m, "charset", v) & (v = "a-v"), "  a value cut to fit");
  BadMime("text", "no MIME subtype");
  BadMime("text/", "no MIME subtype");
  BadMime("text /gemini", "no MIME subtype");
  BadMime("text/ gemini", "no MIME subtype");
  BadMime("/gemini", "no MIME type");
  BadMime("; charset=utf-8", "no MIME type");
  BadMime("ü/gemini", "no MIME type");
  FOR i := 0 TO H.MaxName - 1 DO text[i] := "a" END;
  text[H.MaxName] := "/"; text[H.MaxName + 1] := "B"; text[H.MaxName + 2] := 0X;
  C.Check(H.ParseMime(text, m, why) & (Length(m.type) = H.MaxName) & (m.subtype = "b"),
    "a type of 127 bytes");
  FOR i := 0 TO H.MaxName DO text[i] := "a" END;
  text[H.MaxName + 1] := "/"; text[H.MaxName + 2] := "b"; text[H.MaxName + 3] := 0X;
  BadMime(text, "a MIME type of more than 127 bytes");
  text := "a/"; FOR i := 2 TO H.MaxName + 2 DO text[i] := "b" END; text[H.MaxName + 3] := 0X;
  BadMime(text, "a MIME subtype of more than 127 bytes")
END Mimes;

(* Writing *)

(* WriteHeader(status, meta) writes expect, CR LF, and it reads back. *)
PROCEDURE Writes1(status: INTEGER; meta, expect: ARRAY OF CHAR);
  VAR n, i: LONGINT; ok: BOOLEAN;
BEGIN
  H.WriteHeader(status, meta, line, n);
  i := 0; ok := TRUE;
  WHILE expect[i] # 0X DO ok := ok & (line[i] = expect[i]); INC(i) END;
  ok := ok & (n = i + 2) & (line[i] = CR) & (line[i + 1] = LF) & (line[i + 2] = 0X);
  ok := ok & H.Parse(line, n, h, why) & (h.status = status) & (h.meta = meta);
  C.Check(ok, expect)
END Writes1;

PROCEDURE Writes;
  VAR n, e: LONGINT; s: INTEGER; ok: BOOLEAN;
BEGIN
  Writes1(20, "text/gemini", "20 text/gemini");
  Writes1(20, "text/gemini; lang=en", "20 text/gemini; lang=en");
  Writes1(10, "Name?", "10 Name?");
  Writes1(31, "gemini://example.org/", "31 gemini://example.org/");
  Writes1(51, "", "51");
  Writes1(44, "", "44");
  Writes1(60, "", "60");
  Writes1(59, "Ünïcode €", "59 Ünïcode €");
  (* every status the specification names, with a meta, and read back *)
  ok := TRUE;
  FOR s := 10 TO 69 DO
    IF S.Known(s) THEN
      H.WriteHeader(s, "m", line, n);
      ok := ok & H.Parse(line, n, h, why) & (h.status = s) & (h.meta = "m")
    END
  END;
  C.Check(ok, "every known status written and read back");
  FOR e := 0 TO H.MaxMeta - 1 DO text[e] := "x" END; text[H.MaxMeta] := 0X;
  H.WriteHeader(20, text, line, n);
  C.Check((n = H.MaxHeader) & H.Ended(line, n, e) & (e = n) & H.Parse(line, n, h, why)
    & (h.meta = text), "a meta of 1024 bytes: a header of 1029, read back")
END Writes;

BEGIN
  Statuses; Headers; Ends; Mimes; Writes;
  C.Summary
END TestHeaders.
