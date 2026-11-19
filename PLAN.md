# PLAN.md

pogeminilib's design and roadmap. Decisions and findings are appended
to the relevant section as they happen; a finished phase is marked
`[done]`, and a decided open question struck through.

## Goal and scope

A library of Oberon-2 modules, compiled with poc (the Peaseblossom
Oberon Compiler) and installed as poc libraries are, for programs that
speak the [Gemini protocol](https://geminiprotocol.net/), on Linux and
the BSDs (FreeBSD, OpenBSD, NetBSD; amd64 and i386), the systems poc
runs on. Its first users are Gemini clients: a fetcher like gemget, a
line-mode browser, a crawler or feed reader, written in Oberon. It
gives them:

1. **URLs**: parsing a `gemini://` URL (and any absolute or relative
   reference), resolving a link against its page as RFC 3986 says,
   percent-encoding and decoding, normalising, and putting a URL back
   together; an input (status 1x) answer encoded as a query.
2. **Requests and responses**: sending a request, reading and checking
   the response header (two-digit status, meta of at most 1024 bytes,
   CR LF), the status's class and meaning, the MIME type and its
   parameters (`charset`, `lang`) of a 2x, and the body as a stream,
   whole only if it ended with TLS close_notify.
3. **A client connection**: TCP and TLS 1.2+ with SNI, a deadline on the
   whole exchange, a client certificate if asked for, in poc's
   cooperative `Tasks`, so a program may fetch several URLs at once in
   one thread; following redirects, bounded, if the caller wants.
4. **Trust**: trust on first use (TOFU), as Gemini clients do, with a
   store of known hosts' certificate fingerprints and expiry dates, and
   a policy for a changed certificate that the program decides; or a CA
   file, or nothing checked, when asked for.
5. **Gemtext**: parsing `text/gemini` into its lines (text, link,
   heading 1 to 3, list item, quote, preformatting toggle with its alt
   text, preformatted), both a line at a time as the body arrives and as
   a whole document; and writing it, for a server's or a program's
   generated pages.

6. **Client certificates made**: a self-signed certificate and key for
   an identity, by running `openssl` as pogemini's `GemCert` does
   (decided with the user, 2026-11-18).
7. **Serving**: the server engine, moved from pogemini (decided with
   the user, 2026-11-18; "Should it serve as well?").

Out of scope for now, though nothing should rule them out: Titan
uploads, proxies, other protocols (Spartan, Gopher), conversion of
charsets other than UTF-8, and rendering (word wrapping, a terminal UI:
the program's).

**Portability** is as pogemini's (its PLAN.md, "Goal and scope"): no
Linux-only calls or files, `gmake` assumed, nothing GNU-only in the
GNUmakefile or test scripts, and what needs C comes from a shared po*
library (pounix, posockets, polibtls, poDateTime), not from C of this
library's own. The aim is a library with no C at all.

## Should it serve as well?

The user asked whether pogeminilib should also have what servers need,
given pogemini (`~/Repos/Oberon/pogemini`), a server already built on
polibtls, posockets and `Tasks`. Decided with the user, 2026-11-18:
yes, as proposed here, in three parts:

1. **What both sides share belongs here, from the start.** URLs, status
   codes, the response header (a client parses it, a server writes it),
   MIME types, and gemtext (a client parses it; a server writes
   directory listings, as pogemini does since 2026-11-17, and a dynamic
   server writes pages). pogemini's `GemRequest` already parses and
   checks a request URL; `GeminiUrls` is written so that it covers that,
   with a strict check for a server and a lenient parse for a client,
   and pogemini can later replace `GemRequest` with it.
2. **The server engine belongs here too, but later** (Phase 8), moved
   from pogemini rather than written afresh: `GemServer`'s listeners on
   both families, the accept tasks, a task per connection with a
   deadline, the limit on connections, the clean stop through
   `StopRequests`, and the `Exchange` and `Responder` a program answers
   with. Reasons: this library's own client tests need a server, and a
   misbehaving one, so a server module of some kind is written anyway;
   any second server in Oberon (a dynamic application, a Titan receiver,
   a test fixture in another project) would otherwise copy GemServer;
   and its hard-won facts (lingering close, the 1026-byte line, stack
   sizes in tasks, catching the signal before the port is printed) are
   then kept in one place. Moved only after the client side is done and
   the shared modules have settled, and only with pogemini's tests
   passing on it on every host.
3. **pogemini's policy stays in pogemini**: its configuration file,
   capsules, serving files under a root, hidden names, client
   certificate requires, making self-signed certificates, its log
   format, running as another user, rc scripts and systemd. A library
   server engine takes a log procedure rather than writing pogemini's
   line itself.

The order (shared modules, then the client, then the server engine)
keeps the client, the stated goal, first, and gives pogemini nothing to
change until the library is settled.

## Foundations

- **polibtls** (`~/Repos/Oberon/polibtls`): `Tls` (a client config with
  `InsecureNoVerifyCert`/`InsecureNoVerifyName` for TOFU, a CA file
  otherwise; `ConnectSocket` with the server name for SNI;
  `PeerCertHash`, `SHA256:` and lowercase hex; `PeerCertNotAfter`;
  key pairs for a client certificate) and `TlsTasks` (each call waiting
  through `Tasks` until the connection's deadline). Its
  `examples/GeminiFetch.Mod` is the client side's starting point (a
  response counts only if ended by close_notify; the pin compared
  before the request is sent), as `GeminiHello.Mod` was pogemini's.
  `Read` returns kind `closed` only on close_notify, so a cut-short
  body is told from a whole one.
- **posockets** (`~/Repos/Oberon/posockets`): `Sockets` (addresses,
  name resolution) and `SocketTasks` (`Connect` with a deadline,
  `LingeringClose`).
- **poDateTime** (`~/Repos/Oberon/poDateTime`): `Clocks.Now` and
  `Instants` for a known host's expiry, and anything else timed.
- **pounix** (`~/Repos/Oberon/pounix`): `UnixProcesses` to run
  `openssl` for client certificates (`GeminiIdentities`), so a
  dependency from Phase 5; `UnixFiles` for writing the trust store
  safely (a temporary name, then `rename`) and what else a file needs
  beyond poc's `Files`; `UnixTerminals` for the example browser's
  secret input (Phase 6).
- **poc's runtime**: `Tasks`, `Out`, `Err`, `Args`, `Platform`,
  `StopRequests` (the server engine, Phase 8).
- **pogemini**: `GemRequest` (URL rules, already tested by 82 checks in
  `TestParse`), `GemServer`, `GemFiles`' listing writer, and its tests'
  `GemClient`, `Child` and `Check`.

## Gemini's requirements

Re-read 2026-11-18 (Phase 0) in the protocol specification, 0.24.1,
the one pogemini follows
(`gemini://geminiprotocol.net/docs/protocol-specification.gmi`), and
the gemtext specification, 0.24.1
(`gemini://geminiprotocol.net/docs/gemtext-specification.gmi`), each
rule with its section ("P" the protocol's, "G" gemtext's), as
pogemini's PLAN.md records the server's.

### The protocol

- **URLs** (P "Overview"): scheme `gemini`; no userinfo; an empty path
  and `/` are the same; port 1965 by default; an IP address as host
  SHOULD NOT be used (but works).
- **The request** (P "Requests"): `absolute-URI CRLF`, the URI at most
  1024 bytes; no fragment (MUST NOT); an empty path SHOULD be sent as
  `/`. **`absolute-URI` is RFC 3986's, so ASCII**: an IRI's non-ASCII
  is percent-encoded in the path and query, and a host's is sent as
  punycode (`GeminiPunycode`; RFC 3987 section 3.1 allows either for a
  host, and punycode is what SNI and DNS need), so a request is the
  same whether its link was written as an IRI or a URI.
- **The header** (P "Responses"): UTF-8, no byte order mark, two
  digits and CR LF; a space and the meta after it, which 1x, 2x and
  3x must have (`prompt = 1*(SP / VCHAR)`, `mimetype`, a
  URI-reference) and 4x, 5x and 6x may leave out (`"50" CRLF` is
  whole; P's last example). No C0 or C1
  control characters in the meta (VCHAR). Its length isn't limited
  by the specification; pogemini's 1024 for the meta is ours
  ("Responses").
- **Statuses** (P "Status codes"): a status below 10 or over 69 MUST
  be refused and the user warned; an unknown one within 10..69 SHOULD
  be taken as its first digit's `x0`. 10 input, 11 sensitive input;
  20 success; 30 temporary and 31 permanent redirects; 40..44
  temporary failures (41 unavailable, 42 CGI, 43 proxy, 44 slow down,
  with exponential back-off); 50..53 and 59 permanent (51 not found,
  52 gone, 53 proxy refused, 59 bad request); 60 certificate required,
  61 not authorised, 62 not valid.
- **Input** (P "Input expected"): the answer becomes the query of the
  same URL, replacing any query it had; spaces as `%20`; line breaks,
  if allowed, as `%0A`.
- **Success** (P "Success"): MIME parameters not understood are
  ignored; text MAY end lines with LF alone, consistently, never CR
  alone, and a client MUST accept CR LF and LF; a `text/*` without
  `charset` is UTF-8. A client MUST support `text/gemini` in UTF-8 and
  `text/plain` in US-ASCII or UTF-8. **0.24.1 requires a MIME type**
  after 20; earlier versions let an empty meta mean
  `text/gemini; charset=utf-8`, and many servers still send `20 ` with
  none, so the client accepts that, as earlier versions said (Phase 3
  records it as a leniency).
- **A body's byte order mark** (P "Responses"): a text body SHOULD NOT
  begin with one, and a client parsing `text/gemini` SHOULD ignore one
  if it does: `GeminiText` skips a BOM at the start of a document.
- **The end** (P "Responses", "Closing connections"): the server MUST
  end with close_notify; a client SHOULD handle and tell the user of
  an end without it (`complete`); a client MAY close early for content
  over its limits.
- **Redirects** (P "Redirection"): the meta an absolute or relative
  URI-reference, never empty; the old query not carried over; the new
  location's fragment, or the old one's, the client's choice; **at
  most 5 redirects followed** (MUST). Warning of another host or
  scheme is clients' practice, not the specification's.
- **Client certificates** (P "Status 60"): a certificate made for a 60
  is scoped to that host and port and to the path and everything below
  it; one MUST NOT be made and used without the user taking part, nor
  sent to another host, port or a path above without the user's
  direction. So `GeminiIdentities` makes one only when the program asks
  (never inside a fetch), and its scope helper keeps P's rule.
- **TLS** (P "The use of TLS"): 1.2 or later; SNI MUST be sent for a
  host name and SHOULD NOT for an IP address; a client SHOULD warn
  when it sends a client certificate over TLS 1.2 (in the clear), so a
  response tells the program the TLS version.
- **Trust** (P "TLS Server certificate validation"): TOFU is strongly
  recommended: on first contact the certificate's fingerprint and
  expiry are kept, by host and port; a different fingerprint before
  the stored expiry is evidence of an attack. We pin the public key's
  fingerprint rather than the certificate's ("Trust"), which keeps
  this rule and lets a renewal with the same key through.
- **Proxies** (P "Intermediaries"): a client MAY not support them; out
  of scope.

### Gemtext

- **Media type** (G "Media type parameters"): `charset`, UTF-8 by
  default, and `lang`, a list of BCP 47 tags, **quoted if it has a
  comma** (`lang="en,fr"`), so MIME parameters are parsed with RFC
  2045's quoted strings; other parameters are ignored.
- **Lines** (G "Line oriented design"): a line's type is known from
  its first three characters and the parser's state, normal or
  preformatted, normal at the start (G "Parser state"); the state at
  the end means nothing, so an unclosed preformatted block is no
  error.
- **Text** (G "Text lines"): any line without another type's prefix;
  an empty line is a text line; lines are never joined.
- **Links** (G "Link lines", "Formal grammar"): `=>`, optional spaces
  or tabs, the URL, then optionally spaces or tabs and a label; the
  grammar allows whitespace after the label, which the parser keeps
  (Phase 2: a streaming parser would have to hold it, unbounded, to
  know whether more text follows).
  The URL may be relative; a client MUST NOT connect anywhere just to
  show a link. `=>` with no URL fits the grammar (`URI-reference` may
  be empty): a link with an empty URL, flagged, for the program to
  show as text.
- **Preformatting toggles** (G "Preformatting toggle lines"): three
  backticks at the start of the line, no leading whitespace; the rest
  of an opening toggle MAY be alt text; the rest of a closing one MUST
  be ignored, so a closing toggle has no alt text.
- **Headings** (G "Heading lines"): one to three `#`, optional
  whitespace, the text; the grammar makes `####x` a level-3 heading of
  text `#x`. The first heading may serve as the title.
- **List items** (G "List items"): `*` and a space; `*x` is text.
- **Quotes** (G "Quote lines"): `>` and the rest of the line, any
  whitespace after `>` kept, since the grammar doesn't drop it.
- **In preformatted mode** (G "In pre-formatted mode"): every line but
  a toggle is preformatted text, shown unaltered.
- Heading, list and quote lines MAY be treated as text (G "Line
  oriented design"); `GeminiText` recognises them all, and a program
  that doesn't want them treats them as text.

## Design

Proposed unless it says decided; each point decided with the user
before its phase, then recorded here as decided.

### Library and module names

Decided with the user, 2026-11-18.

- **The library is `pogeminilib`** (`-library pogeminilib`, installed in
  `POCLIBDIR` as `pogeminilib.library`), so it can't be confused with
  the program `pogemini`.
- **Modules begin `Gemini`**, not `Gem`, so a program can import them
  beside pogemini's own `Gem*` modules (`GemRequest` and a library
  `GemRequest` couldn't both be imported):

| Module | What it is |
|---|---|
| `GeminiUrls` | parse, check, resolve, encode, decode, normalise, write URLs |
| `GeminiPunycode` | internationalised host names to ASCII (`xn--`) and back, punycode only |
| `GeminiStatus` | status codes, their classes and names |
| `GeminiHeaders` | the response header: parse (client), write (server); MIME type and parameters |
| `GeminiClient` | a fetch in tasks: connect, send, read the header, the body as a stream; redirects |
| `GeminiFetch` | the same without tasks, for a program that doesn't use them (blocking) |
| `GeminiTrust` | TOFU: the known-hosts store and the check against it |
| `GeminiIdentities` | client certificates: made by `openssl`, kept, listed |
| `GeminiText` | gemtext: line types, a streaming line parser, a whole-document parser |
| `GeminiTextWriter` | gemtext written, a line at a time; a name's link percent-encoded |
| `GeminiServer` | (Phase 8) the server engine, from pogemini's `GemServer` |

The split follows what a program needs: a gemtext renderer imports
`GeminiText` alone, with no TLS; a URL tool `GeminiUrls` alone.

### Integer model and memory

- **`-OC`**, the size model polibtls, posockets, pounix and poDateTime
  are installed in; never mixed.
- **Nothing large on a task's stack.** A task's stack is 64 KiB
  (`TlsTasks.stackSize`), and a value `ARRAY OF CHAR` parameter is
  copied onto the callee's stack (pogemini, Phase 1), so buffers and
  bodies live on the heap, and array parameters are `VAR` or read-only
  (`-`). A URL is a fixed `ARRAY 1025 OF CHAR`; a gemtext line, which
  has no length limit, is a `POINTER TO ARRAY OF CHAR`.
- **No string concatenation in poc**: `COPY` and explicit appends
  (pogemini, Phase 1).

### URLs (`GeminiUrls`)

- A `URL` record of scheme, userinfo, host (lower case, decoded, IPv6
  without brackets, no final `.`), port (`NoPort`, -1, for none;
  `Port(u)` gives 1965 for gemini), path, query and fragment, each kept
  as sent (still encoded), with flags for a `//`, a `?` and a `#` that
  have nothing after them. The server's `Request` has the path decoded
  and normalised, as `GemRequest`'s.
- A host's final `.` is dropped by both: SNI must not have one (RFC
  6066), and the known-hosts file then keeps one entry per host.
- `Parse` for any absolute URL, lenient as a client must be (any
  scheme; `http:` links in a page are links too); `CheckRequest` the
  server's strict rules (`GemRequest`'s: 59 and 53 with a reason).
- `Resolve(base, ref)` by RFC 3986 section 5.2, with section 5.4's
  examples as tests; `.` and `..` removed as section 5.2.4 says (the
  client's way, clamped at the root), whereas the server's check
  refuses `..` above `/` (pogemini, Phase 2). Both are kept, named
  apart.
- `Write(u)` back to text, `WithQuery(u, text)` for an input answer
  (the text percent-encoded, all but RFC 3986's unreserved, as the
  specification asks: spaces as `%20`; the fragment dropped, since it
  named a place in the prompt's page), and `RequestLine(u)` (fragment
  dropped, an empty path sent as `/`; refused with userinfo, with no
  host, or over 1024 bytes).
- Every URL, parsed or resolved, is at most 1024 bytes: a longer one
  could never be fetched, and the record's fields are fixed arrays.
- IRIs: non-ASCII as UTF-8 accepted, as pogemini does; percent-encoded
  when sent. A host is kept as written; its ASCII form, from
  `GeminiPunycode`, is what goes to name resolution, SNI and the
  known-hosts file, and the request line (its `absolute-URI` is ASCII:
  "Gemini's requirements", "The request"), so the line is the same
  whether a link was written as an IRI or a URI.

### Internationalised host names (`GeminiPunycode`)

Decided with the user, 2026-11-18: punycode only (level 1 of the three
in "Open questions"), in a module of its own, pure Oberon.

- **`ToAscii(host, ascii, err)`**: the host split at `.`; an ASCII
  label lowered; any other decoded from UTF-8 to code points, its ASCII
  letters lowered, encoded by RFC 3492's algorithm and given the
  prefix `xn--`. Refused (`FALSE` and why, never a halt): malformed
  UTF-8, an empty label, a label over 63 bytes or a host over 253 once
  encoded. An IP address is left alone.
- **`ToUnicode(host, text, err)`**: each `xn--` label decoded, for a
  program to show; one that doesn't decode is kept as it is, and
  reported.
- **Not done**, as level 1 leaves out: case folding of non-ASCII
  letters (`BÜCHER` gives a name that won't resolve, an error rather
  than a danger), normalisation (NFC), and IDNA2008's checks of which
  characters are allowed. A program showing a decoded host is
  responsible for what it shows (homographs). Levels 2 and 3 can be
  added later behind the same procedures.
- Whether pogemini uses it, to match a request's host with a capsule's
  name, is pogemini's to decide (Phase 8).

### Responses (`GeminiStatus`, `GeminiHeaders`)

As built in Phase 3 (`doc/GeminiStatus.md`, `doc/GeminiHeaders.md`):

- `GeminiStatus`: the specification's statuses as constants, and
  `Valid` (10..69), `Known` (named by the specification), `Class` (the
  first digit), `Effective` (an unknown one as its class's `x0`) and
  `Name` (the specification's name, for a program to show). A status
  outside 10..69 given to `Class`, `Effective` or `Name` halts (124):
  `Parse` never gives one.
- `GeminiHeaders.Ended(buf, len, n)`: whether a client has read enough
  for `Parse`, an LF within `MaxHeader` (1029) bytes or that many
  without one; `n` is where the body begins. `Parse(line, len, h,
  why)`: status and meta, or `FALSE` and why, refusing what the
  specification forbids: a byte order mark; no LF within 1029 bytes;
  an LF without CR; bytes after the LF; no status, a third digit, a
  status outside 10..69; no space before a meta; a meta over 1024
  bytes, not UTF-8, or with a control character (C0, DEL or C1, tab
  included, as VCHAR excludes them); a 1x with no prompt; a 3x with
  no URL. An unknown status within 10..69 is kept. A bad header is an
  error the program sees, never a halt.
- **Two leniencies**, each what servers send: a 2x with no meta (`20`
  or `20 `), which 0.24.1 forbids but earlier versions took as
  `text/gemini; charset=utf-8`; and a space after a 4x..6x with no
  message after it.
- `ParseMime(meta, m, why)`: RFC 2045's grammar, its tokens and
  quoted-strings (backslash escapes), whitespace allowed around `;` and
  `=` (RFC 822's tokens, which RFC 2045's are). Type and subtype lower
  case, each at most 127 bytes (RFC 6838); parameter names lower case,
  values as written, a quoted one unquoted. What isn't a parameter is
  skipped to the next `;` outside quotes and `m.skipped` set, as the
  specification says to ignore parameters not understood; only no
  type or subtype is refused. An empty meta is `text/gemini;
  charset=utf-8`, with `m.assumed` set. `Is`, `Param` (the first of a
  name, if repeated) and `Charset` (`utf-8` for a `text/*` without
  one) read it.
- `WriteHeader(status, meta, line, len)` for a server, stricter than
  `GemServer.Header` (10..69, meta at most 1024): it halts on a status
  the specification doesn't name ("Servers MUST NOT send status codes
  that are not defined"; 124) and on a meta `Parse` would refuse (over
  1024 bytes, not UTF-8, a control character, or empty after 1x, 2x or
  3x; 125). `GeminiServer` (Phase 8) writes its headers with it.

### The client (`GeminiClient`)

- **In tasks.** Every call that waits does so through `Tasks`
  (`SocketTasks`, `TlsTasks`), so a program fetches several URLs at
  once in one thread.
- **And without them** (decided with the user, 2026-11-18): a separate
  blocking API, `GeminiFetch`, for a program that doesn't use `Tasks`
  at all, on a blocking socket and polibtls's blocking `Tls` calls, as
  polibtls's example GeminiFetch does. **Its deadline needs posockets**:
  `Sockets` has no socket timeouts and no blocking wait, and its
  blocking `Connect` waits as long as the kernel does (read
  2026-11-18), so posockets gains, with its tests, either a blocking
  wait with a deadline (`poll` on a non-blocking socket, which also
  bounds `connect`) or `SO_RCVTIMEO`/`SO_SNDTIMEO` (which don't bound
  `connect` everywhere); the first, decided with the user, 2026-11-18.
  The blocking `Tls` calls are then made on the non-blocking socket,
  each `want` waited for by that `poll`. It
  has the same options, `Response` and errors as
  `GeminiClient`, and everything but the waiting (URLs, header,
  trust, redirects) is shared code, so the two can't drift: the
  connection behind a small interface with a blocking and a task
  implementation. Whether a program in tasks may call it (it would
  hold up every task while it waits) is documented, not prevented.
  `GeminiClient` needs no task of its own: poc's main program is a
  task (users' guide, section 12), and a probe (Phase 0) fetched
  from pogemini through `SocketTasks.Connect` and `TlsTasks` in a main
  body that started no task.
- **A request has options**: a deadline (default 10 s, for everything
  from connect to close_notify), a client certificate's key pair, the
  trust (a `GeminiTrust.Store`, a CA file, or none), and the most body
  to accept (none by default; a program reading a stream needs no
  limit).
- **A response** is the status and meta, then the body read through it
  (`Read(buf, pos, len, n)`, as `TlsTasks.Read`), so a renderer shows a
  page as it arrives and a large file isn't held in memory; `ReadAll`
  for a program that wants it whole. `complete` says the body ended
  with close_notify; a body cut short is an error with what came
  before kept. It also gives the TLS version (`Tls.Connection.Version`,
  "TLSv1.3"), so a program can warn when a client certificate went
  over TLS 1.2, as the specification asks.
- **The server certificate is checked before the request is sent**
  (GeminiFetch's rule), so a URL with its query never reaches a server
  the program doesn't trust.
- **Redirects** are the program's by default (`Fetch` returns a 3x as
  it came); `FetchFollowing(url, opts, max)` follows at most `max`
  (0 or over 5 gives 5, the specification's limit), resolving each
  against the URL before it (so the old query is never carried over,
  and a fragment only as RFC 3986 section 5.2 carries it), refusing a
  loop, an empty location, a scheme other than gemini, and asking a
  `RedirectPolicy` procedure about one to another host.
- **Errors** are a record of kind (`request`, `resolve`, `connect`,
  `tls`, `untrusted`, `changed`, `header`, `truncated`, `timedOut`,
  `tooLong`) and text, as polibtls's `Error`; outside data never halts.
  `request` (Phase 4) is a URL that isn't a gemini URL that can be
  requested.
- **The shared code is `GeminiResponses`** (Phase 4): `Options`,
  `Response`, `Error` and the whole of a fetch, waiting through an
  abstract `Waiter` (`Connect`, `Await`); `GeminiClient`'s waits
  through `SocketTasks` and `Tasks`, `GeminiFetch`'s through posockets'
  `ConnectWithin` and `Await`. Each socket is non-blocking and each TLS
  call made non-blocking in both, so the only difference is the wait.

### Trust (`GeminiTrust`)

- A known host is host, port, the fingerprint of the certificate's
  **public key** and the certificate's expiry (from
  `PeerCertNotAfter`). On first contact the host is added; on a later
  one the same key passes (a renewed certificate with the same key
  too, its expiry then updated), a different one is `changed` unless
  the stored certificate has expired, which a policy may allow to
  replace it, as many clients do.
- **The public key, not the certificate** (decided with the user,
  2026-11-18), as Lagrange pins, so a capsule that renews its
  certificate but keeps its key isn't reported as changed. libtls
  hashes only the whole certificate (`PeerCertHash`), and polibtls
  gives neither the peer's certificate nor its key (read 2026-11-18:
  `PeerCertProvided`, `Hash`, `Subject`, `Issuer`, `NotBefore`,
  `NotAfter`, `ContainsName`), so **polibtls gains, with its tests, a
  SHA-256 of the peer's SubjectPublicKeyInfo**, in its repository,
  before Phase 5, written `SHA256:` and lowercase hex, as
  `PeerCertHash` is, and checked against `openssl x509 -pubkey | openssl
  pkey -pubin -outform DER | openssl dgst -sha256`. Done 2026-11-18:
  `Connection.PeerKeyHash`, from `tls_peer_cert_chain_pem` (the peer's
  certificate first) and a new module, `TlsCerts`, in Oberon rather
  than libcrypto (with the user: NetBSD's `-L/usr/pkg/lib` could link a
  second libcrypto); `TlsCerts.KeyHash` and `CertHash` read a
  certificate file too. Tested on Linux and the five BSD hosts
  (polibtls's PLAN.md, "The peer's public key").
- The store is a text file a line per host, at a path the program
  gives (decided with the user, 2026-11-18: the library chooses no
  location; an example program uses
  `$XDG_DATA_HOME/<program>/known_hosts`). Written to a temporary name
  and renamed, so a crash never leaves half a file.
- The check is a procedure of the store, so a program may keep hosts
  elsewhere (in memory, for tests).

**What other clients keep** (looked up 2026-11-18; there is no common
format):

- **Lagrange** (read in its source, `lib/core/src/gmcerts.c`, branch
  `dev`): `trusted.lst` in its configuration directory, formerly
  `trusted.2.txt`; a line per host and port, `<key> <notAfter> <hex>`,
  the time in Unix seconds and the fingerprint lowercase hex with no
  algorithm named. **It pins the public key**
  (`publicKeyFingerprint_TlsCertificate`), not the certificate, so a
  renewed certificate with the same key is still trusted. An expired
  entry is dropped when the file is saved and no longer constrains the
  host; a certificate a CA vouches for replaces a pin. (How the key
  joins host and port is in `makeTrustKey_`, not yet read.)
- **gmni** and Drew DeVault's "TOFU recommendations for Gemini"
  (2020): `known_hosts`, a line per host, `<host> <algorithm>
  <fingerprint> <notAfter>`, the fingerprint hex with `:` between
  octets, the time Unix seconds; a line with an unknown algorithm is
  ignored; an expired entry is disregarded (the host is unknown
  again), and a mismatch with an unexpired one aborts the request and
  must be fixed by editing the file. The most fully documented.
- **go-gemini's `tofu` package** (used by its clients): a
  `known_hosts` of hostname, algorithm (SHA-256 by default) and
  fingerprint; the exact text not read (its source was unreachable).
- **Amfora**: a hash and an `<host:port>/expiry` per host, accepting a
  new certificate once the stored one has expired; its file's syntax
  (TOML) not confirmed.
- **AV-98**: an SQLite database, `tofu.db`, table `cert_cache`
  (hostname, address, fingerprint, count, first_seen, last_seen),
  keyed by host and port. **Offpunk**, its descendant, moved in 3.0 to
  keeping each certificate as a file. Astronomo and Nauyaca use SQLite
  too.

So, decided with the user, 2026-11-18: **our own format**, close to
DeVault's, since it names the algorithm and so survives a change of
hash, is text, and its rules are written down: a line per host,
`<host>:<port> <algorithm> <fingerprint> <notAfter>`, the algorithm
`spki-sha256` (naming what is hashed as well as how), the fingerprint
lowercase hex, `notAfter` Unix seconds. A line that can't be read, or
names an algorithm not known, is kept as it is when the file is
written and otherwise ignored, so a newer program's lines survive an
older one. Lagrange's file, which also pins the public key, could be
imported later, read-only; gmni's pins certificates, so not.

### Gemtext (`GeminiText`, `GeminiTextWriter`)

- **A byte order mark** at the start of a document is skipped, as the
  specification asks of a client ("Gemini's requirements", "A body's
  byte order mark"); one anywhere else is text.
- **A link with no URL** (`=>` alone, or with whitespace), which the
  grammar allows: a `Link` with an empty URL, flagged `noUrl`, for the
  program to show as text or leave out; never fetched.
- **Line types**: `Text`, `Link`, `Heading` (with its level 1..3),
  `ListItem`, `Quote`, `Toggle` (with alt text, on opening), and
  `Preformatted`. A `Line` record has its kind, its text (without the
  marker and the whitespace before a heading's text or a link's
  label), and for a link its URL as written, the label being its text.
- **A streaming parser**: a `Parser` keeps the preformatting state and
  any part line, takes bytes as they come and hands out each piece
  (`Feed(p, buf, pos, end, l)`, called until it gives `FALSE`), and
  `Finish` the last line without an end; so a client parses a body as
  `GeminiClient` reads it. Line ends LF or CR LF; a lone CR is left as
  text. (Feed and Next were to be two calls; they are one, since
  Oberon can't keep a reference to the caller's array between them and
  copying it would undo the bounded memory.)
- **No limit on a line's length, and bounded memory** (the user's
  idea, 2026-11-18): the parser's buffer has a fixed size, given when
  it is made, and a line longer than it comes out in pieces, each as
  much as fits (less the terminating 0X), the next read when the
  program asks again. A `Line` says whether it is a line's `first`
  piece and whether its `last`; the kind, and a heading's level, come
  from the first piece and hold for the rest. A piece never ends inside
  a UTF-8 sequence, which needs only the bytes already in the buffer,
  since UTF-8 marks every byte (RFC 3629): `10xxxxxx` continues a
  character, and a lead byte says how many bytes its character has
  (`110xxxxx` 2, `1110xxxx` 3, `11110xxx` 4). When the buffer is full,
  the parser looks back at most three bytes for a lead byte; if its
  character has more bytes than are left after it, the piece ends
  before the lead byte and those one to three bytes begin the next
  piece. So a piece is at most three bytes short of the buffer. If
  there is no lead byte within three bytes (the bytes aren't UTF-8),
  the piece is cut where the buffer ends, and flagged as malformed,
  as such bytes are anywhere. (A piece may still end between a
  character and a combining mark after it; joining the pieces mends
  that, and a renderer that doesn't join treats a piece's end as a
  place it may wrap.) A link's URL has a buffer of its own, of
  `MaxURL` (1024) bytes: a longer one is cut there and flagged
  (`urlTooLong`), the rest of it dropped, since a request is at most
  1024 bytes and no longer URL can be fetched; the label comes in the
  text's pieces as usual. So what `Parse` gives doesn't depend on the
  buffer's size, which need only be `MinBuffer` (8; a halt if less):
  room for a four-byte character after a cut, so every piece makes
  progress. A renderer that wraps text needs nothing more; one that
  wants whole lines joins the pieces, or uses `Parse`.
- **A document**: `Parse(text)` gives a list of `Line`s, for a program
  that has the whole page; a `Document` can say its first heading (a
  title) and its links.
- **No resolution in the parser**: a link's URL is kept as written; the
  program resolves it with `GeminiUrls.Resolve`, so `GeminiText` needs
  nothing but itself.
- **Malformed input never halts**: bytes that aren't UTF-8 are kept as
  they are and reported by a flag, not refused; a renderer decides.
- **The writer** writes each line type to a `Files.Rider`
  (`FileWriter`), or through a `Writer` extension's `Put`, as a
  server's `Exchange` will. `Link` writes a URL as given (encoding a
  whole URL would encode its `:` and `/`); `NameLink` encodes a name
  of one segment as pogemini's listings do (all but RFC 3986's
  unreserved). Gemtext has no escape, so what would read back as
  something else is refused (`FALSE`, and why), and the program
  chooses: a text line another kind would claim (beginning `=>`, `#`,
  `* `, `>` or ```` ``` ````), a line end in any line, a line of the
  wrong kind inside or outside a block, a preformatted line of three
  backticks, whitespace a reader drops (before a heading's text or a
  label; a byte order mark beginning the page), and a URL empty or
  holding a space or a control character.

### Client certificates (`GeminiIdentities`)

Decided with the user, 2026-11-18: the library makes them.

- **Made as pogemini's `GemCert` makes a server's**: `/bin/sh` run
  through pounix's `UnixProcesses` with a fixed script and the
  arguments as `$1`, `$2`, ..., so nothing is quoted; `openssl genpkey`
  and `req -x509` with options both OpenSSL 3 and LibreSSL accept,
  `-sha256` named (LibreSSL signs with SHA-1 otherwise, which GnuTLS
  refuses); ECDSA P-256 by default; under `umask 077`, written under
  temporary names and renamed, key first, certificate last. Without
  `openssl` on `PATH`, an error the program sees.
- **An identity** is a name (the file names, and the certificate's
  CN unless given another), a lifetime (the program's; a long one by
  default, since an identity's hash is what a capsule knows a user
  by), and the pair's files in a directory the program gives. `List`
  gives the identities there with each one's hash (`SHA256:...`, as
  a server's log shows it) and expiry, from polibtls's
  `TlsCerts.CertHash` and `TlsCerts.Validity` on the certificate's
  file (libtls says nothing of a certificate outside a connection,
  found in Phase 0, so polibtls reads the file's PEM itself, in
  Oberon; decided 2026-11-18, "Open questions").
- **Never made unasked**: the specification forbids making and using a
  certificate without the user taking part, so nothing in a fetch
  makes one; a 60 comes back to the program, which asks its user and
  calls `Make`.
- **Which identity for which URL** is a program's choice, but a helper
  keeps the common rule: an identity attached to a host and a path
  prefix is offered for every URL under it (as Lagrange and Amfora
  do), in a file beside the identities.
- pogemini's `GemCert` could later use the same code; that is
  pogemini's to decide (Phase 8).

### Halt codes

The poc runtime uses 10..20, and the po* libraries 61..119
(polibfyaml 61..65, pofltk 70..78, posockets 80..89, polibtls 90..99,
pogemini 100..109, pounix 110..119). pogeminilib takes **120..129**,
unused by every po* library and program under `~/Repos/Oberon`
(checked in Phase 0: no `ASSERT` or `HALT` with one, nor a constant
for one), assigned as modules need them:

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

`GeminiPunycode` and `GeminiUrls` take only outside data, so nothing
in them halts. Each halt is an `ASSERT`, so it exits with poc's status
10 and prints `assertion failed (n)`, which the halt tests look for:
`HALT(n)` exits with status n instead, and poc refuses
`ASSERT(FALSE, n)` as always false.

### Testing

As its siblings: one main module per concern in `test/`, run from
`test/`, printing `ok   - `/`FAIL - ` through `test/Check.Mod`
(pogemini's) and a summary; halt tests as pounix's (`HALTTESTS`);
certificates made by a script into `build/certs` (polibtls's
`make-certs.sh`), never committed.

- **Unit tests** need no network: URLs (RFC 3986 section 5.4's
  resolution examples, every `GemRequest` case in pogemini's
  `TestParse`, round trips), headers (each status, each malformed form),
  gemtext (a fixture per line type, the specification's own examples,
  CR LF and LF, an unclosed preformatted block, the streaming parser fed
  the same document one byte at a time and in one piece giving the same
  lines), the trust store (in memory and in a file under
  `build/test-<name>`).
- **Client tests** need a server that can misbehave on purpose: a test
  server in `test/` (from polibtls's GeminiHello, as pogemini's
  `GemClient` was from GeminiFetch) answering by the request's path
  with a chosen fault: a bad header, a header without CR LF, a meta over
  1024 bytes, a body cut off without close_notify, a stall past the
  deadline, a redirect loop, a redirect to another host or scheme, a
  changed certificate (two key pairs), 6x when no client certificate
  is given. Run in the same program as tasks, or as a child process
  (pogemini's `test/Child.Mod`) where a test needs a separate process.
- **Interoperability**: the client against `pogemini` if installed
  (skipped, saying so, if not), and gemtext produced by
  `GeminiTextWriter` read back by `GeminiText`. Real capsules on the
  network are checked by hand, never in `make test`.
- **valgrind**: memcheck for every test, those with tasks too, since
  it follows poc's coroutines (Phase 4); not polibtls's `--tool=none`
  for them.

## Roadmap

### Phase 0: skeleton [done]

The repository: README.md (with "This software is developed with the
aid of AI.", as pogemini's), AGENTS.md, this plan, LICENSE (BSD
3-Clause, as its siblings), a GNUmakefile after pounix's (the library
built from `src/` into `build/lib`, tests against it, `make deps`
checking polibtls, posockets, poDateTime and pounix were built by the poc in
use, `install`, `uninstall`, `doc` with `doc/mkref.py`), `test/Check.Mod`.
Then, before any design depends on them:

- re-read the protocol and gemtext specifications and record their
  rules under "Gemini's requirements", with sections;
- a probe: `TlsTasks` called from the main program with no other task,
  to learn whether a tasking program's main body may fetch directly;
- whether polibtls can give a certificate file's hash and expiry
  without a connection (for `GeminiIdentities.List`);
- check the halt code range 120..129 against every po* library and
  program;
- any new question it raises, put to the user under "Open questions".

Done 2026-11-18. `make test` and `make valgrind` pass with
`TestCheck` alone, and `make install` refuses while there is no module.
Found:

- The specifications' rules are under "Gemini's requirements", and the
  design follows them: the request line in ASCII (punycode for a
  host), a status below 10 or over 69 refused, a 1x needing a prompt,
  at most 5 redirects and no query carried over, quoted `lang`
  values, a byte order mark skipped, the TLS version given, no
  identity made unasked, a link with no URL flagged.
- The build of a library: checked with a throwaway module in a copy of
  the repository: built into `build/lib`, tests linked against it,
  `make valgrind` clean, `make install` and `make uninstall` (into a
  scratch `POCLIBDIR`) putting in and taking out both variants, and a
  changed source rebuilding the library and the tests.
- `TlsTasks` from a main body with no task works (The client).
- polibtls can't give a certificate file's hash or expiry (Client
  certificates; "Open questions"). Since 2026-11-18 it can:
  `TlsCerts.CertHash` and `TlsCerts.Validity`.
- Halt codes 120..129 are free (Halt codes).
- `gmake test` passes on OpenBSD 7.9 i386 (erekose) and NetBSD 11.0
  amd64 (terhali), the dependencies from `git archive`s installed in a
  scratch `POCLIBDIR` (AGENTS.md, "Testing on the BSD hosts"); the
  library's build there waits for its first module, in Phase 1.
- posockets' `Sockets.SetDeadline` is only for `SocketTasks`; its own
  calls ignore it (read 2026-11-18), so the blocking deadline is still
  to be added. Another way, if posockets' change proves awkward:
  pounix's `UnixFiles.WaitReadable` with a `WaitWritable` added beside
  it (a connect and a TLS write wait for writable), since a pounix
  wait takes any descriptor.
- ~~poc's users' guide (section 11) says memcheck follows coroutines on
  Linux and FreeBSD, which contradicts the siblings' note that it
  can't (AGENTS.md, "Test"): to be tried with the first task test, in
  Phase 4, and the note corrected if memcheck works.~~ It works
  (Phase 4).

### Phase 1: URLs [done]

`GeminiUrls` ("URLs"), with `TestUrls`: parsing, the server's check
(pogemini's `TestParse` cases, carried over), resolution (RFC 3986
section 5.4), encoding, the request line. `GeminiPunycode`
("Internationalised host names"), with `TestPunycode`: RFC 3492's
section 7.1 sample strings both ways, ASCII lowered, each refusal,
a host that is half ASCII and half not, an IP address untouched, and
encoding then decoding giving the host back. No network.

Done 2026-11-18. `make test` (118 checks in `TestPunycode`, 191 in
`TestUrls`) and `make valgrind` pass, and `gmake test` on OpenBSD 7.9
i386 (erekose) and NetBSD 11.0 amd64 (terhali): the library's first
build on the BSDs. `doc/GeminiPunycode.md` and `doc/GeminiUrls.md`
written by `make doc`. Found:

- poc passes the bytes of a string literal through unchanged, so UTF-8
  literals in a test are UTF-8 at run time (checked with a throwaway
  program).
- RFC 3492's samples were taken from the RFC's text by a script, and
  each encoding also checked against Python's punycode codec; they
  agree but for (I), whose one upper-case letter is the RFC's
  "mixed-case annotation". In decoding, the RFC's check that a decoded
  code point isn't basic can never fail (n starts at 128 and only
  grows), so it was left out.
- RFC 3986 section 5.4's 42 examples were likewise taken from the
  RFC's text; all pass, `http:g` as a strict parser gives it. By
  section 5.2.2 an empty reference keeps the base's path as it is,
  dots and all; only a merged or given path has its dots removed.
- `CheckRequest` is pogemini's `GemRequest.Parse` with one fix:
  pogemini copies an IPv6 literal into the 256-byte host without
  checking its length, and `gemini://[` with 300 hex digits `]/` halts
  it with "index out of range" (checked with a throwaway program
  against pogemini's source): a request from any client stops the
  server. Here it is "a malformed IPv6 address". Fixed in pogemini the
  same way, with its tests (its PLAN.md, "A long IPv6 literal").
- A link in a page may hold what RFC 3986 doesn't allow (`|`, `{`,
  `\`, a non-ASCII character): `Parse` keeps it, and `RequestLine`
  percent-encodes it, so only a space or a control character, which
  can't be in a link at all, is refused.

### Phase 2: gemtext [done]

`GeminiText` and `GeminiTextWriter` ("Gemtext"), with `TestText`: each
line type, the streaming parser equal to the whole-document one however
the input is cut and whatever its buffer's size (a line's pieces joined),
lines many times the buffer's size, a UTF-8 sequence at a piece's end,
a link's URL longer than the first piece, malformed UTF-8 kept and flagged, the writer's output
read back. No network; before the client, since it needs nothing of
it and a program can use it at once (rendering files from disk).

Done 2026-11-18. `make test` (121 checks in `TestText`, and the four
halt tests 120..123) and `make valgrind` pass, and `gmake test` on
OpenBSD 7.9 i386 (erekose) and NetBSD 11.0 amd64 (terhali).
`doc/GeminiText.md` and `doc/GeminiTextWriter.md` written by `make
doc` (whose `mkref.py` no longer shows a private record after an
exported pointer to it). Decided and found:

- The design changed where "Gemtext" now says: `Feed` and `Next` one
  call; the URL in a buffer of its own, so `MinBuffer` is 8, not 2048;
  a label's trailing whitespace kept; `Link` writing a URL as given and
  `NameLink` encoding a name.
- The tests check every piece: none but a line's last shorter than the
  buffer less four, url and its flags on the first piece only,
  `malformed` equal to whether the joined line is UTF-8; and that the
  pieces joined are `Parse`'s lines, for buffers of 8 to 24 bytes and
  then doubling to 6000, the page fed in chunks of 1, 2, 3, 5, 7, 64,
  1000 bytes and whole, and every split of a short page in two.
- A BOM is skipped only as the page's first three bytes (a page of
  only one has no lines); CR CR LF is a line of one CR; a 0X byte is
  kept, so `len`, not the 0X, is a line's length; a closing toggle's
  rest is dropped, an opening one's alt text kept as written.
- poc has no `+` for string constants ("operands must both be numeric
  or both SET"); the writer writes a marker and the text by separate
  `Put`s.
- **valgrind and a stack record's padding**: copying a whole `Line`
  from the stack into a heap array carries its uninitialised padding
  there, and poc's collector then reads it, which memcheck reports in
  `GarbageCollectedHeap.DrainMarkStack` (45384 errors; `poc-gc.supp`
  covers only `MarkCandidate`). Found with `--track-origins`; fixed by
  copying field by field (`GeminiText.Add`, the test's `Take`).
- Mutations of the parser (no cut at the buffer's end, a CR dropped,
  the carried bytes lost, url flags on later pieces, no BOM skip, the
  lookback's test changed) each failed the tests; the one that
  survived, the lookback loop's bound, gives the same result.

### Phase 3: headers and statuses [done]

`GeminiStatus` and `GeminiHeaders`, with `TestHeaders`: every status,
the class of an unknown one, every malformed header, MIME types and
parameters, `WriteHeader`'s checks as halt tests.

Done 2026-11-18. `make test` (165 checks in `TestHeaders`, and the six
halt tests 124..126) and `make valgrind` pass, and `gmake test` on
OpenBSD 7.9 i386 (erekose) and NetBSD 11.0 amd64 (terhali).
`doc/GeminiStatus.md` and `doc/GeminiHeaders.md` written by `make
doc`. Decided and found:

- The design changed where "Responses" now says: `ParseHeader` is
  `Parse`, with `Ended` to say when a client has read enough;
  `Mime` is `ParseMime`, with `Is`, `Param` and `Charset`; the
  record of a parameter is `Parameter` (poc refuses a type and a
  procedure of one name).
- `WriteHeader` is stricter than `GemServer.Header`: a status the
  specification doesn't name, and every meta `Parse` refuses, halt.
- The empty redirect, which the specification calls "not intended to
  be valid", is refused by `Parse`, so the client never sees one.
- A bare LF ends no header: the grammar says CRLF, and accepting LF
  alone would let a header's end differ between this client and
  others. Bytes after the LF in what `Parse` is given are refused,
  since the client gives it exactly `Ended`'s `n`.
- On refusal `h.status` is 0 and `h.meta` empty, so nothing of a bad
  header is acted on by mistake.
- Mutations of the parsers (no C1 check, the C1 bound, `Ended`'s
  bound, a third digit allowed, the meta's length unchecked, an empty
  redirect allowed, no backslash escape, no space after `=`, junk after
  a value, the meta kept on refusal, and `SkipParam`'s quote and escape
  tracking) each failed the tests, by a `FAIL` or, for the meta's
  length, an index halt; the last two needed tests added for a `;`
  and an escaped quote inside a skipped parameter's quotes.

### Phase 4: the client [done]

`GeminiClient` without trust (nothing checked, or a CA file) and without
redirects: connect with a deadline, SNI, a client certificate, the
header, the body as a stream and whole, `complete` and `truncated`.
Tests: the misbehaving test server (`test/TestServer.Mod`), IPv4 and
IPv6, each fault, several fetches at once in tasks, a stalled server not
holding up the others; then pogemini, if installed. Then `GeminiFetch`,
the blocking API, after the deadline it needs is added to posockets
(in posockets's repository, with its tests, and reinstalled), passing
the same tests against the test server, run from a program with no
tasks. An example, `examples/GeminiGet.Mod`, a small gemget, on
`GeminiFetch`, and one fetching several URLs at once on
`GeminiClient`.

Done 2026-11-18, after posockets' `Sockets.Await` and `ConnectWithin`.
`make test` (`TestFetch` 55 checks, `TestClient` 62, and halt tests
127 and 128) and `make valgrind` pass, and `gmake test` on OpenBSD 7.9
i386 (erekose) and NetBSD 11.0 amd64 (terhali, with pogemini's checks
too), posockets' working tree installed there. `doc/GeminiResponses.md`,
`doc/GeminiClient.md` and `doc/GeminiFetch.md` written by `make doc`. `GeminiResponses`,
`GeminiClient` and `GeminiFetch`; `test/TestServer.Mod`, the
misbehaving server (its comment lists each fault), run by
`test/Server.Mod`; `test/ClientCases.Mod`, the checks both APIs run,
given a fetch procedure; `test/Child.Mod`, for a program run as a
child; `test/make-certs.sh`, polibtls's, making the certificates into
`build/certs`. Decided and found:

- **poc 0.14.0's collector frees an empty record's object while it is
  still reachable**, on 64-bit hosts: an object's data starts after
  its block's header, and a record with no fields has a block of only
  that header (16 bytes on amd64), so a pointer to its data points at
  the next block, which is marked instead. The object is swept, and a
  method call on it later crashes. On i386 the header is 8 bytes of a
  16-byte block, so the data stays inside it. `GeminiResponses`'
  abstract `WaiterDesc` was such a record; it has a field
  (`notEmpty`) until poc is fixed. A program of 20 lines shows it
  (an empty record kept in a global, collections forced by garbage:
  its block's header then reads free, and a method call on it
  segfaults); the bug is poc's (`GarbageCollectedHeap`,
  `FindBlock` and `BlockBytesFor`), recorded as bug 28 in
  Peaseblossom's PLAN.md, "Ongoing bug fixing".
- **A fetch's stack**: one with an RSA client certificate and a CA
  file ran in a 24 KiB task stack on amd64 and not in 16 KiB, the TLS
  handshake being the most of it, so `GeminiClient.stackSize` is 64
  KiB, as `TlsTasks.stackSize`. ClientCases' own arrays need more:
  `TestClient` runs it in 1 MiB.
- **memcheck follows poc's coroutines**, as the users' guide says, and
  not as the siblings' notes say, which predate poc's fix of
  2026-11-15 (Peaseblossom's PLAN.md, bug 21): a control that branched on
  uninitialised `malloc`'d memory and read freed memory, in the main
  body and again in a task, had all four errors reported, the task's
  with a stack ending at the task's start. So `make valgrind` runs
  every test, `TestClient` too, under full memcheck. valgrind 3.27.1
  counts a descriptor open at exit as an error, and Tasks' self-pipe
  is two, so no `--error-exitcode`: `test/vg-errors.sh` requires that
  every error be such a descriptor, which `vg-fds.sh` then judges.
  (A first control, reading uninitialised locals, showed nothing in
  main or in a task: they read as zero, so it proved nothing.)
- `test/vg-reachable.sh` allows, besides the collector's and the
  loader's, what polibtls's allows: memory allocated within
  `tls_init` and OpenSSL's caches, kept for the process's life
  (valgrind with `--num-callers=60` to see `tls_init` in a stack).
- The checks: each fault of `TestServer`'s as its error kind, with
  what came before it kept; a stalled header and a stalled body timing
  out at the deadline; IPv4 and IPv6; SNI sent for a name and not for
  an address; a client certificate seen by the server; a CA file that
  verifies and one that doesn't; `maxBody`; closing early; a refused
  connection, a name that doesn't resolve, URLs that can't be fetched.
  In tasks, four fetches of 300000 bytes ending whole while a fifth,
  stalled, waits, and that one timing out at its own deadline.
- pogemini, installed, served a page, a 100000-byte file and a 51 to
  `GeminiClient`, and exited 0 after its three connections.
- The examples are run by the tests: `GeminiGet` (a body of 100000
  bytes with a CA file, a 51's exit, a stalled body's partial output
  and "timed out", bad usage) from `TestFetch`; `GeminiFetchAll`, with
  a stalled URL among others, ending in about its deadline, from
  `TestClient`.

### Phase 5: trust, redirects and identities [done]

First, in polibtls's repository, with its tests, and reinstalled: the
peer's public-key hash (Trust), and a certificate file's hash and
expiry (Client certificates); done 2026-11-18, `PeerKeyHash`,
`TlsCerts.CertHash` and `TlsCerts.Validity`. Then
`GeminiTrust` (TOFU, its file,
the expiry rule) and `FetchFollowing`, with `TestTrust` and
`TestRedirects`: first contact, the same certificate, a renewed one
with the same key passing, a new key refused before the request is
sent, unreadable and unknown-algorithm lines kept on rewrite,
an expired one replaced only if the policy says so; a redirect followed,
relative and absolute, a loop, too many, another scheme, another host
asked about. `GeminiIdentities`, with `TestIdentities`: an identity
made, listed with its hash, used for a request the test server sees it
on (its hash as the server's log shows it), the files' modes, a name
that would escape the directory refused, no `openssl` on `PATH`
reported; made with the OpenSSL and LibreSSL of each host. `GeminiGet`
gains `-known-hosts` and `-identity`.

Done 2026-11-18: `GeminiTrust`, `FetchFollowing` (in
`GeminiResponses`, given a waiter, and in `GeminiClient` and
`GeminiFetch`), `GeminiIdentities`; `TestTrust`, `TestRedirects`,
`TestIdentities`, `GeminiGet`'s new options run from `TestFetch`, and
halt test 129 (`HaltTrustStore`). `make test` and `make valgrind`
pass on Linux, and `gmake test` (pogeminilib's and pounix's) on alerik
(FreeBSD amd64, OpenSSL 3.5.6), artos and yishana (NetBSD amd64 and
i386, OpenSSL 3.5.7) and jherek and cymoril (OpenBSD amd64 and i386,
LibreSSL 4.3.0), identities made with each one's `openssl`. Decided
and found:

- **pounix gained what the files needed** (its Phase 9, in its
  repository, with its tests, and reinstalled): `UnixFiles.OpenWrite`
  with create, truncate, exclusive and append and a mode, `Write`,
  `Sync`, `Rename`, `Remove`, `ModeOf`. poc's `Files` would not do:
  it halts (99) when it can't create or rename a file, and outside
  data never halts here.
- **NetBSD's read(2) of a directory gives its entries** (512 bytes of
  them, on NetBSD 11.0, where `cat` of a directory prints them), not
  EISDIR as Linux, FreeBSD and OpenBSD: a directory named as the known
  hosts or scopes file was read as a file of junk lines. So both
  readers try `UnixFiles.OpenDirectory` on the path first and refuse
  a directory themselves (found by `gmake test` on artos and yishana).
- **`UnixFiles.NextName` ends a directory with `TRUE` and the name
  `""`**, not `FALSE` (`FALSE` is an error): a first loop on `FALSE`
  alone never ended.
- **A save is whole, at once**: each change to a known hosts or
  scopes file writes the file to `<path>.<pid>.<n>.tmp`, created
  exclusively with mode 600 (another name tried while one exists, at
  most 100), synced and renamed over it. If that fails the change is
  undone in memory and the caller gets `FALSE` (trust: `failed`,
  error `untrusted`) with the reason, so memory and file agree.
- **The known hosts file**: `<host>:<port> spki-sha256 <hex>
  <notAfter>`, the host lowercase ASCII, an IPv6 address in brackets;
  fields separated by blanks or tabs, CR LF accepted; a NUL read as a
  blank; a file over 4 MiB, or a directory, refused. A response's
  `trust` is what the store's `Check` said, or -1 if none was asked.
  A changed key is refused before the request is sent: the test
  server's `/count` says how many requests it has read.
- **Redirects**: error kind `redirect` for one not followed (too many,
  a loop, another scheme, another host refused, a location that won't
  resolve). The empty location never reaches `FetchFollowing`:
  `GeminiHeaders` already refuses a 3x with no URL, as a malformed
  header. A loop is a URL fetched before in the chain, compared as
  written by `GeminiUrls.Write`; another host is another host or
  port, and asks the `RedirectPolicy`, `NIL` refusing. The URLs are
  on the heap (3.4 KB each), not a task's stack. The test server
  gained `/count`, `/r/to?<location>`, `/r/self` and `/r/chain/<n>`.
- **Identities**: `Make(dir, name, commonName, days, ...)`, the name
  1..64 of letters, digits, `.`, `_`, `-`, not starting with `.`
  (so never a path), the common name printable ASCII without `/`,
  `\`, `+` or `=` (which `-subj` reads), the days 1..36500,
  `DefaultDays` 7300; the script is `GemCert`'s without a
  subjectAltName and with the CN and days as arguments. Exit 127
  means no `openssl`, checked by the test running itself with `PATH`
  empty of it. `List` passes over a `.crt` it can't read or with no
  `.key`; `Load` says which. `Use` puts one in a fetch's options.
- **Scopes** (`OpenScopes`, `Attach`, `Detach`, `For`): a file the
  program names, `<name> <host>:<port> <path>` a line, other lines
  kept; `For` offers the attachment with the longest path that the
  URL's is, or is below on a segment boundary (`/app` covers `/app`
  and `/app/x`, not `/apple`), no path meaning `/`.
- `GeminiGet`: `-known-hosts file` and `-identity dir/name`; it now
  shows the server's key's hash, not the certificate's, when nothing
  is checked, as that is what is pinned.

### Phase 6: an example browser [done]

`examples/GeminiBrowse.Mod`: a line-mode browser (numbered links, input
for 1x, back, the trust store), showing how the modules fit together,
and finding what an API lacks before it is installed for others. Not
installed, as polibtls's examples aren't.

Started 2026-11-18. The browser reads a command a line from standard
input (`<n>`, `g`, `b`, `r`, `p`, `l`, `i`, `trust`, `save`, `id`,
`id new`, `id use`, `id off`, `q`), and when that isn't a terminal it
echoes each after its prompt, so a test's transcript reads as a
session. `TestBrowse` drives it so, against new pages on `TestServer`
(`/page`, a line of each kind; `/ask`, `/secret`; `/private`, 60
without a certificate; `/plain`, `/latin1`, `/bin`).

What it found:

- **Where an identity is attached**: `Scopes.For` says which identity
  covers a URL but not at what path, which `id off` on a page beneath
  needs for `Detach`. Added `Scopes.Covering`, with checks in
  `TestIdentities`.
- **Trusting a changed key** needed the store's own name for the host:
  the program repeated `GeminiPunycode.ToAscii(r.url.host)` and
  `GeminiUrls.Port`, as `GeminiResponses` does, a second place that
  had to agree with the first. Decided 2026-11-18 (the user): `Response`
  gives them, `host` (the URL's host in ASCII, as connected to and as
  the store knows it) and `port` (1965 if the URL gave none), "" and 0
  if the fetch failed before; `Open` already worked them out, so they
  cost no time, only about 260 bytes a `Response`. The browser trusts
  `r.host` and `r.port`; `ClientCases` checks them for both fetchers.
- **Input not echoed (status 11)**: the library had no call to turn a
  terminal's echo off, and the browser ran `stty -echo` through
  `UnixProcesses`. pounix gained `UnixTerminals` for it (its Phase 10:
  `IsTerminal`, `Echo`, `SetEcho`, and `OpenPseudo` for tests), and
  `ReadSecret` uses `SetEcho`, saying so first if echo won't go off.
  Checked by hand in a terminal (tmux), 2026-11-18: the answer not
  shown, echo back on after. `TestBrowse` can't check it, since
  `Child` gives the browser pipes, not a terminal. What is typed
  before the prompt appears was echoed as it came (pounix's `TCSANOW`).
- **A gemtext quote keeps the whitespace after `>`** (by design, as
  GeminiText says), so a program showing it as "> " plus the text
  doubles the space; the browser leaves out its own space then. A link
  with no URL (`noUrl`) has no text either; the browser leaves it out.
- **`-identities` for a directory not there**: `OpenScopes` and
  `List` both take a missing file or directory for none yet, so the
  browser checks with `UnixFiles.OpenDirectory` itself.
- **The BSDs**: `gmake test` passed on FreeBSD, NetBSD and OpenBSD,
  amd64 and i386 (alerik, artos, yishana, jherek, cymoril), 2026-11-18:
  876 ok each, no FAIL, no core files, and the only `assertion failed`
  the 13 halt tests'. 6 fewer than Linux since pogemini isn't installed
  there and its checks are skipped. The dependencies from their
  committed heads (polibtls d935372, pounix 5bc0c24).
- **memcheck, open, to investigate later** (the user, 2026-11-18:
  leave it open for now): `make valgrind` is clean, `TestBrowse` with it,
  but that doesn't follow the browser, its child. Run directly under
  memcheck through a scripted session, the browser shows 2 "use of
  uninitialised value of size 8" in `GarbageCollectedHeap.DrainMarkStack`,
  the value from a stack allocation in `GeminiBrowse.Visit`; no leaks,
  no descriptors left open. Deterministic, and it takes the session
  `l`, `1`, `hello` (an input page), `b`, `2` (a redirect); any part
  alone shows none. Not explained yet. Ruled out by experiment: Visit's
  character arrays (cleared, no change), its pointer locals `p` and
  `r` (set to NIL, no change), and the whole-record copy `p.url :=
  r.url` (a field-by-field copy, no change).

### Phase 7: the BSDs [done]

`gmake test` on FreeBSD, NetBSD and OpenBSD, amd64 and i386, as
pogemini's Phase 7 and AGENTS.md, "Testing on the BSD hosts"; anything
Linux-only fixed here and the finding recorded in AGENTS.md. Each
networked phase before this is run on at least one BSD host as it
finishes, so nothing waits until here to be found.

Done that way: every phase was run on the BSDs as it finished (Phases
1 to 4 also on erekose and terhali), so nothing was left for here, and
nothing Linux-only turned up. Closed 2026-11-18, after `Response`'s
`host` and `port` (Phase 6, "What it found"), with `gmake test` run
again on all five VMs (alerik, artos, yishana, jherek, cymoril):
exit 0, 884 ok each, Linux's 890 less the 6 that need pogemini
installed, with the dependencies' HEADs (pounix fd77666, polibtls
d935372).

### Phase 8: the server engine

`GeminiServer`, moved from pogemini's `GemServer`, with a log procedure
in place of its log line, `GeminiHeaders.WriteHeader` for its header,
and `GeminiTextWriter` for a responder's pages. Its tests, from
pogemini's `TestServe` and `TestRun`, move with it. Then, in pogemini's
own repository and plan: `GemServer` replaced by `GeminiServer`,
`GemRequest` by `GeminiUrls.CheckRequest`, the listing's writing by
`GeminiTextWriter`, and `make test` passing there on Linux and every
BSD host before the change is kept; pogeminilib becomes one of its
`DEPLIBS`. This library's client tests may then use `GeminiServer` for
their test server.

### Phase 9: documentation and install

README.md as the user's guide (requirements, building, installing, an
example per module), `doc/<Module>.md` generated by `doc/mkref.py` from
the exported declarations and their comments (committed, as pounix's),
`make install` checked on Linux and the BSDs, the halt codes in the
README.

## Open questions

- ~~**Should pogeminilib include the server engine**?~~ Yes (the user,
  2026-11-18): Phase 8.
- ~~**Names**: the library `pogeminilib`, the modules `Gemini*`?~~ Yes
  (the user, 2026-11-18).
- ~~**Client certificates**: should the library make them?~~ Yes (the
  user, 2026-11-18): `GeminiIdentities`, Phase 5.
- ~~**A blocking API** for programs that don't use `Tasks`?~~ Yes, a
  separate one (the user, 2026-11-18): `GeminiFetch`, Phase 4.
- ~~**The known-hosts format**~~: our own, the public key pinned, the
  path always the program's (the user, 2026-11-18; Trust).
- ~~**The blocking API's deadline**~~: a `poll` with a deadline added to
  posockets (the user, 2026-11-18; The client).
- ~~**Internationalised host names**~~: level 1, punycode only, in its
  own module, `GeminiPunycode` (the user, 2026-11-18; Phase 1). The
  levels considered: (1) punycode alone; (2) that plus UTS #46's
  mapping (case folding, NFC), which needs tables generated from
  Unicode's data files; (3) full IDNA2008 validity (RFC 5891..5893),
  more tables still. libidn2 would do (3) but is C and in no BSD's
  base system; glibc's `AI_IDN` is Linux-only.
- ~~**Charsets other than UTF-8** in a 2x's `charset`~~: reported and
  the bytes passed on, nothing converted (the user, 2026-11-18).
- ~~**A limit on a gemtext line's length**~~: none; a long line comes
  out in pieces of the parser's buffer's size (the user, 2026-11-18;
  Gemtext).
- ~~**An identity's hash and expiry from its file**, for
  `GeminiIdentities.List` (found in Phase 0; needed in Phase 5). Either
  (a) polibtls gains it in the same change as the peer's public-key
  hash, which needs libcrypto's certificate parsing anyway: a
  certificate file's hash, as `PeerCertHash` gives it, and its
  `notAfter`; or (b) `List` runs `openssl x509 -fingerprint -sha256
  -enddate`, as `Make` runs `openssl`, and reads its output, as
  pogemini's TestCerts does. (a) is recommended: listing needs no
  program on `PATH` and no output format to parse, and the same code
  is tested on every host polibtls is. Since 2026-11-18 (a) is half
  there without libcrypto: `TlsCerts.CertHash` gives a certificate
  file's hash as `PeerCertHash` does; its `notAfter` would be one more
  step of the same DER walk (validity's UTCTime or GeneralizedTime, to
  Unix seconds), in `TlsCerts`.~~ (a) (the user, 2026-11-18; Client
  certificates): polibtls's `TlsCerts.CertHash` and
  `TlsCerts.Validity` (notBefore and notAfter in Unix seconds, from
  PEM text; RFC 5280's UTCTime and GeneralizedTime), in Oberon, tested
  against openssl on every test certificate (polibtls's PLAN.md, "A
  certificate's validity"). `List` reads the certificate file and
  passes its text; no `openssl` at run time, no C.
