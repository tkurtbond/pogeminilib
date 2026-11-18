MODULE TestFetch; (* GeminiFetch, blocking, against test/TestServer *)

(* ClientCases with GeminiFetch.Fetch, in a program that doesn't import
   Tasks, so memcheck can follow it (PLAN.md, Phase 4); then the example
   built on it, examples/GeminiGet.Mod, run as a child. *)

IMPORT Check, Child, Server, ClientCases, GeminiResponses, GeminiFetch;

VAR port: INTEGER;

(* Runs GeminiGet with args and path, a path on the test server: its
   exit status, and its output in out, len bytes. Its standard error
   is left out if quiet. *)
PROCEDURE Get(args, path: ARRAY OF CHAR; quiet: BOOLEAN; out: GeminiResponses.Chars;
    VAR len: LONGINT): INTEGER;
  VAR c: Child.Child; cmd: ARRAY 512 OF CHAR; url: ARRAY 256 OF CHAR;
BEGIN
  COPY("exec ../build/GeminiGet ", cmd); ClientCases.Append(cmd, args);
  ClientCases.Url("localhost", port, path, url);
  ClientCases.Append(cmd, " '"); ClientCases.Append(cmd, url); ClientCases.Append(cmd, "'");
  IF quiet THEN ClientCases.Append(cmd, " 2> /dev/null") END;
  len := 0;
  IF ~Child.Spawn(cmd, "", 0, c) THEN RETURN -1 END;
  RETURN Child.Wait(c, out^, len)
END Get;

PROCEDURE Example;
  VAR out: GeminiResponses.Chars; len: LONGINT; st: INTEGER;
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
  Check.Check((st = 2) & ClientCases.Has(out^, len, "usage: "), "GeminiGet: bad usage, exit 2")
END Example;

BEGIN
  port := Server.Start();
  IF port > 0 THEN ClientCases.Run(GeminiFetch.Fetch, port); Example; Server.Stop END;
  Check.Summary
END TestFetch.
