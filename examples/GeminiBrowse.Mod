MODULE GeminiBrowse; (* a line-mode Gemini browser: the modules together *)

(* Usage: GeminiBrowse [-known-hosts file] [-identities dir] [-width n] [url]

   Reads commands, a line each, from standard input, and shows each page
   on standard output, its links numbered:

     <n>             follow link n
     g <url>         go to url, resolved against the page (so "g ../x")
     b               back
     r               reload
     p               show the page again
     l               list the page's links, and where they go
     i               about the page: its URL, header, server key, identity
     trust           trust the key a server was refused for, as changed
     id              list the identities in the -identities dir
     id new <name> [<common name>]  make one
     id use <name>   offer it here, and below, and reload
     id off          stop offering the one offered here, and reload
     save <file>     save the page's body in file, a new file
     h               this help
     q               quit (end of input does as well)

   A gemini URL alone on a line goes there too. An input prompt (status
   10 or 11) asks for the answer on a line of its own, not echoed for
   11 if standard input is a terminal; an empty answer gives up. A
   redirect to another host is asked about before it is followed.

   -known-hosts keeps the servers' keys in file (GeminiTrust), trusting
   each on first use; without it they are kept for this run only.
   -identities is the directory of the identities (GeminiIdentities),
   and of the file "scopes" there saying which is offered where; it must
   exist. -width wraps text at n columns (80 if not given, 0 for not at
   all), counting characters, not bytes; preformatted text is never
   wrapped.

   It shows what a program does with each module, and is where a missing
   piece of the library shows first (PLAN.md, Phase 6): it is not
   installed. *)

IMPORT Platform, Args, UnixFiles, UnixErrors, UnixTerminals, GeminiPunycode, GeminiUrls, GeminiStatus,
  GeminiHeaders, GeminiText, GeminiTrust, GeminiResponses, GeminiIdentities, GeminiFetch;

CONST
  StdIn = 0; StdOut = 1;
  LF = 0AX; CR = 0DX; Tab = 09X;
  OutSize = 8192;
  InSize = 4096;
  MaxLine = 4096;          (* a command, or an answer, at most *)
  MaxHistory = 64;         (* pages to go back to *)
  MaxBody = 16777216;      (* 16 MiB: a page held whole at most *)

TYPE
  Text = GeminiUrls.Text;

  (* A page shown: the URL it came from (after any redirects), its
     header, and its body, whole, parsed if it is gemtext. *)
  Page = POINTER TO PageDesc;
  PageDesc = RECORD
    url: GeminiUrls.URL;
    link: Text;
    status: INTEGER;
    meta: ARRAY GeminiHeaders.MaxMeta + 1 OF CHAR;
    mime: GeminiHeaders.Mime;
    body: GeminiResponses.Chars;
    len: LONGINT;
    complete: BOOLEAN;
    doc: GeminiText.Document;   (* NIL if it isn't text/gemini *)
    keyHash: ARRAY 128 OF CHAR;
    version: ARRAY 32 OF CHAR;
    identity: GeminiIdentities.Name
  END;

VAR
  opts: GeminiResponses.Options;
  hosts: GeminiTrust.Hosts;
  idDir: GeminiResponses.Path;
  scopes: GeminiIdentities.Scopes;      (* NIL without -identities *)
  width: LONGINT;
  interactive: BOOLEAN;                 (* standard input is a terminal *)

  current: Page;                        (* NIL before the first *)
  last: Text;                           (* the URL fetched last, whatever came *)
  history: ARRAY MaxHistory OF Text;
  depth: INTEGER;

  (* A changed key refused: what "trust" would trust. *)
  refused: BOOLEAN;
  refusedHost: ARRAY 256 OF CHAR;
  refusedPort: LONGINT;
  refusedHash: ARRAY 128 OF CHAR;
  refusedNotAfter: HUGEINT;
  refusedLink: Text;

  outBuf: ARRAY OutSize OF CHAR;
  outLen: LONGINT;
  inBuf: ARRAY InSize OF CHAR;
  inPos, inLen: LONGINT;
  inEnded: BOOLEAN;

(* Output, buffered, and written with its length: a page may hold 0X *)

PROCEDURE Flush;
  VAR pos, n: LONGINT; err: UnixErrors.Error;
BEGIN
  pos := 0;
  WHILE pos < outLen DO
    IF ~UnixFiles.Write(StdOut, outBuf, pos, outLen - pos, n, err) THEN Platform.Exit(1) END;
    INC(pos, n)
  END;
  outLen := 0
END Flush;

PROCEDURE Bytes(s-: ARRAY OF CHAR; from, n: LONGINT);
BEGIN
  WHILE n > 0 DO
    IF outLen = OutSize THEN Flush END;
    outBuf[outLen] := s[from]; INC(outLen); INC(from); DEC(n)
  END
END Bytes;

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Length;

PROCEDURE Str(s-: ARRAY OF CHAR);
BEGIN Bytes(s, 0, Length(s))
END Str;

PROCEDURE Ln;
BEGIN IF outLen = OutSize THEN Flush END; outBuf[outLen] := LF; INC(outLen)
END Ln;

PROCEDURE Int(n: HUGEINT);
  VAR d: ARRAY 24 OF CHAR; i: INTEGER;
BEGIN
  IF n < 0 THEN Str("-"); n := -n END;
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + SHORT(SHORT(n MOD 10))); n := n DIV 10; INC(i) UNTIL n = 0;
  WHILE i > 0 DO DEC(i); Bytes(d, i, 1) END
