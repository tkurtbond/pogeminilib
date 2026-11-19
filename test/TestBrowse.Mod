MODULE TestBrowse; (* examples/GeminiBrowse, against test/TestServer *)

(* The example browser run as a child, its commands on its standard
   input, which isn't a terminal, so it echoes each after its prompt and
   the transcript reads as a session would. Its known hosts file and
   identities under build/test-TestBrowse, made afresh and removed. *)

IMPORT Check, Child, Server, ClientCases, GeminiResponses;

CONST
  LF = 0AX;

VAR
  port: INTEGER;
  input: ARRAY 4096 OF CHAR;    (* the commands for the next Browse *)
  inLen: LONGINT;
  out: GeminiResponses.Chars;   (* what it wrote *)
  len: LONGINT;

(* Adds line to the commands. *)
PROCEDURE Cmd(line: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE line[i] # 0X DO input[inLen] := line[i]; INC(inLen); INC(i) END;
  input[inLen] := LF; INC(inLen)
END Cmd;

(* Runs GeminiBrowse with args, at path on the test server if it isn't
   "", with the commands given since the last: its exit status, its
   output in out, len bytes. *)
PROCEDURE Browse(args, path: ARRAY OF CHAR): INTEGER;
  VAR c: Child.Child; cmd: ARRAY 1024 OF CHAR; url: ARRAY 256 OF CHAR; n: LONGINT;
BEGIN
  COPY("exec ../build/GeminiBrowse ", cmd); ClientCases.Append(cmd, args);
  IF path # "" THEN
    ClientCases.Url("localhost", port, path, url);
    ClientCases.Append(cmd, " '"); ClientCases.Append(cmd, url); ClientCases.Append(cmd, "'")
  END;
  n := inLen; inLen := 0; len := 0;
  IF ~Child.Spawn(cmd, input, n, c) THEN RETURN -1 END;
  RETURN Child.Wait(c, out^, len)
END Browse;

(* Whether the output has a, a line's end, then b. *)
PROCEDURE HasLines(a, b: ARRAY OF CHAR): BOOLEAN;
  VAR s: ARRAY 256 OF CHAR; i: LONGINT;
BEGIN
  COPY(a, s); i := 0; WHILE s[i] # 0X DO INC(i) END;
  s[i] := LF; s[i + 1] := 0X; ClientCases.Append(s, b);
  RETURN ClientCases.Has(out^, len, s)
END HasLines;

PROCEDURE Has(part: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN ClientCases.Has(out^, len, part)
END Has;

PROCEDURE Shell(cmd: ARRAY OF CHAR): BOOLEAN;
  VAR c: Child.Child; o: ARRAY 4096 OF CHAR; n: LONGINT;
BEGIN RETURN Child.Spawn(cmd, "", 0, c) & (Child.Wait(c, o, n) = 0)
END Shell;

PROCEDURE Pages;
  VAR st: INTEGER; s, url: ARRAY 256 OF CHAR;
BEGIN
  Cmd("l"); Cmd("1"); Cmd("hello"); Cmd("b"); Cmd("2"); Cmd("r");
  Cmd("g /secret"); Cmd("shh");
  s := "g /r/to?"; ClientCases.Url("127.0.0.1", port, "/x", url); ClientCases.Append(s, url);
  Cmd(s); Cmd("n");
  Cmd("g /latin1"); Cmd("g /bin"); Cmd("save ../build/test-TestBrowse/bin"); Cmd("save ../build/test-TestBrowse/bin");
  Cmd("g /status/51"); Cmd("99"); Cmd("zz"); Cmd("q");
  st := Browse("-width 40 -known-hosts ../build/test-TestBrowse/known", "/page");
  Check.Check(st = 0, "GeminiBrowse: a session, exit 0");
  Check.Check(Has("trusted on first use: SHA256:"), "... the server trusted on first use, and said so");
  Check.Check(Has("# A page") & HasLines("wrapped at", "a narrow width") & Has("## Below"),
    "... a page shown, its headings marked, its text wrapped at -width");
  Check.Check(Has("  preformatted,   kept as it is, however long it goes on for, past any width"),
    "... preformatted text as it came, not wrapped");
  Check.Check(HasLines("[1] Ask something", "[2] /r/chain/1") & Has("(https) [3] Elsewhere")
    & HasLines("> a quote", "  preformatted") & Has("* an item") & ~Has(">  a quote"),
    "... links numbered, another scheme's marked, a link with no URL left out, items and quotes");
  s := "[4] gemini://localhost:"; ClientCases.AppendInt(s, port); ClientCases.Append(s, "/plain");
  Check.Check(Has(s), "... l: where each link goes, resolved");
  Check.Check(HasLines("ask?", "> hello") & Has("answer hello"), "... a 10: asked, and the answer sent");
  Check.Check(HasLines("gemini> b", "# A page"), "... b: back to the page");
  Check.Check(HasLines("gemini> 2", "chain end") & HasLines("gemini> r", "chain end"),
    "... a link followed, through a redirect; r reloads");
  Check.Check(HasLines("secret?", "(not shown) > ") & Has("answer shh") & ~Has("> shh"),
    "... an 11: asked, the answer sent, not echoed");
  Check.Check(Has("redirected to another host: gemini://127.0.0.1:") & Has("follow it? (y/n) n")
    & Has("failed: a redirect to another host, refused"), "... a redirect to another host asked about, and refused");
  Check.Check(Has("(text in iso-8859-1, not shown"), "... text not in UTF-8 not shown");
  Check.Check(Has("(application/octet-stream, 5 bytes") & Has("saved 5 bytes in")
    & Has("File exists") & Shell("printf abcde | cmp -s - ../build/test-TestBrowse/bin"),
    "... another type's size given, the body saved, not over a file there");
  Check.Check(Has("51 not found: status 51"), "... a failure status shown");
  Check.Check(Has("no such link") & Has("not a command"), "... a link not there, and a bad command")
END Pages;

PROCEDURE Trust;
  VAR st: INTEGER; cmd: ARRAY 512 OF CHAR;
BEGIN
  cmd := "printf 'localhost:%d spki-sha256 1111111111111111111111111111111111111111111111111111111111111111 9999999999\n' ";
  ClientCases.AppendInt(cmd, port); ClientCases.Append(cmd, " > ../build/test-TestBrowse/known");
  Check.Check(Shell(cmd), "a known hosts file with another key");
  Cmd("trust"); Cmd("trust"); Cmd("q");
  st := Browse("-known-hosts ../build/test-TestBrowse/known", "/");
  Check.Check((st = 0) & Has("failed: the server's key isn't the one known for localhost:")
    & HasLines("gemini> trust", "trusted: SHA256:") & Has("cert -") & Has("no changed key to trust"),
    "GeminiBrowse: a changed key refused, trust trusts it, and the page shown");
  Cmd("q");
  st := Browse("-known-hosts ../build/test-TestBrowse/known", "/");
  Check.Check((st = 0) & Has("cert -") & ~Has("trusted") & ~Has("failed"),
    "GeminiBrowse: ... then known, kept in the file")
END Trust;

PROCEDURE Identities;
  VAR st: INTEGER;
BEGIN
  Check.Check(Shell("mkdir ../build/test-TestBrowse/ids"), "an identities directory");
  Cmd("id"); Cmd("id new me"); Cmd("id new me"); Cmd("id use me"); Cmd("id"); Cmd("g /");
  Cmd("g /private"); Cmd("id off"); Cmd("id off"); Cmd("q");
  st := Browse("-identities ../build/test-TestBrowse/ids", "/private");
  Check.Check((st = 0) & Has("client certificate required: who are you?"), "GeminiBrowse: a 60 shown");
  Check.Check(Has("no identities yet") & Has("made me SHA256:") & Has("an identity named me exists already"),
    "... id lists none; id new makes one, not over another");
  Check.Check(HasLines("offered here and below: me", "hello SHA256:")
    & Has("(offered here)"), "... id use offers it, and reloads; id says where");
  Check.Check(HasLines("gemini> g /", "url gemini") & Has("cert -"), "... not offered above where it's used");
  Check.Check(Has("no longer offered: me, attached at /private")
    & Has("no identity is offered here"), "... id off stops offering it");
  Cmd("g /private"); Cmd("q");
  st := Browse("-identities ../build/test-TestBrowse/ids", "/private");
  Check.Check((st = 0) & (Has("who are you?")), "GeminiBrowse: ... and it stays off")
END Identities;

PROCEDURE Usage;
  VAR st: INTEGER;
BEGIN
  st := Browse("-x 2>&1", "");
  Check.Check((st = 2) & Has("usage: GeminiBrowse"), "GeminiBrowse: bad usage, exit 2");
  st := Browse("-identities ../build/test-TestBrowse/none", "");
  Check.Check((st = 1) & Has("No such file"), "GeminiBrowse: an identities directory not there, exit 1");
  st := Browse("", "");
  Check.Check((st = 0) & Has("gemini> "), "GeminiBrowse: no URL, end of input at once, exit 0")
END Usage;

BEGIN
  NEW(out, 65536); inLen := 0;
  port := Server.Start();
  IF port > 0 THEN
    IF Shell("rm -rf ../build/test-TestBrowse && mkdir ../build/test-TestBrowse") THEN
      Pages; Trust; Identities; Usage;
      IF Shell("rm -rf ../build/test-TestBrowse") THEN END
    ELSE Check.Check(FALSE, "making build/test-TestBrowse")
    END;
    Server.Stop
  END;
  Check.Summary
END TestBrowse.
