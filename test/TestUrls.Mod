MODULE TestUrls; (* GeminiUrls: a client's URLs, and a server's check *)

(* The server's check, CheckRequest, with every case of pogemini's
   TestParse, from which it was carried over; then the client's side:
   Parse, Write, Port, Resolve (RFC 3986 section 5.4's examples, all 42,
   taken from the RFC's text by a script), WithQuery, Encode and
   RequestLine. *)

IMPORT Out, C := Check, U := GeminiUrls;

CONST BOM = "﻿";  (* U+FEFF as UTF-8 *)

VAR
  r: U.Request; why: ARRAY 128 OF CHAR; status: INTEGER;
  u, base: U.URL;
  text, line: ARRAY 1100 OF CHAR;

(* The server's check. *)

(* url parses, to host, port, path and, if query isn't "-", query. *)
PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END; RETURN n
END Length;

PROCEDURE Good(url, host: ARRAY OF CHAR; port: LONGINT; path, query: ARRAY OF CHAR);
  VAR ok: BOOLEAN; label: ARRAY 1100 OF CHAR;
BEGIN
  status := U.CheckRequest(url, r, why);
  ok := (status = U.Ok) & (r.scheme = "gemini") & (r.host = host)
    & (r.port = port) & (r.path = path);
  IF query = "-" THEN ok := ok & ~r.hasQuery & (r.query = "")
  ELSE ok := ok & r.hasQuery & (r.query = query)
  END;
  COPY(url, label);
  IF Length(url) = 1024 THEN label := "(the 1024-byte URL)"
  ELSIF Length(url) > 100 THEN label := "(a long URL)"
  END;
  C.Check(ok, label);
  IF ~ok THEN
    Out.String("  status "); Out.Int(status, 0); Out.String(" "); Out.String(why);
    Out.String(", host "); Out.String(r.host); Out.String(", port "); Out.Int(r.port, 0);
    Out.String(", path "); Out.String(r.path); Out.String(", query "); Out.String(r.query); Out.Ln
  END
END Good;

(* url is refused with status, and a reason that is reason. *)
PROCEDURE Bad(label, url: ARRAY OF CHAR; st: INTEGER; reason: ARRAY OF CHAR);
  VAR ok: BOOLEAN;
BEGIN
  status := U.CheckRequest(url, r, why);
  ok := (status = st) & (why = reason);
  C.Check(ok, label);
  IF ~ok THEN Out.String("  status "); Out.Int(status, 0); Out.String(" "); Out.String(why); Out.Ln END
END Bad;

PROCEDURE Server;
  VAR u, p: ARRAY 1100 OF CHAR; d: ARRAY 64 OF CHAR; i, n: LONGINT;
BEGIN
  (* hosts and ports *)
  Good("gemini://example.org", "example.org", 1965, "/", "-");
  C.Check(r.rawPath = "", "  ... its raw path is empty");
  Good("gemini://example.org/", "example.org", 1965, "/", "-");
  Good("GEMINI://Example.ORG.:1966/a/b", "example.org", 1966, "/a/b", "-");
  Good("gemini://example.org:/x", "example.org", 1965, "/x", "-");
  Good("gemini://[::1]:1965/", "::1", 1965, "/", "-");
  Good("gemini://[2001:DB8::1]/", "2001:db8::1", 1965, "/", "-");
  Good("gemini://127.0.0.1:0/", "127.0.0.1", 0, "/", "-");
  Good("gemini://xn--bcher-kva.example/", "xn--bcher-kva.example", 1965, "/", "-");
  Good("gemini://bücher.example/", "bücher.example", 1965, "/", "-");
  Good("gemini://ex%41mple.org/", "example.org", 1965, "/", "-");

  (* paths *)
  Good("gemini://h/a/./b/../c/", "h", 1965, "/a/c/", "-");
  C.Check(r.rawPath = "/a/./b/../c/", "  ... its raw path is as sent");
  Good("gemini://h/a//b", "h", 1965, "/a/b", "-");
  Good("gemini://h/a/.", "h", 1965, "/a/", "-");
  Good("gemini://h/a/..", "h", 1965, "/", "-");
  Good("gemini://h/a/b/..", "h", 1965, "/a/", "-");
  Good("gemini://h/./a", "h", 1965, "/a", "-");
  Good("gemini://h/a/%2E%2E/b", "h", 1965, "/b", "-");
  Good("gemini://h/a/%2e/b", "h", 1965, "/a/b", "-");
  Good("gemini://h/...", "h", 1965, "/...", "-");
  Good("gemini://h/.a/..b", "h", 1965, "/.a/..b", "-");
  Good("gemini://h/a%20b/%C3%A9", "h", 1965, "/a b/é", "-");
  Good("gemini://h/é", "h", 1965, "/é", "-");
  Good("gemini://h/a~b_c-d!$&'()*+,;=:@", "h", 1965, "/a~b_c-d!$&'()*+,;=:@", "-");

  (* queries *)
  Good("gemini://h/search?gemini%20search", "h", 1965, "/search", "gemini%20search");
  C.Check(U.Decode(r.query, d, n) & (n = 13) & (d = "gemini search"),
    "  ... decoded: gemini search");
  Good("gemini://h/?", "h", 1965, "/", "");
  Good("gemini://h?q", "h", 1965, "/", "q");
  Good("gemini://h/a?b/../c?d", "h", 1965, "/a", "b/../c?d");
  C.Check(U.Decode("a%00b", d, n) & (n = 3) & (d[1] = 0X), "Decode: %00 is a byte");
  C.Check(~U.Decode("a%0", d, n), "Decode: a short escape, refused");
  C.Check(~U.Decode("0123456789012345678901234567890123456789012345678901234567890123", d, n),
    "Decode: too long for its buffer, refused");

  (* the longest *)
  u := "gemini://h/"; FOR i := 11 TO 1023 DO u[i] := "a" END; u[1024] := 0X;
  p := "/"; FOR i := 1 TO 1013 DO p[i] := "a" END; p[1014] := 0X;
  Good(u, "h", 1965, p, "-");
  u[1024] := "a"; u[1025] := 0X;
  Bad("a 1025-byte URL", u, 59, "the URL is over 1024 bytes");

  (* what the specification forbids *)
  Bad("userinfo", "gemini://u@h/", 59, "userinfo in the URL");
  Bad("userinfo with a password", "gemini://u:p@h/", 59, "userinfo in the URL");
  Bad("a fragment", "gemini://h/a#f", 59, "a fragment");
  Bad("an empty fragment", "gemini://h/#", 59, "a fragment");

  (* other schemes, which aren't served here *)
  Bad("https", "https://h/", 53, "only gemini: URLs are served here");
  Bad("mailto", "mailto:x@h", 53, "only gemini: URLs are served here");

  (* not URLs, or not well-formed *)
  Bad("empty", "", 59, "no URL");
  Bad("a relative reference", "//h/a", 59, "not an absolute URL");
  Bad("a path alone", "/a", 59, "not an absolute URL");
  Bad("no scheme", "h", 59, "not an absolute URL");
  Bad("a byte order mark first", BOM, 59, "not an absolute URL");
  u := BOM; COPY("gemini://h/", d); i := 0; WHILE d[i] # 0X DO u[3 + i] := d[i]; INC(i) END;
  u[3 + i] := 0X;
  Bad("a byte order mark before the URL", u, 59, "not an absolute URL");
  Bad("a space", "gemini://h/a b", 59, "a character not allowed in a URL");
  Bad("a tab", "gemini://h/a	b", 59, "a character not allowed in a URL");
  Bad("a backslash", "gemini://h/a\b", 59, "a character not allowed in a URL");
  Bad("no //", "gemini:/a", 59, "no host");
  Bad("no host", "gemini:///a", 59, "no host");
  Bad("only a port", "gemini://:1965/", 59, "no host");
  Bad("a port not a number", "gemini://h:x/", 59, "a malformed port");
  Bad("a port too large", "gemini://h:65536/", 59, "a malformed port");
  Bad("an IPv6 address unclosed", "gemini://[::1/", 59, "a malformed IPv6 address");
  Bad("an IPv6 address not hex", "gemini://[::g]/", 59, "a malformed IPv6 address");
  Bad("an empty IPv6 address", "gemini://[]/", 59, "a malformed IPv6 address");
  Bad("text after an IPv6 address", "gemini://[::1]x/", 59, "a malformed host");
  Bad("a bracket in a host", "gemini://h]/", 59, "a malformed host");
  Bad("an encoded space in a host", "gemini://a%20b/", 59, "a malformed host");
  Bad("bad encoding in a host", "gemini://a%2/", 59, "bad percent-encoding in the host");

  (* paths that leave the root, or that name no file *)
  Bad("..", "gemini://h/..", 59, "the path climbs above /");
  Bad("../a", "gemini://h/../a", 59, "the path climbs above /");
  Bad("a/../..", "gemini://h/a/../..", 59, "the path climbs above /");
  Bad("an encoded ..", "gemini://h/%2e%2E", 59, "the path climbs above /");
  Bad("an encoded / ", "gemini://h/a%2Fb", 59, "an encoded / in the path");
  Bad("an encoded ../ ", "gemini://h/..%2Fetc", 59, "an encoded / in the path");
  Bad("an encoded NUL", "gemini://h/a%00b", 59, "a control character in the path");
  Bad("an encoded LF", "gemini://h/a%0Ab", 59, "a control character in the path");
  Bad("an encoded DEL", "gemini://h/a%7Fb", 59, "a control character in the path");
  Bad("an encoded byte not UTF-8", "gemini://h/%FF", 59, "the path is not UTF-8");
  Bad("an encoded surrogate", "gemini://h/%ED%A0%80", 59, "the path is not UTF-8");
  Bad("a bad escape", "gemini://h/a%zz", 59, "bad percent-encoding in the path");
  Bad("a short escape", "gemini://h/a%4", 59, "bad percent-encoding in the path");
  Bad("a bad escape in the query", "gemini://h/?a%zz", 59, "bad percent-encoding in the query");

  (* malformed UTF-8 *)
  u := "gemini://h/"; u[11] := 0FFX; u[12] := 0X;
  Bad("a byte FF", u, 59, "the URL is not UTF-8");
  u[11] := 0C0X; u[12] := 80X; u[13] := 0X;
  Bad("an overlong NUL", u, 59, "the URL is not UTF-8");
  u[11] := 0E0X; u[12] := 80X; u[13] := 80X; u[14] := 0X;
  Bad("an overlong three bytes", u, 59, "the URL is not UTF-8");
  u[11] := 0F4X; u[12] := 90X; u[13] := 80X; u[14] := 80X; u[15] := 0X;
  Bad("over U+10FFFF", u, 59, "the URL is not UTF-8");
  u[11] := 0C3X; u[12] := 0X;
  Bad("cut short", u, 59, "the URL is not UTF-8");
  u[11] := 0F0X; u[12] := 9FX; u[13] := 98X; u[14] := 80X; u[15] := 0X;
  Good(u, "h", 1965, "/😀", "-");


  (* An IPv6 address too long for the host, which pogemini once copied
     in unchecked: the longest r.host holds, 255 bytes, and longer. *)
  u := "gemini://["; FOR i := 10 TO 264 DO u[i] := "a" END; u[265] := "]"; u[266] := "/"; u[267] := 0X;
  FOR i := 0 TO 254 DO p[i] := "a" END; p[255] := 0X;
  Good(u, p, 1965, "/", "-");
  u := "gemini://["; FOR i := 10 TO 265 DO u[i] := "a" END; u[266] := "]"; u[267] := "/"; u[268] := 0X;
  Bad("an IPv6 address of 256 bytes", u, 59, "a malformed IPv6 address");
  u := "gemini://["; FOR i := 10 TO 309 DO u[i] := "a" END; u[310] := "]"; u[311] := "/"; u[312] := 0X;
  Bad("an IPv6 address of 300 bytes", u, 59, "a malformed IPv6 address")
END Server;

(* The client's side. *)

(* s := n copies of c, after s[0..from-1]. *)
PROCEDURE Fill(VAR s: ARRAY OF CHAR; from: LONGINT; c: CHAR; n: LONGINT);
  VAR i: LONGINT;
BEGIN i := 0; WHILE i < n DO s[from + i] := c; INC(i) END; s[from + n] := 0X
END Fill;

(* u, written, is expected; if not, says what it is. *)
PROCEDURE Is(expected, label: ARRAY OF CHAR);
  VAR ok: BOOLEAN;
BEGIN
  ok := U.Write(u, text) & (text = expected);
  C.Check(ok, label);
  IF ~ok THEN Out.String("  got "); Out.String(text); Out.String(" "); Out.String(why); Out.Ln END
END Is;

(* s parses, and is written back as written. *)
PROCEDURE Parses(s, written: ARRAY OF CHAR);
BEGIN
  IF U.Parse(s, u, why) THEN Is(written, s)
  ELSE C.Check(FALSE, s); Out.String("  "); Out.String(why); Out.Ln
  END
END Parses;

(* s is refused for reason, u left empty. *)
PROCEDURE NotParsed(label, s, reason: ARRAY OF CHAR);
  VAR ok: BOOLEAN;
BEGIN
  ok := ~U.Parse(s, u, why) & (why = reason) & (u.scheme = "") & (u.host = "") & (u.path = "");
  C.Check(ok, label);
  IF ~ok THEN Out.String("  "); Out.String(why); Out.Ln END
END NotParsed;

(* ref, resolved against base, is expected. *)
PROCEDURE Res(ref, expected: ARRAY OF CHAR);
  VAR label: ARRAY 64 OF CHAR;
BEGIN

  COPY(ref, label); IF ref = "" THEN label := "(empty)" END;
  IF U.Resolve(base, ref, u, why) THEN Is(expected, label)
  ELSE C.Check(FALSE, label); Out.String("  "); Out.String(why); Out.Ln
  END
END Res;

(* u, parsed from s, gives the request line expected. *)
PROCEDURE Line(s, expected: ARRAY OF CHAR);
  VAR ok: BOOLEAN;
BEGIN
  ok := U.Parse(s, u, why) & U.RequestLine(u, line, why) & (line = expected) & (why = "");
  C.Check(ok, s);
  IF ~ok THEN Out.String("  got "); Out.String(line); Out.String(" "); Out.String(why); Out.Ln END
END Line;

(* u, parsed from s, has no request line, for a reason containing reason. *)
PROCEDURE NoLine(label, s, reason: ARRAY OF CHAR);
  VAR ok: BOOLEAN;
BEGIN
  line := "junk";
  ok := U.Parse(s, u, why) & ~U.RequestLine(u, line, why) & (line = "") & C.Contains(why, reason);
  C.Check(ok, label);
  IF ~ok THEN Out.String("  got "); Out.String(line); Out.String(" "); Out.String(why); Out.Ln END
END NoLine;

PROCEDURE Client;
  VAR s: ARRAY 1100 OF CHAR; small: ARRAY 8 OF CHAR; ok: BOOLEAN; i: LONGINT;
BEGIN
  (* Parse: any scheme, each part kept *)
  ok := U.Parse("GEMINI://Example.ORG.:1966/a/B?Q#F", u, why);
  C.Check(ok & (u.scheme = "gemini") & u.hasAuthority & ~u.hasUserinfo
    & (u.host = "example.org") & (u.port = 1966) & (u.path = "/a/B")
    & u.hasQuery & (u.query = "Q") & u.hasFragment & (u.fragment = "F") & (why = ""),
    "Parse: every part; scheme and host lowered, the host's final dot dropped");
  C.Check(U.Port(u) = 1966, "Port: as given");
  ok := U.Parse("gemini://h", u, why);
  C.Check(ok & (u.port = U.NoPort) & (U.Port(u) = U.DefaultPort) & (u.path = "") & ~u.hasQuery
    & ~u.hasFragment, "Parse: no port, path, query or fragment; Port gives 1965");
  ok := U.Parse("mailto:x@h", u, why);
  C.Check(ok & (u.scheme = "mailto") & ~u.hasAuthority & (u.path = "x@h") & (U.Port(u) = U.NoPort),
    "Parse: mailto, no authority; Port gives none");
  ok := U.Parse("HTTPS://u:p@[2001:DB8::1]:8443/", u, why);
  C.Check(ok & u.hasUserinfo & (u.userinfo = "u:p") & (u.host = "2001:db8::1") & (u.port = 8443),
    "Parse: userinfo, and an IPv6 address lowered without its brackets");
  ok := U.Parse("gemini://ex%41mple.org/", u, why);
  C.Check(ok & (u.host = "example.org"), "Parse: the host decoded");
  ok := U.Parse("gemini://bücher.example/é", u, why);
  C.Check(ok & (u.host = "bücher.example") & (u.path = "/é"), "Parse: UTF-8 kept");
  ok := U.Parse("gemini:///a", u, why);
  C.Check(ok & u.hasAuthority & (u.host = ""), "Parse: an empty host");

  (* Write: back as written, but for scheme and host *)
  Parses("GEMINI://Example.ORG.:1966/a/B?Q#F", "gemini://example.org:1966/a/B?Q#F");
  Parses("https://u:p@[2001:db8::1]:8443/", "https://u:p@[2001:db8::1]:8443/");
  Parses("gemini://h/?#", "gemini://h/?#");
  Parses("gemini://h:/", "gemini://h/");
  Parses("gemini://h/a%20b|c?%7C", "gemini://h/a%20b|c?%7C");
  Parses("mailto:x@h", "mailto:x@h");
  Parses("urn:isbn:0451450523", "urn:isbn:0451450523");
  ok := U.Parse("gemini://h/abc", u, why) & ~U.Write(u, small) & (small = "");
  C.Check(ok, "Write: too long for the buffer, refused, empty");

  (* Parse's refusals *)
  NotParsed("empty", "", "no URL");
  NotParsed("a path alone", "/a", "not an absolute URL");
  NotParsed("a relative reference", "//h/a", "not an absolute URL");
  NotParsed("a byte order mark first", BOM, "not an absolute URL");
  NotParsed("a space", "gemini://h/a b", "a space or control character in the URL");
  NotParsed("a tab", "gemini://h/a	b", "a space or control character in the URL");
  NotParsed("a port not a number", "gemini://h:x/", "a malformed port");
  NotParsed("a port too large", "gemini://h:65536/", "a malformed port");
  NotParsed("an IPv6 address unclosed", "gemini://[::1/", "a malformed IPv6 address");
  NotParsed("text after an IPv6 address", "gemini://[::1]x/", "a malformed host");
  NotParsed("an encoded space in a host", "gemini://a%20b/", "a malformed host");
  NotParsed("an encoded / in a host", "gemini://a%2Fb/", "a malformed host");
  NotParsed("bad encoding in a host", "gemini://a%2/", "bad percent-encoding in the host");
  NotParsed("an encoded host not UTF-8", "gemini://%FF/", "the host is not UTF-8");
  s := "gemini://h/"; s[11] := 0FFX; s[12] := 0X;
  NotParsed("a byte FF", s, "the URL is not UTF-8");
  s := "gemini://["; Fill(s, 10, "a", 300); s[310] := "]"; s[311] := 0X;
  NotParsed("an IPv6 address of 300 bytes", s, "a malformed IPv6 address");
  s := "gemini://h/"; Fill(s, 11, "a", 1013);
  C.Check(U.Parse(s, u, why), "Parse: a 1024-byte URL");
  Fill(s, 11, "a", 1014);
  NotParsed("a 1025-byte URL", s, "the URL is over 1024 bytes");

  (* Resolve: RFC 3986, section 5.4 *)
  ok := U.Parse("http://a/b/c/d;p?q", base, why); C.Check(ok, "the RFC's base");
  Res("g:h", "g:h");
  Res("g", "http://a/b/c/g");
  Res("./g", "http://a/b/c/g");
  Res("g/", "http://a/b/c/g/");
  Res("/g", "http://a/g");
  Res("//g", "http://g");
  Res("?y", "http://a/b/c/d;p?y");
  Res("g?y", "http://a/b/c/g?y");
  Res("#s", "http://a/b/c/d;p?q#s");
  Res("g#s", "http://a/b/c/g#s");
  Res("g?y#s", "http://a/b/c/g?y#s");
  Res(";x", "http://a/b/c/;x");
  Res("g;x", "http://a/b/c/g;x");
  Res("g;x?y#s", "http://a/b/c/g;x?y#s");
  Res("", "http://a/b/c/d;p?q");
  Res(".", "http://a/b/c/");
  Res("./", "http://a/b/c/");
  Res("..", "http://a/b/");
  Res("../", "http://a/b/");
  Res("../g", "http://a/b/g");
  Res("../..", "http://a/");
  Res("../../", "http://a/");
  Res("../../g", "http://a/g");
  Res("../../../g", "http://a/g");
  Res("../../../../g", "http://a/g");
  Res("/./g", "http://a/g");
  Res("/../g", "http://a/g");
  Res("g.", "http://a/b/c/g.");
  Res(".g", "http://a/b/c/.g");
  Res("g..", "http://a/b/c/g..");
  Res("..g", "http://a/b/c/..g");
  Res("./../g", "http://a/b/g");
  Res("./g/.", "http://a/b/c/g/");
  Res("g/./h", "http://a/b/c/g/h");
  Res("g/../h", "http://a/b/c/h");
  Res("g;x=1/./y", "http://a/b/c/g;x=1/y");
  Res("g;x=1/../y", "http://a/b/c/y");
  Res("g?y/./x", "http://a/b/c/g?y/./x");
  Res("g?y/../x", "http://a/b/c/g?y/../x");
  Res("g#s/./x", "http://a/b/c/g#s/./x");
  Res("g#s/../x", "http://a/b/c/g#s/../x");
  Res("http:g", "http:g");

  (* Resolve: more *)
  ok := U.Parse("http://a/b/../c?q", base, why);
  Res("#f", "http://a/b/../c?q#f");   (* the base's path as it is, by 5.2.2 *)
  ok := U.Parse("gemini://h", base, why);
  Res("x", "gemini://h/x");            (* an empty base path, by 5.2.3 *)
  Res("gemini://Other.Example./y", "gemini://other.example/y");
  Res("//o/", "gemini://o/");
  ok := U.Parse("gemini://h/a/b", base, why);
  Res("é?ü", "gemini://h/a/é?ü");
  ok := U.Resolve(base, "c", base, why);
  C.Check(ok, "Resolve: into its base"); u := base; Is("gemini://h/a/c", "  ... which is the result");
  ok := ~U.Resolve(base, "a b", u, why) & (why = "a space or control character in the URL") & (u.scheme = "");
  C.Check(ok, "Resolve: a malformed reference, refused, the result empty");
  s := "gemini://h/"; Fill(s, 11, "a", 1000); s[1011] := "/"; s[1012] := 0X; ok := U.Parse(s, base, why);
  s := ""; Fill(s, 0, "b", 100);
  ok := ok & ~U.Resolve(base, s, u, why) & (why = "the URL is over 1024 bytes") & (u.scheme = "");
  C.Check(ok, "Resolve: a result over 1024 bytes, refused");

  (* WithQuery and Encode *)
  s := "a b"; s[3] := 0AX; s[4] := "c"; s[5] := 0X;
  ok := U.Parse("gemini://h/search?old#frag", u, why) & U.WithQuery(u, s, why);
  C.Check(ok, "WithQuery"); Is("gemini://h/search?a%20b%0Ac", "  ... a space and a line feed encoded, the fragment dropped");
  ok := U.WithQuery(u, "-._~é&=/?#%+", why);
  Is("gemini://h/search?-._~%C3%A9%26%3D%2F%3F%23%25%2B", "WithQuery: all but unreserved encoded");
  ok := U.WithQuery(u, "", why) & u.hasQuery;
  Is("gemini://h/search?", "WithQuery: an empty answer, an empty query");
  s := ""; Fill(s, 0, "&", 400);
  ok := ~U.WithQuery(u, s, why) & (why = "the answer is too long");
  C.Check(ok, "WithQuery: an answer too long, refused"); Is("gemini://h/search?", "  ... u unchanged");
  C.Check(~U.Encode("a b c", small) & (small = ""), "Encode: too long for the buffer, refused, empty");

  (* RequestLine *)
  Line("gemini://Bücher.Example./é?ü#frag", "gemini://xn--bcher-kva.example/%C3%A9?%C3%BC");
  Line("gemini://h", "gemini://h/");
  Line("gemini://h:1966?q", "gemini://h:1966/?q");
  Line("gemini://[::1]:1965/", "gemini://[::1]:1965/");
  Line("gemini://h/a%20b?c%2Fd", "gemini://h/a%20b?c%2Fd");
  Line("gemini://h/a|b{c}\^`", "gemini://h/a%7Cb%7Bc%7D%5C%5E%60");
  Line("gemini://h/a!$&'()*+,;=:@~?/?", "gemini://h/a!$&'()*+,;=:@~?/?");
  Line("titan://h/x", "titan://h/x");
  NoLine("userinfo", "gemini://u@h/", "userinfo in the URL");
  NoLine("no authority", "mailto:x@h", "no host");
  NoLine("an empty host", "gemini:///a", "no host");
  NoLine("an empty label", "gemini://a..b/", "the host: label 2");
  s := "gemini://h/"; Fill(s, 11, "a", 1013); Line(s, s);
  s := "gemini://h/"; i := 11; WHILE i < 611 DO s[i] := 0C3X; s[i + 1] := 0A9X; INC(i, 2) END; s[i] := 0X;
  NoLine("over 1024 bytes once encoded", s, "the URL is over 1024 bytes");
  ok := U.Parse("gemini://h/abc", u, why) & ~U.RequestLine(u, small, why) & (small = "")
    & (why = "too long for the buffer");
  C.Check(ok, "RequestLine: too long for the buffer, refused, empty")
END Client;

BEGIN
  Server;
  Client;
  C.Summary
END TestUrls.
