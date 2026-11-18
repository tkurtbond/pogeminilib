MODULE TestClient; (* GeminiClient, in tasks, against test/TestServer and pogemini *)

(* PLAN.md, Phase 4: ClientCases with GeminiClient.Fetch, in a task;
   then several fetches at once, one of them stalled, to see that the
   stalled one holds up none of the others; then, if pogemini is
   installed, a few fetches from it, as a real server. And the example
   built on it, examples/GeminiFetchAll.Mod, run as a child. *)

IMPORT Sockets, Tasks, Check, Child, Server, ClientCases, GeminiResponses, GeminiClient;

CONST
  StackSize = 1048576;   (* ClientCases' arrays don't fit in 64 KiB *)
  Bigs = 4;              (* fetches alongside the stalled one *)
  Big = 300000;
  StallFor = 2000;       (* ms the stalled fetch waits *)
  Slack = 1000;
  Files = "../build/test-client";
  FileSize = 100000;

TYPE
  Cases = POINTER TO RECORD (Tasks.TaskDesc) port: INTEGER END;

  (* One fetch of link, read whole: ok, its length, and when it ended *)
  Fetch = POINTER TO RECORD (Tasks.TaskDesc)
    link: ARRAY 256 OF CHAR;
    deadline: LONGINT;
    ok: BOOLEAN;
    r: GeminiResponses.Response;
    body: GeminiResponses.Chars;
    len, ended: LONGINT
  END;

VAR
  port: INTEGER;

PROCEDURE (t: Cases) Run*;
BEGIN ClientCases.Run(GeminiClient.Fetch, t.port)
END Run;

PROCEDURE (f: Fetch) Run*;
  VAR o: GeminiResponses.Options;
BEGIN
  GeminiResponses.InitOptions(o); o.deadline := f.deadline;
  f.ok := GeminiClient.Fetch(f.link, o, f.r) & f.r.ReadAll(f.body, f.len);
  f.ended := Sockets.Now()
END Run;

PROCEDURE Start(path: ARRAY OF CHAR; host: ARRAY OF CHAR; port: INTEGER; deadline: LONGINT): Fetch;
  VAR f: Fetch;
BEGIN
  NEW(f); ClientCases.Url(host, port, path, f.link); f.deadline := deadline;
  Tasks.Start(f, StackSize);
  RETURN f
END Start;

(* Fetches of Big bytes alongside one that stalls: each ends whole while
   the stalled one still waits, and that one times out on its own. *)
PROCEDURE Concurrency;
  VAR stalled: Fetch; bigs: ARRAY Bigs OF Fetch; i: INTEGER; t0: LONGINT; ok: BOOLEAN;
BEGIN
  t0 := Sockets.Now();
  stalled := Start("/stall", "localhost", port, StallFor);
  FOR i := 0 TO Bigs - 1 DO bigs[i] := Start("/big?300000", "127.0.0.1", port, 0) END;
  FOR i := 0 TO Bigs - 1 DO Tasks.Join(bigs[i]) END;
  Tasks.Join(stalled);
  ok := TRUE;
  FOR i := 0 TO Bigs - 1 DO
    ok := ok & bigs[i].ok & (bigs[i].len = Big) & ClientCases.IsBig(bigs[i].body^, 0, Big, 0)
      & (bigs[i].ended < stalled.ended)
  END;
  Check.Check(ok, "4 fetches of 300000 bytes end whole while a stalled one waits");
  Check.Check(~stalled.ok & (stalled.r.error.kind = GeminiResponses.timedOut)
    & (stalled.ended - t0 >= StallFor - 5) & (stalled.ended - t0 <= StallFor + Slack),
    "and the stalled one times out at its own deadline")
END Concurrency;

(* Runs command in the shell, for its status *)
PROCEDURE Shell(command: ARRAY OF CHAR): INTEGER;
  VAR c: Child.Child; out: ARRAY 4096 OF CHAR; n: LONGINT;
BEGIN
  IF ~Child.Spawn(command, "", 0, c) THEN RETURN -1 END;
  RETURN Child.Wait(c, out, n)
END Shell;

(* GeminiFetchAll, fetching a stalled URL and two others at once: the
   others are done at once, the stalled one fails at the deadline, and
   the whole takes about as long as that. *)
PROCEDURE Example;
  VAR c: Child.Child; cmd: ARRAY 1024 OF CHAR; url: ARRAY 256 OF CHAR;
    out: GeminiResponses.Chars; len, t0, el: LONGINT; st: INTEGER;
