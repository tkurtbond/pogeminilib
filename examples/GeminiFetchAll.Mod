MODULE GeminiFetchAll; (* fetches several gemini URLs at once, in tasks *)

(* Usage: GeminiFetchAll [-deadline ms] url...

   Fetches every url at once, each in a task of its own, reading each
   success's body whole, and when all are done prints a line for each,
   in the order given:

     url status meta, bytes, ms

   or, for one that failed, "url failed: " and why. A body that ended
   without close_notify, or over its deadline, counts as failed. Nothing
   is checked of the servers' certificates. -deadline is the time each
   fetch may take, in milliseconds, 0 for no limit (10000 if not
   given). Exits 0 if every fetch was a success, 1 if not, 2 for bad
   usage.

   It shows GeminiClient in tasks: a slow or stalled server holds up
   only its own fetch, and the whole takes about as long as the slowest
   one, not the sum of them. *)

IMPORT Platform, Out, Err, Args, Sockets, Tasks, GeminiResponses, GeminiClient;

CONST
  MaxUrls = 64;

TYPE
  Fetch = POINTER TO RECORD (Tasks.TaskDesc)
    url: ARRAY 2048 OF CHAR;
    ok: BOOLEAN;
    r: GeminiResponses.Response;
    len, ms: LONGINT
  END;

VAR
  deadline: LONGINT;

(* It needs no more stack than the fetch's own: GeminiClient.stackSize. *)
PROCEDURE (f: Fetch) Run*;
  VAR o: GeminiResponses.Options; body: GeminiResponses.Chars; t0: LONGINT;
BEGIN
  GeminiResponses.InitOptions(o); o.deadline := deadline;
  t0 := Sockets.Now();
  f.ok := GeminiClient.Fetch(f.url, o, f.r);
  IF f.ok & (f.r.status DIV 10 = 2) THEN f.ok := f.r.ReadAll(body, f.len) END;
  f.ms := Sockets.Now() - t0
END Run;

PROCEDURE Usage;
BEGIN
  Err.String("usage: GeminiFetchAll [-deadline ms] url..."); Err.Ln;
  Platform.Exit(2)
END Usage;

PROCEDURE Main;
  VAR fs: ARRAY MaxUrls OF Fetch; n, i, first: INTEGER; all: BOOLEAN;
    arg: ARRAY 16 OF CHAR;
BEGIN
  deadline := GeminiResponses.DefaultDeadline; first := 1;
  IF Args.argc > 1 THEN
    Args.Get(1, arg);
    IF arg = "-deadline" THEN
      IF Args.argc < 3 THEN Usage END;
      deadline := -1; Args.GetInt(2, deadline);   (* left alone if not a number *)
      IF deadline < 0 THEN Usage END;
      first := 3
    END
  END;
  n := Args.argc - first;
  IF (n < 1) OR (n > MaxUrls) THEN Usage END;
  FOR i := 0 TO n - 1 DO
    NEW(fs[i]); Args.Get(first + i, fs[i].url);
    Tasks.Start(fs[i], GeminiClient.stackSize)
  END;
  all := TRUE;
  FOR i := 0 TO n - 1 DO
    Tasks.Join(fs[i]);
    Out.String(fs[i].url);
    IF fs[i].ok THEN
      Out.String(" "); Out.Int(fs[i].r.status, 0); Out.String(" "); Out.String(fs[i].r.meta);
      Out.String(", "); Out.Int(fs[i].len, 0); Out.String(" bytes, ");
      Out.Int(fs[i].ms, 0); Out.String(" ms");
      all := all & (fs[i].r.status DIV 10 = 2)
    ELSE
      Out.String(" failed: "); Out.String(fs[i].r.error.text); all := FALSE
    END;
    Out.Ln
  END;
  IF ~all THEN Platform.Exit(1) END
END Main;

BEGIN
  Main
END GeminiFetchAll.
