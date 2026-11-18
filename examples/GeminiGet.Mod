MODULE GeminiGet; (* a small gemget: fetches a gemini URL, blocking *)

(* Usage: GeminiGet [-ca file] [-cert file -key file] [-deadline ms] url

   Fetches url and writes a success's body on standard output, as it
   comes, and the header on standard error. Exits 0 for a success whose
   body ended with close_notify; 1 for any other response, or a failure,
   saying why on standard error; 2 for bad usage.

   With -ca, the server's certificate must be valid, for the URL's host,
   and signed by a CA in file; without it nothing is checked (trust on
   first use comes in Phase 5), and the certificate's fingerprint is
   shown, as a program would keep it. With -cert and -key it presents
   that client certificate. -deadline is the time the whole fetch may
   take, in milliseconds, 0 for no limit (10000 if not given).

   It shows GeminiFetch, the blocking API, in a program that doesn't use
   Tasks, and a body read as a stream (Response.Read), so one of any size
   needs only a buffer's worth of memory. *)

IMPORT Platform, Err, Args, UnixFiles, UnixErrors, GeminiResponses, GeminiFetch;

CONST
  Chunk = 16384;
  StdOut = 1;

VAR
  opts: GeminiResponses.Options;
  url: ARRAY 2048 OF CHAR;

PROCEDURE Usage;
BEGIN
  Err.String("usage: GeminiGet [-ca file] [-cert file -key file] [-deadline ms] url"); Err.Ln;
  Platform.Exit(2)
END Usage;

PROCEDURE Fail(r: GeminiResponses.Response);
BEGIN
  Err.String("GeminiGet: "); Err.String(r.error.text); Err.Ln;
  Platform.Exit(1)
END Fail;

(* Reads the arguments into opts and url, or exits 2. *)
PROCEDURE Arguments;
  VAR i: INTEGER; arg: ARRAY 2048 OF CHAR; n: LONGINT;
BEGIN
  GeminiResponses.InitOptions(opts);
  i := 1; url[0] := 0X;
  WHILE i < Args.argc DO
    Args.Get(i, arg);
    IF (arg = "-ca") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, opts.caFile)
    ELSIF (arg = "-cert") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, opts.certFile)
    ELSIF (arg = "-key") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, opts.keyFile)
    ELSIF (arg = "-deadline") & (i + 1 < Args.argc) THEN
      INC(i); n := -1; Args.GetInt(i, n);   (* left alone if not a number *)
      IF n < 0 THEN Usage END;
      opts.deadline := n
    ELSIF (arg[0] = "-") OR (url # "") THEN Usage
    ELSE COPY(arg, url)
    END;
    INC(i)
  END;
  IF (url = "") OR ((opts.certFile = "") # (opts.keyFile = "")) THEN Usage END
END Arguments;

(* Writes buf[0..n-1] on standard output, all of it. *)
PROCEDURE Put(VAR buf: ARRAY OF CHAR; n: LONGINT);
  VAR pos, m: LONGINT; err: UnixErrors.Error;
BEGIN
  pos := 0;
  WHILE pos < n DO
    IF ~UnixFiles.Write(StdOut, buf, pos, n - pos, m, err) THEN
      Err.String("GeminiGet: "); Err.String(err.text); Err.Ln; Platform.Exit(1)
    END;
    INC(pos, m)
  END
END Put;

PROCEDURE Main;
  VAR r: GeminiResponses.Response; buf: GeminiResponses.Chars; n: LONGINT;
BEGIN
  Arguments;
  IF ~GeminiFetch.Fetch(url, opts, r) THEN Fail(r) END;
  Err.Int(r.status, 0); Err.String(" "); Err.String(r.meta); Err.Ln;
  IF opts.caFile = "" THEN
    Err.String("GeminiGet: the server's certificate, not checked: "); Err.String(r.peerHash); Err.Ln
  END;
  IF r.status DIV 10 # 2 THEN Platform.Exit(1) END;
  NEW(buf, Chunk);
  WHILE r.Read(buf^, 0, Chunk, n) DO Put(buf^, n) END;
  IF ~r.complete THEN Fail(r) END
END Main;

BEGIN
  Main
END GeminiGet.