BEGIN
  COPY("exec ../build/GeminiFetchAll -deadline 1000", cmd);
  ClientCases.Url("localhost", port, "/big?300000", url);
  ClientCases.Append(cmd, " '"); ClientCases.Append(cmd, url); ClientCases.Append(cmd, "'");
  ClientCases.Url("127.0.0.1", port, "/stall", url);
  ClientCases.Append(cmd, " '"); ClientCases.Append(cmd, url); ClientCases.Append(cmd, "'");
  ClientCases.Url("[::1]", port, "/status/31", url);
  ClientCases.Append(cmd, " '"); ClientCases.Append(cmd, url); ClientCases.Append(cmd, "'");
  NEW(out, 4096); len := 0; st := -1;
  t0 := Sockets.Now();
  IF Child.Spawn(cmd, "", 0, c) THEN st := Child.Wait(c, out^, len) END;
  el := Sockets.Now() - t0;
  Check.Check((st = 1) & ClientCases.Has(out^, len, "/big?300000 20 application/octet-stream, 300000 bytes")
    & ClientCases.Has(out^, len, "/stall failed: reading the header: timed out")
    & ClientCases.Has(out^, len, "/status/31 31 status 31, 0 bytes"),
    "GeminiFetchAll: two fetched while a third stalls, which fails at its deadline, exit 1");
  Check.Check((el >= 1000) & (el <= 1000 + Slack), "  ... all in about the time of the stalled one")
END Example;

(* pogemini, if installed, serving Files: a page, a file of FileSize
   bytes, and one that isn't there. *)
PROCEDURE Pogemini;
  VAR c: Child.Child; line: ARRAY 64 OF CHAR; log: ARRAY 65536 OF CHAR; n: LONGINT;
    i, p: INTEGER; f: Fetch; ok: BOOLEAN;
BEGIN
  IF Shell("command -v pogemini > /dev/null") # 0 THEN
    Check.Check(TRUE, "pogemini isn't installed: its checks skipped");
    RETURN
  END;
  ok := Shell("rm -rf ../build/test-client && mkdir -p ../build/test-client && printf '# Hello\n' > ../build/test-client/index.gmi && head -c 100000 /dev/zero | tr '\000' x > ../build/test-client/big.txt") = 0;
  Check.Check(ok, "the files for pogemini made");
  ok := ok & Child.Spawn("exec pogemini -listen 127.0.0.1 -port 0 -host localhost -n 3 -deadline 5000 -root ../build/test-client -cert ../build/certs/server-ec.crt -key ../build/certs/server-ec.key",
      "", 0, c)
    & Child.ReadLine(c, line, 15000) & (line[0] = "p");
  Check.Check(ok, "pogemini starts and says its port");
  IF ~ok THEN Child.Kill(c); IF Child.Wait(c, log, n) # 0 THEN END; RETURN END;
  i := 5; p := 0;
  WHILE (line[i] >= "0") & (line[i] <= "9") DO p := 10 * p + ORD(line[i]) - ORD("0"); INC(i) END;

  f := Start("/", "localhost", p, 5000); Tasks.Join(f);
  Check.Check(f.ok & (f.r.status = 20) & (f.r.meta = "text/gemini") & (f.len = 8) & ClientCases.Has(f.body^, f.len, "# Hello") & (f.body[7] = 0AX)
    & f.r.complete, "pogemini: its page, whole");
  f := Start("/big.txt", "localhost", p, 5000); Tasks.Join(f);
  ok := f.ok & (f.r.status = 20) & (f.len = FileSize);
  i := 0;
  WHILE ok & (i < FileSize) DO ok := f.body[i] = "x"; INC(i) END;
  Check.Check(ok, "pogemini: a file of 100000 bytes, whole");
  f := Start("/not-there", "localhost", p, 5000); Tasks.Join(f);
  Check.Check(f.ok & (f.r.status = 51) & f.r.complete, "pogemini: 51 for what isn't there");
  Check.Check(Child.Wait(c, log, n) = 0, "pogemini exits 0 after its 3 connections");
  Check.Check(Shell("rm -rf ../build/test-client") = 0, "the files removed")
END Pogemini;

PROCEDURE Main;
  VAR t: Cases;
BEGIN
  port := Server.Start();
  IF port > 0 THEN
    NEW(t); t.port := port; Tasks.Start(t, StackSize); Tasks.Join(t);
    Concurrency;
    Example;
    Server.Stop
  END;
  Pogemini;
  Check.Summary
END Main;

BEGIN
  Main
END TestClient.