END Int;

(* A line of its own, saying something *)
PROCEDURE Say(s-: ARRAY OF CHAR);
BEGIN Str(s); Ln
END Say;

PROCEDURE Say2(s-, t-: ARRAY OF CHAR);
BEGIN Str(s); Str(t); Ln
END Say2;

(* Input *)

(* Reads a line from standard input into line, without its LF (or CR
   LF), as much as fits, after showing prompt: FALSE at the end of the
   input. Read here, not through In, so that the end of the input and
   a line too long are known. When the input isn't a terminal, the line
   is shown after the prompt, as it would be if typed, so a transcript
   reads as a session did; unless echo is FALSE. *)
PROCEDURE ReadLine(prompt-: ARRAY OF CHAR; echo: BOOLEAN; VAR line: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT; err: UnixErrors.Error; got: BOOLEAN;
BEGIN
  Str(prompt); Flush;
  i := 0; got := FALSE;
  LOOP
    IF inPos = inLen THEN
      IF inEnded THEN EXIT END;
      inPos := 0;
      IF ~UnixFiles.Read(StdIn, inBuf, 0, InSize, inLen, err) OR (inLen = 0) THEN
        inLen := 0; inEnded := TRUE; EXIT
      END
    END;
    got := TRUE;
    IF inBuf[inPos] = LF THEN INC(inPos); EXIT END;
    IF i < LEN(line) - 1 THEN line[i] := inBuf[inPos]; INC(i) END;
    INC(inPos)
  END;
  IF (i > 0) & (line[i - 1] = CR) THEN DEC(i) END;
  line[i] := 0X;
  IF ~got THEN Ln; RETURN FALSE END;
  IF ~interactive THEN
    IF echo THEN Str(line) END;
    Ln
  END;
  RETURN TRUE
END ReadLine;

(* Reads an answer that isn't to be shown: not echoed by the terminal,
   nor by ReadLine. Should the terminal's echo not go off, the answer
   would be seen as typed, so that is said first. *)
PROCEDURE ReadSecret(prompt-: ARRAY OF CHAR; VAR line: ARRAY OF CHAR): BOOLEAN;
  VAR ok, off: BOOLEAN; err: UnixErrors.Error;
BEGIN
  off := interactive & UnixTerminals.SetEcho(StdIn, FALSE, err);
  IF interactive & ~off THEN Str("(it will be shown: "); Str(err.text); Str(")"); Ln END;
  ok := ReadLine(prompt, FALSE, line);
  IF off THEN
    IF UnixTerminals.SetEcho(StdIn, TRUE, err) THEN END;
    Ln
  END;
  RETURN ok
END ReadSecret;

(* Showing gemtext *)

(* The number of characters in s[from..to-1], UTF-8: its bytes that
   don't continue a character. *)
PROCEDURE Chars(VAR s: ARRAY OF CHAR; from, to: LONGINT): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0;
  WHILE from < to DO
    IF ORD(s[from]) DIV 64 # 2 THEN INC(n) END;
    INC(from)
  END;
  RETURN n
END Chars;

(* Shows s[0..len-1], the first line after first, the rest after rest,
   wrapped at width characters, at a space where there is one: a long
   word is cut, between characters. *)
PROCEDURE Wrapped(first-, rest-: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; len: LONGINT);
  VAR pos, i, space, count, room: LONGINT; lead: BOOLEAN;
BEGIN
  room := width - Length(first);
  IF (width = 0) OR (room < 20) OR (Chars(s, 0, len) <= room) THEN
    Str(first); Bytes(s, 0, len); Ln; RETURN
  END;
  pos := 0; lead := TRUE;
  REPEAT
    IF lead THEN Str(first); room := width - Length(first)
    ELSE
      Str(rest); room := width - Length(rest);
      WHILE (pos < len) & (s[pos] = " ") DO INC(pos) END
    END;
    lead := FALSE;
    i := pos; count := 0; space := -1;
    WHILE (i < len) & ((count < room) OR (ORD(s[i]) DIV 64 = 2)) DO
      IF ORD(s[i]) DIV 64 # 2 THEN INC(count) END;
      IF (s[i] = " ") OR (s[i] = Tab) THEN space := i END;
      INC(i)
    END;
    IF (i < len) & (s[i] = " ") THEN space := i END;   (* breaks right after the word *)
    IF i >= len THEN Bytes(s, pos, len - pos); pos := len
    ELSIF space > pos THEN Bytes(s, pos, space - pos); pos := space + 1
    ELSE Bytes(s, pos, i - pos); pos := i
    END;
    Ln
  UNTIL pos >= len
END Wrapped;

(* The link l on page p resolved, in u: FALSE, with why, if it can't be. *)
PROCEDURE Target(p: Page; VAR l: GeminiText.Line; VAR u: GeminiUrls.URL;
    VAR why: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF l.noUrl THEN COPY("the link has no URL", why); RETURN FALSE END;
  IF l.urlTooLong THEN COPY("the link's URL is too long to fetch", why); RETURN FALSE END;
  RETURN GeminiUrls.Resolve(p.url, l.url^, u, why)
END Target;

(* The index of p's link n (from 1), -1 if there is none. *)
PROCEDURE NthLink(p: Page; n: LONGINT): LONGINT;
  VAR i: LONGINT;
BEGIN
  i := -1;
  IF (p # NIL) & (p.doc # NIL) & (n > 0) THEN
    REPEAT i := GeminiText.NextLink(p.doc, i); DEC(n) UNTIL (i < 0) OR (n = 0)
  END;
  RETURN i
END NthLink;

PROCEDURE ShowGemtext(p: Page);
  VAR i, n: LONGINT; l: GeminiText.Line; mark, pad: ARRAY 32 OF CHAR; k: INTEGER;
    u: GeminiUrls.URL; why: ARRAY 256 OF CHAR;
BEGIN
  n := 0;
  FOR i := 0 TO p.doc.count - 1 DO
    l := p.doc.lines[i];
    CASE l.kind OF
      GeminiText.Text: Wrapped("", "", l.text^, l.len)
    | GeminiText.Link:
        IF l.noUrl THEN   (* "=>" alone: nothing to show, nothing to follow *)
        ELSE
          INC(n); mark := "["; k := 1;
          IF n >= 100 THEN mark[k] := CHR(ORD("0") + n DIV 100 MOD 10); INC(k) END;
          IF n >= 10 THEN mark[k] := CHR(ORD("0") + n DIV 10 MOD 10); INC(k) END;
          mark[k] := CHR(ORD("0") + n MOD 10); INC(k);
          mark[k] := "]"; mark[k + 1] := " "; mark[k + 2] := 0X;
          k := 0; WHILE mark[k] # 0X DO pad[k] := " "; INC(k) END; pad[k] := 0X;
          IF ~Target(p, l, u, why) THEN Str("(") ; Str(why); Str(") ")
          ELSIF u.scheme # "gemini" THEN Str("("); Str(u.scheme); Str(") ")
          END;
          IF l.len > 0 THEN Wrapped(mark, pad, l.text^, l.len)
          ELSE Wrapped(mark, pad, l.url^, l.urlLen)
          END
        END
    | GeminiText.Heading:
        IF l.level = 1 THEN Wrapped("# ", "  ", l.text^, l.len)
        ELSIF l.level = 2 THEN Wrapped("## ", "   ", l.text^, l.len)
        ELSE Wrapped("### ", "    ", l.text^, l.len)
        END
    | GeminiText.ListItem: Wrapped("* ", "  ", l.text^, l.len)
    | GeminiText.Quote:   (* its text keeps the whitespace after ">" *)
        IF (l.len > 0) & ((l.text[0] = " ") OR (l.text[0] = Tab)) THEN Wrapped(">", "> ", l.text^, l.len)
        ELSE Wrapped("> ", "> ", l.text^, l.len)
        END
    | GeminiText.Toggle:
    | GeminiText.Preformatted: Bytes(l.text^, 0, l.len); Ln
    END
  END
END ShowGemtext;

PROCEDURE Show(p: Page);
  VAR cs: ARRAY 64 OF CHAR;
BEGIN
  IF p.doc # NIL THEN ShowGemtext(p)
  ELSIF p.mime.type = "text" THEN
    GeminiHeaders.Charset(p.mime, cs);
    IF (cs = "utf-8") OR (cs = "us-ascii") THEN
      Bytes(p.body^, 0, p.len);
      IF (p.len > 0) & (p.body[p.len - 1] # LF) THEN Ln END
    ELSE
      Str("(text in "); Str(cs); Str(", not shown: "); Int(p.len); Say(" bytes; save it to read it)")
    END
  ELSE
    Str("("); Str(p.meta); Str(", "); Int(p.len); Say(" bytes; save it to keep it)")
  END;
  IF ~p.complete THEN Say("(the page may be incomplete: it ended without close_notify)") END
END Show;

PROCEDURE ListLinks(p: Page);
  VAR i, n: LONGINT; l: GeminiText.Line; u: GeminiUrls.URL; why: ARRAY 256 OF CHAR;
    t: Text;
BEGIN
  IF (p = NIL) OR (p.doc = NIL) THEN Say("no links"); RETURN END;
  i := GeminiText.NextLink(p.doc, -1); n := 0;
  WHILE i >= 0 DO
    l := p.doc.lines[i];
    IF ~l.noUrl THEN
      INC(n); Str("["); Int(n); Str("] ");
      IF Target(p, l, u, why) & GeminiUrls.Write(u, t) THEN Say(t) ELSE Say2(l.url^, "") END
    END;
    i := GeminiText.NextLink(p.doc, i)
  END;
  IF n = 0 THEN Say("no links") END
END ListLinks;

(* Fetching *)

(* The identity scopes say to offer for u, put in opts; or none. *)
PROCEDURE ChooseIdentity(VAR u: GeminiUrls.URL; VAR name: ARRAY OF CHAR);
  VAR id: GeminiIdentities.Identity; why: ARRAY 512 OF CHAR;
BEGIN
  opts.certFile := ""; opts.keyFile := ""; name[0] := 0X;
  IF (scopes # NIL) & scopes.For(u, name) THEN
    IF GeminiIdentities.Load(idDir, name, id, why) THEN GeminiIdentities.Use(id, opts)
    ELSE Say2("the identity for this page can't be used: ", why); name[0] := 0X
    END
  END
END ChooseIdentity;

(* The policy for a redirect to another host: the user decides. *)
PROCEDURE AskRedirect(VAR from, to: GeminiUrls.URL): BOOLEAN;
  VAR t: Text; answer: ARRAY 16 OF CHAR;
BEGIN
  IF ~GeminiUrls.Write(to, t) THEN RETURN FALSE END;
  Say2("redirected to another host: ", t);
  RETURN ReadLine("follow it? (y/n) ", TRUE, answer) & ((answer = "y") OR (answer = "yes"))
END AskRedirect;

PROCEDURE Push(VAR link: ARRAY OF CHAR);
  VAR i: INTEGER;
BEGIN
  IF depth = MaxHistory THEN
    FOR i := 1 TO MaxHistory - 1 DO history[i - 1] := history[i] END;
    DEC(depth)
  END;
  COPY(link, history[depth]); INC(depth)
END Push;

(* Fetches link, and shows what came. remember: the page shown now is
   one to go back to. link is copied first: it may be a variable that
   this changes (last, refusedLink). *)
PROCEDURE Visit(link-: ARRAY OF CHAR; remember: BOOLEAN);
  VAR u: GeminiUrls.URL; here, t, answer: Text; why: ARRAY 512 OF CHAR; ok: BOOLEAN;
    r: GeminiResponses.Response; p: Page; name: GeminiIdentities.Name;
    status: ARRAY 64 OF CHAR;
BEGIN
  COPY(link, here);
  IF ~GeminiUrls.Parse(here, u, why) THEN Say2("not a URL: ", why); RETURN END;
  IF u.scheme # "gemini" THEN Say2("not a gemini URL: ", here); RETURN END;
  IF ~GeminiUrls.Write(u, t) THEN Say("the URL is too long"); RETURN END;
  COPY(t, last); refused := FALSE;
  ChooseIdentity(u, name);
  ok := GeminiFetch.FetchFollowing(t, opts, 0, AskRedirect, r);
  IF r.trust = GeminiTrust.added THEN Say2("the server's key, trusted on first use: ", r.keyHash)
  ELSIF r.trust = GeminiTrust.replaced THEN Say2("the server's key, replacing one expired: ", r.keyHash)
  END;
  IF ~ok THEN
    Say2("failed: ", r.error.text);
    IF (r.error.kind = GeminiResponses.changed) & (r.keyHash # "") THEN
      (* The store knows the host by its ASCII name, as it went to the
         server; Trust is given the same. *)
      refused := GeminiPunycode.ToAscii(r.url.host, refusedHost, why);
      IF refused THEN
        u := r.url; refusedPort := GeminiUrls.Port(u);
        COPY(r.keyHash, refusedHash); refusedNotAfter := r.notAfter; COPY(t, refusedLink);
        Say2("its key now: ", r.keyHash); Say('"trust" trusts it from now on')
      END
    END;
    r.Close; RETURN
  END;
  IF (name # "") & (r.version = "TLSv1.2") THEN
    Say("(the identity went over TLS 1.2, which doesn't hide it from onlookers)")
  END;
  u := r.url;
  IF ~GeminiUrls.Write(u, t) THEN COPY(here, t) END;
  COPY(t, last);
  CASE GeminiStatus.Class(r.status) OF
    GeminiStatus.InputClass:
      Say(r.meta);
      IF r.status = GeminiStatus.SensitiveInput THEN ok := ReadSecret("(not shown) > ", answer)
      ELSE ok := ReadLine("> ", TRUE, answer)
      END;
      IF ok & (answer # "") THEN
        u := r.url;
        IF GeminiUrls.WithQuery(u, answer, why) & GeminiUrls.Write(u, t) THEN Visit(t, remember)
        ELSE Say2("the answer can't be sent: ", why)
        END
      END
  | GeminiStatus.SuccessClass:
      NEW(p); p.url := r.url; COPY(t, p.link); p.status := r.status; COPY(r.meta, p.meta);
      COPY(r.keyHash, p.keyHash); COPY(r.version, p.version); COPY(name, p.identity);
      IF ~GeminiHeaders.ParseMime(r.meta, p.mime, why) THEN
        IF GeminiHeaders.ParseMime("application/octet-stream", p.mime, why) THEN END
      END;
      p.complete := r.ReadAll(p.body, p.len);
      IF ~p.complete & (r.error.kind # GeminiResponses.truncated) THEN
        Say2("failed: ", r.error.text); r.Close; RETURN
      END;
      p.doc := NIL;
      IF GeminiHeaders.Is(p.mime, "text", "gemini") THEN p.doc := GeminiText.Parse(p.body^, p.len) END;
      IF remember & (current # NIL) THEN Push(current.link) END;
      current := p;
      Show(p)
  | GeminiStatus.CertificateClass:
      GeminiStatus.Name(r.status, status);
      Str(status); Str(": "); Say(r.meta);
      IF scopes = NIL THEN Say("(no -identities directory was given)")
      ELSIF name = "" THEN Say('"id use <name>" offers one here; "id" lists them, "id new <name>" makes one')
      ELSE Say2("(the identity offered was ", name); Say(")")
      END
  ELSE
    GeminiStatus.Name(r.status, status);
    Int(r.status); Str(" "); Str(status); Str(": "); Say(r.meta)
  END;
  r.Close
END Visit;

(* Commands *)

PROCEDURE Help;
BEGIN
  Say("<n> follow link n; g <url> go; b back; r reload; p show again; l links;");
  Say("i about the page; trust trust a changed key; save <file> save the body;");
  Say("id list identities; id new <name> [<cn>] make one; id use <name> offer it here;");
  Say("id off stop offering one here; h help; q quit")
END Help;

(* Splits line at its first run of blanks: the word in cmd, the rest in arg. *)
PROCEDURE Split(VAR line, cmd, arg: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE (line[i] = " ") OR (line[i] = Tab) DO INC(i) END;
  j := 0;
  WHILE (line[i] # 0X) & (line[i] # " ") & (line[i] # Tab) DO
    IF j < LEN(cmd) - 1 THEN cmd[j] := line[i]; INC(j) END;
    INC(i)
  END;
  cmd[j] := 0X;
  WHILE (line[i] = " ") OR (line[i] = Tab) DO INC(i) END;
  j := 0;
  WHILE line[i] # 0X DO
    IF j < LEN(arg) - 1 THEN arg[j] := line[i]; INC(j) END;
    INC(i)
  END;
  WHILE (j > 0) & ((arg[j - 1] = " ") OR (arg[j - 1] = Tab)) DO DEC(j) END;
  arg[j] := 0X
END Split;

PROCEDURE Number(VAR s: ARRAY OF CHAR; VAR n: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  n := 0; i := 0;
  WHILE (s[i] >= "0") & (s[i] <= "9") DO
    IF n < 1000000 THEN n := n * 10 + ORD(s[i]) - ORD("0") END;
    INC(i)
  END;
  RETURN (i > 0) & (s[i] = 0X)
END Number;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t-: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := Length(s); j := 0;
  WHILE (j < LEN(t)) & (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

(* Goes to ref, resolved against the page there is, if one; a bare host
   and path ("example.org/x") taken as a gemini URL. *)
PROCEDURE Go(VAR ref: ARRAY OF CHAR);
  VAR u: GeminiUrls.URL; t: Text; why: ARRAY 512 OF CHAR;
BEGIN
  IF ref = "" THEN Say("go where?"); RETURN END;
  IF current # NIL THEN
    IF ~GeminiUrls.Resolve(current.url, ref, u, why) THEN Say2("not a URL: ", why); RETURN END
  ELSIF ~GeminiUrls.Parse(ref, u, why) THEN
    t := "gemini://"; Append(t, ref);
    IF ~GeminiUrls.Parse(t, u, why) THEN Say2("not a URL: ", why); RETURN END
  END;
  IF GeminiUrls.Write(u, t) THEN Visit(t, TRUE) ELSE Say("the URL is too long") END
END Go;

PROCEDURE Follow(n: LONGINT);
  VAR i: LONGINT; l: GeminiText.Line; u: GeminiUrls.URL; t: Text; why: ARRAY 512 OF CHAR;
BEGIN
  i := NthLink(current, n);
  IF i < 0 THEN Say("no such link"); RETURN END;
  l := current.doc.lines[i];
  IF ~Target(current, l, u, why) THEN Say2("can't follow it: ", why)
  ELSIF ~GeminiUrls.Write(u, t) THEN Say("the URL is too long")
  ELSIF u.scheme # "gemini" THEN Say2("not a gemini URL, not followed: ", t)
  ELSE Visit(t, TRUE)
  END
END Follow;

PROCEDURE Back;
BEGIN
  IF depth = 0 THEN Say("nothing to go back to")
  ELSE DEC(depth); Visit(history[depth], FALSE)
  END
END Back;

PROCEDURE Info;
  VAR p: Page;
BEGIN
  p := current;
  IF p = NIL THEN Say("no page yet"); RETURN END;
  Say(p.link);
  Int(p.status); Str(" "); Say(p.meta);
  Str(p.version); Str(", the server's key "); Say(p.keyHash);
  IF p.identity # "" THEN Say2("identity: ", p.identity) END;
  Int(p.len); Say(" bytes")
END Info;

PROCEDURE Trust;
  VAR why: ARRAY 512 OF CHAR;
BEGIN
  IF ~refused THEN Say("no changed key to trust"); RETURN END;
  refused := FALSE;
  IF hosts.Trust(refusedHost, refusedPort, refusedHash, refusedNotAfter, why) THEN
    Say2("trusted: ", refusedHash); Visit(refusedLink, TRUE)
  ELSE Say2("not trusted: ", why)
  END
END Trust;

PROCEDURE Save(VAR file: ARRAY OF CHAR);
  VAR fd, pos, n: LONGINT; err: UnixErrors.Error; ok: BOOLEAN;
BEGIN
  IF current = NIL THEN Say("no page to save"); RETURN END;
  IF file = "" THEN Say("save it where?"); RETURN END;
  IF ~UnixFiles.OpenWrite(file, {UnixFiles.create, UnixFiles.exclusive}, 1A4H, fd, err) THEN
    Say2("not saved: ", err.text); RETURN
  END;
  pos := 0; ok := TRUE;
  WHILE ok & (pos < current.len) DO
    ok := UnixFiles.Write(fd, current.body^, pos, current.len - pos, n, err);
    INC(pos, n)
  END;
  UnixFiles.Close(fd);
  IF ok THEN Str("saved "); Int(current.len); Say2(" bytes in ", file)
  ELSE Say2("not saved: ", err.text)
  END
END Save;

(* id: the identities, and which is offered where. Each acts on the
   URL fetched last, whatever it gave: a 60 shows no page. *)
PROCEDURE Identities(VAR arg: ARRAY OF CHAR);
  VAR sub: ARRAY 16 OF CHAR; rest, cn: ARRAY 256 OF CHAR; name: GeminiIdentities.Name;
    id: GeminiIdentities.Identity; why: ARRAY 512 OF CHAR; u, v: GeminiUrls.URL;
    path: Text; offered: GeminiIdentities.Name; have: BOOLEAN;
BEGIN
  IF scopes = NIL THEN Say("no -identities directory was given"); RETURN END;
  Split(arg, sub, rest);
  have := (last # "") & GeminiUrls.Parse(last, u, why) & (u.host # "");
  IF sub = "" THEN
    IF ~GeminiIdentities.List(idDir, id, why) THEN Say2("can't list them: ", why)
    ELSIF id = NIL THEN Say("no identities yet")
    ELSE
      IF have & scopes.For(u, offered) THEN END;
      WHILE id # NIL DO
        Str(id.name); Str(" "); Str(id.hash);
        IF have & (id.name = offered) THEN Str(" (offered here)") END;
        Ln; id := id.next
      END
    END
  ELSIF sub = "new" THEN
    Split(rest, name, cn);
    IF GeminiIdentities.Make(idDir, name, cn, GeminiIdentities.DefaultDays, id, why) THEN
      Str("made "); Str(id.name); Str(" "); Say(id.hash)
    ELSE Say2("not made: ", why)
    END
  ELSIF sub = "use" THEN
    IF ~have THEN Say("no page to use it on")
    ELSIF ~GeminiIdentities.Load(idDir, rest, id, why) THEN Say2("can't use it: ", why)
    ELSIF ~scopes.Attach(rest, u, why) THEN Say2("can't use it: ", why)
    ELSE Say2("offered here and below: ", rest); Visit(last, FALSE)
    END
  ELSIF sub = "off" THEN
    IF ~have OR ~scopes.Covering(u, name, path) THEN Say("no identity is offered here")
    ELSIF ~GeminiUrls.Resolve(u, path, v, why) OR ~scopes.Detach(v, why) THEN Say2("can't stop it: ", why)
    ELSE Str("no longer offered: "); Str(name); Say2(", attached at ", path); Visit(last, FALSE)
    END
  ELSE Say("id, id new <name> [<cn>], id use <name> or id off")
  END
END Identities;

PROCEDURE Prefix(VAR s: ARRAY OF CHAR; p-: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE (p[i] # 0X) & (s[i] = p[i]) DO INC(i) END;
  RETURN p[i] = 0X
END Prefix;

(* Does the command in line: FALSE to quit. *)
PROCEDURE Command(VAR line: ARRAY OF CHAR): BOOLEAN;
  VAR cmd: ARRAY 16 OF CHAR; arg: ARRAY MaxLine OF CHAR; n: LONGINT;
BEGIN
  Split(line, cmd, arg);
  IF cmd = "" THEN
  ELSIF Number(cmd, n) & (arg = "") THEN Follow(n)
  ELSIF (cmd = "q") OR (cmd = "quit") THEN RETURN FALSE
  ELSIF (cmd = "h") OR (cmd = "help") OR (cmd = "?") THEN Help
  ELSIF (cmd = "g") OR (cmd = "go") THEN Go(arg)
  ELSIF cmd = "b" THEN Back
  ELSIF cmd = "r" THEN IF current = NIL THEN Say("no page yet") ELSE Visit(current.link, FALSE) END
  ELSIF cmd = "p" THEN IF current = NIL THEN Say("no page yet") ELSE Show(current) END
  ELSIF cmd = "l" THEN ListLinks(current)
  ELSIF cmd = "i" THEN Info
  ELSIF cmd = "trust" THEN Trust
  ELSIF cmd = "save" THEN Save(arg)
  ELSIF cmd = "id" THEN Identities(arg)
  ELSIF (arg = "") & Prefix(line, "gemini://") THEN Go(line)
  ELSE Say("not a command; h for help")
  END;
  RETURN TRUE
END Command;

PROCEDURE Usage;
BEGIN
  Str("usage: GeminiBrowse [-known-hosts file] [-identities dir] [-width n] [url]"); Ln;
  Flush; Platform.Exit(2)
END Usage;

PROCEDURE Main;
  VAR i: INTEGER; arg, known, start: ARRAY 2048 OF CHAR; n: LONGINT; why: ARRAY 512 OF CHAR;
    line: ARRAY MaxLine OF CHAR; dir: UnixFiles.Directory; err: UnixErrors.Error;
BEGIN
  known := ""; start := ""; idDir := ""; width := 80;
  i := 1;
  WHILE i < Args.argc DO
    Args.Get(i, arg);
    IF (arg = "-known-hosts") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, known)
    ELSIF (arg = "-identities") & (i + 1 < Args.argc) THEN INC(i); Args.Get(i, idDir)
    ELSIF (arg = "-width") & (i + 1 < Args.argc) THEN
      INC(i); n := -1; Args.GetInt(i, n);
      IF n < 0 THEN Usage END;
      width := n
    ELSIF (arg[0] = "-") OR (start # "") THEN Usage
    ELSE COPY(arg, start)
    END;
    INC(i)
  END;
  interactive := Platform.IsConsole(StdIn);
  GeminiResponses.InitOptions(opts);
  opts.maxBody := MaxBody;
  IF known = "" THEN hosts := GeminiTrust.New()
  ELSIF ~GeminiTrust.Open(known, hosts, why) THEN Say2("GeminiBrowse: ", why); Flush; Platform.Exit(1)
  END;
  opts.trust := hosts;
  scopes := NIL;
  IF idDir # "" THEN
    COPY(idDir, arg); Append(arg, "/scopes");
    (* Opened to see that it's there, which neither OpenScopes nor List,
       taking a missing file or directory for none yet, would say. *)
    IF UnixFiles.OpenDirectory(idDir, {}, dir, err) THEN UnixFiles.CloseDirectory(dir)
    ELSE Say2("GeminiBrowse: ", err.text); Flush; Platform.Exit(1)
    END;
    IF ~GeminiIdentities.OpenScopes(arg, scopes, why) THEN Say2("GeminiBrowse: ", why); Flush; Platform.Exit(1) END
  END;
  IF start # "" THEN Go(start) END;
  WHILE ReadLine("gemini> ", TRUE, line) & Command(line) DO END;
  Flush
END Main;

BEGIN
  current := NIL; depth := 0; last := ""; refused := FALSE;
  outLen := 0; inPos := 0; inLen := 0; inEnded := FALSE;
  Main
END GeminiBrowse.
