MODULE GeminiTrust; (* trust on first use: the keys of the servers a program knows *)

(* Gemini servers mostly sign their own certificates, so a client
   trusts a server on first use (TOFU), as ssh does: the first time it
   meets a host and port it keeps the server's key, and later it
   accepts only that key. What is kept is the SHA-256 of the
   certificate's public key (its SubjectPublicKeyInfo, as polibtls's
   Connection.PeerKeyHash gives it), not of the certificate, so a
   server that renews its certificate but keeps its key is still
   known, as Lagrange does (PLAN.md, "Trust"). With the key goes the
   certificate's expiry: a different key before it is changed, which
   is refused; after it, the old certificate has expired, and the new
   key replaces the old one only if the store's replaceExpired says
   so.

   A Store's Check is what a fetch calls (GeminiResponses.Options.trust)
   after the TLS handshake and before the request is sent, so a URL and
   its query never reach a server that isn't trusted. Hosts is the
   store this module gives, in memory (New) or kept in a file (Open); a
   program may extend Store to keep hosts elsewhere.

   The file is text, a line per host and port:

     <host>:<port> spki-sha256 <fingerprint> <notAfter>

   the host lower case, ASCII (punycode, as it went to the server), an
   IPv6 address in brackets; the fingerprint 64 lowercase hex digits;
   notAfter the certificate's expiry in Unix seconds; the fields
   separated by blanks. A line that can't be read as one, or names
   another algorithm, is kept as it is when the file is written and
   otherwise ignored, so a newer program's lines survive an older one's
   rewriting, and so do comments. The library chooses no path: the
   program gives it.

   The file is read once, by Open, and written whenever a host is added
   or its entry changes: in full, to a temporary name in the same
   directory, synced and renamed over it, so a crash leaves the old
   file or the new one, never half of one. Two programs sharing a file
   each write what they have read and changed, so the last to write
   wins. A file that can't be written fails the check (failed), and the
   host is as it was, so trust that can't be kept isn't given.

   Outside data never halts: a file that can't be read or written comes
   back as FALSE or failed and a reason. A Store whose Check isn't
   overridden halts (129). *)

IMPORT Platform, UnixErrors, UnixFiles, Clocks, Instants;

