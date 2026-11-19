MODULE TestReadme; (* README.md's programs, run as it shows them *)

(* Builds nothing: make builds README.md's programs, examples/readme,
   into build/readme, and checks that README.md shows them as they are
   (doc/mkreadme.awk). This runs each as README.md does, in
   build/test-TestReadme, and checks that it says what README.md says
   it does: the same output where nothing varies (Links, Outline, Index,
   Header), and where the port and keys do (Hello, Get, Both, Identity),
   the same lines with this run's port and hashes. Hello is started on
   a port the kernel chooses, with the tests' server-ec pair, then with
   other-ec on the same port, so Get sees a key that has changed;
   Identity is run against GeminiServe, whose page shows the client
   certificate's hash, and needs openssl, so it skips without. *)

IMPORT Out, Check, Child;

CONST
  Dir = "../build/test-TestReadme";
  LF = 0AX;

TYPE
  Text = ARRAY 8192 OF CHAR;

VAR
  server: Child.Child;
  portText: ARRAY 8 OF CHAR;

PROCEDURE Length(s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END; RETURN n
END Length;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := Length(s); j := 0;
  WHILE (i < LEN(s) - 1) & (j < LEN(t)) & (t[j] # 0X) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

(* s with each "|" a line feed, and P the port: the output README.md
   shows, written on one line. *)
PROCEDURE Expect(s: ARRAY OF CHAR; VAR e: ARRAY OF CHAR);
  VAR i: LONGINT; c: ARRAY 2 OF CHAR;
BEGIN
  e[0] := 0X; i := 0; c[1] := 0X;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF s[i] = "|" THEN c[0] := LF; Append(e, c)
    ELSIF s[i] = "P" THEN Append(e, portText)
    ELSE c[0] := s[i]; Append(e, c)
    END;
    INC(i)
  END
END Expect;

(* Runs cmd in Dir, P in it the port: its exit status, and its output
   in out. *)
PROCEDURE Shell(cmd: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): INTEGER;
  VAR c: Child.Child; n: LONGINT; full, line: Text;
BEGIN
  out[0] := 0X;
  full := "cd "; Append(full, Dir); Append(full, " && "); Expect(cmd, line); Append(full, line);
  IF ~Child.Spawn(full, "", 0, c) THEN RETURN -1 END;
  RETURN Child.Wait(c, out, n)
END Shell;

(* Runs cmd in Dir, and checks that it exits 0 and says what README.md
   shows (as for Expect). *)
PROCEDURE Says(cmd, shown, label: ARRAY OF CHAR);
  VAR out, e: Text; status: INTEGER;
BEGIN
  Expect(shown, e); status := Shell(cmd, out);
  Check.Check((status = 0) & (out = e), label);
  IF (status # 0) OR (out # e) THEN
    Out.String("  exit "); Out.Int(status, 0); Out.String(", got:"); Out.Ln; Out.String(out);
    Out.String("  expected:"); Out.Ln; Out.String(e)
  END
END Says;

(* Starts a server, cmd in Dir, and reads the port it says; FALSE, with
   the server ended, if it doesn't. *)
PROCEDURE Start(cmd: ARRAY OF CHAR): BOOLEAN;
  VAR full, got: Text; line: ARRAY 64 OF CHAR; i, n: LONGINT;
BEGIN
  full := "cd "; Append(full, Dir); Append(full, " && exec "); Append(full, cmd);
  IF ~Child.Spawn(full, "", 0, server) OR ~Child.ReadLine(server, line, 15000)
    OR (line[0] # "p") THEN
    Child.Kill(server); IF Child.Wait(server, got, n) # 0 THEN END;
    Out.String("  "); Out.String(line); Out.String(got); Out.Ln;
    RETURN FALSE
  END;
  i := 5;
  WHILE (line[i] >= "0") & (line[i] <= "9") DO portText[i - 5] := line[i]; INC(i) END;
  portText[i - 5] := 0X;
  RETURN TRUE
END Start;

(* Stops the server by SIGTERM: whether it exited 0. *)
PROCEDURE Stop(): BOOLEAN;
  VAR got: Text; n: LONGINT;
BEGIN
  Child.Kill(server); RETURN Child.Wait(server, got, n) = 0
END Stop;

(* The text in s from position i to the end of its line. *)
PROCEDURE LineAt(s: ARRAY OF CHAR; i: LONGINT; VAR line: ARRAY OF CHAR);
  VAR j: LONGINT;
BEGIN
  j := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) & (s[i] # LF) & (j < LEN(line) - 1) DO
    line[j] := s[i]; INC(i); INC(j)
  END;
  line[j] := 0X
END LineAt;

PROCEDURE Plain;
BEGIN
  Says("../readme/Links 'gemini://Bücher.example/a/b/c.gmi?q#f' ../x.gmi //other.example:1966/ gemini://u@h/",
    "gemini://xn--bcher-kva.example/a/x.gmi (host bücher.example)|gemini://other.example:1966/ (host other.example)|gemini://u@h/: userinfo in the URL|",
    "Links: as README.md shows");
  Says("printf '%s\n' '# Title' 'some text' '=> gemini://example.com/ Example' '```' '# not a heading' '```' '## Sub' '=> rel.gmi' > t.gmi && ../readme/Outline t.gmi",
    "1 Title|  => gemini://example.com/|2 Sub|  => rel.gmi|",
    "Outline: as README.md shows");
  Says("../readme/Index 'a b?.gmi' c:d.gmi notes.gmi && cat index.gmi",
    "# Index|=> a%20b%3F.gmi a b?.gmi|=> c%3Ad.gmi c:d.gmi|=> notes.gmi notes.gmi|",
    "Index: as README.md shows");
  Says("../readme/Header '20 text/plain;charset=ISO-8859-1'",
    "20: success, text/plain in iso-8859-1|", "Header: 20 with a type and charset");
  Says("../readme/Header 20", "20: success, text/gemini in utf-8, gemtext|", "  ... 20 alone");
  Says("../readme/Header '14 x'", "14: input, x|", "  ... 14");
  Says("../readme/Header '7 bad'", "no status|", "  ... a status of one digit")
END Plain;

(* Hello, and Get and Both against it. *)
PROCEDURE Served;
  VAR out, e, hash, first: Text; port: ARRAY 8 OF CHAR;
BEGIN
  IF Shell("cp ../certs/server-ec.crt server.crt && cp ../certs/server-ec.key server.key", out) # 0 THEN
    Check.Check(FALSE, "the server's pair copied"); Out.String(out); RETURN
  END;
  IF ~Start("../readme/Hello 0") THEN Check.Check(FALSE, "Hello starts and says its port"); RETURN END;
  Check.Check(TRUE, "Hello starts and says its port");

  Check.Check(Shell("../readme/Get gemini://localhost:P/", out) = 0, "Get: the first time");
  (* "first use: SHA256:<64 hex digits>" *)
  LineAt(out, Length("20 text/gemini") + 1, first);
  LineAt(first, Length("first use: SHA256:"), hash);
  Expect("20 text/gemini|first use: SHA256:", e); Append(e, hash);
  Append(e, LF); Append(e, "# Hello"); Append(e, LF); Append(e, "Served by GeminiServer."); Append(e, LF);
  Check.Check((Length(hash) = 64) & (out = e), "  ... trusts on first use, then shows the page");
  IF out # e THEN Out.String(out) END;
  Expect("localhost:P spki-sha256 ", e); Append(e, hash);
  Check.Check((Shell("cat known-hosts", out) = 0) & (out[0] # 0X) & Check.Contains(out, e),
    "  ... known-hosts has the key's hash for localhost and the port");
  Says("../readme/Get gemini://localhost:P/", "20 text/gemini|# Hello|Served by GeminiServer.|",
    "Get: the second time, nothing about trust");
  Says("../readme/Both gemini://localhost:P/ gemini://localhost:P/x",
    "gemini://localhost:P/: 20 text/gemini|gemini://localhost:P/x: 51 not found|",
    "Both: as README.md shows");
  Check.Check(Stop(), "Hello exits 0 on SIGTERM");

  COPY(portText, port);
  IF Shell("cp ../certs/other-ec.crt server.crt && cp ../certs/other-ec.key server.key", out) # 0 THEN
    Check.Check(FALSE, "another pair copied"); Out.String(out); RETURN
  END;
  e := "../readme/Hello "; Append(e, port);
  IF ~Start(e) OR (portText # port) THEN
    Check.Check(FALSE, "Hello starts again, with another key, on that port");
    IF Stop() THEN END;
    RETURN
  END;
  Says("../readme/Get gemini://localhost:P/",
    "the server's key isn't the one known for localhost:P, whose certificate hasn't expired|",
    "Get: refused once the server's key has changed");
  IF Stop() THEN END
END Served;

(* Identity against GeminiServe, in Dir, so the certificates are a
   directory further up than Certs. *)
PROCEDURE Identified;
  VAR out, page, hash: Text; i, j: LONGINT;
BEGIN
  IF Shell("command -v openssl", out) # 0 THEN Check.Skip("Identity: no openssl"); RETURN END;
  IF ~Start("../GeminiServe -port 0 -cert ../certs/self-ec.crt -key ../certs/self-ec.key") THEN
    Check.Check(FALSE, "GeminiServe starts and says its port"); RETURN
  END;
  Check.Check(Shell("mkdir ids && ../readme/Identity gemini://localhost:P/", out) = 0,
    "Identity: an identity made and used");
  LineAt(out, Length("as me, "), hash);
  Check.Check((out[0] = "a") & (Length(hash) = 7 + 64) & Check.Contains(hash, "SHA256:"),
    "  ... says it is me, and its hash");
  (* the page, after that line, shows the hash the server saw *)
  i := 0; WHILE (out[i] # 0X) & (out[i] # LF) DO INC(i) END;
  j := 0; IF out[i] = LF THEN INC(i) END;
  WHILE out[i] # 0X DO page[j] := out[i]; INC(i); INC(j) END;
  page[j] := 0X;
  Check.Check(Check.Contains(page, "# GeminiServe") & Check.Contains(page, hash),
    "  ... the server saw that hash");
  IF ~Check.Contains(page, hash) THEN Out.String(out) END;
  Says("cat scopes", "me localhost:P /|", "  ... scopes attach it to the host, port and /");
  IF Stop() THEN END
END Identified;

PROCEDURE Setup(): BOOLEAN;
  VAR c: Child.Child; out: Text; n: LONGINT;
BEGIN
  IF ~Child.Spawn("rm -rf ../build/test-TestReadme && mkdir ../build/test-TestReadme", "", 0, c)
    OR (Child.Wait(c, out, n) # 0) THEN
    Check.Check(FALSE, "the test directory made"); Out.String(out); RETURN FALSE
  END;
  RETURN TRUE
END Setup;

PROCEDURE Teardown;
  VAR c: Child.Child; out: Text; n: LONGINT;
BEGIN
  IF Child.Spawn("rm -rf ../build/test-TestReadme", "", 0, c) & (Child.Wait(c, out, n) = 0) THEN END
END Teardown;

BEGIN
  IF Setup() THEN Plain; Served; Identified; Teardown END;
  Check.Summary
END TestReadme.
