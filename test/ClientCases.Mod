MODULE ClientCases; (* the checks GeminiClient and GeminiFetch must both pass *)

(* One fetch procedure's checks against test/TestServer (PLAN.md,
   Phase 4), so that TestClient, in a task, and TestFetch, without
   tasks, run exactly the same ones: what a response gives, over IPv4
   and IPv6, with and without SNI and a client certificate, the CA file
   verifying or not, the body as a stream and whole, its limit, closing
   early, and each fault the server makes, each failure the network
   gives, each URL that can't be fetched, and a slow name lookup, which
   the deadline covers. Run from test/, with the certificates in
   ../build/certs. *)

IMPORT SYSTEM, Sockets, Check, GeminiResponses;

CONST
  Certs = "../build/certs/";
  Slack = 1000;     (* ms a timed fetch may run late on a busy machine *)

TYPE
  Fetcher* = PROCEDURE (link-: ARRAY OF CHAR; VAR opts: GeminiResponses.Options;
    VAR r: GeminiResponses.Response): BOOLEAN;

VAR
  fetch: Fetcher;
  port: INTEGER;

(* posockets' hook for its own tests (its PLAN.md, Phase 11): every name
   lookup started after it waits ms in its thread before getaddrinfo,
   so a lookup of localhost is slow enough to time out, with no name
   server. *)
PROCEDURE ["C", "Sockets.-set-resolve-delay"] CSetResolveDelay(ms: SYSTEM.INT32);

PROCEDURE SetResolveDelay*(ms: INTEGER);
BEGIN CSetResolveDelay(ms)
END SetResolveDelay;

