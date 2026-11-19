MODULE Both; (* fetches two gemini URLs at once, a task each *)

IMPORT Args, Out, Tasks, GeminiResponses, GeminiClient;

TYPE
  Fetch = POINTER TO RECORD (Tasks.TaskDesc)
    url: ARRAY 1100 OF CHAR;
    ok: BOOLEAN;
    r: GeminiResponses.Response
  END;

VAR a, b: Fetch;

PROCEDURE (f: Fetch) Run*;
  VAR opts: GeminiResponses.Options;
BEGIN
  GeminiResponses.InitOptions(opts);
  (* while this task waits for its server, the other runs *)
  f.ok := GeminiClient.Fetch(f.url, opts, f.r);
  IF f.ok THEN f.r.Close END   (* the header's enough *)
END Run;

PROCEDURE Show(f: Fetch);
BEGIN
  Out.String(f.url); Out.String(": ");
  IF f.ok THEN Out.Int(f.r.status, 0); Out.String(" "); Out.String(f.r.meta)
  ELSE Out.String(f.r.error.text)
  END;
  Out.Ln
END Show;

BEGIN
  NEW(a); Args.Get(1, a.url); Tasks.Start(a, GeminiClient.stackSize);
  NEW(b); Args.Get(2, b.url); Tasks.Start(b, GeminiClient.stackSize);
  Tasks.Join(a); Tasks.Join(b);
  Show(a); Show(b)
END Both.