CONST
  (* Check's results *)
  known* = 0;      (* the key is the one known (its expiry updated if
                      the certificate was renewed) *)
  added* = 1;      (* first contact: the host is now known *)
  replaced* = 2;   (* another key, the known certificate expired, and
                      replaceExpired: the new key is now the one known *)
  changed* = 3;    (* another key, the known certificate not expired:
                      refused *)
  expired* = 4;    (* another key, the known certificate expired, and
                      not replaceExpired: refused *)
  failed* = 5;     (* not checked: the hash isn't a SHA-256, the host or
                      port is malformed, or the file couldn't be
                      written; refused *)

  Prefix = "SHA256:";  (* a hash as polibtls gives it *)
  HashLen* = 64;       (* hex digits of a SHA-256 *)
  MaxHash* = 7 + HashLen;   (* "SHA256:" and the digits *)
  MaxKey = 272;        (* "[" host "]:" port *)
  MaxFile = 4194304;   (* bytes of a file read at most *)
  MaxTries = 100;      (* temporary names tried *)
  Mode = 180H;         (* 600 octal: which hosts a user visits is theirs *)

  Abstract = 129;      (* a Store's Check not overridden *)

TYPE
  Chars = POINTER TO ARRAY OF CHAR;

  (* Where the hosts are kept. replaceExpired: a new key replaces the
     known one once the known certificate has expired (FALSE by
     default, as gmni does; many clients allow it). *)
  Store* = POINTER TO StoreDesc;
  StoreDesc* = RECORD
    replaceExpired*: BOOLEAN
  END;

  (* A line of the file: an entry of ours (entry), or any other line,
     kept as it was (raw). An entry read from the file keeps its raw
     text too, until it is changed. *)
  Line = POINTER TO LineDesc;
  LineDesc = RECORD
    next: Line;
    raw: Chars;
    entry: BOOLEAN;
    key: ARRAY MaxKey OF CHAR;
    hash: ARRAY HashLen + 1 OF CHAR;
    notAfter: HUGEINT
  END;

  (* The hosts, in memory, and in a file if path isn't NIL. *)
  Hosts* = POINTER TO HostsDesc;
  HostsDesc* = RECORD (StoreDesc)
    path: Chars;
    first, last: Line
  END;

(* Texts *)

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
  RETURN i
END Length;

(* s := s + t, cut short if s is full. *)
PROCEDURE Append(VAR s: ARRAY OF CHAR; t-: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := Length(s); j := 0;
  WHILE (j < LEN(t)) & (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; n: HUGEINT);
  VAR d: ARRAY 24 OF CHAR; i: INTEGER; t: ARRAY 2 OF CHAR;
BEGIN
  t[1] := 0X;
  IF n < 0 THEN t[0] := "-"; Append(s, t); n := -n END;
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + SHORT(n MOD 10)); n := n DIV 10; INC(i) UNTIL n = 0;
  WHILE i > 0 DO DEC(i); t[0] := d[i]; Append(s, t) END
END AppendInt;

PROCEDURE Hex(c: CHAR): BOOLEAN;
BEGIN RETURN (c >= "0") & (c <= "9") OR (c >= "a") & (c <= "f")
END Hex;

PROCEDURE Lower(c: CHAR): CHAR;
BEGIN
  IF (c >= "A") & (c <= "Z") THEN c := CHR(ORD(c) + 32) END;
  RETURN c
END Lower;

(* The time now, in Unix seconds. *)
PROCEDURE Now*(): HUGEINT;
  VAR t: Instants.Instant;
BEGIN
  Clocks.Now(t);
  RETURN Instants.UnixSeconds(t)
END Now;

(* host and port as the file has them, in key: FALSE if host is empty,
   has a blank or a control character, or port isn't 1..65535. *)
PROCEDURE MakeKey(host-: ARRAY OF CHAR; port: LONGINT; VAR key: ARRAY OF CHAR): BOOLEAN;
  VAR i, n: LONGINT; v6: BOOLEAN; t: ARRAY 2 OF CHAR;
BEGIN
  key[0] := 0X; n := Length(host);
  IF (n = 0) OR (n > 255) OR (port < 1) OR (port > 65535) THEN RETURN FALSE END;
  v6 := FALSE;
  FOR i := 0 TO n - 1 DO
    IF host[i] <= " " THEN RETURN FALSE END;
    IF host[i] = ":" THEN v6 := TRUE END
  END;
  IF v6 THEN Append(key, "[") END;
  t[1] := 0X;
  FOR i := 0 TO n - 1 DO t[0] := Lower(host[i]); Append(key, t) END;
  IF v6 THEN Append(key, "]") END;
  Append(key, ":"); AppendInt(key, port);
  RETURN TRUE
END MakeKey;

(* hash, "SHA256:" and 64 hex digits, as its digits, lower case, in
   digits: FALSE if it isn't one. *)
PROCEDURE Digits(hash-: ARRAY OF CHAR; VAR digits: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT; p: ARRAY 8 OF CHAR;
BEGIN
  digits[0] := 0X;
  IF Length(hash) # MaxHash THEN RETURN FALSE END;
  FOR i := 0 TO 6 DO p[i] := hash[i] END; p[7] := 0X;
  IF p # Prefix THEN RETURN FALSE END;
  FOR i := 0 TO HashLen - 1 DO
    IF ~Hex(Lower(hash[7 + i])) THEN digits[0] := 0X; RETURN FALSE END;
    digits[i] := Lower(hash[7 + i])
  END;
  digits[HashLen] := 0X;
  RETURN TRUE
END Digits;

(* Store *)

(* Checks the key whose hash (as polibtls gives it, "SHA256:" and hex)
   the server at host (ASCII, as it was asked for) and port gave, its
   certificate's expiry notAfter, at the time now (both Unix seconds):
   known, added or replaced to trust the server; changed, expired or
   failed to refuse it, with why saying so. *)
PROCEDURE (s: Store) Check*(host-: ARRAY OF CHAR; port: LONGINT; hash-: ARRAY OF CHAR;
    notAfter, now: HUGEINT; VAR why: ARRAY OF CHAR): INTEGER;
BEGIN ASSERT(s = NIL, Abstract); RETURN failed
END Check;

(* Reading the file *)

(* Skips blanks from s[i]. *)
PROCEDURE Blanks(VAR s: ARRAY OF CHAR; VAR i: LONGINT);
BEGIN
  WHILE (s[i] = " ") OR (s[i] = 9X) DO INC(i) END
END Blanks;

(* The field at s[i..] into f, if it fits: FALSE if it doesn't, or is
   empty. *)
PROCEDURE Field(VAR s: ARRAY OF CHAR; VAR i: LONGINT; VAR f: ARRAY OF CHAR): BOOLEAN;
  VAR j: LONGINT;
BEGIN
  j := 0;
  WHILE (s[i] # 0X) & (s[i] # " ") & (s[i] # 9X) DO
    IF j = LEN(f) - 1 THEN RETURN FALSE END;
    f[j] := s[i]; INC(j); INC(i)
  END;
  f[j] := 0X;
  RETURN j > 0
END Field;

(* l's raw text read as an entry of ours, into its fields: l.entry. *)
PROCEDURE ReadEntry(l: Line);
  VAR i, j, n: LONGINT; alg: ARRAY 16 OF CHAR; hash: ARRAY HashLen + 2 OF CHAR;
    time: ARRAY 20 OF CHAR; key: ARRAY MaxKey OF CHAR; v: HUGEINT;
BEGIN
  l.entry := FALSE; i := 0;
  Blanks(l.raw^, i);
  IF ~Field(l.raw^, i, key) THEN RETURN END; Blanks(l.raw^, i);
  IF ~Field(l.raw^, i, alg) OR (alg # "spki-sha256") THEN RETURN END; Blanks(l.raw^, i);
  IF ~Field(l.raw^, i, hash) OR (Length(hash) # HashLen) THEN RETURN END; Blanks(l.raw^, i);
  IF ~Field(l.raw^, i, time) THEN RETURN END; Blanks(l.raw^, i);
  IF l.raw[i] # 0X THEN RETURN END;
  (* the key: something, a ":", and a port of digits *)
  n := Length(key); j := n;
  WHILE (j > 0) & (key[j - 1] # ":") DO DEC(j) END;
  IF (j < 2) OR (j = n) OR (n - j > 5) THEN RETURN END;
  v := 0;
  FOR i := j TO n - 1 DO
    IF (key[i] < "0") OR (key[i] > "9") THEN RETURN END;
    v := v * 10 + ORD(key[i]) - ORD("0")
  END;
  IF (v < 1) OR (v > 65535) THEN RETURN END;
  FOR i := 0 TO HashLen - 1 DO IF ~Hex(hash[i]) THEN RETURN END END;
  n := Length(time);
  IF n > 18 THEN RETURN END;
  v := 0;
  FOR i := 0 TO n - 1 DO
    IF (time[i] < "0") OR (time[i] > "9") THEN RETURN END;
    v := v * 10 + ORD(time[i]) - ORD("0")
  END;
  COPY(key, l.key); COPY(hash, l.hash); l.notAfter := v; l.entry := TRUE
END ReadEntry;

PROCEDURE AddLine(h: Hosts; l: Line);
BEGIN
  l.next := NIL;
  IF h.first = NIL THEN h.first := l ELSE h.last.next := l END;
  h.last := l
END AddLine;

(* The lines of buf[0..len-1] into h, each without its LF (or CR LF). *)
PROCEDURE Split(h: Hosts; VAR buf: ARRAY OF CHAR; len: LONGINT);
  VAR i, j, k, e: LONGINT; l: Line;
BEGIN
  i := 0;
  WHILE i < len DO
    j := i; WHILE (j < len) & (buf[j] # 0AX) DO INC(j) END;
    e := j; IF (e > i) & (buf[e - 1] = 0DX) THEN DEC(e) END;
    NEW(l); NEW(l.raw, e - i + 1);
    FOR k := i TO e - 1 DO
      (* a NUL would end the line early when written back *)
      IF buf[k] = 0X THEN l.raw[k - i] := " " ELSE l.raw[k - i] := buf[k] END
    END;
    l.raw[e - i] := 0X; l.key := ""; l.hash := ""; l.notAfter := 0;
    ReadEntry(l);
    AddLine(h, l);
    i := j + 1
  END
END Split;

(* The hosts kept in memory only, none yet. *)
PROCEDURE New*(): Hosts;
  VAR h: Hosts;
BEGIN
  NEW(h); h.replaceExpired := FALSE; h.path := NIL; h.first := NIL; h.last := NIL;
  RETURN h
END New;

(* The hosts kept in the file path, read now: none if it doesn't exist
   yet (it is made when one is added). FALSE, with why, h NIL, if it
   can't be read, or is over 4 MiB. *)
PROCEDURE Open*(path-: ARRAY OF CHAR; VAR h: Hosts; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR fd, len, n: LONGINT; err: UnixErrors.Error; buf, more: Chars; i: LONGINT;
    dir: UnixFiles.Directory;
BEGIN
  why[0] := 0X; h := NIL;
  IF (Length(path) = 0) OR (Length(path) = LEN(path)) THEN
    COPY("the known hosts file has no name", why); RETURN FALSE
  END;
  h := New();
  NEW(h.path, Length(path) + 1); COPY(path, h.path^);
  IF ~UnixFiles.OpenRead(h.path^, {UnixFiles.nonBlocking}, fd, err) THEN
    IF err.code = UnixErrors.ENOENT THEN RETURN TRUE END;
    COPY(err.text, why); h := NIL; RETURN FALSE
  END;
  (* NetBSD reads a directory as its entries, where the others refuse *)
  IF UnixFiles.OpenDirectory(h.path^, {}, dir, err) THEN
    UnixFiles.CloseDirectory(dir); UnixFiles.Close(fd);
    COPY(path, why); Append(why, " is a directory"); h := NIL; RETURN FALSE
  END;
  NEW(buf, 4096); len := 0;
  LOOP
    IF len = LEN(buf^) THEN
      IF len >= MaxFile THEN
        UnixFiles.Close(fd); COPY("the known hosts file is over 4 MiB", why); h := NIL;
        RETURN FALSE
      END;
      NEW(more, 2 * len);
      FOR i := 0 TO len - 1 DO more[i] := buf[i] END;
      buf := more
    END;
    IF ~UnixFiles.Read(fd, buf^, len, LEN(buf^) - len, n, err) THEN
      UnixFiles.Close(fd); COPY(err.text, why); h := NIL; RETURN FALSE
    END;
    IF n = 0 THEN EXIT END;
    INC(len, n)
  END;
  UnixFiles.Close(fd);
  Split(h, buf^, len);
  RETURN TRUE
END Open;

(* Writing the file *)

(* buf[len..] := s, buf grown as it must be. *)
PROCEDURE Put(VAR buf: Chars; VAR len: LONGINT; s-: ARRAY OF CHAR);
  VAR i, n: LONGINT; more: Chars;
BEGIN
  n := Length(s);
  IF len + n > LEN(buf^) THEN
    NEW(more, 2 * (len + n));
    FOR i := 0 TO len - 1 DO more[i] := buf[i] END;
    buf := more
  END;
  FOR i := 0 TO n - 1 DO buf[len + i] := s[i] END;
  INC(len, n)
END Put;

(* Writes buf[0..len-1] to the file temp, made new: FALSE, with why,
   and temp removed, if it can't be. *)
PROCEDURE WriteTemp(VAR temp: ARRAY OF CHAR; VAR buf: ARRAY OF CHAR; len: LONGINT;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR fd, pos, n, tries: LONGINT; err: UnixErrors.Error; ok: BOOLEAN; base: LONGINT;
BEGIN
  (* <path>.<pid>.<n>.tmp, made exclusive, so neither another program's
     temporary file nor a link put there is written through *)
  base := Length(temp); tries := 0;
  LOOP
    temp[base] := 0X;
    Append(temp, "."); AppendInt(temp, Platform.PID); Append(temp, ".");
    AppendInt(temp, tries); Append(temp, ".tmp");
    IF UnixFiles.OpenWrite(temp, {UnixFiles.create, UnixFiles.exclusive}, Mode, fd, err) THEN
      EXIT
    END;
    INC(tries);
    IF (err.code # UnixErrors.EEXIST) OR (tries = MaxTries) THEN
      COPY(err.text, why); RETURN FALSE
    END
  END;
  pos := 0; ok := TRUE;
  WHILE ok & (pos < len) DO
    ok := UnixFiles.Write(fd, buf, pos, len - pos, n, err); INC(pos, n)
  END;
  ok := ok & UnixFiles.Sync(fd, err);
  UnixFiles.Close(fd);
  IF ~ok THEN COPY(err.text, why); IF UnixFiles.Remove(temp, err) THEN END END;
  RETURN ok
END WriteTemp;

(* Writes h to its file, if it has one: FALSE, with why, if it can't,
   and the file as it was. *)
PROCEDURE Save(h: Hosts; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR buf: Chars; len: LONGINT; l: Line; temp: Chars; err: UnixErrors.Error;
    n: ARRAY 24 OF CHAR;
BEGIN
  IF h.path = NIL THEN RETURN TRUE END;
  NEW(buf, 4096); len := 0; l := h.first;
  WHILE l # NIL DO
    IF l.raw # NIL THEN Put(buf, len, l.raw^)
    ELSE
      n := ""; AppendInt(n, l.notAfter);
      Put(buf, len, l.key); Put(buf, len, " spki-sha256 "); Put(buf, len, l.hash);
      Put(buf, len, " "); Put(buf, len, n)
    END;
    n[0] := 0AX; n[1] := 0X; Put(buf, len, n);
    l := l.next
  END;
  NEW(temp, LEN(h.path^) + 40); COPY(h.path^, temp^);
  IF ~WriteTemp(temp^, buf^, len, why) THEN RETURN FALSE END;
  IF ~UnixFiles.Rename(temp^, h.path^, err) THEN
    COPY(err.text, why); IF UnixFiles.Remove(temp^, err) THEN END; RETURN FALSE
  END;
  RETURN TRUE
END Save;

(* Hosts *)

(* The entry for key, or NIL: the first, if the file has several. *)
PROCEDURE Find(h: Hosts; VAR key: ARRAY OF CHAR): Line;
  VAR l: Line;
BEGIN
  l := h.first;
  WHILE (l # NIL) & ~(l.entry & (l.key = key)) DO l := l.next END;
  RETURN l
END Find;

(* key's entry made digits and notAfter, added if there is none, and h
   saved: FALSE, with why, if it can't be, and h as it was. *)
PROCEDURE Set(h: Hosts; VAR key, digits: ARRAY OF CHAR; notAfter: HUGEINT;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR l, last: Line; raw: Chars; hash: ARRAY HashLen + 1 OF CHAR; time: HUGEINT;
BEGIN
  l := Find(h, key);
  IF l = NIL THEN
    NEW(l); l.raw := NIL; l.entry := TRUE; COPY(key, l.key);
    COPY(digits, l.hash); l.notAfter := notAfter;
    last := h.last; AddLine(h, l);
    IF Save(h, why) THEN RETURN TRUE END;
    h.last := last; IF last = NIL THEN h.first := NIL ELSE last.next := NIL END;
    RETURN FALSE
  END;
  raw := l.raw; COPY(l.hash, hash); time := l.notAfter;
  l.raw := NIL; COPY(digits, l.hash); l.notAfter := notAfter;
  IF Save(h, why) THEN RETURN TRUE END;
  l.raw := raw; COPY(hash, l.hash); l.notAfter := time;
  RETURN FALSE
END Set;

(* The Store's check, keeping hosts in h (and its file). *)
PROCEDURE (h: Hosts) Check*(host-: ARRAY OF CHAR; port: LONGINT; hash-: ARRAY OF CHAR;
    notAfter, now: HUGEINT; VAR why: ARRAY OF CHAR): INTEGER;
  VAR key: ARRAY MaxKey OF CHAR; digits: ARRAY HashLen + 1 OF CHAR; l: Line;
    result: INTEGER; msg: ARRAY 512 OF CHAR;
BEGIN
  why[0] := 0X;
  IF ~MakeKey(host, port, key) THEN COPY("not a host and port to know", why); RETURN failed END;
  IF ~Digits(hash, digits) THEN COPY("the server's key hash isn't a SHA-256", why); RETURN failed END;
  l := Find(h, key);
  IF l = NIL THEN result := added
  ELSIF l.hash = digits THEN
    IF l.notAfter = notAfter THEN RETURN known END;
    result := known      (* renewed, or an older certificate with the key *)
  ELSIF l.notAfter > now THEN
    COPY("the server's key isn't the one known for ", why); Append(why, key);
    Append(why, ", whose certificate hasn't expired");
    RETURN changed
  ELSIF ~h.replaceExpired THEN
    COPY("the server's key isn't the one known for ", why); Append(why, key);
    Append(why, ", whose certificate has expired");
    RETURN expired
  ELSE result := replaced
  END;
  IF ~Set(h, key, digits, notAfter, msg) THEN
    COPY("the known hosts file: ", why); Append(why, msg);
    RETURN failed
  END;
  RETURN result
END Check;

(* The key known for host and port, as polibtls gives it ("SHA256:"
   and hex), in hash, and its certificate's expiry: FALSE if none is
   known. *)
PROCEDURE (h: Hosts) Lookup*(host-: ARRAY OF CHAR; port: LONGINT; VAR hash: ARRAY OF CHAR;
    VAR notAfter: HUGEINT): BOOLEAN;
  VAR key: ARRAY MaxKey OF CHAR; l: Line;
BEGIN
  hash[0] := 0X; notAfter := 0;
  IF ~MakeKey(host, port, key) THEN RETURN FALSE END;
  l := Find(h, key);
  IF l = NIL THEN RETURN FALSE END;
  COPY(Prefix, hash); Append(hash, l.hash); notAfter := l.notAfter;
  RETURN TRUE
END Lookup;

(* Makes hash, with its certificate's expiry notAfter, the key known
   for host and port, whatever was known before: for a program whose
   user has decided to trust a changed key. FALSE, with why, if the
   host, port or hash is malformed, or the file can't be written. *)
PROCEDURE (h: Hosts) Trust*(host-: ARRAY OF CHAR; port: LONGINT; hash-: ARRAY OF CHAR;
    notAfter: HUGEINT; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR key: ARRAY MaxKey OF CHAR; digits: ARRAY HashLen + 1 OF CHAR;
BEGIN
  why[0] := 0X;
  IF ~MakeKey(host, port, key) THEN COPY("not a host and port to know", why); RETURN FALSE END;
  IF ~Digits(hash, digits) THEN COPY("not a SHA-256 key hash", why); RETURN FALSE END;
  RETURN Set(h, key, digits, notAfter, why)
END Trust;

(* Forgets host and port, so its next key is trusted on first use
   again: TRUE if it wasn't known, or is forgotten; FALSE, with why, if
   the file can't be written. Every entry for it goes, if the file had
   several. *)
PROCEDURE (h: Hosts) Forget*(host-: ARRAY OF CHAR; port: LONGINT; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR key: ARRAY MaxKey OF CHAR; l: Line; old: POINTER TO ARRAY OF Line; i, n: LONGINT;
BEGIN
  why[0] := 0X;
  IF ~MakeKey(host, port, key) OR (Find(h, key) = NIL) THEN RETURN TRUE END;
  (* the lines kept in order, to put back if the file can't be written *)
  n := 0; l := h.first; WHILE l # NIL DO INC(n); l := l.next END;
  NEW(old, n); l := h.first;
  FOR i := 0 TO n - 1 DO old[i] := l; l := l.next END;
  h.first := NIL; h.last := NIL;
  FOR i := 0 TO n - 1 DO
    IF ~(old[i].entry & (old[i].key = key)) THEN AddLine(h, old[i]) END
  END;
  IF Save(h, why) THEN RETURN TRUE END;
  h.first := NIL; h.last := NIL;
  FOR i := 0 TO n - 1 DO AddLine(h, old[i]) END;
  RETURN FALSE
END Forget;

END GeminiTrust.
