MODULE TestServe; (* GeminiServer, in GeminiServe, against a raw client *)

(* Moved from pogemini's test/TestServe, with GeminiServe for pogemini:
   starts build/GeminiServe on port 0, as a user would start it, reads
   the port from its first line, and sends it requests from a task, by
   RawClient: over IPv4 and IPv6, with and without a client
   certificate, at and past the longest request, with a control
   character, for a page made by a Writer, input (10) and another host
   (53), and from two clients that say nothing, which must not hold up
   a third and must be dropped at the server's deadline. Then the
   server, told how many connections to serve, must exit 0 with a line
   in its log, by its Logger, for each. Once more with an RSA key
   pair. First, in this process, a server that listens and closes. *)

IMPORT Out, Platform, Tasks, Sockets, SocketTasks, Tls, Check, Child,
  RawClient, GeminiIdentities, GeminiServer;

CONST
  Certs = "../build/certs/";
  Client1Crt = "../build/certs/client1-ec.crt";
  Client1Key = "../build/certs/client1-ec.key";
  Deadline = 1000;  (* the server's, ms: short, for the silent clients *)
  Count = 13;       (* the connections Test makes *)
  CR = 0DX; LF = 0AX;
  (* The test's tasks pass whole responses (64 KiB) by value, to
     Check.Contains, so they need more than TlsTasks.stackSize. *)
  StackSize = 1024 * 1024;

TYPE
  Test = POINTER TO RECORD (Tasks.TaskDesc) port: INTEGER END;
  Rsa = POINTER TO RECORD (Tasks.TaskDesc) port: INTEGER END;

VAR
  hash: ARRAY 128 OF CHAR;  (* client1-ec.crt's, as the log gives it *)
  home: ARRAY 64 OF CHAR;   (* gemini://localhost:<the server's port>/ *)
  longest: ARRAY 1100 OF CHAR;  (* a URL of 1024 bytes, the most there may be *)

PROCEDURE Length(s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END; RETURN n
END Length;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := Length(s); j := 0;
  WHILE (i < LEN(s) - 1) & (j < LEN(t)) & (t[j] # 0X) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE StartsWith(s, prefix: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (prefix[i] # 0X) & (i < LEN(s)) & (s[i] = prefix[i]) DO INC(i) END;
  RETURN prefix[i] = 0X
END StartsWith;

(* How many times part occurs in s. *)
PROCEDURE Occurs(s, part: ARRAY OF CHAR): INTEGER;
  VAR i, j: LONGINT; n: INTEGER;
BEGIN
  n := 0; i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    j := 0;
    WHILE (part[j] # 0X) & (i + j < LEN(s)) & (s[i + j] = part[j]) DO INC(j) END;
    IF part[j] = 0X THEN INC(n) END;
    INC(i)
  END;
  RETURN n
END Occurs;

(* How many lines of log are line, after the time that begins each
   (TestRun checks it). *)
PROCEDURE Lines(log, line: ARRAY OF CHAR): INTEGER;
  VAR l: ARRAY 1300 OF CHAR; i, j: LONGINT; n: INTEGER;
BEGIN
  n := 0; i := 0;
  WHILE (i < LEN(log)) & (log[i] # 0X) DO
    j := 0;
    IF (i + 21 < LEN(log)) & (log[i + 19] = "Z") & (log[i + 20] = " ") THEN INC(i, 21) END;
    WHILE (i < LEN(log)) & (log[i] # 0X) & (log[i] # LF) DO
      IF j < LEN(l) - 1 THEN l[j] := log[i]; INC(j) END;
      INC(i)
    END;
    l[j] := 0X;
    IF l = line THEN INC(n) END;
    IF (i < LEN(log)) & (log[i] = LF) THEN INC(i) END
  END;
  RETURN n
END Lines;

(* A request line: url and CR LF. *)
PROCEDURE Request(url: ARRAY OF CHAR; VAR req: ARRAY OF CHAR; VAR len: LONGINT);
BEGIN
  COPY(url, req); len := Length(req);
  req[len] := CR; req[len + 1] := LF; req[len + 2] := 0X; INC(len, 2)
END Request;

(* A response's header line, up to its CR LF. *)
PROCEDURE Header(r: RawClient.Response; VAR h: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < r.len) & (r.data[i] # CR) & (i < LEN(h) - 1) DO h[i] := r.data[i]; INC(i) END;
  h[i] := 0X
END Header;

PROCEDURE Fetch(host: ARRAY OF CHAR; port: INTEGER; url, cert, key: ARRAY OF CHAR): RawClient.Response;
  VAR req: ARRAY 1100 OF CHAR; len: LONGINT;
BEGIN
  Request(url, req, len);
  RETURN RawClient.Fetch(host, port, req, len, cert, key)
END Fetch;

(* r is complete, ended by close_notify, with header h. *)
PROCEDURE Expect(r: RawClient.Response; h, label: ARRAY OF CHAR);
  VAR got: ARRAY 1100 OF CHAR;
BEGIN
  Header(r, got);
  Check.Check(r.ok & (got = h), label);
  IF ~r.ok THEN Out.String("  error: "); Out.String(r.error); Out.Ln
  ELSIF got # h THEN Out.String("  header: "); Out.String(got); Out.Ln
  END
END Expect;

PROCEDURE (t: Test) Run*;
  VAR r: RawClient.Response; req: ARRAY 1200 OF CHAR; i, len, n, start: LONGINT;
    silent: RawClient.Conn; tcp: Sockets.Socket; err: Sockets.Error;
    error: ARRAY 256 OF CHAR; buf: ARRAY 16 OF CHAR;
BEGIN
  r := Fetch("127.0.0.1", t.port, home, "", "");
  Expect(r, "20 text/gemini", "IPv4: 20 text/gemini");
  Check.Check(Check.Contains(r.data^, "# GeminiServe"), "IPv4: the page, by a Writer");
  Check.Check(Check.Contains(r.data^, "You sent no client certificate."), "  ... with no client certificate");
  r := Fetch("::1", t.port, home, "", "");
  Expect(r, "20 text/gemini", "IPv6: 20 text/gemini");
  r := Fetch("127.0.0.1", t.port, home, Client1Crt, Client1Key);
  Expect(r, "20 text/gemini", "with a client certificate: 20 text/gemini");
  COPY("Your client certificate: ", req); Append(req, hash);
  Check.Check(Check.Contains(r.data^, req), "  ... the page gives its hash");

  COPY(home, req); Append(req, "hello");
  r := Fetch("127.0.0.1", t.port, req, "", "");
  Expect(r, "10 Your name?", "input: 10");
  Append(req, "?Kurt%20B%C3%A9");
  r := Fetch("127.0.0.1", t.port, req, "", "");
  Expect(r, "20 text/gemini", "input answered: 20 text/gemini");
  COPY("Hello, Kurt B", req); Append(req, 0C3X); Append(req, 0A9X); Append(req, ".");
  Check.Check(Check.Contains(r.data^, req), "  ... the name decoded");
  r := Fetch("127.0.0.1", t.port, "gemini://example.org/", "", "");
  Expect(r, "53 not served here", "another host: 53");

  (* The longest request there may be is read and answered, and one byte longer
     is refused; so is one without CR LF in the first 1026 bytes. *)
  r := Fetch("127.0.0.1", t.port, longest, "", "");
  Expect(r, "51 not found", "a 1024-byte request: read and answered (51: there is no such file)");
  COPY(longest, req); Append(req, "a");
  r := Fetch("127.0.0.1", t.port, req, "", "");
  Expect(r, "59 request too long, or no CR LF", "a 1025-byte request: 59");
  FOR i := 0 TO 1099 DO req[i] := "a" END;
  r := RawClient.Fetch("127.0.0.1", t.port, req, 1100, "", "");
  Expect(r, "59 request too long, or no CR LF", "1100 bytes without CR LF: 59");

  COPY(home, req); Append(req, "a"); Append(req, 09X); Append(req, "b");
  r := Fetch("127.0.0.1", t.port, req, "", "");
  Expect(r, "59 a character not allowed in a URL", "a control character in the request: 59");

  (* Two clients that say nothing: one connects and makes no handshake,
     the other makes one and sends no request. Neither holds up a
     third, and the server drops both at its deadline. *)
  start := Platform.Time();
  IF ~SocketTasks.Connect("127.0.0.1", t.port, RawClient.Deadline, tcp, err) THEN
    Check.Check(FALSE, "a silent TCP client connects"); Out.String("  "); Out.String(err.text); Out.Ln;
    tcp := NIL
  END;
  IF ~RawClient.Open("127.0.0.1", t.port, "", "", silent, error) THEN
    Check.Check(FALSE, "a silent TLS client connects"); Out.String("  "); Out.String(error); Out.Ln;
    silent := NIL
  END;
  r := Fetch("127.0.0.1", t.port, home, "", "");
  Expect(r, "20 text/gemini", "served while two clients say nothing");
  Check.Check(Platform.Time() - start < Deadline, "  ... without waiting for them");
  IF silent # NIL THEN
    r := RawClient.Receive(silent);
    n := Platform.Time() - start;
    Check.Check(~r.ok & (r.len = 0), "the silent TLS client is dropped, without close_notify");
    Check.Check((n >= Deadline - 100) & (n < RawClient.Deadline), "  ... at the deadline");
    RawClient.Close(silent)
  END;
  IF tcp # NIL THEN
    Sockets.SetDeadline(tcp, RawClient.Deadline);
    Check.Check(~SocketTasks.Read(tcp, buf, 0, LEN(buf), len, err) & (err.kind = Sockets.closed),
      "the silent TCP client is dropped");
    Sockets.Close(tcp)
  END
END Run;

PROCEDURE (t: Rsa) Run*;
  VAR r: RawClient.Response;
BEGIN
  r := Fetch("127.0.0.1", t.port, home, "", "");
  Expect(r, "20 text/gemini", "RSA: 20 text/gemini")
END Run;

(* Starts the server with the key pair self-<kind> to serve count
   connections, and reads the port it listens on. *)
PROCEDURE Start(kind: ARRAY OF CHAR; count: INTEGER; VAR c: Child.Child;
    VAR port: INTEGER): BOOLEAN;
  VAR cmd: ARRAY 512 OF CHAR; line: ARRAY 64 OF CHAR; n: ARRAY 8 OF CHAR;
    i: INTEGER; p: LONGINT;
BEGIN
  cmd := "exec ../build/GeminiServe -port 0 -deadline ";
  n[0] := CHR(ORD("0") + Deadline DIV 1000); n[1] := "0"; n[2] := "0"; n[3] := "0"; n[4] := 0X;
  Append(cmd, n); Append(cmd, " -n ");
  n[0] := CHR(ORD("0") + count DIV 10); n[1] := CHR(ORD("0") + count MOD 10); n[2] := 0X;
  Append(cmd, n);
  Append(cmd, " -cert "); Append(cmd, Certs); Append(cmd, "self-"); Append(cmd, kind);
  Append(cmd, ".crt -key "); Append(cmd, Certs); Append(cmd, "self-"); Append(cmd, kind);
  Append(cmd, ".key");
  IF ~Child.Spawn(cmd, "", 0, c) THEN RETURN FALSE END;
  IF ~Child.ReadLine(c, line, 5000) OR ~StartsWith(line, "port ") THEN
    Out.String("  "); Out.String(line); Child.Kill(c); RETURN FALSE
  END;
  p := 0; i := 5;
  WHILE (line[i] >= "0") & (line[i] <= "9") DO p := p * 10 + ORD(line[i]) - ORD("0"); INC(i) END;
  port := SHORT(p);
  home := "gemini://localhost:"; n[0] := 0X; i := 5;
  WHILE (line[i] >= "0") & (line[i] <= "9") DO n[i - 5] := line[i]; INC(i) END;
  n[i - 5] := "/"; n[i - 4] := 0X; Append(home, n);
  RETURN (p > 0) & (p <= 65535)
END Start;

(* The hash of the certificate name.crt in Certs, as libtls gives it
   ("SHA256:", lowercase hex), by GeminiIdentities (which has it from
   polibtls's TlsCerts): pogemini's test ran openssl for it. *)
PROCEDURE Hash(name: ARRAY OF CHAR; VAR h: ARRAY OF CHAR);
  VAR id: GeminiIdentities.Identity; why: ARRAY 256 OF CHAR;
BEGIN
  IF GeminiIdentities.Load(Certs, name, id, why) THEN COPY(id.hash, h)
  ELSE COPY("(no hash)", h); Out.String("  "); Out.String(why); Out.Ln
  END
END Hash;

PROCEDURE NotFound(x: GeminiServer.Exchange);
BEGIN
  IF x.Header(51, "not found") THEN END
END NotFound;

(* A server that listens and then closes, as pogemini does when it
   can't become another user: its port takes connections until Close,
   and none after; Close again does nothing. In this process, since
   GeminiServe never closes without serving. *)
PROCEDURE Close;
  VAR s: GeminiServer.Server; c: Sockets.Socket; err: Sockets.Error;
BEGIN
  s := GeminiServer.New(Tls.NewServer(), NotFound);
  IF ~s.Listen("127.0.0.1", 0, err) THEN
    Check.Check(FALSE, "Close: the server listens"); Out.String("  "); Out.String(err.text); Out.Ln;
    RETURN
  END;
  IF Sockets.Connect("127.0.0.1", s.port, c, err) THEN
    Check.Check(TRUE, "Close: before it, a client connects"); Sockets.Close(c)
  ELSE Check.Check(FALSE, "Close: before it, a client connects")
  END;
  s.Close;
  IF Sockets.Connect("127.0.0.1", s.port, c, err) THEN
    Check.Check(FALSE, "Close: after it, a client is refused"); Sockets.Close(c)
  ELSE Check.Check(TRUE, "Close: after it, a client is refused")
  END;
  s.Close;
  Check.Check(TRUE, "Close: again, nothing")
END Close;

PROCEDURE Main;
  VAR c: Child.Child; t: Test; rsa: Rsa; port: INTEGER; i: LONGINT;
    log: ARRAY 65536 OF CHAR; line: ARRAY 1200 OF CHAR;
BEGIN
  Close;
  Hash("client1-ec", hash);
  IF ~Start("ec", Count, c, port) THEN
    Check.Check(FALSE, "the server starts and says its port");
    IF Child.Wait(c, log, i) # 0 THEN END; Out.String(log); Out.Ln
  ELSE
    COPY(home, longest); FOR i := Length(home) TO 1023 DO longest[i] := "a" END; longest[1024] := 0X;
    NEW(t); t.port := port; Tasks.Start(t, StackSize); Tasks.Join(t);
    Check.Check(Child.Wait(c, log, i) = 0, "the server exits 0 after its connections");
    Check.Check(Occurs(log, LF) = Count, "  ... with a line for each");
    line := "127.0.0.1 20 "; Append(line, home); Append(line, " -");
    Check.Check(Lines(log, line) = 2, "log: IPv4, no certificate");
    line := "127.0.0.1 10 "; Append(line, home); Append(line, "hello -");
    Check.Check(Lines(log, line) = 1, "log: input");
    line := "127.0.0.1 53 gemini://example.org/ -";
    Check.Check(Lines(log, line) = 1, "log: another host");
    line := "::1 20 "; Append(line, home); Append(line, " -");
    Check.Check(Lines(log, line) = 1, "log: IPv6");
    line := "127.0.0.1 20 "; Append(line, home); Append(line, " "); Append(line, hash);
    Check.Check(Lines(log, line) = 1, "log: the client certificate's hash");
    line := "127.0.0.1 51 "; Append(line, longest); Append(line, " -");
    Check.Check(Lines(log, line) = 1, "log: the longest request, whole");
    Check.Check(Lines(log, "127.0.0.1 59 - -") = 2, "log: the two refused");
    line := "127.0.0.1 59 "; Append(line, home); Append(line, "a%09b -");
    Check.Check(Lines(log, line) = 1, "log: the control character escaped");
    Check.Check(Lines(log, "127.0.0.1 failed: handshake timed out") = 1,
      "log: the silent TCP client timed out");
    Check.Check(Lines(log, "127.0.0.1 failed: read timed out") = 1,
      "log: the silent TLS client timed out");
    Out.String(log)
  END;

  IF ~Start("rsa", 1, c, port) THEN
    Check.Check(FALSE, "RSA: the server starts");
    IF Child.Wait(c, log, i) # 0 THEN END; Out.String(log); Out.Ln
  ELSE
    NEW(rsa); rsa.port := port; Tasks.Start(rsa, StackSize); Tasks.Join(rsa);
    Check.Check(Child.Wait(c, log, i) = 0, "RSA: the server exits 0")
  END;
  Check.Summary
END Main;

BEGIN
  Main
END TestServe.
