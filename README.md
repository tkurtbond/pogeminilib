# pogeminilib - Gemini for poc

This software is developed with the aid of AI.

An Oberon-2 library for programs that speak the
[Gemini protocol](https://geminiprotocol.net/), for poc, the
[Peaseblossom](https://github.com/tkurtbond/peaseblossom) Oberon
compiler. Clients first, and the engine of a server:

- `GeminiUrls`: URLs parsed, resolved against a page's, written, and
  made into a request line; and a request checked as a server must;
- `GeminiPunycode`: internationalised host names, to ASCII and back;
- `GeminiText`: gemtext parsed, a page at a time or streamed in fixed
  memory;
- `GeminiTextWriter`: gemtext written, refusing what would read back
  as something else;
- `GeminiStatus`: a response's status, its class and its name;
- `GeminiHeaders`: a response's header read and written, and its MIME
  type parsed;
- `GeminiFetch`: a URL fetched, blocking, for a program without tasks;
- `GeminiClient`: a URL fetched in poc's cooperative `Tasks`, so a
  program fetches several at once;
- `GeminiResponses`: the two's shared types: a fetch's options, its
  response, read as a stream or whole, and its errors;
- `GeminiTrust`: trust on first use, the servers' keys kept in a file;
- `GeminiIdentities`: client certificates made, listed, and chosen for
  a URL;
- `GeminiServer`: a server's engine: listeners, a task per
  connection, deadlines, and a clean stop on a signal.

Each module's reference is in [doc/](doc/), made from its source's
comments. [PLAN.md](PLAN.md) has the design and the decisions behind
it; [AGENTS.md](AGENTS.md) has the working notes.

**Status:** every phase of PLAN.md's roadmap is done: every module
above, tested on Linux, FreeBSD, NetBSD and OpenBSD (amd64 and i386 on
the BSDs), the client's and server's tests under valgrind on Linux, and
`make install` checked on each. pogemini, a Gemini server, runs on
`GeminiServer`. Two memcheck errors in the example browser,
`GeminiBrowse`, are still to be looked into.

## Requirements

- poc 0.14.0.
- Installed in `~/.local/lib/poc` (or `POCLIBDIR=<dir>`), by the same
  poc: poDateTime, posockets, polibtls and pounix. `make deps` checks.
  polibtls needs libtls: LibreSSL's, or libretls on OpenSSL.
- Linux, FreeBSD, NetBSD or OpenBSD; GNU make, as `gmake` on the BSDs.
- `openssl` on `PATH` for the tests' certificates only:
  `GeminiIdentities` makes keys and certificates through polibtls's
  `TlsMake`, with the libcrypto libtls loads.
- valgrind, for `make valgrind` (Linux); python3 for `make doc`.

## Building and installing

    make            # the library, the examples and the tests, under build/
    make test       # run the tests
    make valgrind   # the tests under valgrind
    make doc        # doc/<Module>.md from the source
    make install    # into ~/.local/lib/poc (POCLIBDIR=<dir> to change)
    make uninstall

`make install` installs the library in poc's `-OC` model, as its
dependencies are, plain and with `-g`. A program then builds with

    poc -OC -library-path ~/.local/lib/poc Program.Mod

and needs no other flags: poc links what the libraries record, libtls
among it.

A library works only with the poc that built it: after upgrading poc,
install poDateTime, then posockets, polibtls and pounix, then
pogeminilib again.

[examples/](examples/) has four programs, built and run by the tests:
`GeminiGet`, a small gemget; `GeminiFetchAll`, several URLs fetched at
once; `GeminiBrowse`, a line-mode browser with history, trust,
identities and input; and `GeminiServe`, a small server.

## Examples

Each of these is a whole program, built against the installed library
as above and run; between them they use every module. Their source is
in `examples/readme/`, and `make test` runs each as shown here.

### URLs and host names: `GeminiUrls`, `GeminiPunycode`

Links in a page are resolved against the page's URL, and the request
line is what goes to the server: ASCII, with an internationalised host
as punycode.

<!-- program examples/readme/Links.Mod -->
```oberon
MODULE Links; (* resolves links against a page's URL, as a client does *)

IMPORT Args, Out, GeminiUrls, GeminiPunycode;

VAR
  base, u: GeminiUrls.URL; i: INTEGER;
  arg, line: GeminiUrls.Text; host: ARRAY 256 OF CHAR; why: ARRAY 256 OF CHAR;

BEGIN
  Args.Get(1, arg);
  IF ~GeminiUrls.Parse(arg, base, why) THEN Out.String(why); Out.Ln
  ELSE
    FOR i := 2 TO Args.argc - 1 DO
      Args.Get(i, arg);
      IF ~GeminiUrls.Resolve(base, arg, u, why)
        OR ~GeminiUrls.RequestLine(u, line, why) THEN
        Out.String(arg); Out.String(": "); Out.String(why)
      ELSE
        Out.String(line);   (* what goes to the server, ASCII *)
        IF GeminiPunycode.ToUnicode(u.host, host, why) THEN
          Out.String(" (host "); Out.String(host); Out.String(")")
        END
      END;
      Out.Ln
    END
  END
END Links.
```
<!-- end program -->

    $ Links 'gemini://Bücher.example/a/b/c.gmi?q#f' ../x.gmi //other.example:1966/ gemini://u@h/
    gemini://xn--bcher-kva.example/a/x.gmi (host bücher.example)
    gemini://other.example:1966/ (host other.example)
    gemini://u@h/: userinfo in the URL

A server checks a request with `GeminiUrls.CheckRequest` instead,
which is strict, and gives the path decoded and normalised (see
`Hello`, below).

### Reading gemtext: `GeminiText`

A parser takes a page's bytes as they come, in a buffer of any size,
and gives its lines in memory fixed when it is made: a page of any
length, or a line of any length, needs no more. A program with the
whole page in memory calls `GeminiText.Parse` instead.

<!-- program examples/readme/Outline.Mod -->
```oberon
MODULE Outline; (* prints a gemtext file's headings and links *)

IMPORT Args, Out, Files, GeminiText;

VAR
  f: Files.File; r: Files.Rider; p: GeminiText.Parser; l: GeminiText.Line;
  buf: POINTER TO ARRAY 4096 OF CHAR; name: ARRAY 1024 OF CHAR;
  pos, end: LONGINT;

PROCEDURE Show(VAR l: GeminiText.Line);
BEGIN
  IF (l.kind = GeminiText.Heading) & l.first THEN
    Out.Int(l.level, 0); Out.String(" "); Out.String(l.text^); Out.Ln
  ELSIF (l.kind = GeminiText.Link) & l.first & ~l.noUrl THEN
    Out.String("  => "); Out.String(l.url^); Out.Ln
  END
END Show;

BEGIN
  Args.Get(1, name); f := Files.Old(name);
  IF f = NIL THEN Out.String("no file "); Out.String(name); Out.Ln
  ELSE
    (* Lines longer than 256 bytes come in pieces: only the first is shown. *)
    p := GeminiText.New(256); NEW(buf); Files.Set(r, f, 0);
    REPEAT
      Files.ReadBytes(r, buf^, LEN(buf^)); end := LEN(buf^) - r.res; pos := 0;
      WHILE GeminiText.Feed(p, buf^, pos, end, l) DO Show(l) END
    UNTIL r.eof OR (end = 0);
    WHILE GeminiText.Finish(p, l) DO Show(l) END
  END
END Outline.
```
<!-- end program -->

    $ cat t.gmi
    # Title
    some text
    => gemini://example.com/ Example
    ```
    # not a heading
    ```
    ## Sub
    => rel.gmi
    $ Outline t.gmi
    1 Title
      => gemini://example.com/
    2 Sub
      => rel.gmi

### Writing gemtext: `GeminiTextWriter`

A writer refuses what would read back as another kind of line, or as
something else, rather than writing it; `GeminiServer.NewWriter` gives
one that writes to a response.

<!-- program examples/readme/Index.Mod -->
```oberon
MODULE Index; (* writes index.gmi, a page linking to the files named *)

IMPORT Args, Out, Files, GeminiTextWriter;

VAR
  f: Files.File; r: Files.Rider; w: GeminiTextWriter.FileWriter;
  i: INTEGER; name: ARRAY 256 OF CHAR; why: ARRAY 128 OF CHAR; ok: BOOLEAN;

BEGIN
  f := Files.New("index.gmi"); Files.Set(r, f, 0);
  w := GeminiTextWriter.NewFile(r);
  ok := GeminiTextWriter.Heading(w, 1, "Index", why);
  i := 1;
  WHILE ok & (i < Args.argc) DO
    Args.Get(i, name);
    (* NameLink percent-encodes the name, so "a b?.gmi" is a file's name *)
    ok := GeminiTextWriter.NameLink(w, name, name, why); INC(i)
  END;
  IF ok THEN Files.Register(f) ELSE Out.String(why); Out.Ln END
END Index.
```
<!-- end program -->

    $ Index 'a b?.gmi' c:d.gmi notes.gmi && cat index.gmi
    # Index
    => a%20b%3F.gmi a b?.gmi
    => c%3Ad.gmi c:d.gmi
    => notes.gmi notes.gmi

### Headers and statuses: `GeminiStatus`, `GeminiHeaders`

A fetch parses the header for the program; this parses one given as
an argument, to show what it means. A status the specification
doesn't name is taken as its class's first, as it says to.

<!-- program examples/readme/Header.Mod -->
```oberon
MODULE Header; (* says what a response header means *)

IMPORT Args, Out, GeminiStatus, GeminiHeaders;

VAR
  line: GeminiHeaders.Line; h: GeminiHeaders.Header; m: GeminiHeaders.Mime;
  n: LONGINT; name: ARRAY 64 OF CHAR; cs: ARRAY 64 OF CHAR; why: ARRAY 128 OF CHAR;

BEGIN
  Args.Get(1, line); n := 0; WHILE line[n] # 0X DO INC(n) END;
  line[n] := 0DX; line[n + 1] := 0AX; INC(n, 2);   (* as it comes, CR LF *)
  IF ~GeminiHeaders.Parse(line, n, h, why) THEN Out.String(why)
  ELSE
    GeminiStatus.Name(h.status, name);
    Out.Int(h.status, 0); Out.String(": "); Out.String(name);
    IF GeminiStatus.Class(h.status) = GeminiStatus.SuccessClass THEN
      IF ~GeminiHeaders.ParseMime(h.meta, m, why) THEN Out.String(", "); Out.String(why)
      ELSE
        GeminiHeaders.Charset(m, cs);
        Out.String(", "); Out.String(m.type); Out.String("/"); Out.String(m.subtype);
        IF cs # "" THEN Out.String(" in "); Out.String(cs) END;
        IF GeminiHeaders.Is(m, "text", "gemini") THEN Out.String(", gemtext") END
      END
    ELSIF h.meta # "" THEN Out.String(", "); Out.String(h.meta)
    END
  END;
  Out.Ln
END Header.
```
<!-- end program -->

    $ Header '20 text/plain;charset=ISO-8859-1'
    20: success, text/plain in iso-8859-1
    $ Header 20
    20: success, text/gemini in utf-8, gemtext
    $ Header '14 x'
    14: input, x
    $ Header '7 bad'
    no status

### A fetch, and trust on first use: `GeminiFetch`, `GeminiResponses`, `GeminiTrust`

A fetch blocks until its header has come, or its deadline
(`opts.deadline`, ten seconds unless set) has passed. The server's key
is checked against the known hosts before the request is sent, so a
URL and its query never reach a server that isn't trusted.

<!-- program examples/readme/Get.Mod -->
```oberon
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
```
<!-- end program -->

    $ Get gemini://localhost/
    20 text/gemini
    first use: SHA256:6f56eee559cd4908c82c5cba28f57d89a21e13f9566847c35b11320e1d2e4446
    # Hello
    Served by GeminiServer.
    $ cat known-hosts
    localhost:1965 spki-sha256 6f56eee559cd4908c82c5cba28f57d89a21e13f9566847c35b11320e1d2e4446 2110415777

and once the server's key has changed:

    $ Get gemini://localhost/
    the server's key isn't the one known for localhost:1965, whose certificate hasn't expired

A body is read whole (`ReadAll`) or as a stream (`Read`), as
`examples/GeminiGet.Mod` does, so one of any size needs only a
buffer's worth of memory. `FetchFollowing` follows redirects.

### Fetches in tasks: `GeminiClient`

The same fetch, in a task: while it waits for the network the
program's other tasks run, so a slow server holds up only its own.

<!-- program examples/readme/Both.Mod -->
```oberon
MODULE Both; (* fetches two gemini URLs at once, a task each *)

IMPORT Args, Out, Tasks, GeminiResponses, GeminiClient;

TYPE
  Fetch = POINTER TO RECORD (Tasks.TaskDesc)
    url: ARRAY 1100 OF CHAR;
    ok: BOOLEAN;
    r: GeminiResponses.Response
  END;

VAR a, b: Fetch;

PROCEDURE (f: Fetch) Run*;
  VAR opts: GeminiResponses.Options;
BEGIN
  GeminiResponses.InitOptions(opts);
  (* while this task waits for its server, the other runs *)
  f.ok := GeminiClient.Fetch(f.url, opts, f.r);
  IF f.ok THEN f.r.Close END   (* the header's enough *)
END Run;

PROCEDURE Show(f: Fetch);
BEGIN
  Out.String(f.url); Out.String(": ");
  IF f.ok THEN Out.Int(f.r.status, 0); Out.String(" "); Out.String(f.r.meta)
  ELSE Out.String(f.r.error.text)
  END;
  Out.Ln
END Show;

BEGIN
  NEW(a); Args.Get(1, a.url); Tasks.Start(a, GeminiClient.stackSize);
  NEW(b); Args.Get(2, b.url); Tasks.Start(b, GeminiClient.stackSize);
  Tasks.Join(a); Tasks.Join(b);
  Show(a); Show(b)
END Both.
```
<!-- end program -->

    $ Both gemini://localhost/ gemini://localhost/x
    gemini://localhost/: 20 text/gemini
    gemini://localhost/x: 51 not found

### Client certificates: `GeminiIdentities`

An identity is a certificate and its key in a directory, and the scopes
file says which is offered for which URL: the one attached to its host
and port and the longest path above it.

<!-- program examples/readme/Identity.Mod -->
```oberon
MODULE Identity; (* fetches a URL with the identity attached to it, made if need be *)

IMPORT Args, Out, GeminiUrls, GeminiResponses, GeminiIdentities, GeminiFetch;

VAR
  link: ARRAY 1100 OF CHAR; name: GeminiIdentities.Name; why: ARRAY 256 OF CHAR;
  url: GeminiUrls.URL; scopes: GeminiIdentities.Scopes; id: GeminiIdentities.Identity;
  opts: GeminiResponses.Options; r: GeminiResponses.Response; body: GeminiResponses.Chars;
  len: LONGINT; ok: BOOLEAN;

BEGIN
  Args.Get(1, link);
  ok := GeminiUrls.Parse(link, url, why) & GeminiIdentities.OpenScopes("scopes", scopes, why);
  IF ok THEN
    IF scopes.For(url, name) THEN ok := GeminiIdentities.Load("ids", name, id, why)
    ELSE
      (* None yet: one made, and attached to the URL and every page
         below it. A real client asks its user first (status 60). *)
      name := "me";
      ok := (GeminiIdentities.Load("ids", name, id, why)
             OR GeminiIdentities.Make("ids", name, "", GeminiIdentities.DefaultDays, id, why))
        & scopes.Attach(name, url, why)
    END
  END;
  IF ~ok THEN Out.String(why); Out.Ln
  ELSE
    Out.String("as "); Out.String(id.name); Out.String(", "); Out.String(id.hash); Out.Ln;
    GeminiResponses.InitOptions(opts); GeminiIdentities.Use(id, opts);
    IF ~GeminiFetch.Fetch(link, opts, r) THEN Out.String(r.error.text); Out.Ln
    ELSIF (r.status DIV 10 = 2) & r.ReadAll(body, len) THEN Out.String(body^)   (* its own line ends *)
    ELSE Out.Int(r.status, 0); Out.String(" "); Out.String(r.meta); Out.Ln
    END
  END
END Identity.
```
<!-- end program -->

    $ mkdir ids; Identity gemini://localhost/
    as me, SHA256:d5e88ace82510b0d523adaafc7117b1d6c1c41615ff451254011791a69e245c3
    # GeminiServe
    ...
    $ cat scopes
    me localhost:1965 /

That run was against `examples/GeminiServe`, whose page shows the
client certificate's hash: the one the identity has.

A server's own certificate is made once and kept by
`GeminiIdentities.Ensure(dir, name, names, days, id, why)`: the next
time it loads the same one, since a capsule is known by its key, and a
certificate whose key is missing is refused rather than replaced.

### A server: `GeminiServer`

The engine serves each connection in a task of its own, within a
deadline, and hands its request to a procedure of the program's,
which decides what it means: here, `GeminiUrls.CheckRequest`'s path.
The `Get` and `Both` runs above were against it, with a key pair in
`server.crt` and `server.key`, as `Hello` alone, on port 1965; `Hello
0` lets the kernel choose a port, and the line `port n` says which.
SIGINT or SIGTERM stops it cleanly.

<!-- program examples/readme/Hello.Mod -->
```oberon
MODULE Hello; (* a Gemini server: a page at "/", 51 for anything else *)

(* Usage: Hello [port], 1965 if not given, 0 for one the kernel chooses *)

IMPORT Args, Out, Sockets, Tls, GeminiUrls, GeminiTextWriter, GeminiServer;

VAR
  c: Tls.Config; ctx: Tls.Context; s: GeminiServer.Server; err: Sockets.Error;
  port: LONGINT;

PROCEDURE Respond(x: GeminiServer.Exchange);
  VAR r: GeminiUrls.Request; w: GeminiServer.Writer; why: ARRAY 128 OF CHAR; status: INTEGER;
BEGIN
  status := GeminiUrls.CheckRequest(x.request, r, why);
  IF status # GeminiUrls.Ok THEN
    IF x.Header(status, why) THEN END
  ELSIF r.path # "/" THEN
    IF x.Header(51, "not found") THEN END
  ELSIF x.Header(20, "text/gemini") THEN
    w := GeminiServer.NewWriter(x);
    IF GeminiTextWriter.Heading(w, 1, "Hello", why)
      & GeminiTextWriter.Text(w, "Served by GeminiServer.", why) THEN
    END
  END
END Respond;

BEGIN
  port := 1965; IF Args.argc > 1 THEN Args.GetInt(1, port) END;
  c := Tls.NewConfig();
  IF ~c.SetKeypairFile("server.crt", "server.key") THEN Out.String(c.error.text^); Out.Ln
  ELSE
    ctx := Tls.NewServer();
    IF ~ctx.Configure(c) THEN Out.String(ctx.error.text^); Out.Ln
    ELSE
      c.Close;
      s := GeminiServer.New(ctx, Respond);
      IF ~s.Listen("localhost", SHORT(port), err) THEN Out.String(err.text); Out.Ln
      ELSE
        Out.String("port "); Out.Int(s.port, 0); Out.Ln;
        s.Serve(0)   (* until SIGINT or SIGTERM *)
      END
    END
  END
END Hello.
```
<!-- end program -->

`examples/GeminiServe.Mod` adds a log, an input prompt, and checking
that the host and port asked for are the server's own; given `-certs
dir` instead of `-cert` and `-key`, it makes its certificate there
through `Ensure`.

## Errors and halts

What comes from outside never halts a program: a server's response, a
page's gemtext, a URL in a link, a known-hosts or scopes file, a
network that fails. Each comes back as `FALSE` (or a status, or a
flag on a line) and a reason a person can read: `why`, or a fetch's
`r.error`, whose `kind` (`GeminiResponses.connect`, `.untrusted`,
`.changed`, `.truncated`, `.timedOut`, ...) a program can act on.

A response is complete only if the server ended it with TLS
close_notify; one cut short without it is an error, `truncated`, even
though what came before it has been read.

A programmer's error halts, as an `ASSERT`, so the program exits with
poc's status 10 and prints `assertion failed (n)`, n one of:

<!-- halt codes: PLAN.md, "Halt codes" -->
| Code | Module | Meaning |
|---|---|---|
| 120 | `GeminiText` | `New`: a buffer smaller than `MinBuffer` |
| 121 | `GeminiText` | `Feed` or `Parse`: an end or length past the array |
| 122 | `GeminiTextWriter` | `Writer.Put` not overridden by an extension |
| 123 | `GeminiTextWriter` | `Heading`: a level not 1..3 |
| 124 | `GeminiStatus`, `GeminiHeaders` | `Class`, `Effective` or `Name`: a status outside 10..69; `WriteHeader`: a status the specification doesn't name |
| 125 | `GeminiHeaders` | `WriteHeader`: a meta over 1024 bytes, not UTF-8, with a control character, or empty after 1x..3x |
| 126 | `GeminiHeaders` | `Ended` or `Parse`: a length past the array |
| 127 | `GeminiResponses` | `Waiter.Connect` or `Await` not overridden by an extension |
| 128 | `GeminiResponses` | `Response.Read`: a position or length outside the buffer |
| 129 | `GeminiTrust` | `Store.Check` not overridden by an extension |
| 130 | `GeminiServer` | `Exchange.Header` a second time |
| 131 | `GeminiServer` | `Exchange.Write` after a header other than 2x |
| 132 | `GeminiServer` | a `Responder` returned without a header |
| 133 | `GeminiServer` | `Server.Serve` before a `Listen` succeeded |
<!-- end halt codes -->

`GeminiPunycode` and `GeminiUrls` take only outside data, so nothing
in them halts.

`GeminiResponses.Fetch` and `GeminiServer.Server.Serve` ignore SIGPIPE
for the whole program, so a peer that goes away makes a write fail
rather than end it.

## License

BSD 3-clause; see [LICENSE](LICENSE).
