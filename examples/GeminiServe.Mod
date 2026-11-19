MODULE GeminiServe; (* a small Gemini server, on GeminiServer *)

(* Usage: GeminiServe (-cert file -key file | -certs dir) [-listen host]
                     [-port port] [-host name] [-n count] [-deadline ms]
                     [-connections n]

   Serves a page made as it is asked for, at "/" of host name
   ("localhost" if not given), and a greeting at "/hello", which asks
   for a name (10) and answers with it; anything else is 51, a request
   GeminiUrls.CheckRequest refuses gets its status and why, and one for
   another host or port 53. It presents the certificate in -cert and
   -key, or, with -certs, its own for the host name, made in dir the
   first time and kept there (GeminiIdentities.Ensure); and accepts any
   client certificate, as a Gemini server does, showing its hash on the
   page.

   It listens on -listen ("" for every local address, IPv6 and IPv4
   alike) at -port (1965; 0 for one the kernel chooses), says "port
   <n>" on standard output as its first line, then logs a line for each
   connection, each beginning with the time, UTC:

     <time> <client address> <status> <request> <client certificate | ->
     <time> <client address> failed: <why>

   the request with its control characters as %XX, so a line of log is
   always one line. It serves count connections (-n; until SIGTERM or
   SIGINT if not given), each within -deadline ms (10000), at most
   -connections at once (256), then exits 0. Exits 1 if it can't
   start, saying why on standard error, and 2 for bad usage.

   It shows GeminiServer: a Responder answering from a request
   CheckRequest has checked, a page written by a Writer, and a Logger;
   and the tests drive it (TestServe, TestRun). *)

IMPORT Platform, Out, Err, Args, Clocks, Instants, TimeStrings, Sockets, Tls,
  GeminiUrls, GeminiTextWriter, GeminiIdentities, GeminiServer;

