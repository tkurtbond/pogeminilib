MODULE TestIdentities; (* GeminiIdentities: made, listed, used, and scoped *)

(* Identities made with the host's openssl under
   build/test-TestIdentities, afresh, and removed at the end: listed
   with their hashes, their files' modes, one presented to
   test/TestServer, which echoes the hash it saw; names that would
   leave the directory refused; and, run again by itself with PATH
   empty of openssl ("nossl"), the error saying so. Then the scopes
   file's rule. Skipped, but for the scopes, where there is no openssl. *)

IMPORT Out, Args, Check, Child, Server, ClientCases, UnixErrors, UnixFiles,
  GeminiUrls, GeminiResponses, GeminiIdentities, GeminiFetch;

CONST
  Dir = "../build/test-TestIdentities";
  Ids = "../build/test-TestIdentities/ids";

VAR
  port: INTEGER;

PROCEDURE Shell(cmd: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): INTEGER;
  VAR c: Child.Child; n: LONGINT;
BEGIN
  out[0] := 0X;
  IF ~Child.Spawn(cmd, "", 0, c) THEN RETURN -1 END;
  RETURN Child.Wait(c, out, n)
END Shell;

(* The permission bits of path, -1 if it can't be opened. *)
PROCEDURE ModeOf(path: ARRAY OF CHAR): LONGINT;
  VAR fd, mode: LONGINT; err: UnixErrors.Error;
BEGIN
  IF ~UnixFiles.OpenRead(path, {}, fd, err) THEN RETURN -1 END;
  IF ~UnixFiles.ModeOf(fd, mode, err) THEN mode := -1 END;
  UnixFiles.Close(fd);
  RETURN mode
END ModeOf;

PROCEDURE Count(id: GeminiIdentities.Identity): INTEGER;
  VAR n: INTEGER;
BEGIN
  n := 0; WHILE id # NIL DO INC(n); id := id.next END;
  RETURN n
END Count;

(* Fetches the server's echo with opts: whether its "cert" line is
   cert. *)
PROCEDURE Presented(VAR opts: GeminiResponses.Options; cert: ARRAY OF CHAR): BOOLEAN;
  VAR link: ARRAY 512 OF CHAR; line: ARRAY 128 OF CHAR; r: GeminiResponses.Response;
    b: GeminiResponses.Chars; n: LONGINT;
BEGIN
  ClientCases.Url("localhost", port, "/", link);
  line := "cert "; ClientCases.Append(line, cert);
  RETURN GeminiFetch.Fetch(link, opts, r) & (r.status = 20) & r.ReadAll(b, n)
    & ClientCases.Has(b^, n, line)
END Presented;

PROCEDURE Identities;
  VAR id, id2, first: GeminiIdentities.Identity; why: ARRAY 512 OF CHAR;
    out: ARRAY 4096 OF CHAR; opts: GeminiResponses.Options; cmd: ARRAY 256 OF CHAR;
BEGIN
  Check.Check(GeminiIdentities.List(Ids, first, why) & (first = NIL),
    "a directory that isn't there holds no identities");
  Check.Check(~GeminiIdentities.Make(Ids, "alice", "", 30, id, why) & (id = NIL),
    "... and none can be made in it");
  IF Shell("mkdir ../build/test-TestIdentities/ids", out) # 0 THEN Check.Check(FALSE, "mkdir"); RETURN END;

  Check.Check(GeminiIdentities.Make(Ids, "alice", "", GeminiIdentities.DefaultDays, id, why)
    & (id.name = "alice") & Check.Contains(id.hash, "SHA256:")
    & (id.notAfter - id.notBefore >= 7299 * 86400) & (id.notAfter - id.notBefore <= 7301 * 86400),
    "an identity made, with its hash, for 20 years");
  IF id = NIL THEN Out.String("  "); Out.String(why); Out.Ln; RETURN END;
  Check.Check(ModeOf(id.keyFile) = 180H, "its key's mode is 600");
  Check.Check(ModeOf(id.certFile) = 1A4H, "its certificate's 644");
  Check.Check(Shell("cd ../build/test-TestIdentities/ids && ls | tr '\n' ' '", out) = 0,
    "its directory listed");
  Check.Check(out = "alice.crt alice.key ", "only its two files are left");
  cmd := "openssl x509 -noout -subject -in ../build/test-TestIdentities/ids/alice.crt";
  Check.Check((Shell(cmd, out) = 0) & Check.Contains(out, "CN") & Check.Contains(out, "alice"),
    "its common name is its name");

  Check.Check(GeminiIdentities.Make(Ids, "bob.2", "Bob Smith, Esq.", 30, id2, why)
    & (id2.notAfter - id2.notBefore >= 29 * 86400) & (id2.notAfter - id2.notBefore <= 31 * 86400)
    & (id2.hash # id.hash), "another, with a common name of its own, for 30 days");
  cmd := "openssl x509 -noout -subject -in ../build/test-TestIdentities/ids/bob.2.crt";
  Check.Check((Shell(cmd, out) = 0) & Check.Contains(out, "Bob Smith, Esq."), "... which it has");
  Check.Check(~GeminiIdentities.Make(Ids, "alice", "", 30, id2, why) & Check.Contains(why, "exists"),
    "an identity's name can't be made twice");
  Check.Check(GeminiIdentities.Load(Ids, "alice", id2, why) & (id2.hash = id.hash)
    & (id2.notAfter = id.notAfter), "it is loaded as it was made");

  Check.Check(GeminiIdentities.List(Ids, first, why) & (Count(first) = 2)
    & (first.name = "alice") & (first.hash = id.hash) & (first.next.name = "bob.2"),
    "both listed, by name, with their hashes");
  IF Shell("cd ../build/test-TestIdentities/ids && touch carol.crt && cp alice.crt dave.crt && touch .x.crt", out) = 0 THEN
    Check.Check(GeminiIdentities.List(Ids, first, why) & (Count(first) = 2),
      "a .crt that isn't one, or has no key, or a hidden one, isn't listed")
  END;
  Check.Check(~GeminiIdentities.Load(Ids, "carol", id2, why) & Check.Contains(why, "certificate"),
    "... and can't be loaded");
  Check.Check(~GeminiIdentities.Load(Ids, "dave", id2, why) & Check.Contains(why, "no key"),
    "... nor one with no key");
  Check.Check(~GeminiIdentities.Load(Ids, "erin", id2, why) & Check.Contains(why, "no identity"),
    "... nor one that isn't there");

  Check.Check(~GeminiIdentities.Make(Ids, "../x", "", 30, id2, why)
    & ~GeminiIdentities.Make(Ids, "a/b", "", 30, id2, why)
    & ~GeminiIdentities.Make(Ids, ".hidden", "", 30, id2, why)
    & ~GeminiIdentities.Make(Ids, "", "", 30, id2, why)
    & ~GeminiIdentities.Make(Ids, "a b", "", 30, id2, why)
    & ~GeminiIdentities.Load(Ids, "../ids/alice", id2, why),
    "a name that would leave the directory, or isn't a file's, refused");
  Check.Check(~GeminiIdentities.Make(Ids, "f", "/CN=x", 30, id2, why)
    & ~GeminiIdentities.Make(Ids, "f", "a=b", 30, id2, why)
    & ~GeminiIdentities.Make(Ids, "f", "a+b", 30, id2, why),
    "a common name openssl would read as its own refused");
  Check.Check(~GeminiIdentities.Make(Ids, "f", "", 0, id2, why)
    & ~GeminiIdentities.Make(Ids, "f", "", GeminiIdentities.MaxDays + 1, id2, why),
    "a lifetime out of range refused");
  Check.Check(Shell("! ls -a ../build/test-TestIdentities/ids | grep -v -e '^[a-e]' -e '^[.]x[.]crt$' -e '^[.][.]*$'", out) = 0,
    "nothing made by what was refused");

  IF port > 0 THEN
    GeminiResponses.InitOptions(opts);
    Check.Check(Presented(opts, "-"), "without an identity, none presented");
    GeminiIdentities.Use(id, opts);
    Check.Check(Presented(opts, id.hash), "with one, the server sees the hash listed")
  END;

  Check.Check((Shell("PATH=/nonexistent; export PATH; exec ../build/TestIdentities nossl", out) = 0)
    & Check.Contains(out, "isn't on PATH"),
    "no openssl on PATH: said so")
END Identities;

PROCEDURE Url(s: ARRAY OF CHAR; VAR u: GeminiUrls.URL);
  VAR why: ARRAY 128 OF CHAR;
BEGIN IF ~GeminiUrls.Parse(s, u, why) THEN Out.String("bad URL "); Out.String(s); Out.Ln END
END Url;

PROCEDURE For(s: GeminiIdentities.Scopes; link: ARRAY OF CHAR; want: ARRAY OF CHAR): BOOLEAN;
  VAR u: GeminiUrls.URL; name: ARRAY 80 OF CHAR;
BEGIN
  Url(link, u);
  IF want = "" THEN RETURN ~s.For(u, name) & (name = "") END;
  RETURN s.For(u, name) & (name = want)
END For;

PROCEDURE Scopes;
  VAR s, t: GeminiIdentities.Scopes; why: ARRAY 512 OF CHAR; u: GeminiUrls.URL;
    out: ARRAY 4096 OF CHAR; ok: BOOLEAN; name: ARRAY 80 OF CHAR; path: GeminiUrls.Text;
BEGIN
  Check.Check(GeminiIdentities.OpenScopes("../build/test-TestIdentities/scopes", s, why),
    "a scopes file that isn't there yet: none");
  Check.Check(For(s, "gemini://example.org/", ""), "... so no identity for a URL");
  Url("gemini://Example.ORG/app", u);
  Check.Check(s.Attach("alice", u, why), "one attached to a path");
  Check.Check(For(s, "gemini://example.org/app", "alice") & For(s, "gemini://example.org/app/x/y?q", "alice")
    & For(s, "gemini://EXAMPLE.org:1965/app/", "alice"),
    "... offered there and below it, whatever the host's case and the port's spelling");
  Check.Check(For(s, "gemini://example.org/apple", "") & For(s, "gemini://example.org/", "")
    & For(s, "gemini://example.org:1966/app", "") & For(s, "gemini://www.example.org/app", ""),
    "... but not on a path it merely starts, above it, on another port or host");
  Url("gemini://example.org/app/admin/", u);
  Check.Check(s.Attach("bob", u, why), "another attached below it");
  Check.Check(For(s, "gemini://example.org/app/admin/x", "bob") & For(s, "gemini://example.org/app/x", "alice")
    & For(s, "gemini://example.org/app/admin", "alice"),
    "the longest path wins; a prefix ending in / is a directory");
  Url("gemini://example.org", u);
  Check.Check(s.Attach("carol", u, why) & For(s, "gemini://example.org/other", "carol")
    & For(s, "gemini://example.org/app/x", "alice"), "one for the whole capsule, no path");
  Url("gemini://bücher.example/", u);
  Check.Check(s.Attach("dave", u, why) & For(s, "gemini://xn--bcher-kva.example/x", "dave"),
    "a host kept as ASCII");
  Url("gemini://[::1]:1966/", u);
  Check.Check(s.Attach("erin", u, why) & For(s, "gemini://[::1]:1966/a", "erin"), "an IPv6 address");
  Url("gemini://example.org/app", u);
  Check.Check(s.Attach("frank", u, why) & For(s, "gemini://example.org/app/x", "frank"),
    "attaching again replaces");
  Check.Check(~s.Attach("../x", u, why) & For(s, "gemini://example.org/app/x", "frank"),
    "a name that isn't one isn't attached");

  IF Shell("printf '# mine\nnot an entry\n' >> ../build/test-TestIdentities/scopes", out) = 0 THEN END;
  ok := GeminiIdentities.OpenScopes("../build/test-TestIdentities/scopes", t, why);
  Check.Check(ok & For(t, "gemini://example.org/app/admin/x", "bob") & For(t, "gemini://example.org/app/x", "frank")
    & For(t, "gemini://xn--bcher-kva.example/", "dave") & For(t, "gemini://[::1]:1966/", "erin"),
    "read back from its file");
  Url("gemini://example.org/app/admin/x?q", u);
  Check.Check(ok & t.Covering(u, name, path) & (name = "bob") & (path = "/app/admin/"),
    "Covering: the identity and the path it is attached at");
  Url("gemini://example.org:1966/", u);
  Check.Check(ok & ~t.Covering(u, name, path) & (name = "") & (path = ""), "... none: both empty");
  Url("gemini://example.org/app/admin/", u);
  Check.Check(ok & t.Detach(u, why) & For(t, "gemini://example.org/app/admin/x", "frank"),
    "one detached: the next longest offered");
  Check.Check(ok & t.Detach(u, why), "detaching what isn't there is no error");
  Check.Check((Shell("grep -c . ../build/test-TestIdentities/scopes", out) = 0) & Check.Contains(out, "6"),
    "the file holds the rest, and the lines it doesn't know");
  Check.Check((Shell("grep -x '# mine' ../build/test-TestIdentities/scopes && grep -x 'not an entry' ../build/test-TestIdentities/scopes", out) = 0)
    & (Shell("grep -x 'frank example.org:1965 /app' ../build/test-TestIdentities/scopes && grep -x 'erin \[::1\]:1966 /' ../build/test-TestIdentities/scopes", out) = 0),
    "... as they were, and as documented");
  Check.Check(ModeOf("../build/test-TestIdentities/scopes") = 180H, "its mode is 600");
  Check.Check((Shell("ls -a ../build/test-TestIdentities | grep -c tmp", out) = 1) & Check.Contains(out, "0"),
    "no temporary file left");

  Check.Check(~GeminiIdentities.OpenScopes("../build/test-TestIdentities", t, why) & (t = NIL),
    "a directory isn't a scopes file");
  IF (Shell("test `id -u` -ne 0", out) = 0)
      & (Shell("chmod 500 ../build/test-TestIdentities", out) = 0) THEN
    Url("gemini://example.net/", u);
    Check.Check(~s.Attach("alice", u, why) & (why # "") & For(s, "gemini://example.net/", ""),
      "a file that can't be written: FALSE, and the scopes as they were");
    IF Shell("chmod 700 ../build/test-TestIdentities", out) = 0 THEN END
  ELSE Check.Skip("a file that can't be written (root writes anywhere)")
  END
END Scopes;

PROCEDURE NoSsl;
  VAR id: GeminiIdentities.Identity; why: ARRAY 512 OF CHAR;
BEGIN
  IF GeminiIdentities.Make(Ids, "nossl", "", 30, id, why) THEN Out.String("made")
  ELSE Out.String(why)
  END;
  Out.Ln
END NoSsl;

PROCEDURE Main;
  VAR arg: ARRAY 16 OF CHAR; out: ARRAY 4096 OF CHAR;
BEGIN
  IF Args.argc = 2 THEN Args.Get(1, arg) ELSE arg := "" END;
  IF arg = "nossl" THEN NoSsl; RETURN END;
  IF Shell("rm -rf ../build/test-TestIdentities && mkdir ../build/test-TestIdentities", out) # 0 THEN
    Check.Check(FALSE, "making the test's directory")
  ELSE
    IF Shell("command -v openssl", out) = 0 THEN
      port := Server.Start();
      Identities;
      IF port > 0 THEN Server.Stop END
    ELSE Check.Skip("identities: no openssl here")
    END;
    Scopes;
    IF Shell("rm -rf ../build/test-TestIdentities", out) # 0 THEN END
  END;
  Check.Summary
END Main;

BEGIN Main
END TestIdentities.
