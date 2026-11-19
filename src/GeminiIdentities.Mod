MODULE GeminiIdentities; (* certificates: a client's made, listed, and chosen for a URL; a server's kept *)

(* An identity is a client certificate and its key, which a capsule
   knows a user by (status 60): the files <name>.crt and <name>.key in a
   directory the program gives. Make makes one, through polibtls's
   TlsMake; List and Load read them, each with its certificate's
   hash, as a server sees it ("SHA256:" and hex, polibtls's
   TlsCerts.CertHash, the same as Tls.Connection.PeerCertHash), and its
   validity (TlsCerts.Validity), all in Oberon. Use puts one in a
   fetch's options.

   The specification forbids making or using a certificate without the
   user taking part (P "Status 60"), so nothing here is called by a
   fetch: a 60 comes back to the program, which asks its user, and then
   calls Make, or picks one.

   Make makes the pair through polibtls's TlsMake, with the libcrypto
   libtls loads, so no openssl command is needed (PLAN.md, "Client
   certificates"): an ECDSA P-256 key, mode 600, then a self-signed
   certificate, SHA-256, mode 644, each file written whole or not at
   all, the key first, so an identity exists exactly when its .crt
   does. A .key without its .crt, as an interrupted Make leaves, is
   given its certificate. A name is letters, digits, ".", "_" and "-",
   not starting with ".", so it can't name a file outside the
   directory.

   Ensure is the same for a server: the certificate a capsule presents,
   made the first time and kept from then on, since Gemini clients pin
   the certificate they first see (TOFU), and a new one at every start
   would look like an attack. It is pogemini's, moved here so every
   server on GeminiServer can make its own (PLAN.md, "A server's
   certificate").

   Scopes says which identity to offer for a URL, by the common rule
   (as Lagrange and Amfora have it, and as P scopes a certificate made
   for a 60): an identity attached to a host, port and path is offered
   for that path and every one below it, the longest such path winning.
   It is kept in a file the program names, a line per attachment:

     <name> <host>:<port> <path>

   the host lower case, ASCII (punycode), an IPv6 address in brackets;
   the path as the URL has it, "/" for none. Other lines are kept as
   they are and otherwise ignored. The file is written as GeminiTrust's
   is: whole, to a temporary name, synced and renamed.

   Outside data never halts: a file that can't be read or written, or a
   pair that can't be made, comes back as FALSE and a reason. *)

IMPORT Platform, Directories, Clocks, Instants, UnixErrors, UnixFiles, Tls, TlsCerts, TlsMake,
  GeminiPunycode, GeminiUrls, GeminiResponses;

CONST
  MaxName* = 64;        (* an identity's name, and its common name, at most *)
  DefaultDays* = 7300;  (* 20 years: a capsule knows its user by the hash *)
  MaxDays* = 36500;
  MaxHash = TlsCerts.HashLength;
  MaxPem = 65536;       (* bytes of a certificate file read at most *)
  MaxFile = 4194304;    (* bytes of a scopes file read at most *)
  MaxKey = 272;         (* "[" host "]:" port *)
  MaxTries = 100;
  Mode = 180H;          (* 600 octal *)
  DirMode = 1C0H;       (* 700 octal: a directory Ensure makes *)

TYPE
  Chars = POINTER TO ARRAY OF CHAR;
  Name* = ARRAY MaxName + 1 OF CHAR;

  (* An identity in a directory: its name, its files, its certificate's
     hash ("SHA256:" and hex) and validity (Unix seconds). next is the
     next one List found. *)
  Identity* = POINTER TO IdentityDesc;
  IdentityDesc* = RECORD
    next-: Identity;
    name-: Name;
    certFile-, keyFile-: GeminiResponses.Path;
    hash-: ARRAY MaxHash OF CHAR;
    notBefore-, notAfter-: HUGEINT
  END;

  (* A line of a scopes file: an attachment (entry), or any other line,
     kept as it was (raw, which an entry read from the file keeps too
     until it changes). *)
  Line = POINTER TO LineDesc;
  LineDesc = RECORD
    next: Line;
    raw: Chars;
    entry: BOOLEAN;
    name: Name;
    key: ARRAY MaxKey OF CHAR;
    path: GeminiUrls.Text
  END;

  (* Which identity for which URL, kept in a file. *)
  Scopes* = POINTER TO ScopesDesc;
  ScopesDesc* = RECORD
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

PROCEDURE Append(VAR s: ARRAY OF CHAR; t-: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := Length(s); j := 0;
  WHILE (j < LEN(t)) & (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; n: LONGINT);
  VAR d: ARRAY 12 OF CHAR; i: INTEGER; t: ARRAY 2 OF CHAR;
BEGIN
  t[1] := 0X; i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  WHILE i > 0 DO DEC(i); t[0] := d[i]; Append(s, t) END
END AppendInt;

(* ValidName's rule, and ':' too if colon, for a server named by its
   IPv6 address: harmless in a file's name, and never a path. *)
PROCEDURE Named(name-: ARRAY OF CHAR; colon: BOOLEAN): BOOLEAN;
  VAR i, n: LONGINT; c: CHAR;
BEGIN
  n := Length(name);
  IF (n = 0) OR (n > MaxName) OR (name[0] = ".") THEN RETURN FALSE END;
  FOR i := 0 TO n - 1 DO
    c := name[i];
    IF ~((c >= "a") & (c <= "z") OR (c >= "A") & (c <= "Z") OR (c >= "0") & (c <= "9")
        OR (c = ".") OR (c = "_") OR (c = "-") OR colon & (c = ":")) THEN
      RETURN FALSE
    END
  END;
  RETURN TRUE
END Named;

(* Whether name can be an identity's: 1..MaxName of letters, digits,
   ".", "_" and "-", not starting with ".", so neither a path nor a
   hidden file. *)
PROCEDURE ValidName*(name-: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Named(name, FALSE)
END ValidName;

(* Whether cn can be a certificate's common name here: 1..MaxName
   printable ASCII characters, as many as X.509's CN holds (ub-common-name,
   which TlsMake enforces too). *)
PROCEDURE ValidCommonName(cn-: ARRAY OF CHAR): BOOLEAN;
  VAR i, n: LONGINT; c: CHAR;
BEGIN
  n := Length(cn);
  IF (n = 0) OR (n > MaxName) THEN RETURN FALSE END;
  FOR i := 0 TO n - 1 DO
    c := cn[i];
    IF (c < " ") OR (c > "~") THEN
      RETURN FALSE
    END
  END;
  RETURN TRUE
END ValidCommonName;

(* path := dir "/" name ext: FALSE if it won't fit. *)
PROCEDURE Join(dir-, name-, ext-: ARRAY OF CHAR; VAR path: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF Length(dir) + Length(name) + Length(ext) + 1 >= LEN(path) THEN path[0] := 0X; RETURN FALSE END;
  COPY(dir, path); Append(path, "/"); Append(path, name); Append(path, ext);
  RETURN TRUE
END Join;

(* Whether path names something, as far as can be told: not if it or
   a directory on the way is missing, or that is a file (ENOTDIR), so
   Ensure then tries to make the directory, and says it can't. *)
PROCEDURE Exists(VAR path: ARRAY OF CHAR): BOOLEAN;
  VAR fd: LONGINT; err: UnixErrors.Error;
BEGIN
  IF UnixFiles.OpenRead(path, {UnixFiles.nonBlocking}, fd, err) THEN UnixFiles.Close(fd); RETURN TRUE END;
  RETURN (err.code # UnixErrors.ENOENT) & (err.code # UnixErrors.ENOTDIR)
END Exists;

(* The file path, whole, at most max bytes, in buf[0..len-1]: FALSE,
   with why, if it can't be read, or is longer. A missing file is
   FALSE with missing. *)
PROCEDURE ReadFile(VAR path: ARRAY OF CHAR; max: LONGINT; VAR buf: Chars; VAR len: LONGINT;
    VAR missing: BOOLEAN; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR fd, n, i: LONGINT; err: UnixErrors.Error; more: Chars; dir: UnixFiles.Directory;
BEGIN
  len := 0; missing := FALSE; buf := NIL;
  IF ~UnixFiles.OpenRead(path, {UnixFiles.nonBlocking}, fd, err) THEN
    missing := err.code = UnixErrors.ENOENT; COPY(err.text, why); RETURN FALSE
  END;
  (* NetBSD reads a directory as its entries, where the others refuse *)
  IF UnixFiles.OpenDirectory(path, {}, dir, err) THEN
    UnixFiles.CloseDirectory(dir); UnixFiles.Close(fd);
    COPY(path, why); Append(why, " is a directory"); RETURN FALSE
  END;
  NEW(buf, 4096);
  LOOP
    IF len = LEN(buf^) THEN
      IF len >= max THEN
        UnixFiles.Close(fd); COPY(path, why); Append(why, " is too long"); RETURN FALSE
      END;
      NEW(more, 2 * len);
      FOR i := 0 TO len - 1 DO more[i] := buf[i] END;
      buf := more
    END;
    IF ~UnixFiles.Read(fd, buf^, len, LEN(buf^) - len, n, err) THEN
      UnixFiles.Close(fd); COPY(err.text, why); RETURN FALSE
    END;
    IF n = 0 THEN EXIT END;
    INC(len, n)
  END;
  UnixFiles.Close(fd);
  RETURN TRUE
END ReadFile;

(* Identities *)

(* Load, the name Named(name, colon). *)
PROCEDURE Loaded(dir-, name-: ARRAY OF CHAR; colon: BOOLEAN; VAR id: Identity; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR buf: Chars; len: LONGINT; missing: BOOLEAN;
BEGIN
  why[0] := 0X; id := NIL;
  IF ~Named(name, colon) THEN COPY("not a name for an identity", why); RETURN FALSE END;
  NEW(id); id.next := NIL; COPY(name, id.name);
  IF ~Join(dir, name, ".crt", id.certFile) OR ~Join(dir, name, ".key", id.keyFile) THEN
    COPY("the identities' directory's name is too long", why); id := NIL; RETURN FALSE
  END;
  IF ~ReadFile(id.certFile, MaxPem, buf, len, missing, why) THEN
    IF missing THEN COPY("no identity ", why); Append(why, name); Append(why, " in "); Append(why, dir) END;
    id := NIL; RETURN FALSE
  END;
  IF ~TlsCerts.CertHash(buf^, len, id.hash) OR ~TlsCerts.Validity(buf^, len, id.notBefore, id.notAfter) THEN
    COPY(id.certFile, why); Append(why, " isn't a certificate that can be read");
    id := NIL; RETURN FALSE
  END;
  IF ~Exists(id.keyFile) THEN
    COPY(id.certFile, why); Append(why, " has no key beside it"); id := NIL; RETURN FALSE
  END;
  RETURN TRUE
END Loaded;

(* The identity name in dir, read from its files: FALSE, with why, if
   it isn't there, or its certificate can't be read. *)
PROCEDURE Load*(dir-, name-: ARRAY OF CHAR; VAR id: Identity; VAR why: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Loaded(dir, name, FALSE, id, why)
END Load;

(* Makes name's pair in dir, which exists: a key, unless one is there
   already, then a certificate for it with common name cn and subject
   alternative names names, valid for days days from now; and loads it
   into id. *)
PROCEDURE MakePair(dir-, name-, cn-, names-: ARRAY OF CHAR; days: LONGINT; VAR id: Identity;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR crt, key: GeminiResponses.Path; t: Instants.Instant; now: HUGEINT; error: Tls.String;
BEGIN
  IF ~Join(dir, name, ".crt", crt) OR ~Join(dir, name, ".key", key) THEN
    COPY("the directory's name is too long", why); RETURN FALSE
  END;
  IF ~Exists(key) & ~TlsMake.EcKey(key, error) THEN COPY(error^, why); RETURN FALSE END;
  Clocks.Now(t); now := Instants.UnixSeconds(t);
  IF ~TlsMake.SelfSigned(key, crt, cn, names, FALSE, now, now + days * 86400, error) THEN
    COPY(error^, why); RETURN FALSE
  END;
  RETURN Loaded(dir, name, TRUE, id, why)
END MakePair;

(* Makes the identity name in dir, which must exist, with commonName as
   its certificate's (name if ""), valid for days days from now (1..
   MaxDays; DefaultDays is long, as an identity should be): id, or
   FALSE, with why, if the name or common name can't be one, the
   identity exists already, or the pair can't be made. *)
PROCEDURE Make*(dir-, name-, commonName-: ARRAY OF CHAR; days: LONGINT; VAR id: Identity;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR crt: GeminiResponses.Path; cn: Name;
BEGIN
  why[0] := 0X; id := NIL;
  IF ~ValidName(name) THEN
    COPY("an identity's name is letters, digits, '.', '_' and '-', not starting with '.'", why);
    RETURN FALSE
  END;
  IF commonName[0] = 0X THEN COPY(name, cn)
  ELSIF ValidCommonName(commonName) THEN COPY(commonName, cn)
  ELSE COPY("a common name is 1 to 64 printable ASCII characters", why); RETURN FALSE
  END;
  IF (days < 1) OR (days > MaxDays) THEN COPY("an identity's lifetime is 1 to 36500 days", why); RETURN FALSE END;
  IF ~Join(dir, name, ".key", crt) THEN
    COPY("the identities' directory's name is too long", why); RETURN FALSE
  END;
  IF Join(dir, name, ".crt", crt) & Exists(crt) THEN
    COPY("an identity named ", why); Append(why, name); Append(why, " exists already"); RETURN FALSE
  END;
  RETURN MakePair(dir, name, cn, "", days, id, why)
END Make;

(* The server certificate name in dir, in id: the pair made before, or,
   the first time, a new one, with name as its common name and names
   (name if "") as its subject alternative names, separated by spaces,
   which libtls matches SNI against, valid for days days (1..MaxDays)
   from when it is made. The name is ValidName's, but may hold ':', as
   an IPv6 address does. dir is made if it isn't there, its owner's
   only (700 octal); one that is is left as it is, since whoever made
   it chose its mode. A .crt without its .key is refused, never
   replaced. FALSE, with why, if the pair can't be had. *)
PROCEDURE Ensure*(dir-, name-, names-: ARRAY OF CHAR; days: LONGINT; VAR id: Identity;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR d, crt: GeminiResponses.Path; err: UnixErrors.Error;
BEGIN
  why[0] := 0X; id := NIL;
  IF ~Named(name, TRUE) THEN
    COPY("a certificate's name is 1 to 64 letters, digits, '.', '_', '-' and ':', not starting with '.'", why);
    RETURN FALSE
  END;
  IF (days < 1) OR (days > MaxDays) THEN COPY("a certificate's lifetime is 1 to 36500 days", why); RETURN FALSE END;
  IF dir[0] = 0X THEN COPY("no directory for certificates", why); RETURN FALSE END;
  IF (Length(dir) >= LEN(d)) OR ~Join(dir, name, ".key", crt) OR ~Join(dir, name, ".crt", crt) THEN
    COPY("the certificate directory's name is too long", why); RETURN FALSE
  END;
  IF Exists(crt) THEN RETURN Loaded(dir, name, TRUE, id, why) END;
  COPY(dir, d);
  IF ~Exists(d) THEN
    (* MakeDirectory gives the umask's mode, and makes any parents with
       it too: only dir itself is made private. *)
    IF ~Directories.MakeDirectory(d) THEN
      COPY("can't make the certificate directory ", why); Append(why, dir); RETURN FALSE
    END;
    IF ~UnixFiles.ChangeMode(d, DirMode, err) THEN COPY(err.text, why); RETURN FALSE END
  END;
  IF names[0] = 0X THEN RETURN MakePair(dir, name, name, name, days, id, why) END;
  RETURN MakePair(dir, name, name, names, days, id, why)
END Ensure;

(* The identities in dir, by name, in first (NIL for none): FALSE, with
   why, if dir can't be read. A missing dir has none. A .crt that can't
   be read, or has no .key, is passed over. *)
PROCEDURE List*(dir-: ARRAY OF CHAR; VAR first: Identity; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR d: UnixFiles.Directory; err: UnixErrors.Error; file: ARRAY UnixFiles.NameLen OF CHAR;
    name: Name; n, i: LONGINT; id, p, q: Identity; msg: ARRAY 256 OF CHAR;
BEGIN
  why[0] := 0X; first := NIL;
  IF ~UnixFiles.OpenDirectory(dir, {}, d, err) THEN
    IF err.code = UnixErrors.ENOENT THEN RETURN TRUE END;
    COPY(err.text, why); RETURN FALSE
  END;
  LOOP
    IF ~UnixFiles.NextName(d, file, err) THEN
      IF err.code # UnixErrors.ENAMETOOLONG THEN
        UnixFiles.CloseDirectory(d); COPY(err.text, why); first := NIL; RETURN FALSE
      END
    ELSIF file = "" THEN EXIT
    ELSE
      n := Length(file);
      IF (n > 4) & (n - 4 <= MaxName) & (file[n - 4] = ".") & (file[n - 3] = "c")
          & (file[n - 2] = "r") & (file[n - 1] = "t") THEN
        FOR i := 0 TO n - 5 DO name[i] := file[i] END;
        name[n - 4] := 0X;
        IF ValidName(name) & Load(dir, name, id, msg) THEN
          (* in order of name *)
          p := NIL; q := first;
          WHILE (q # NIL) & (q.name < id.name) DO p := q; q := q.next END;
          id.next := q;
          IF p = NIL THEN first := id ELSE p.next := id END
        END
      END
    END
  END;
  UnixFiles.CloseDirectory(d);
  RETURN TRUE
END List;

(* Puts id in opts, to be presented by the fetches made with them. *)
PROCEDURE Use*(id: Identity; VAR opts: GeminiResponses.Options);
BEGIN
  COPY(id.certFile, opts.certFile); COPY(id.keyFile, opts.keyFile)
END Use;

(* Scopes *)

(* url's host and port as the file has them, and its path, "/" for
   none: FALSE if it has no host, or the host won't go to ASCII. *)
PROCEDURE Where(VAR url: GeminiUrls.URL; VAR key, path: ARRAY OF CHAR): BOOLEAN;
  VAR host: ARRAY 256 OF CHAR; why: ARRAY 128 OF CHAR; i: LONGINT; v6: BOOLEAN;
BEGIN
  key[0] := 0X; path[0] := 0X;
  IF (url.host = "") OR ~GeminiPunycode.ToAscii(url.host, host, why) THEN RETURN FALSE END;
  v6 := FALSE; i := 0;
  WHILE host[i] # 0X DO IF host[i] = ":" THEN v6 := TRUE END; INC(i) END;
  IF v6 THEN Append(key, "[") END;
  Append(key, host);
  IF v6 THEN Append(key, "]") END;
  Append(key, ":"); AppendInt(key, GeminiUrls.Port(url));
  IF url.path = "" THEN COPY("/", path) ELSE COPY(url.path, path) END;
  RETURN TRUE
END Where;

(* Whether path is prefix or below it: equal, or prefix then a "/" (or
   prefix ending in one). *)
PROCEDURE Under(VAR path, prefix: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE prefix[i] # 0X DO
    IF path[i] # prefix[i] THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN (path[i] = 0X) OR (path[i] = "/") OR (i > 0) & (prefix[i - 1] = "/")
END Under;

PROCEDURE Blanks(VAR s: ARRAY OF CHAR; VAR i: LONGINT);
BEGIN WHILE (s[i] = " ") OR (s[i] = 9X) DO INC(i) END
END Blanks;

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

(* l's raw text read as an attachment: l.entry. *)
PROCEDURE ReadEntry(l: Line);
  VAR i: LONGINT;
BEGIN
  l.entry := FALSE; i := 0;
  Blanks(l.raw^, i);
  IF ~Field(l.raw^, i, l.name) OR ~ValidName(l.name) THEN RETURN END; Blanks(l.raw^, i);
  IF ~Field(l.raw^, i, l.key) THEN RETURN END; Blanks(l.raw^, i);
  IF ~Field(l.raw^, i, l.path) OR (l.path[0] # "/") THEN RETURN END; Blanks(l.raw^, i);
  l.entry := l.raw[i] = 0X
END ReadEntry;

PROCEDURE AddLine(s: Scopes; l: Line);
BEGIN
  l.next := NIL;
  IF s.first = NIL THEN s.first := l ELSE s.last.next := l END;
  s.last := l
END AddLine;

(* The scopes kept in the file path, read now: none if it doesn't exist
   yet. FALSE, with why, s NIL, if it can't be read. *)
PROCEDURE OpenScopes*(path-: ARRAY OF CHAR; VAR s: Scopes; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR buf: Chars; len, i, j, k, e: LONGINT; missing: BOOLEAN; l: Line;
BEGIN
  why[0] := 0X; s := NIL;
  IF (Length(path) = 0) OR (Length(path) = LEN(path)) THEN
    COPY("the scopes file has no name", why); RETURN FALSE
  END;
  NEW(s); s.first := NIL; s.last := NIL;
  NEW(s.path, Length(path) + 1); COPY(path, s.path^);
  IF ~ReadFile(s.path^, MaxFile, buf, len, missing, why) THEN
    IF missing THEN why[0] := 0X; RETURN TRUE END;
    s := NIL; RETURN FALSE
  END;
  i := 0;
  WHILE i < len DO
    j := i; WHILE (j < len) & (buf[j] # 0AX) DO INC(j) END;
    e := j; IF (e > i) & (buf[e - 1] = 0DX) THEN DEC(e) END;
    NEW(l); NEW(l.raw, e - i + 1);
    FOR k := i TO e - 1 DO
      IF buf[k] = 0X THEN l.raw[k - i] := " " ELSE l.raw[k - i] := buf[k] END
    END;
    l.raw[e - i] := 0X; l.name := ""; l.key := ""; l.path := "";
    ReadEntry(l); AddLine(s, l);
    i := j + 1
  END;
  RETURN TRUE
END OpenScopes;

PROCEDURE Put(VAR buf: Chars; VAR len: LONGINT; t-: ARRAY OF CHAR);
  VAR i, n: LONGINT; more: Chars;
BEGIN
  n := Length(t);
  IF len + n > LEN(buf^) THEN
    NEW(more, 2 * (len + n));
    FOR i := 0 TO len - 1 DO more[i] := buf[i] END;
    buf := more
  END;
  FOR i := 0 TO n - 1 DO buf[len + i] := t[i] END;
  INC(len, n)
END Put;

(* Writes s to its file, whole, through a temporary name: FALSE, with
   why, the file as it was, if it can't be. *)
PROCEDURE Save(s: Scopes; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR buf, temp: Chars; len, fd, pos, n, tries, base: LONGINT; l: Line; err: UnixErrors.Error;
    lf: ARRAY 2 OF CHAR; ok: BOOLEAN;
BEGIN
  NEW(buf, 4096); len := 0; l := s.first; lf[0] := 0AX; lf[1] := 0X;
  WHILE l # NIL DO
    IF l.raw # NIL THEN Put(buf, len, l.raw^)
    ELSE Put(buf, len, l.name); Put(buf, len, " "); Put(buf, len, l.key); Put(buf, len, " "); Put(buf, len, l.path)
    END;
    Put(buf, len, lf);
    l := l.next
  END;
  NEW(temp, LEN(s.path^) + 40); base := Length(s.path^); tries := 0;
  LOOP
    COPY(s.path^, temp^);
    Append(temp^, "."); AppendInt(temp^, Platform.PID); Append(temp^, ".");
    AppendInt(temp^, tries); Append(temp^, ".tmp");
    IF UnixFiles.OpenWrite(temp^, {UnixFiles.create, UnixFiles.exclusive}, Mode, fd, err) THEN EXIT END;
    INC(tries);
    IF (err.code # UnixErrors.EEXIST) OR (tries = MaxTries) THEN COPY(err.text, why); RETURN FALSE END
  END;
  pos := 0; ok := TRUE;
  WHILE ok & (pos < len) DO ok := UnixFiles.Write(fd, buf^, pos, len - pos, n, err); INC(pos, n) END;
  ok := ok & UnixFiles.Sync(fd, err);
  UnixFiles.Close(fd);
  IF ok THEN ok := UnixFiles.Rename(temp^, s.path^, err) END;
  IF ~ok THEN COPY(err.text, why); IF UnixFiles.Remove(temp^, err) THEN END END;
  RETURN ok
END Save;

(* Attaches the identity name to url's host, port and path, so it is
   offered there and below (an attachment there before is replaced):
   FALSE, with why, if the name can't be one, the URL has no host, or
   the file can't be written, s then as it was. *)
PROCEDURE (s: Scopes) Attach*(name-: ARRAY OF CHAR; VAR url: GeminiUrls.URL;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR key: ARRAY MaxKey OF CHAR; path: GeminiUrls.Text; l, last: Line; raw: Chars; old: Name;
BEGIN
  why[0] := 0X;
  IF ~ValidName(name) THEN COPY("not a name for an identity", why); RETURN FALSE END;
  IF ~Where(url, key, path) THEN COPY("the URL has no host that can be attached to", why); RETURN FALSE END;
  l := s.first;
  WHILE (l # NIL) & ~(l.entry & (l.key = key) & (l.path = path)) DO l := l.next END;
  IF l = NIL THEN
    NEW(l); l.raw := NIL; l.entry := TRUE; COPY(name, l.name); COPY(key, l.key); COPY(path, l.path);
    last := s.last; AddLine(s, l);
    IF Save(s, why) THEN RETURN TRUE END;
    s.last := last; IF last = NIL THEN s.first := NIL ELSE last.next := NIL END;
    RETURN FALSE
  END;
  raw := l.raw; COPY(l.name, old);
  l.raw := NIL; COPY(name, l.name);
  IF Save(s, why) THEN RETURN TRUE END;
  l.raw := raw; COPY(old, l.name);
  RETURN FALSE
END Attach;

(* Detaches whatever identity is attached to url's host, port and path
   exactly: TRUE if none was, or it is detached; FALSE, with why, if
   the file can't be written. *)
PROCEDURE (s: Scopes) Detach*(VAR url: GeminiUrls.URL; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR key: ARRAY MaxKey OF CHAR; path: GeminiUrls.Text; l, p: Line;
BEGIN
  why[0] := 0X;
  IF ~Where(url, key, path) THEN RETURN TRUE END;
  p := NIL; l := s.first;
  WHILE (l # NIL) & ~(l.entry & (l.key = key) & (l.path = path)) DO p := l; l := l.next END;
  IF l = NIL THEN RETURN TRUE END;
  IF p = NIL THEN s.first := l.next ELSE p.next := l.next END;
  IF s.last = l THEN s.last := p END;
  IF Save(s, why) THEN RETURN TRUE END;
  (* put back *)
  IF p = NIL THEN s.first := l ELSE p.next := l END;
  IF l.next = NIL THEN s.last := l END;
  RETURN FALSE
END Detach;

(* The attachment that covers url: the one to its host and port at the
   longest path that url's is, or is below; NIL if none. *)
PROCEDURE Best(s: Scopes; VAR url: GeminiUrls.URL): Line;
  VAR key: ARRAY MaxKey OF CHAR; path: GeminiUrls.Text; l, best: Line;
BEGIN
  IF ~Where(url, key, path) THEN RETURN NIL END;
  best := NIL; l := s.first;
  WHILE l # NIL DO
    IF l.entry & (l.key = key) & Under(path, l.path)
        & ((best = NIL) OR (Length(l.path) > Length(best.path))) THEN
      best := l
    END;
    l := l.next
  END;
  RETURN best
END Best;

(* The name of the identity to offer for url, in name: the one attached
   to its host and port and the longest path that it is, or is below;
   FALSE, name "", if there is none. *)
PROCEDURE (s: Scopes) For*(VAR url: GeminiUrls.URL; VAR name: ARRAY OF CHAR): BOOLEAN;
  VAR best: Line;
BEGIN
  name[0] := 0X;
  best := Best(s, url);
  IF best = NIL THEN RETURN FALSE END;
  COPY(best.name, name);
  RETURN TRUE
END For;

(* As For, and the path the identity is attached at, in path, which url's
   is or is below: for a program to detach it from a page beneath (with
   url's host and port and that path), or to say where it applies.
   FALSE, both "", if none covers url. *)
PROCEDURE (s: Scopes) Covering*(VAR url: GeminiUrls.URL; VAR name, path: ARRAY OF CHAR): BOOLEAN;
  VAR best: Line;
BEGIN
  name[0] := 0X; path[0] := 0X;
  best := Best(s, url);
  IF best = NIL THEN RETURN FALSE END;
  COPY(best.name, name); COPY(best.path, path);
  RETURN TRUE
END Covering;

END GeminiIdentities.