CONST
  Days = 3650;  (* a made certificate's lifetime *)

VAR
  host: ARRAY 256 OF CHAR;   (* the one served, "" for any *)

PROCEDURE Usage;
BEGIN
  Err.String("usage: GeminiServe (-cert file -key file | -certs dir) [-listen host]"); Err.Ln;
  Err.String("                   [-port port] [-host name] [-n count] [-deadline ms]"); Err.Ln;
  Err.String("                   [-connections n]"); Err.Ln;
  Platform.Exit(2)
END Usage;

PROCEDURE Fail(what, why: ARRAY OF CHAR);
BEGIN
  Err.String("GeminiServe: "); Err.String(what); Err.String(": "); Err.String(why); Err.Ln;
  Platform.Exit(1)
END Fail;

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END; RETURN n
END Length;

(* Appends t to s, as much as fits. *)
PROCEDURE Append(VAR s: ARRAY OF CHAR; t-: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := Length(s); j := 0;
  WHILE (i < LEN(s) - 1) & (j < LEN(t)) & (t[j] # 0X) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

(* The page at "/". Each line is written as it is made; a line the
   Writer refuses (why) ends it, as the connection is no use then. *)
PROCEDURE Home(x: GeminiServer.Exchange);
  VAR w: GeminiServer.Writer; why: ARRAY 128 OF CHAR; line: ARRAY 256 OF CHAR;
BEGIN
  IF x.Header(20, "text/gemini") THEN
    w := GeminiServer.NewWriter(x);
    line := "Hello, "; Append(line, x.peer.host); Append(line, ".");
    IF GeminiTextWriter.Heading(w, 1, "GeminiServe", why)
      & GeminiTextWriter.Text(w, "", why)
      & GeminiTextWriter.Text(w, line, why) THEN
      IF x.certHash = NIL THEN line := "You sent no client certificate."
      ELSE line := "Your client certificate: "; Append(line, x.certHash^)
      END;
      IF GeminiTextWriter.Text(w, line, why)
        & GeminiTextWriter.Link(w, "/hello", "Be greeted by name", why) THEN
      END
    END
  END
END Home;

(* "/hello": asks for a name, and greets it. *)
PROCEDURE Hello(x: GeminiServer.Exchange; VAR r: GeminiUrls.Request);
  VAR w: GeminiServer.Writer; name: GeminiUrls.Text; line: ARRAY 1100 OF CHAR;
    why: ARRAY 128 OF CHAR; n: LONGINT;
BEGIN
  IF ~r.hasQuery OR (r.query = "") THEN
    IF x.Header(10, "Your name?") THEN END
  ELSIF ~GeminiUrls.Decode(r.query, name, n) OR ~GeminiUrls.Utf8(name, n) OR (n # Length(name)) THEN
    IF x.Header(59, "the name isn't percent-encoded UTF-8") THEN END
  ELSIF x.Header(20, "text/gemini") THEN
    w := GeminiServer.NewWriter(x);
    line := "Hello, "; Append(line, name); Append(line, ".");
    (* A name with a line end in it is no line of gemtext. *)
    IF ~GeminiTextWriter.Text(w, line, why) THEN
      IF GeminiTextWriter.Text(w, "Hello. (Your name can't be written as one line.)", why) THEN END
    END
  END
END Hello;

PROCEDURE Respond(x: GeminiServer.Exchange);
  VAR r: GeminiUrls.Request; why: ARRAY 128 OF CHAR; status: INTEGER;
BEGIN
  status := GeminiUrls.CheckRequest(x.request, r, why);
  IF status # GeminiUrls.Ok THEN
    IF x.Header(status, why) THEN END
  ELSIF ((host # "") & (r.host # host)) OR (r.port # x.server.port) THEN
    IF x.Header(GeminiUrls.Refused, "not served here") THEN END
  ELSIF r.path = "/" THEN Home(x)
  ELSIF r.path = "/hello" THEN Hello(x, r)
  ELSIF x.Header(51, "not found") THEN
  END
END Respond;

(* Writes s with its control characters as %XX. *)
PROCEDURE OutEscaped(s-: ARRAY OF CHAR);
  CONST hex = "0123456789ABCDEF";
  VAR i: LONGINT; h: ARRAY 17 OF CHAR;
BEGIN
  h := hex; i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF (s[i] < " ") OR (s[i] = 7FX) THEN
      Out.Char("%"); Out.Char(h[ORD(s[i]) DIV 16]); Out.Char(h[ORD(s[i]) MOD 16])
    ELSE Out.Char(s[i])
    END;
    INC(i)
  END
END OutEscaped;

(* A line of log, beginning with the time, UTC, in whole seconds (as
   2026-11-16T12:34:56Z), from poDateTime: the C library's gmtime_r
   loads the zone first, which needs more stack than a task has on
   NetBSD and OpenBSD. Nothing in it waits, so lines never mix. *)
PROCEDURE Log(s: GeminiServer.Server; event: INTEGER; x: GeminiServer.Exchange; why-: ARRAY OF CHAR);
  VAR now: Instants.Instant; t: ARRAY 32 OF CHAR;
BEGIN
  Clocks.Now(now); TimeStrings.Instant(now, 0, t);
  Out.String(t); Out.Char(" ");
  CASE event OF
  | GeminiServer.served:
    Out.String(x.peer.host); Out.Char(" "); Out.Int(x.status, 0); Out.Char(" ");
    IF x.request = "" THEN Out.Char("-") ELSE OutEscaped(x.request) END;
    Out.Char(" ");
    IF x.certHash = NIL THEN Out.Char("-") ELSE Out.String(x.certHash^) END
  | GeminiServer.failed:
    Out.String(x.peer.host); Out.String(" failed: "); Out.String(why)
  | GeminiServer.acceptFailed:
    Out.String("accept failed: "); Out.String(why)
  | GeminiServer.stopping:
    Out.String("stopping on signal "); Out.Int(s.signal, 0);
    Out.String(", connections in progress: "); Out.Int(s.active, 0)
  | GeminiServer.stopped:
    Out.String("stopped")
  END;
  Out.Ln
END Log;

PROCEDURE Main;
  VAR i: INTEGER; arg, cert, key, certs, listen, name: ARRAY 1024 OF CHAR;
    port, count, deadline, limit: LONGINT; id: GeminiIdentities.Identity;
    why: ARRAY 512 OF CHAR; c: Tls.Config; ctx: Tls.Context; s: GeminiServer.Server; err: Sockets.Error;
BEGIN
  cert := ""; key := ""; certs := ""; listen := ""; host := "localhost";
  port := 1965; count := 0; deadline := GeminiServer.DefaultDeadline;
  limit := GeminiServer.DefaultLimit;
  i := 1;
  WHILE i < Args.argc DO
    Args.Get(i, arg);
    IF i + 1 >= Args.argc THEN Usage END;
    INC(i);
    IF arg = "-cert" THEN Args.Get(i, cert)
    ELSIF arg = "-key" THEN Args.Get(i, key)
    ELSIF arg = "-certs" THEN Args.Get(i, certs)
    ELSIF arg = "-listen" THEN Args.Get(i, listen)
    ELSIF arg = "-host" THEN Args.Get(i, host)
    ELSIF arg = "-port" THEN port := -1; Args.GetInt(i, port); IF (port < 0) OR (port > 65535) THEN Usage END
    ELSIF arg = "-n" THEN count := -1; Args.GetInt(i, count); IF count < 0 THEN Usage END
    ELSIF arg = "-deadline" THEN deadline := -1; Args.GetInt(i, deadline); IF deadline < 1 THEN Usage END
    ELSIF arg = "-connections" THEN limit := -1; Args.GetInt(i, limit); IF limit < 1 THEN Usage END
    ELSE Usage
    END;
    INC(i)
  END;
  IF certs # "" THEN
    IF (cert # "") OR (key # "") THEN Usage END;
    (* Named for the host it serves, or localhost if it serves any. *)
    IF host = "" THEN name := "localhost" ELSE COPY(host, name) END;
    IF ~GeminiIdentities.Ensure(certs, name, "", Days, id, why) THEN Fail(certs, why) END;
    COPY(id.certFile, cert); COPY(id.keyFile, key)
  ELSIF (cert = "") OR (key = "") THEN Usage
  END;

  c := Tls.NewConfig();
  IF ~c.SetKeypairFile(cert, key) THEN Fail(cert, c.error.text^) END;
  c.VerifyClientOptional; c.InsecureNoVerifyCert;
  ctx := Tls.NewServer();
  IF ~ctx.Configure(c) THEN Fail("certificate", ctx.error.text^) END;
  c.Close;

  s := GeminiServer.New(ctx, Respond);
  s.SetLog(Log); s.SetDeadline(deadline); s.SetLimit(limit);
  IF ~s.Listen(listen, SHORT(port), err) THEN Fail("listen", err.text) END;
  Out.String("port "); Out.Int(s.port, 0); Out.Ln;
  s.Serve(count)
END Main;

BEGIN
  Main
END GeminiServe.
