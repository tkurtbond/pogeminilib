MODULE TestServer; (* a Gemini server that misbehaves on purpose, for the client's tests *)

(* Usage: TestServer cert key

   Listens on a port the kernel chooses, on every local address (IPv6
   and IPv4 alike, one port), prints "port <n>" as its only line, and
   serves until SIGTERM (StopRequests), each connection in a task of
   its own, so a stalled one holds up none of the others. Built from
   polibtls's examples/GeminiHello.Mod. It accepts any client
   certificate, as a Gemini server does.

   What it sends depends on the request's path (PLAN.md, Phase 4); a
   response ends with close_notify unless it says otherwise:

     /big?N        20, and N bytes, "a".."z" over and over
     /badheader    a header with no status
     /nocrlf       "20 text/gemini" and no line end
     /longmeta     a header whose meta is over 1024 bytes
     /empty        nothing
     /cut          20 and "partial", then a close without close_notify
     /cuthead      51, then a close without close_notify
     /junk         51, and bytes after its header
     /stall        nothing, until the client goes away
     /stallbody    20 and "partial", then nothing, as /stall
     /status/NN    NN and "status NN"
     anything else 20 text/gemini, and lines "url" (the request's URL),
                   "sni" (the name the client sent, or "-") and "cert"
                   (its certificate's fingerprint, or "-")

   It never prints a key, nor anything after its port, since nothing
   reads its output while it runs. *)

IMPORT Platform, Out, Err, Args, Tasks, StopRequests, Sockets, SocketTasks, Tls, TlsTasks;

CONST
  Tick = 200;          (* ms an accept waits before looking at StopRequests *)
  Deadline = 10000;    (* ms a connection has, but for a stall *)
  Stall = 30000;       (* ms a stall lasts at most *)
  Linger = 2000;
  MaxUrl = 1024;
  Chunk = 16384;
  CR = 0DX; LF = 0AX;

TYPE
  Handler = POINTER TO RECORD (Tasks.TaskDesc)
    s: Sockets.Socket;
    peer: Sockets.Address
  END;
  Acceptor = POINTER TO RECORD (Tasks.TaskDesc)
    l: Sockets.Socket
  END;
  Text = POINTER TO ARRAY Chunk OF CHAR;

VAR
  ctx: Tls.Context;

PROCEDURE Append(VAR s: ARRAY OF CHAR; VAR i: LONGINT; part: ARRAY OF CHAR);
  VAR j: LONGINT;
BEGIN
  j := 0;
  WHILE (j < LEN(part)) & (part[j] # 0X) & (i < LEN(s) - 1) DO s[i] := part[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE Put(VAR s: ARRAY OF CHAR; VAR i: LONGINT; c: CHAR);
BEGIN
  IF i < LEN(s) - 1 THEN s[i] := c; INC(i) END;
  s[i] := 0X
END Put;

PROCEDURE CrLf(VAR s: ARRAY OF CHAR; VAR i: LONGINT);
BEGIN Put(s, i, CR); Put(s, i, LF)
END CrLf;

(* Reads the request line, up to CR LF, into url without them: FALSE if
   it failed or there was no CR LF in the first MaxUrl + 2 bytes. *)
PROCEDURE ReadRequest(c: Tls.Connection; VAR url: ARRAY OF CHAR): BOOLEAN;
  VAR buf: ARRAY MaxUrl + 2 OF CHAR; n, m: LONGINT;
BEGIN
  n := 0; url[0] := 0X;
  REPEAT
    IF ~TlsTasks.Read(c, buf, n, LEN(buf) - n, m) THEN RETURN FALSE END;
    INC(n, m)
  UNTIL (n >= 2) & (buf[n - 2] = CR) & (buf[n - 1] = LF) OR (n = LEN(buf));
  IF (buf[n - 2] # CR) OR (buf[n - 1] # LF) THEN RETURN FALSE END;
  buf[n - 2] := 0X; COPY(buf, url);
  RETURN TRUE
END ReadRequest;

(* path := url's path and query, from the "/" after its authority *)
PROCEDURE PathOf(url: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
  VAR i, j, slashes: LONGINT;
BEGIN
  i := 0; slashes := 0;
  WHILE (url[i] # 0X) & (slashes < 3) DO
    IF url[i] = "/" THEN INC(slashes) END;
    INC(i)
  END;
  path[0] := 0X;
  IF slashes = 3 THEN
    path[0] := "/"; j := 1;
    WHILE (url[i] # 0X) & (j < LEN(path) - 1) DO path[j] := url[i]; INC(i); INC(j) END;
    path[j] := 0X
  END
END PathOf;

PROCEDURE StartsWith(s, prefix: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE prefix[i] # 0X DO
    IF s[i] # prefix[i] THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END StartsWith;

(* The number in s from i on, 0 if none *)
PROCEDURE Number(s: ARRAY OF CHAR; i: LONGINT): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0;
  WHILE (s[i] >= "0") & (s[i] <= "9") DO n := 10 * n + ORD(s[i]) - ORD("0"); INC(i) END;
  RETURN n
END Number;

PROCEDURE Send(c: Tls.Connection; VAR t: ARRAY OF CHAR; len: LONGINT): BOOLEAN;
  VAR n: LONGINT;
BEGIN RETURN (len = 0) OR TlsTasks.WriteAll(c, t, 0, len, n)
END Send;

(* N bytes of "a".."z", in chunks *)
PROCEDURE SendBig(c: Tls.Connection; t: Text; total: LONGINT): BOOLEAN;
  VAR i, k, n: LONGINT;
BEGIN
  k := 0;
  WHILE k < total DO
    n := total - k; IF n > Chunk THEN n := Chunk END;
    FOR i := 0 TO n - 1 DO t[i] := CHR(ORD("a") + (k + i) MOD 26) END;
    IF ~Send(c, t^, n) THEN RETURN FALSE END;
    INC(k, n)
  END;
  RETURN TRUE
END SendBig;

(* What the request in url gets: sends it, and says how to end. *)
PROCEDURE Respond(c: Tls.Connection; url: ARRAY OF CHAR; VAR stall, cut: BOOLEAN): BOOLEAN;
  VAR t: Text; path: ARRAY MaxUrl + 1 OF CHAR; i: LONGINT; s: Tls.String;
BEGIN
  NEW(t); t[0] := 0X; i := 0; stall := FALSE; cut := FALSE;
  PathOf(url, path);
  IF StartsWith(path, "/big?") THEN
    Append(t^, i, "20 application/octet-stream"); CrLf(t^, i);
    RETURN Send(c, t^, i) & SendBig(c, t, Number(path, 5))
  ELSIF path = "/badheader" THEN Append(t^, i, "xx bad"); CrLf(t^, i)
  ELSIF path = "/nocrlf" THEN Append(t^, i, "20 text/gemini")
  ELSIF path = "/longmeta" THEN
    Append(t^, i, "20 ");
    WHILE i < 1100 DO Put(t^, i, "a") END;
    CrLf(t^, i)
  ELSIF path = "/empty" THEN
  ELSIF path = "/cut" THEN Append(t^, i, "20 text/gemini"); CrLf(t^, i); Append(t^, i, "partial"); cut := TRUE
  ELSIF path = "/cuthead" THEN Append(t^, i, "51 gone"); CrLf(t^, i); cut := TRUE
  ELSIF path = "/junk" THEN Append(t^, i, "51 gone"); CrLf(t^, i); Append(t^, i, "junk after the header")
  ELSIF path = "/stall" THEN stall := TRUE
  ELSIF path = "/stallbody" THEN
    Append(t^, i, "20 text/gemini"); CrLf(t^, i); Append(t^, i, "partial"); stall := TRUE
  ELSIF StartsWith(path, "/status/") & (path[8] # 0X) & (path[9] # 0X) THEN
    Put(t^, i, path[8]); Put(t^, i, path[9]); Append(t^, i, " status ");
    Put(t^, i, path[8]); Put(t^, i, path[9]); CrLf(t^, i)
  ELSE
    Append(t^, i, "20 text/gemini"); CrLf(t^, i);
    Append(t^, i, "url "); Append(t^, i, url); Put(t^, i, LF);
    Append(t^, i, "sni "); s := c.Servername();
    IF s = NIL THEN Append(t^, i, "-") ELSE Append(t^, i, s^) END;
    Put(t^, i, LF);
    Append(t^, i, "cert "); s := c.PeerCertHash();
    IF s = NIL THEN Append(t^, i, "-") ELSE Append(t^, i, s^) END;
    Put(t^, i, LF)
  END;
  RETURN Send(c, t^, i)
END Respond;

PROCEDURE (h: Handler) Run*;
  VAR c: Tls.Connection; url: ARRAY MaxUrl + 1 OF CHAR; stall, cut, closed: BOOLEAN;
BEGIN
  closed := FALSE;
  IF ctx.AcceptSocket(h.s.fd, c) THEN
    c.SetDeadline(Deadline);
    IF TlsTasks.Handshake(c) & ReadRequest(c, url) & Respond(c, url, stall, cut) THEN
      IF stall THEN
        (* until the client gives up and closes, which makes the socket
           readable *)
        IF Tasks.AwaitReadableFor(h.s.fd, Stall) THEN END;
        c.Discard
      ELSIF cut THEN c.Discard
      ELSIF TlsTasks.Close(c) THEN
        closed := TRUE; IF SocketTasks.LingeringClose(h.s, Linger) THEN END
      ELSE c.Discard
      END
    ELSE c.Discard
    END
  END;
  IF ~closed THEN Sockets.Close(h.s) END
END Run;

PROCEDURE (a: Acceptor) Run*;
  VAR h: Handler; err: Sockets.Error;
BEGIN
  WHILE StopRequests.Latest() = StopRequests.none DO
    NEW(h);
    Sockets.SetDeadline(a.l, Tick);
    IF SocketTasks.Accept(a.l, h.s, h.peer, err) THEN Tasks.Start(h, TlsTasks.stackSize)
    ELSIF err.kind # Sockets.timedOut THEN Tasks.Sleep(10)
    END
  END;
  Sockets.Close(a.l)
END Run;

PROCEDURE Fail(what: ARRAY OF CHAR);
BEGIN
  Err.String("TestServer: "); Err.String(what); Err.Ln; Platform.Exit(1)
END Fail;

PROCEDURE Main;
  VAR cert, key: ARRAY 1024 OF CHAR; c: Tls.Config; ls: ARRAY 2 OF Sockets.Socket;
    as: ARRAY 2 OF Acceptor; a: Sockets.Address; err: Sockets.Error; i, n: INTEGER;
BEGIN
  IF Args.argc # 3 THEN Fail("usage: TestServer cert key") END;
  Args.Get(1, cert); Args.Get(2, key);
  c := Tls.NewConfig();
  IF ~c.SetKeypairFile(cert, key) THEN Fail(c.error.text^) END;
  c.VerifyClientOptional; c.InsecureNoVerifyCert;
  ctx := Tls.NewServer();
  IF ~ctx.Configure(c) THEN Fail(ctx.error.text^) END;
  c.Close;
  Sockets.IgnoreBrokenPipe;
  StopRequests.Catch;
  IF ~Sockets.Listen("", 0, 64, TRUE, ls, n, err) OR ~Sockets.LocalAddress(ls[0], a, err) THEN
    Fail(err.text)
  END;
  Out.String("port "); Out.Int(a.port, 0); Out.Ln;
  FOR i := 0 TO n - 1 DO NEW(as[i]); as[i].l := ls[i]; Tasks.Start(as[i], TlsTasks.stackSize) END;
  FOR i := 0 TO n - 1 DO Tasks.Join(as[i]) END;
  (* Stalled connections aren't waited for. *)
  Platform.Exit(0)
END Main;

BEGIN
  Main
END TestServer.
