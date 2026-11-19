MODULE Get; (* fetches a gemini URL, blocking, trusting its server on first use *)

IMPORT Args, Out, GeminiTrust, GeminiResponses, GeminiFetch;

VAR
  url: ARRAY 1100 OF CHAR; why: ARRAY 256 OF CHAR;
  opts: GeminiResponses.Options; hosts: GeminiTrust.Hosts;
  r: GeminiResponses.Response; body: GeminiResponses.Chars; len: LONGINT;

BEGIN
  Args.Get(1, url);
  GeminiResponses.InitOptions(opts);
  IF ~GeminiTrust.Open("known-hosts", hosts, why) THEN Out.String(why); Out.Ln
  ELSE
    opts.trust := hosts;   (* asked before the request is sent *)
    IF ~GeminiFetch.Fetch(url, opts, r) THEN
      Out.String(r.error.text); Out.Ln   (* a changed key: r.error.kind = changed *)
    ELSE
      Out.Int(r.status, 0); Out.String(" "); Out.String(r.meta); Out.Ln;
      IF r.trust = GeminiTrust.added THEN
        Out.String("first use: "); Out.String(r.keyHash); Out.Ln
      END;
      IF r.status DIV 10 = 2 THEN
        IF r.ReadAll(body, len) THEN Out.String(body^)   (* its own line ends *)
        ELSE Out.String(r.error.text); Out.Ln   (* cut short, say *)
        END
      END
    END
  END
END Get.