(* s := s + t *)
PROCEDURE Append*(VAR s: ARRAY OF CHAR; t-: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0;
  WHILE (j < LEN(t)) & (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE AppendInt*(VAR s: ARRAY OF CHAR; n: LONGINT);
  VAR d: ARRAY 24 OF CHAR; i: INTEGER; t: ARRAY 2 OF CHAR;
BEGIN
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  t[1] := 0X;
  WHILE i > 0 DO DEC(i); t[0] := d[i]; Append(s, t) END
END AppendInt;

(* url := "gemini://" host ":" port path *)
PROCEDURE Url*(host-: ARRAY OF CHAR; port: LONGINT; path-: ARRAY OF CHAR; VAR url: ARRAY OF CHAR);
BEGIN
  COPY("gemini://", url); Append(url, host); Append(url, ":"); AppendInt(url, port); Append(url, path)
END Url;

(* path := Certs + name *)
PROCEDURE Cert(name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
BEGIN COPY(Certs, path); Append(path, name)
END Cert;

PROCEDURE Local(path-: ARRAY OF CHAR; VAR url: ARRAY OF CHAR);
BEGIN Url("localhost", port, path, url)
END Local;

(* Whether s[0..len-1] contains part *)
PROCEDURE Has*(VAR s: ARRAY OF CHAR; len: LONGINT; part-: ARRAY OF CHAR): BOOLEAN;
  VAR i, j: LONGINT;
BEGIN
  i := 0;
  WHILE i < len DO
    j := 0;
    WHILE (j < LEN(part)) & (part[j] # 0X) & (i + j < len) & (s[i + j] = part[j]) DO INC(j) END;
    IF (j = LEN(part)) OR (part[j] = 0X) THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END Has;

PROCEDURE StartsWith(s-, prefix: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE prefix[i] # 0X DO
    IF s[i] # prefix[i] THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END StartsWith;

(* Whether s[from..to-1] is TestServer's /big pattern there *)
PROCEDURE IsBig*(VAR s: ARRAY OF CHAR; from, to, offset: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  FOR i := from TO to - 1 DO
    IF s[i] # CHR(ORD("a") + (offset + i) MOD 26) THEN RETURN FALSE END
  END;
  RETURN TRUE
END IsBig;

(* The line "name value" of TestServer's echo, value only *)
PROCEDURE Line(VAR body: ARRAY OF CHAR; len: LONGINT; name: ARRAY OF CHAR; VAR value: ARRAY OF CHAR);
  VAR i, j, k: LONGINT;
BEGIN
  value[0] := 0X; i := 0;
  WHILE i < len DO
    j := 0;
    WHILE (name[j] # 0X) & (i + j < len) & (body[i + j] = name[j]) DO INC(j) END;
    IF (name[j] = 0X) & (i + j < len) & (body[i + j] = " ") & ((i = 0) OR (body[i - 1] = 0AX)) THEN
      INC(j); k := 0;
      WHILE (i + j < len) & (body[i + j] # 0AX) & (k < LEN(value) - 1) DO
        value[k] := body[i + j]; INC(k); INC(j)
      END;
      value[k] := 0X; RETURN
    END;
    INC(i)
  END
END Line;

(* Fetches TestServer's echo at link: its lines' values in url, sni and cert *)
PROCEDURE Echo(link-: ARRAY OF CHAR; VAR opts: GeminiResponses.Options;
    VAR r: GeminiResponses.Response; VAR url, sni, cert: ARRAY OF CHAR): BOOLEAN;
  VAR body: GeminiResponses.Chars; len: LONGINT;
BEGIN
  url[0] := 0X; sni[0] := 0X; cert[0] := 0X;
  IF ~fetch(link, opts, r) OR ~r.ReadAll(body, len) THEN RETURN FALSE END;
  Line(body^, len, "url", url); Line(body^, len, "sni", sni); Line(body^, len, "cert", cert);
  RETURN TRUE
END Echo;

PROCEDURE Basics;
  VAR o: GeminiResponses.Options; r: GeminiResponses.Response; ok: BOOLEAN;
    link, url, sni, cert, cert1: ARRAY 1100 OF CHAR;
BEGIN
  GeminiResponses.InitOptions(o);
  Local("/", link);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok & (r.status = 20) & (r.meta = "text/gemini") & r.complete
    & (r.error.kind = GeminiResponses.none), "a fetch over localhost: 20 text/gemini, complete");
  Check.Check(url = link, "the request was the URL");
  Check.Check(sni = "localhost", "SNI named the host");
  Check.Check(cert = "-", "no client certificate was sent");
  Check.Check(StartsWith(r.version, "TLSv1.") & StartsWith(r.peerHash, "SHA256:"),
    "the TLS version and the server's fingerprint are given");
  Check.Check(r.url.host = "localhost", "url is what was fetched");
  Check.Check((r.host = "localhost") & (r.port = port), "host and port, as connected to");

  Url("127.0.0.1", port, "/", link);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok & (url = link) & (sni = "-"), "over IPv4 by address, with no SNI");
  Url("[::1]", port, "/", link);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok & (url = link) & (sni = "-"), "over IPv6 by address, with no SNI");
  Url("LocalHost", port, "/a?b", link);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok & (sni = "localhost") & Check.Contains(url, "/a?b"),
    "the host as written is sent lowercased by SNI, the query as it is");
  Check.Check(r.host = "localhost", "... and given lowercased in host, as a trust store knows it");
  Url("[::1]", port, "/", link);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok & (r.host = "::1"), "an IPv6 address in host, without its brackets");

  (* A client certificate *)
  Cert("client1-ec.crt", o.certFile); Cert("client1-ec.key", o.keyFile);
  Local("/", link);
  ok := Echo(link, o, r, url, sni, cert1);
  Check.Check(ok & StartsWith(cert1, "SHA256:"), "a client certificate is sent");
  Cert("client2-rsa.crt", o.certFile); Cert("client2-rsa.key", o.keyFile);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok & StartsWith(cert, "SHA256:") & (cert # cert1), "and another, an RSA one");
  Cert("nonexistent.key", o.keyFile);
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.tls) & (r.status = 0);
  Check.Check(ok, "a key file that won't load: tls");
  Check.Check(Check.Contains(r.error.text, "client certificate"), "its text says so");

  (* Verifying the server *)
  GeminiResponses.InitOptions(o);
  Cert("ca-ec.crt", o.caFile);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok, "the server's certificate verified by its CA, by name");
  Url("127.0.0.1", port, "/", link);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok, "and by IPv4 address");
  Url("[::1]", port, "/", link);
  ok := Echo(link, o, r, url, sni, cert);
  Check.Check(ok, "and by IPv6 address");
  Cert("ca-rsa.crt", o.caFile);
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.tls);
  Check.Check(ok & Check.Contains(r.error.text, "handshake"),
    "and not by another CA: tls, in the handshake");
  Cert("nonexistent.crt", o.caFile);
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.tls);
  Check.Check(ok & Check.Contains(r.error.text, "CA file"), "a CA file that won't load: tls")
END Basics;

PROCEDURE Bodies;
  CONST Big = 300000;
  VAR o: GeminiResponses.Options; r: GeminiResponses.Response; ok: BOOLEAN;
    link: ARRAY 256 OF CHAR; body: GeminiResponses.Chars; buf: GeminiResponses.Chars;
    len, n, total: LONGINT;
BEGIN
  GeminiResponses.InitOptions(o);
  Local("/big?300000", link);
  ok := fetch(link, o, r) & (r.status = 20) & (r.meta = "application/octet-stream")
    & r.ReadAll(body, len);
  Check.Check(ok & (len = Big) & IsBig(body^, 0, len, 0) & (body[len] = 0X) & (r.bodyRead = Big),
    "ReadAll: the whole of a 300000-byte body, 0X after it");
  ok := ~r.Read(body^, 0, 10, n) & (n = 0) & r.complete;
  Check.Check(ok, "and Read after it gives the end again");

  NEW(buf, 1000);
  ok := fetch(link, o, r); total := 0;
  WHILE ok & r.Read(buf^, 0, 1000, n) DO
    (* the pattern continues across reads *)
    ok := (n >= 1) & (n <= 1000) & IsBig(buf^, 0, n, total);
    INC(total, n)
  END;
  Check.Check(ok & (total = Big) & r.complete & (r.error.kind = GeminiResponses.none),
    "Read: the same body in pieces of 1000 at most, complete");
  ok := fetch(link, o, r) & r.Read(buf^, 10, 0, n) & (n = 0);
  Check.Check(ok, "Read of 0 bytes reads nothing, while there is more");
  r.Close;

  (* The limit *)
  o.maxBody := 1000;
  Local("/big?1000", link);
  ok := fetch(link, o, r) & r.ReadAll(body, len);
  Check.Check(ok & (len = 1000), "a body of exactly maxBody is complete");
  o.maxBody := 999;
  ok := fetch(link, o, r) & ~r.ReadAll(body, len);
  Check.Check(ok & (len = 999) & (r.error.kind = GeminiResponses.tooLong) & ~r.complete,
    "one byte more is tooLong, after maxBody bytes");
  Check.Check(Check.Contains(r.error.text, "999"), "its text gives the limit");
  o.maxBody := 0;

  (* Closing early *)
  Local("/big?3000000", link);
  ok := fetch(link, o, r) & r.Read(buf^, 0, 1000, n);
  r.Close;
  Check.Check(ok & ~r.Read(buf^, 0, 1000, n) & ~r.complete & (r.error.kind = GeminiResponses.none),
    "Close part way: Read gives the end, not complete, and no error");
  r.Close;
  Check.Check(TRUE, "and Close again does nothing")
END Bodies;

PROCEDURE Statuses;
  VAR o: GeminiResponses.Options; r: GeminiResponses.Response; ok: BOOLEAN;
    link: ARRAY 256 OF CHAR; buf: ARRAY 10 OF CHAR; n: LONGINT;
BEGIN
  GeminiResponses.InitOptions(o);
  Local("/status/51", link);
  ok := fetch(link, o, r) & (r.status = 51) & (r.meta = "status 51") & r.complete;
  Check.Check(ok, "51: its header, and complete at once");
  Check.Check(~r.Read(buf, 0, 10, n) & (n = 0), "and no body");
  Local("/status/10", link);
  ok := fetch(link, o, r) & (r.status = 10) & (r.meta = "status 10") & r.complete;
  Check.Check(ok, "10, input: its prompt");
  Local("/status/31", link);
  ok := fetch(link, o, r) & (r.status = 31) & r.complete;
  Check.Check(ok, "31, a redirect, isn't followed");
  Local("/status/20", link);
  ok := fetch(link, o, r) & (r.status = 20) & ~r.Read(buf, 0, 10, n) & r.complete;
  Check.Check(ok, "20 with an empty body: complete at once");
  Local("/junk", link);
  ok := fetch(link, o, r) & (r.status = 51) & r.complete & (r.error.kind = GeminiResponses.none);
  Check.Check(ok, "bytes after a header that has no body are ignored");
  Local("/cuthead", link);
  ok := fetch(link, o, r) & (r.status = 51) & ~r.complete
    & (r.error.kind = GeminiResponses.truncated)
    & Check.Contains(r.error.text, "the response ended without close_notify (");
  Check.Check(ok, "51 without close_notify: its header, not complete, truncated, saying so")
END Statuses;

PROCEDURE Faults;
  VAR o: GeminiResponses.Options; r: GeminiResponses.Response; ok: BOOLEAN;
    link: ARRAY 256 OF CHAR; body: GeminiResponses.Chars; len, t0, el: LONGINT;
BEGIN
  GeminiResponses.InitOptions(o);
  Local("/badheader", link);
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.header) & (r.status = 0);
  Check.Check(ok, "a header with no status: header");
  Local("/nocrlf", link);
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.header);
  Check.Check(ok & Check.Contains(r.error.text, "ended in its header"),
    "a header with no line end: header, ended in it");
  Local("/longmeta", link);
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.header);
  Check.Check(ok, "a meta over 1024 bytes: header");
  Local("/empty", link);
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.header);
  Check.Check(ok & Check.Contains(r.error.text, "no header"), "no response at all: header");
  Local("/cut", link);
  ok := fetch(link, o, r) & (r.status = 20) & ~r.ReadAll(body, len);
  Check.Check(ok & (body^ = "partial") & ~r.complete & (r.error.kind = GeminiResponses.truncated)
    & Check.Contains(r.error.text, "the body ended without close_notify, so it may be incomplete ("),
    "a body without close_notify: what came, and truncated, saying so");
  Local("/cutinhead", link);
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.header)
    & Check.Contains(r.error.text, "the response ended in its header, without close_notify (");
  Check.Check(ok, "a header cut off without close_notify: header, saying so");

  o.deadline := 300;
  Local("/stall", link);
  t0 := Sockets.Now();
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.timedOut);
  el := Sockets.Now() - t0;
  Check.Check(ok & (el >= 295) & (el < 300 + Slack), "a server that stalls before its header: timedOut at the deadline");
  Check.Check(Check.Contains(r.error.text, "timed out"), "its text says so");
  Local("/stallbody", link);
  t0 := Sockets.Now();
  ok := fetch(link, o, r) & ~r.ReadAll(body, len);
  el := Sockets.Now() - t0;
  Check.Check(ok & (body^ = "partial") & (r.error.kind = GeminiResponses.timedOut)
    & (el >= 295) & (el < 300 + Slack),
    "one that stalls in its body: what came, then timedOut at the deadline")
