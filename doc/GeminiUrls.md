# GeminiUrls: URLs: parsed, checked, resolved and written

<!-- Made by doc/mkref.py from GeminiUrls.Mod; edit the source, then make doc. -->

Two views of a URL. A client's (Parse, Resolve, Write, WithQuery, RequestLine) is lenient, since links in a page are what their authors wrote: any scheme, userinfo, a fragment, and any character but a space or a control character, kept as written. A server's (CheckRequest) is strict: pogemini's GemRequest, carried over, which refuses what the Gemini specification says a server must, and gives the path decoded and normalised, ready to be looked up.

A URL may hold non-ASCII characters as UTF-8, as an IRI (RFC 3987) does; malformed UTF-8 is refused. What goes on the wire is ASCII (the specification's "absolute-URI" is RFC 3986's): RequestLine percent-encodes the rest of the path and query, and gives the host as GeminiPunycode.ToAscii does.

Every URL is at most MaxURL bytes, as a request's must be: a longer one could never be fetched. Nothing here halts: what can't be done gives FALSE (or a status) and the reason in why.

## Constants

```oberon
MaxURL* = 1024;      (* a URL at most, by the specification *)
DefaultPort* = 1965;
NoPort* = -1;        (* a URL with no port: Port gives the scheme's *)
Ok* = 0;
BadRequest* = 59;    (* not a URL, or one the specification forbids *)
Refused* = 53;       (* not a gemini: URL *)
```

## Types

```oberon
Text* = ARRAY MaxURL + 1 OF CHAR;
```

```oberon
URL* = RECORD
  scheme-: ARRAY 64 OF CHAR;
  hasAuthority-: BOOLEAN;     (* a "//", so a host, even an empty one *)
  hasUserinfo-: BOOLEAN;
  userinfo-: ARRAY 256 OF CHAR;
  host-: ARRAY 256 OF CHAR;
  port-: LONGINT;             (* NoPort if none was given *)
  path-: Text;                (* "" for none *)
  hasQuery-: BOOLEAN;         (* a "?", perhaps with nothing after *)
  query-: Text;
  hasFragment-: BOOLEAN;
  fragment-: Text
END;
```

A URL, as Parse or Resolve gives it: each part as written (path, query and fragment still percent-encoded) but the scheme and host, which are lower case, and the host, which is decoded, with no brackets round an IPv6 address and no "." at its end.

```oberon
Request* = RECORD
  scheme-: ARRAY 64 OF CHAR;  (* lower case *)
  host-: ARRAY 256 OF CHAR;   (* lower case, decoded, with no
  port-: LONGINT;             (* DefaultPort if none was given *)
  path-: Text;                (* decoded and normalised: CheckRequest *)
  rawPath-: Text;             (* as sent, "" for none *)
  hasQuery-: BOOLEAN;         (* there was a "?", perhaps with nothing after *)
  query-: Text                (* after the "?", as sent *)
END;
```

A request, as CheckRequest gives it: a server's view.

## Procedures

#### Utf8

```oberon
PROCEDURE Utf8*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
```

s[0..n-1] is well-formed UTF-8 (RFC 3629): no overlong forms, no surrogates, nothing over U+10FFFF.

#### Decode

```oberon
PROCEDURE Decode*(s-: ARRAY OF CHAR; VAR d: ARRAY OF CHAR; VAR n: LONGINT): BOOLEAN;
```

Decodes s's percent-encoding (a query's, say) into d: FALSE if a "%" isn't followed by two hex digits, or the result doesn't fit d. The result may contain any byte, 0X included, so n is its length.

#### Encode

```oberon
PROCEDURE Encode*(s-: ARRAY OF CHAR; VAR out: ARRAY OF CHAR): BOOLEAN;
```

Percent-encodes s, to its 0X, into out: every byte but RFC 3986's unreserved (letters, digits, "-", ".", "_", "~"), so a space is "%20" and a line feed "%0A", as the specification asks of an input answer. FALSE, out empty, if it doesn't fit out.

#### Parse

```oberon
PROCEDURE Parse*(s-: ARRAY OF CHAR; VAR u: URL; VAR why: ARRAY OF CHAR): BOOLEAN;
```

Parses s, an absolute URL with any scheme, into u: FALSE, with why, if it is over MaxURL bytes, has no scheme, has a space or control character or malformed UTF-8, or its host or port is malformed. Nothing else is checked: Gemini's rules are RequestLine's.

#### Port

```oberon
PROCEDURE Port*(VAR u: URL): LONGINT;
```

u's port, or the scheme's if it has none: 1965 for gemini, else NoPort.

#### Write

```oberon
PROCEDURE Write*(VAR u: URL; VAR s: ARRAY OF CHAR): BOOLEAN;
```

Writes u back as text, by RFC 3986 section 5.3, into s: FALSE, s empty, if it doesn't fit. The host is written as Parse keeps it (so not as punycode: RequestLine does that).

#### Resolve

```oberon
PROCEDURE Resolve*(VAR base: URL; ref-: ARRAY OF CHAR; VAR u: URL;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

Resolves ref, a URL or a relative reference, against base, by RFC 3986 section 5.2.2, into u (which may be base itself): FALSE, with why, u empty, if ref is malformed or the result is over MaxURL bytes. ".." never climbs above the root.

#### WithQuery

```oberon
PROCEDURE WithQuery*(VAR u: URL; answer-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
```

Sets u's query to answer, percent-encoded as Encode does, for the answer to an input prompt (status 10 or 11), and drops u's fragment, which named a place in the prompt's page, not the answer's. FALSE, u unchanged, if the encoded answer won't fit.

#### RequestLine

```oberon
PROCEDURE RequestLine*(VAR u: URL; VAR line: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
```

The request for u, in line, without its CR LF: u as an absolute URI in ASCII, at most MaxURL bytes, with no fragment, as the specification's "Requests" says: the host as GeminiPunycode.ToAscii gives it, an empty path as "/", and the path and query with non-ASCII and what RFC 3986 doesn't allow percent-encoded. FALSE, with why, line empty, if u has no host or has userinfo (which Gemini forbids), its host can't be converted, or the result is over MaxURL bytes or doesn't fit line.

### The server's check.

#### CheckRequest

```oberon
PROCEDURE CheckRequest*(url-: ARRAY OF CHAR; VAR r: Request; VAR why: ARRAY OF CHAR): INTEGER;
```

Checks url, a request line without its CR LF, as a server must (pogemini's GemRequest): Ok, with r filled in, or BadRequest or Refused, with the reason in why, for the response's meta.

A request is an absolute URI, at most 1024 bytes (the specification, "Requests"). Refused with BadRequest (59): what the specification says a server must reject (a URL over 1024 bytes, userinfo, a fragment) and what is not a URL at all; with Refused (53), a scheme other than gemini. Whether the host and port are this server's is the caller's to say. Besides RFC 3986's characters, non-ASCII as UTF-8 is taken, as an IRI's, since some clients send it.

r.path is decoded and normalised, ready to be looked up: each segment percent-decoded, "." and ".." resolved after decoding (so "%2E%2E" is ".." too), empty segments dropped, always beginning with "/" (an empty path is "/"). A ".." that would climb above "/", or a segment that decodes to "/", a control character or malformed UTF-8, is refused (59): none names a file a server should serve, and refusing them here means no later code has to remember to. A trailing "/" is kept: the client asked for a directory. The query is left as sent: Decode decodes it.
