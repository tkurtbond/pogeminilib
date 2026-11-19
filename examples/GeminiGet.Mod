MODULE GeminiGet; (* a small gemget: fetches a gemini URL, blocking *)

(* Usage: GeminiGet [-ca file] [-known-hosts file]
                   [-cert file -key file | -identity dir/name] [-deadline ms] url

   Fetches url and writes a success's body on standard output, as it
   comes, and the header on standard error. Exits 0 for a success whose
   body ended with close_notify; 1 for any other response, or a failure,
   saying why on standard error; 2 for bad usage.

   With -ca, the server's certificate must be valid, for the URL's host,
   and signed by a CA in file. With -known-hosts, the server's key is
   trusted on first use, kept in file (GeminiTrust), and a server whose
   key has changed is refused before the request is sent. With
   neither, nothing is checked, and the server's key's fingerprint is
   shown, as a program would keep it. With -cert and -key it presents
   that client certificate; with -identity, the identity name in the
   directory dir, as GeminiIdentities made it (dir/name.crt and
   dir/name.key). -deadline is the time the whole fetch may take, in
   milliseconds, 0 for no limit (10000 if not given).

   It shows GeminiFetch, the blocking API, in a program that doesn't use
   Tasks, and a body read as a stream (Response.Read), so one of any size
   needs only a buffer's worth of memory. *)

IMPORT Platform, Err, Args, UnixFiles, UnixErrors, GeminiTrust, GeminiResponses,
  GeminiIdentities, GeminiFetch;

CONST
  Chunk = 16384;
  StdOut = 1;

VAR
  opts: GeminiResponses.Options;
  url: ARRAY 2048 OF CHAR;

PROCEDURE Usage;
BEGIN
  Err.String("usage: GeminiGet [-ca file] [-known-hosts file]"); Err.Ln;
  Err.String("                 [-cert file -key file | -identity dir/name] [-deadline ms] url"); Err.Ln;
  Platform.Exit(2)
END Usage;

PROCEDURE Die(why: ARRAY OF CHAR);
BEGIN
  Err.String("GeminiGet: "); Err.String(why); Err.Ln;
  Platform.Exit(1)
END Die;

PROCEDURE Fail(r: GeminiResponses.Response);
BEGIN Die(r.error.text)
END Fail;

(* Puts the identity path, dir/name (or name, in the current
   directory), in opts. *)
PROCEDURE UseIdentity(VAR path: ARRAY OF CHAR);
  VAR i, slash: INTEGER; dir: ARRAY 2048 OF CHAR; name: ARRAY 2048 OF CHAR;
    id: GeminiIdentities.Identity; why: ARRAY 512 OF CHAR;
BEGIN
  slash := -1; i := 0;
  WHILE path[i] # 0X DO IF path[i] = "/" THEN slash := i END; INC(i) END;
  IF slash < 0 THEN dir := "."; COPY(path, name)
  ELSE
    FOR i := 0 TO slash - 1 DO dir[i] := path[i] END; dir[slash] := 0X;
    IF slash = 0 THEN dir := "/" END;
    i := 0; WHILE path[slash + 1 + i] # 0X DO name[i] := path[slash + 1 + i]; INC(i) END;
    name[i] := 0X
  END;
  IF ~GeminiIdentities.Load(dir, name, id, why) THEN Die(why) END;
  GeminiIdentities.Use(id, opts)
END UseIdentity;

(* Reads the arguments into opts and url, or exits 2. *)
PROCEDURE Arguments;
  VAR i: INTEGER; arg, identity, known: ARRAY 2048 OF CHAR; n: LONGINT;
    hosts: GeminiTrust.Hosts; why: ARRAY 512 OF CHAR;
BEGIN
  identity := ""; known := "";
  GeminiResponses.InitOptions(opts);
  i := 1; url[0] := 0X;
  WHILE i < Args.argc DO
    Args.Get(i, arg);
    IF (arg = "-ca") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, opts.caFile)
    ELSIF (arg = "-cert") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, opts.certFile)
    ELSIF (arg = "-key") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, opts.keyFile)
    ELSIF (arg = "-identity") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, identity)
    ELSIF (arg = "-known-hosts") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, known)
    ELSIF (arg = "-deadline") & (i + 1 < Args.argc) THEN
      INC(i); n := -1; Args.GetInt(i, n);   (* left alone if not a number *)
      IF n < 0 THEN Usage END;
      opts.deadline := n
    ELSIF (arg[0] = "-") OR (url # "") THEN Usage
    ELSE COPY(arg, url)
    END;
    INC(i)
  END;
  IF (url = "") OR ((opts.certFile = "") # (opts.keyFile = ""))
      OR (identity # "") & (opts.certFile # "") THEN
    Usage
  END;
  IF identity # "" THEN UseIdentity(identity) END;
  IF known # "" THEN
    IF ~GeminiTrust.Open(known, hosts, why) THEN Die(why) END;
    opts.trust := hosts
  END
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
  IF r.trust = GeminiTrust.added THEN
    Err.String("GeminiGet: the server's key, trusted on first use: "); Err.String(r.keyHash); Err.Ln
  ELSIF r.trust = GeminiTrust.replaced THEN
    Err.String("GeminiGet: the server's key, replacing one expired: "); Err.String(r.keyHash); Err.Ln
  ELSIF (opts.caFile = "") & (opts.trust = NIL) THEN
    Err.String("GeminiGet: the server's key, not checked: "); Err.String(r.keyHash); Err.Ln
  END;
  IF r.status DIV 10 # 2 THEN Platform.Exit(1) END;
  NEW(buf, Chunk);
  WHILE r.Read(buf^, 0, Chunk, n) DO Put(buf^, n) END;
  IF ~r.complete THEN Fail(r) END
END Main;

BEGIN
  Main
END GeminiGet.