END Faults;

(* Failures before a server answers *)
PROCEDURE Network;
  VAR o: GeminiResponses.Options; r: GeminiResponses.Response; ok: BOOLEAN;
    link: ARRAY 256 OF CHAR; ls: ARRAY 2 OF Sockets.Socket; n: INTEGER;
    a: Sockets.Address; err: Sockets.Error; t0, el: LONGINT;
BEGIN
  GeminiResponses.InitOptions(o);
  (* A port nothing listens on: one just closed *)
  ok := Sockets.Listen("127.0.0.1", 0, 1, TRUE, ls, n, err) & Sockets.LocalAddress(ls[0], a, err);
  IF ok THEN Sockets.Close(ls[0]) END;
  Url("127.0.0.1", a.port, "/", link);
  ok := ok & ~fetch(link, o, r) & (r.error.kind = GeminiResponses.connect);
  Check.Check(ok, "a port nothing listens on: connect");
  ok := ~fetch("gemini://nonexistent.invalid/", o, r) & (r.error.kind = GeminiResponses.resolve);
  Check.Check(ok & Check.Contains(r.error.text, "nonexistent.invalid"),
    "a name that doesn't resolve: resolve, naming it");

  (* A listener that never accepts: the connection is made by the
     kernel, and the handshake gets no answer. *)
  ok := Sockets.Listen("127.0.0.1", 0, 4, TRUE, ls, n, err) & Sockets.LocalAddress(ls[0], a, err);
  Url("127.0.0.1", a.port, "/", link);
  o.deadline := 300;
  t0 := Sockets.Now();
  ok := ok & ~fetch(link, o, r) & (r.error.kind = GeminiResponses.timedOut);
  el := Sockets.Now() - t0;
  Check.Check(ok & (el >= 295) & (el < 300 + Slack) & Check.Contains(r.error.text, "handshake"),
    "a server that never answers the handshake: timedOut at the deadline");
  IF n > 0 THEN Sockets.Close(ls[0]) END
