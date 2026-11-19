MODULE TestTrust; (* GeminiTrust: trust on first use, in memory, in a file, and in a fetch *)

(* The store's rule first, in memory; then its file, made under
   build/test-TestTrust afresh and removed at the end; then fetches
   from test/TestServer through GeminiFetch with a store, which must
   refuse a changed key before the request is sent (the server's
   /count says how many requests it has read). *)

IMPORT Check, Child, Server, ClientCases, UnixErrors, UnixFiles,
  GeminiTrust, GeminiResponses, GeminiFetch;

CONST
  Dir = "../build/test-TestTrust";
  Key1 = "SHA256:1111111111111111111111111111111111111111111111111111111111111111";
  Key2 = "SHA256:2222222222222222222222222222222222222222222222222222222222222222";
  Key3 = "SHA256:abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd";
  Upper3 = "SHA256:ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD";
  Hex1 = "1111111111111111111111111111111111111111111111111111111111111111";
  Hex2 = "2222222222222222222222222222222222222222222222222222222222222222";
  Now = 1800000000;          (* "now", for the store's rule *)
  Later = Now + 86400;       (* a certificate not yet expired *)
  Earlier = Now - 86400;     (* one expired *)
  LF = 0AX; CR = 0DX;

VAR
  port: INTEGER;

PROCEDURE Shell(cmd: ARRAY OF CHAR): BOOLEAN;
  VAR c: Child.Child; out: ARRAY 4096 OF CHAR; n: LONGINT;
BEGIN RETURN Child.Spawn(cmd, "", 0, c) & (Child.Wait(c, out, n) = 0)
END Shell;

(* path := Dir "/" name *)
PROCEDURE PathOf(name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
BEGIN COPY(Dir, path); ClientCases.Append(path, "/"); ClientCases.Append(path, name)
END PathOf;

(* The file's contents in s, 0X-terminated: FALSE if it can't be read. *)
PROCEDURE Contents(path: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; VAR len: LONGINT): BOOLEAN;
  VAR fd, n: LONGINT; err: UnixErrors.Error; ok: BOOLEAN;
BEGIN
  len := 0; s[0] := 0X;
  IF ~UnixFiles.OpenRead(path, {}, fd, err) THEN RETURN FALSE END;
  REPEAT ok := UnixFiles.Read(fd, s, len, LEN(s) - 1 - len, n, err); INC(len, n)
  UNTIL ~ok OR (n = 0);
  UnixFiles.Close(fd);
  s[len] := 0X;
  RETURN ok
END Contents;

PROCEDURE Make(path: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; len: LONGINT): BOOLEAN;
  VAR fd, n: LONGINT; err: UnixErrors.Error; ok: BOOLEAN;
BEGIN
  IF ~UnixFiles.OpenWrite(path, {UnixFiles.create, UnixFiles.truncate}, 180H, fd, err) THEN
    RETURN FALSE
  END;
  ok := UnixFiles.Write(fd, s, 0, len, n, err) & (n = len);
  UnixFiles.Close(fd);
  RETURN ok
END Make;

(* How many names Dir holds. *)
PROCEDURE Names(): INTEGER;
  VAR d: UnixFiles.Directory; err: UnixErrors.Error; name: ARRAY UnixFiles.NameLen OF CHAR;
    n: INTEGER;
BEGIN
  n := 0;
  IF ~UnixFiles.OpenDirectory(Dir, {}, d, err) THEN RETURN -1 END;
  WHILE UnixFiles.NextName(d, name, err) & (name # "") DO INC(n) END;
  UnixFiles.CloseDirectory(d);
  RETURN n
END Names;

PROCEDURE Is(h: GeminiTrust.Hosts; host: ARRAY OF CHAR; port: LONGINT; hash: ARRAY OF CHAR;
    notAfter: HUGEINT): BOOLEAN;
  VAR got: ARRAY GeminiTrust.MaxHash + 1 OF CHAR; t: HUGEINT;
BEGIN RETURN h.Lookup(host, port, got, t) & (got = hash) & (t = notAfter)
END Is;

PROCEDURE Rule;
  VAR h: GeminiTrust.Hosts; why: ARRAY 512 OF CHAR; got: ARRAY 80 OF CHAR; t: HUGEINT;
BEGIN
  h := GeminiTrust.New();
  Check.Check(~h.Lookup("example.org", 1965, got, t) & (got = "") & (t = 0),
    "a store starts knowing nothing");
  Check.Check((h.Check("example.org", 1965, Key1, Later, Now, why) = GeminiTrust.added)
    & Is(h, "example.org", 1965, Key1, Later), "first contact: added");
  Check.Check(h.Check("example.org", 1965, Key1, Later, Now, why) = GeminiTrust.known,
    "the same key: known");
  Check.Check(h.Check("EXAMPLE.org", 1965, Key1, Later, Now, why) = GeminiTrust.known,
    "the host's case doesn't matter");
  Check.Check((h.Check("example.org", 1965, Key1, Later + 100, Now, why) = GeminiTrust.known)
    & Is(h, "example.org", 1965, Key1, Later + 100),
    "a renewed certificate with the same key: known, its expiry updated");
  Check.Check((h.Check("example.org", 1965, Key2, Later, Now, why) = GeminiTrust.changed)
    & Check.Contains(why, "example.org:1965") & Is(h, "example.org", 1965, Key1, Later + 100),
    "another key before the known one expires: changed, and nothing changed");
  Check.Check(h.Check("example.org", 1966, Key2, Later, Now, why) = GeminiTrust.added,
    "another port is another server");
  Check.Check(h.Trust("hex.example", 1965, Key3, Later, why)
    & (h.Check("hex.example", 1965, Upper3, Later, Now, why) = GeminiTrust.known),
    "a key's hex is compared whatever its case");
  Check.Check(h.Trust("old.example", 1965, Key1, Earlier, why), "Trust sets a key");
  Check.Check((h.Check("old.example", 1965, Key2, Later, Now, why) = GeminiTrust.expired)
    & Is(h, "old.example", 1965, Key1, Earlier),
    "another key once the known one has expired: refused by default");
  h.replaceExpired := TRUE;
  Check.Check((h.Check("old.example", 1965, Key2, Later, Now, why) = GeminiTrust.replaced)
    & Is(h, "old.example", 1965, Key2, Later),
    "... and replaced if the store's replaceExpired says so");
  Check.Check(h.Check("example.org", 1965, Key2, Later, Now, why) = GeminiTrust.changed,
    "... but never one not yet expired");
  Check.Check((h.Check("example.org", 1965, "SHA256:12", Later, Now, why) = GeminiTrust.failed)
    & (h.Check("example.org", 1965, "MD5:1111111111111111111111111111111111111111111111111111111111111111",
         Later, Now, why) = GeminiTrust.failed)
    & (h.Check("example.org", 1965, "", Later, Now, why) = GeminiTrust.failed),
    "a hash that isn't a SHA-256: failed");
  Check.Check((h.Check("example.org", 0, Key1, Later, Now, why) = GeminiTrust.failed)
    & (h.Check("example.org", 65536, Key1, Later, Now, why) = GeminiTrust.failed)
    & (h.Check("", 1965, Key1, Later, Now, why) = GeminiTrust.failed)
    & (h.Check("a b", 1965, Key1, Later, Now, why) = GeminiTrust.failed),
    "a port or host that can't be: failed");
  Check.Check((h.Check("::1", 1965, Key1, Later, Now, why) = GeminiTrust.added)
    & Is(h, "::1", 1965, Key1, Later), "an IPv6 address");
  Check.Check(h.Forget("example.org", 1965, why) & ~h.Lookup("example.org", 1965, got, t)
    & Is(h, "example.org", 1966, Key2, Later),
    "Forget forgets that host and port only");
  Check.Check(h.Forget("never.example", 1965, why), "Forget of a host never known");
  Check.Check(h.Check("example.org", 1965, Key2, Later, Now, why) = GeminiTrust.added,
    "a forgotten host is trusted on first use again")
END Rule;

PROCEDURE Files;
  VAR h: GeminiTrust.Hosts; why: ARRAY 512 OF CHAR; path: ARRAY 256 OF CHAR;
    s: ARRAY 8192 OF CHAR; len, fd, mode: LONGINT; err: UnixErrors.Error; got: ARRAY 80 OF CHAR;
    t: HUGEINT;
BEGIN
  PathOf("known_hosts", path);
  Check.Check(GeminiTrust.Open(path, h, why) & (h # NIL) & ~h.Lookup("a.example", 1965, got, t),
    "a file that doesn't exist yet: none known");
  Check.Check(Names() = 0, "... and no file made for it");
  Check.Check((h.Check("a.example", 1965, Key1, Later, Now, why) = GeminiTrust.added)
    & Contents(path, s, len), "first contact makes the file");
  COPY("a.example:1965 spki-sha256 ", got); ClientCases.Append(got, Hex1);
  Check.Check(Check.Contains(s, got) & (s[len - 1] = LF), "... with the host's line");
  Check.Check(UnixFiles.OpenRead(path, {}, fd, err) & UnixFiles.ModeOf(fd, mode, err)
    & (mode = 180H), "... readable by its owner only");
  UnixFiles.Close(fd);
  Check.Check(GeminiTrust.Open(path, h, why) & Is(h, "a.example", 1965, Key1, Later),
    "... and read back");

  (* Lines that aren't ours, or can't be read, kept *)
  s := "# a comment"; ClientCases.Append(s, "|");
  ClientCases.Append(s, "b.example:1965 sha512-whole AAAA 1|");
  ClientCases.Append(s, "c.example:1965 spki-sha256 nothex 12|");
  ClientCases.Append(s, "d.example:1965 spki-sha256 "); ClientCases.Append(s, Hex2);
  ClientCases.Append(s, " 1800086400 trailing|");
  ClientCases.Append(s, "|");
  ClientCases.Append(s, "[::1]:1965  spki-sha256^"); ClientCases.Append(s, Hex1);
  ClientCases.Append(s, " 1800086400~|");
  ClientCases.Append(s, "e.example:1965 spki-sha256 "); ClientCases.Append(s, Hex2);
  ClientCases.Append(s, " 1800086400");
  len := 0;
  WHILE s[len] # 0X DO
    IF s[len] = "|" THEN s[len] := LF ELSIF s[len] = "~" THEN s[len] := CR
    ELSIF s[len] = "^" THEN s[len] := 9X
    END;
    INC(len)
  END;
  (* "~" is CR, so [::1]'s line ends CR LF; e.example's has no LF *)
  Check.Check(Make(path, s, len), "a file with others' lines made");
  Check.Check(GeminiTrust.Open(path, h, why), "... read");
  Check.Check(~h.Lookup("b.example", 1965, got, t) & ~h.Lookup("c.example", 1965, got, t)
    & ~h.Lookup("d.example", 1965, got, t),
    "... its unknown algorithm, unreadable hash and extra field ignored");
  Check.Check(Is(h, "::1", 1965, Key1, Later) & Is(h, "e.example", 1965, Key2, Later),
    "... its lines with tabs, CR LF, and no final LF read");
  Check.Check(h.Check("f.example", 1965, Key1, Later, Now, why) = GeminiTrust.added,
    "... a host added to it");
  Check.Check(Contents(path, s, len)
    & Check.Contains(s, "# a comment")
    & Check.Contains(s, "b.example:1965 sha512-whole AAAA 1")
    & Check.Contains(s, "c.example:1965 spki-sha256 nothex 12")
    & Check.Contains(s, " 1800086400 trailing")
    & Check.Contains(s, "f.example:1965 spki-sha256 1111"),
    "... and the lines it didn't know kept as they were");
  Check.Check(Names() = 1, "... and no temporary file left");
  Check.Check(GeminiTrust.Open(path, h, why) & Is(h, "f.example", 1965, Key1, Later)
    & Is(h, "e.example", 1965, Key2, Later), "... read back");

  (* Can't be read, can't be written *)
  Check.Check(~GeminiTrust.Open(Dir, h, why) & (h = NIL) & (why # ""),
    "a directory as the file: FALSE, with why");
  Check.Check(~GeminiTrust.Open("", h, why) & (h = NIL), "no name: FALSE");
  PathOf("none/known_hosts", path);
  Check.Check(GeminiTrust.Open(path, h, why), "a file in a directory that doesn't exist: none known");
  Check.Check((h.Check("a.example", 1965, Key1, Later, Now, why) = GeminiTrust.failed)
    & Check.Contains(why, "known hosts file") & ~h.Lookup("a.example", 1965, got, t),
    "... a host that can't be written there fails, and isn't known")
END Files;

PROCEDURE Fetches;
  VAR h: GeminiTrust.Hosts; opts: GeminiResponses.Options; r: GeminiResponses.Response;
    url: ARRAY 256 OF CHAR; why: ARRAY 512 OF CHAR; key: ARRAY 80 OF CHAR; t: HUGEINT;
    before, after: LONGINT; ok: BOOLEAN; buf: GeminiResponses.Chars;

  (* The number of requests the server read before this one. *)
  PROCEDURE Count(): LONGINT;
    VAR o: GeminiResponses.Options; r: GeminiResponses.Response; n, i: LONGINT;
      u: ARRAY 256 OF CHAR;
  BEGIN
    GeminiResponses.InitOptions(o); ClientCases.Url("localhost", port, "/count", u);
    IF ~GeminiFetch.Fetch(u, o, r) OR ~r.ReadAll(buf, n) THEN RETURN -1 END;
    i := 0; t := 0;
    WHILE (i < n) & (buf[i] >= "0") & (buf[i] <= "9") DO t := t * 10 + ORD(buf[i]) - ORD("0"); INC(i) END;
    RETURN SHORT(t)
  END Count;

BEGIN
  GeminiResponses.InitOptions(opts);
  h := GeminiTrust.New(); opts.trust := h;
  ClientCases.Url("localhost", port, "/", url);
  ok := GeminiFetch.Fetch(url, opts, r);
  Check.Check(ok & (r.trust = GeminiTrust.added) & (r.status = 20)
    & h.Lookup("localhost", port, key, t) & (key = r.keyHash) & (t = r.notAfter)
    & (r.notAfter > GeminiTrust.Now()),
    "a fetch: the server added, by its key's hash and its certificate's expiry");
  IF ok THEN r.Close END;
  ok := GeminiFetch.Fetch(url, opts, r);
  Check.Check(ok & (r.trust = GeminiTrust.known), "again: known");
  IF ok THEN r.Close END;
  Check.Check(h.Trust("localhost", port, key, r.notAfter - 1000, why)
    & GeminiFetch.Fetch(url, opts, r) & (r.trust = GeminiTrust.known)
    & h.Lookup("localhost", port, key, t) & (t = r.notAfter),
    "the same key with another expiry: known, and the expiry updated");
  r.Close;

  before := Count();
  Check.Check(h.Trust("localhost", port, Key1, GeminiTrust.Now() + 1000, why), "another key set");
  ok := GeminiFetch.Fetch(url, opts, r);
  Check.Check(~ok & (r.trust = GeminiTrust.changed) & (r.error.kind = GeminiResponses.changed)
    & (r.status = 0) & Check.Contains(r.error.text, "isn't the one known"),
    "a changed key: refused, error changed");
  after := Count();
  Check.Check((before >= 0) & (after = before + 1), "... before the request was sent");

  Check.Check(h.Trust("localhost", port, Key1, GeminiTrust.Now() - 1000, why), "an expired key set");
  ok := GeminiFetch.Fetch(url, opts, r);
  Check.Check(~ok & (r.trust = GeminiTrust.expired) & (r.error.kind = GeminiResponses.untrusted),
    "a new key once the known one expired: refused by default, untrusted");
  h.replaceExpired := TRUE;
  ok := GeminiFetch.Fetch(url, opts, r);
  Check.Check(ok & (r.trust = GeminiTrust.replaced) & h.Lookup("localhost", port, key, t)
    & (key = r.keyHash), "... replaced when the store allows it");
  IF ok THEN r.Close END;

  opts.trust := NIL;
  ok := GeminiFetch.Fetch(url, opts, r);
  Check.Check(ok & (r.trust = -1) & (r.keyHash # ""), "no store: nothing asked, the key's hash given");
  IF ok THEN r.Close END
END Fetches;

BEGIN
  Rule;
  IF Shell("rm -rf ../build/test-TestTrust && mkdir ../build/test-TestTrust") THEN
    Files;
    Check.Check(Shell("rm -rf ../build/test-TestTrust"), "the test's files removed")
  ELSE Check.Check(FALSE, "the test's directory made")
  END;
  port := Server.Start();
  IF port > 0 THEN Fetches; Server.Stop END;
  Check.Summary
END TestTrust.
