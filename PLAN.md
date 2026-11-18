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
  beyond poc's `Files`.
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
  digits and CR LF; a space and the meta after it, which 1x and 2x
  must have (`prompt = 1*(SP / VCHAR)`, `mimetype`) and 4x, 5x and 6x
  may leave out (`"50" CRLF` is whole; P's last example). No C0 or C1
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
  grammar allows whitespace after the label, which the parser drops.
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
| `GeminiTextWriter` | gemtext written, a line at a time, links percent-encoded |
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

- `ParseHeader(line, h, why)`: status, meta, and refusal of what the
  specification forbids (no space, a third digit, a status below 10 or
  over 69, a 1x without a prompt, a control character in the meta,
  meta over 1024 bytes, a byte order mark, no CR LF within 1029
  bytes). An unknown status within 10..69 is kept, and `Class` gives
  its first digit's. A bad header is an error the program sees, never
  a halt.
- `Mime(meta, type, params)`: type and subtype lower case, parameters
  as name and value, a quoted value (`lang="en,fr"`) unquoted;
  `text/gemini; charset=utf-8` when a 2x's meta is empty, which 0.24.1
  forbids but servers still send ("Gemini's requirements",
  "Success").
- `WriteHeader` for a server, with the checks `GemServer.Header` makes
  (status 10..69, meta at most 1024 bytes), so `GeminiServer` uses it.

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
- **Errors** are a record of kind (`resolve`, `connect`, `tls`,
  `untrusted`, `changed`, `header`, `truncated`, `timedOut`, `tooLong`)
  and text, as polibtls's `Error`; outside data never halts.

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
  before Phase 5. How (libtls's `tls_peer_cert_chain_pem` and
  libcrypto, with both OpenSSL's libtls and LibreSSL's) is to be
  verified there; the result written `SHA256:` and lowercase hex, as
  `PeerCertHash` is, and checked against `openssl x509 -pubkey | openssl
  pkey -pubin -outform DER | openssl dgst -sha256`.
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
  marker and the whitespace the specification says to drop), and for a
  link its URL as written and its label (empty if none).
- **A streaming parser**: a `Parser` keeps the preformatting state and
  any part line, takes bytes as they come (`Feed(buf, pos, len)`) and
  hands out each line (`Next(l)`), and `Finish` the last line without
  an end; so a client parses a body as `GeminiClient` reads it. Line
  ends LF or CR LF; a lone CR is left as text.
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
  place it may wrap.) A link's URL must lie within its first piece; one that
  doesn't is cut there and flagged (`urlTooLong`), the rest of it
  dropped and the label, if any, coming in the later pieces as usual:
  a request is at most 1024 bytes, so no URL that long can be fetched
  anyway, and the size of a buffer may not be less than 2048 (a halt
  if it is). A renderer that wraps text needs nothing more; one that
  wants whole lines joins the pieces, or uses `Parse`.
- **The minimum buffer and the piece flags are to be confirmed in
  Phase 2** by the tests: the concatenation of a line's pieces equal
  to the line `Parse` gives, however the input is cut and whatever the
  buffer's size.
- **A document**: `Parse(text)` gives a list of `Line`s, for a program
  that has the whole page; a `Document` can say its first heading (a
  title) and its links.
- **No resolution in the parser**: a link's URL is kept as written; the
  program resolves it with `GeminiUrls.Resolve`, so `GeminiText` needs
  nothing but itself.
- **Malformed input never halts**: bytes that aren't UTF-8 are kept as
  they are and reported by a flag, not refused; a renderer decides.
- **The writer** writes each line type to a `Files.Rider`, or through a
  procedure a server's `Exchange` provides, encoding a link's URL as
  pogemini's listings do (all but RFC 3986's unreserved), and it can't
  be made to write a text line another kind would claim (a text line
  beginning `=>`, `#`, `* `, `>` or ```` ``` ````): gemtext has no
  escape, so the writer says so (`FALSE`), and the program chooses.

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
  a server's log shows it) and expiry. **polibtls can't read them
  from a file** (checked in Phase 0: libtls loads a pair into a
  `Config` but says nothing of a certificate outside a connection, and
  polibtls has no other access): see "Open questions".
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

None yet: `GeminiPunycode` and `GeminiUrls` take only outside data,
so nothing in them halts.

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
- **valgrind** as polibtls's: `--tool=none --track-fds=yes` for
  programs with tasks, memcheck for the unit tests.

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
  certificates; "Open questions").
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
- poc's users' guide (section 11) says memcheck follows coroutines on
  Linux and FreeBSD, which contradicts the siblings' note that it
  can't (AGENTS.md, "Test"): to be tried with the first task test, in
  Phase 4, and the note corrected if memcheck works.

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

### Phase 2: gemtext

`GeminiText` and `GeminiTextWriter` ("Gemtext"), with `TestText`: each
line type, the streaming parser equal to the whole-document one however
the input is cut and whatever its buffer's size (a line's pieces joined),
lines many times the buffer's size, a UTF-8 sequence at a piece's end,
a link's URL longer than the first piece, malformed UTF-8 kept and flagged, the writer's output
read back. No network; before the client, since it needs nothing of
it and a program can use it at once (rendering files from disk).

### Phase 3: headers and statuses

`GeminiStatus` and `GeminiHeaders`, with `TestHeaders`: every status,
the class of an unknown one, every malformed header, MIME types and
parameters, `WriteHeader`'s checks as halt tests.

### Phase 4: the client

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

### Phase 5: trust, redirects and identities

First, in polibtls's repository, with its tests, and reinstalled: the
peer's public-key hash (Trust). Then `GeminiTrust` (TOFU, its file,
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

### Phase 6: an example browser

`examples/GeminiBrowse.Mod`: a line-mode browser (numbered links, input
for 1x, back, the trust store), showing how the modules fit together,
and finding what an API lacks before it is installed for others. Not
installed, as polibtls's examples aren't.

### Phase 7: the BSDs

`gmake test` on FreeBSD, NetBSD and OpenBSD, amd64 and i386, as
pogemini's Phase 7 and AGENTS.md, "Testing on the BSD hosts"; anything
Linux-only fixed here and the finding recorded in AGENTS.md. Each
networked phase before this is run on at least one BSD host as it
finishes, so nothing waits until here to be found.

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
- **An identity's hash and expiry from its file**, for
  `GeminiIdentities.List` (found in Phase 0; needed in Phase 5). Either
  (a) polibtls gains it in the same change as the peer's public-key
  hash, which needs libcrypto's certificate parsing anyway: a
  certificate file's hash, as `PeerCertHash` gives it, and its
  `notAfter`; or (b) `List` runs `openssl x509 -fingerprint -sha256
  -enddate`, as `Make` runs `openssl`, and reads its output, as
  pogemini's TestCerts does. (a) is recommended: listing needs no
  program on `PATH` and no output format to parse, and the same code
  is tested on every host polibtls is.