END Network;

(* A slow name lookup (posockets resolves names in a thread since its
   Phase 11): the deadline covers it, and a fetch that has time for it
   succeeds. *)
PROCEDURE Lookups;
  CONST Delay = 300;
  VAR o: GeminiResponses.Options; r: GeminiResponses.Response; ok: BOOLEAN;
    link: ARRAY 256 OF CHAR; t0, el, len: LONGINT; body: GeminiResponses.Chars;
BEGIN
  GeminiResponses.InitOptions(o);
  SetResolveDelay(Delay);
  Local("/", link);
  o.deadline := 100;
  t0 := Sockets.Now();
  ok := ~fetch(link, o, r) & (r.error.kind = GeminiResponses.timedOut);
  el := Sockets.Now() - t0;
  Check.Check(ok & (el >= 95) & (el < 100 + Slack)
    & Check.Contains(r.error.text, "resolve localhost port"),
    "a lookup slower than the deadline: timedOut at the deadline, naming the lookup");
  o.deadline := 5000;
  t0 := Sockets.Now();
  ok := fetch(link, o, r) & (r.status = 20) & r.ReadAll(body, len) & r.complete;
  el := Sockets.Now() - t0;
  IF r # NIL THEN r.Close END;
  Check.Check(ok & (el >= Delay - 5), "a slow lookup within the deadline: fetched");
  SetResolveDelay(0)
  (* The abandoned lookup's thread was done before the second fetch's,
     started later with the same delay, so none is left running. *)
END Lookups;

PROCEDURE Urls;
  VAR o: GeminiResponses.Options; r: GeminiResponses.Response; ok: BOOLEAN;
BEGIN
  GeminiResponses.InitOptions(o);
  ok := ~fetch("https://localhost/", o, r) & (r.error.kind = GeminiResponses.request)
    & (r.status = 0) & ~r.complete;
  Check.Check(ok, "an https URL: request");
  ok := ~fetch("/relative", o, r) & (r.error.kind = GeminiResponses.request);
  Check.Check(ok, "a relative reference: request");
  ok := ~fetch("gemini://user@localhost/", o, r) & (r.error.kind = GeminiResponses.request);
  Check.Check(ok, "userinfo: request");
  ok := ~fetch("gemini:///path", o, r) & (r.error.kind = GeminiResponses.request);
  Check.Check(ok, "no host: request");
  Check.Check((r.host = "") & (r.port = 0), "... and no host or port given")
END Urls;

(* All of the checks, fetching with f from TestServer at port. *)
PROCEDURE Run*(f: Fetcher; serverPort: INTEGER);
BEGIN
  fetch := f; port := serverPort;
  Basics; Bodies; Statuses; Faults; Network; Lookups; Urls
END Run;

END ClientCases.
