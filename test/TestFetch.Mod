MODULE TestFetch; (* GeminiFetch, blocking, against test/TestServer *)

(* ClientCases with GeminiFetch.Fetch, in a program that doesn't import
   Tasks, so memcheck can follow it (PLAN.md, Phase 4); then the example
   built on it, examples/GeminiGet.Mod, run as a child, with its known
   hosts file under build/test-TestFetch, made afresh and removed. *)

IMPORT Check, Child, Server, ClientCases, GeminiResponses, GeminiIdentities, GeminiFetch;

VAR port: INTEGER;

(* Runs GeminiGet with args and path, a path on the test server: its
   exit status, and its output in out, len bytes. Its standard error
   is left out if quiet. *)
PROCEDURE Get(args, path: ARRAY OF CHAR; quiet: BOOLEAN; out: GeminiResponses.Chars;
    VAR len: LONGINT): INTEGER;
  VAR c: Child.Child; cmd: ARRAY 1024 OF CHAR; url: ARRAY 256 OF CHAR;
BEGIN
  COPY("exec ../build/GeminiGet ", cmd); ClientCases.Append(cmd, args);
  ClientCases.Url("localhost", port, path, url);
  ClientCases.Append(cmd, " '"); ClientCases.Append(cmd, url); ClientCases.Append(cmd, "'");
  IF quiet THEN ClientCases.Append(cmd, " 2> /dev/null") END;
  len := 0;
  IF ~Child.Spawn(cmd, "", 0, c) THEN RETURN -1 END;
  RETURN Child.Wait(c, out^, len)
END Get;

(* Its output goes on the heap: the compiler inlines Shell into Example, and a
   buffer this large in Example's frame, never written before
   GeminiIdentities.Load allocates, is stale stack the collector scans
   and may follow, which memcheck reports in DrainMarkStack. *)
PROCEDURE Shell(cmd: ARRAY OF CHAR): BOOLEAN;
  VAR c: Child.Child; out: GeminiResponses.Chars; n: LONGINT;
BEGIN NEW(out, 4096); RETURN Child.Spawn(cmd, "", 0, c) & (Child.Wait(c, out^, n) = 0)
END Shell;

PROCEDURE Example;
  VAR out: GeminiResponses.Chars; len: LONGINT; st: INTEGER; cmd: ARRAY 512 OF CHAR;
    id: GeminiIdentities.Identity; why, line: ARRAY 512 OF CHAR;
BEGIN
  NEW(out, 200000);
  st := Get("-ca ../build/certs/ca-ec.crt", "/big?100000", TRUE, out, len);
  Check.Check((st = 0) & (len = 100000) & ClientCases.IsBig(out^, 0, len, 0),
    "GeminiGet: a body of 100000 bytes on standard output, exit 0");
  st := Get("", "/status/51", FALSE, out, len);
  Check.Check((st = 1) & ClientCases.Has(out^, len, "51 status 51"),
    "GeminiGet: a 51, its header shown, exit 1");
  st := Get("-deadline 300", "/stallbody", FALSE, out, len);
  Check.Check((st = 1) & ClientCases.Has(out^, len, "partial")
    & ClientCases.Has(out^, len, "timed out"),
    "GeminiGet: a body that stalls, what came, then timed out, exit 1");
  st := Get("-deadline", "/", FALSE, out, len);
  Check.Check((st = 2) & ClientCases.Has(out^, len, "usage: "), "GeminiGet: bad usage, exit 2");
  st := Get("-identity ../build/certs/client1-ec -cert x -key y", "/", FALSE, out, len);
  Check.Check(st = 2, "GeminiGet: -identity and -cert both, bad usage");

  IF GeminiIdentities.Load("../build/certs", "client1-ec", id, why) THEN
    st := Get("-identity ../build/certs/client1-ec", "/", FALSE, out, len);
    line := "cert "; ClientCases.Append(line, id.hash);
    Check.Check((st = 0) & ClientCases.Has(out^, len, line),
      "GeminiGet: -identity presents it, as the server sees")
  ELSE Check.Check(FALSE, "loading client1-ec as an identity")
  END;
  st := Get("-identity ../build/certs/nonexistent", "/", FALSE, out, len);
  Check.Check((st = 1) & ClientCases.Has(out^, len, "no identity"), "GeminiGet: -identity not there, exit 1");

  IF Shell("rm -rf ../build/test-TestFetch && mkdir ../build/test-TestFetch") THEN
    st := Get("-known-hosts ../build/test-TestFetch/known", "/", FALSE, out, len);
    Check.Check((st = 0) & ClientCases.Has(out^, len, "trusted on first use: SHA256:"),
      "GeminiGet: -known-hosts, first contact: trusted, and said so");
    st := Get("-known-hosts ../build/test-TestFetch/known", "/", FALSE, out, len);
    Check.Check((st = 0) & ~ClientCases.Has(out^, len, "GeminiGet:"),
      "GeminiGet: ... then known, nothing said");
    cmd := "printf 'localhost:%d spki-sha256 1111111111111111111111111111111111111111111111111111111111111111 9999999999\n' ";
    ClientCases.AppendInt(cmd, port); ClientCases.Append(cmd, " > ../build/test-TestFetch/known");
    Check.Check(Shell(cmd), "a known hosts file with another key");
    st := Get("-known-hosts ../build/test-TestFetch/known", "/", FALSE, out, len);
    Check.Check((st = 1) & ClientCases.Has(out^, len, "localhost:"), "GeminiGet: a changed key refused, exit 1");
    st := Get("-known-hosts ../build/test-TestFetch", "/", FALSE, out, len);
    Check.Check(st = 1, "GeminiGet: a known hosts file that can't be read, exit 1");
    IF Shell("rm -rf ../build/test-TestFetch") THEN END
  ELSE Check.Check(FALSE, "making build/test-TestFetch")
  END
END Example;

BEGIN
  port := Server.Start();
  IF port > 0 THEN ClientCases.Run(GeminiFetch.Fetch, port); Example; Server.Stop END;
  Check.Summary
END TestFetch.
