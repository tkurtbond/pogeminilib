# GeminiResponses: a request made and its response read, waiting through a Waiter

<!-- Made by doc/mkref.py from GeminiResponses.Mod; edit the source, then make doc. -->

What GeminiClient (in tasks) and GeminiFetch (blocking) share: a request's Options, the Response read through it, and its Error, and every step of a fetch but the waiting, so the two can't drift (PLAN.md, "The client"). A program uses one of those two modules to fetch, and this one for the types; it calls Fetch here only with a Waiter of its own.

A fetch: the URL is parsed and its request line made (GeminiUrls); a connection is made to its host and port within the deadline; TLS with SNI for a host name (libtls sends none for an IP address, as the specification says), the server's certificate checked as the options say, before the request is sent, so a URL and its query never reach a server the program doesn't trust; the request sent; the header read and parsed (GeminiHeaders). A success's body is then the program's to read, as a stream (Read) or whole (ReadAll); any other response has no body, so it is read to its end at once.

A response is complete only if the server ended it with TLS close_notify: an end without one may be an attacker cutting it short (P "Responses", "Closing connections"). A body cut short is an error, kind truncated, and what came before it has been read.

Every socket is non-blocking, and every TLS call is made non-blocking; where one would block, the Waiter waits until the socket is ready or the deadline passes. That is the only difference between the two APIs: GeminiClient's waits through Tasks, so other tasks run meanwhile, and GeminiFetch's in the kernel (posockets' Sockets.Await).

Outside data never halts: a server's response, a bad URL, a key file that won't load come back as FALSE and an Error. A program's mistakes halt (PLAN.md, "Halt codes"). Fetch ignores SIGPIPE for the whole program (Sockets.IgnoreBrokenPipe), since a server that goes away while the request is written would otherwise end it.

## Constants

```oberon
none* = 0;
request* = 1;      (* the URL isn't a gemini URL that can be requested *)
resolve* = 2;      (* the host's name doesn't resolve *)
connect* = 3;      (* no connection could be made *)
tls* = 4;          (* TLS: a key pair that won't load, a handshake that
untrusted* = 5;    (* the trust store refuses the server (Phase 5) *)
changed* = 6;      (* the server's key isn't the one known (Phase 5) *)
header* = 7;       (* the header is malformed, or the response ended in it *)
truncated* = 8;    (* the body ended without close_notify *)
timedOut* = 9;     (* the deadline passed *)
tooLong* = 10;     (* the body is over Options.maxBody *)
```

Error kinds

```oberon
DefaultDeadline* = 10000;   (* ms, from connecting to close_notify *)
MaxPath* = 1023;            (* a key, certificate or CA file's name at most *)
```

## Types

```oberon
Error* = RECORD
  kind-: INTEGER;
  text-: ARRAY MaxText + 1 OF CHAR
END;
```

What went wrong: kind, and a text saying so, for a person.

```oberon
Path* = ARRAY MaxPath + 1 OF CHAR;
```

```oberon
Options* = RECORD
  deadline*: LONGINT;
  certFile*, keyFile*, caFile*: Path;
  maxBody*: LONGINT
END;
```

A request's options; InitOptions gives the defaults. deadline: ms for everything from connecting to the response's end (close_notify), 0 for none; DefaultDeadline by default. certFile, keyFile: a client certificate and its key, PEM files, "" for none (both or neither). caFile: CA certificates, PEM, that must have signed the server's, which must also name the URL's host; "" to check nothing (the trust store of Phase 5 will be the usual choice). maxBody: the most bytes of body accepted, 0 for no limit, the default: a program that reads a stream needs none.

```oberon
Waiter* = POINTER TO WaiterDesc;
WaiterDesc* = RECORD notEmpty: LONGINT END;
```

How a fetch waits: GeminiClient's through Tasks, GeminiFetch's in the kernel. An extension overrides both methods.

The field is there only so that the record isn't empty: poc 0.14.0's collector, on 64-bit hosts, frees an object of a record with no fields while it is still reachable, since its data starts where its block ends, so a pointer to it marks the next block instead (PLAN.md, Phase 4).

```oberon
Response* = POINTER TO ResponseDesc;
ResponseDesc* = RECORD
  url-: GeminiUrls.URL;
  status-: INTEGER;
  meta-: ARRAY GeminiHeaders.MaxMeta + 1 OF CHAR;
  version-: ARRAY 32 OF CHAR;
  peerHash-: ARRAY 128 OF CHAR;
  bodyRead-: LONGINT;
  complete-: BOOLEAN;
  error-: Error;
END;
```

A response. url is what was fetched; status and meta its header; version the TLS version agreed ("TLSv1.3"), for a program to warn when a client certificate went over TLS 1.2, as the specification asks; peerHash the server certificate's fingerprint ("SHA256:" and hex). bodyRead counts the body's bytes read so far. complete: the response has ended with close_notify; while it is FALSE after the end, error says why.

```oberon
Chars* = POINTER TO ARRAY OF CHAR;
```

## Procedures

### Waiter

#### Connect

```oberon
PROCEDURE (w: Waiter) Connect*(host-: ARRAY OF CHAR; port: INTEGER; ms: LONGINT;
    VAR s: Sockets.Socket; VAR err: Sockets.Error): BOOLEAN;
```

Connects to host (a name, ASCII, or an address) and port as a non-blocking s, within ms milliseconds (0: no limit). FALSE, s NIL, with err as posockets gives it.

#### Await

```oberon
PROCEDURE (w: Waiter) Await*(s: Sockets.Socket; want: INTEGER; ms: LONGINT;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

Waits until s is ready for want (Sockets.wantRead or wantWrite), at most ms milliseconds (ms > 0), or with no limit (ms < 0): TRUE when it is ready; FALSE when the time passed, why ""; or FALSE when the wait itself failed, and why says how.

### Options

#### InitOptions

```oberon
PROCEDURE InitOptions*(VAR o: Options);
```

### Closing

#### Close

```oberon
PROCEDURE (r: Response) Close*;
```

Closes r's connection, if it is still open, as a program does that has read as much of the body as it wants: the server is sent close_notify, which a client MAY send early (P "Responses"). Later calls do nothing.

### The body

#### Read

```oberon
PROCEDURE (r: Response) Read*(VAR buf: ARRAY OF CHAR; pos, len: LONGINT;
    VAR n: LONGINT): BOOLEAN;
```

Reads up to len bytes of the body into buf[pos..], waiting for them, and n says how many, at least one: TRUE. FALSE at the end, n = 0: then complete says whether the server ended with close_notify, and if not error says why (truncated, timedOut, tooLong, ...); the connection is closed then, and later calls give FALSE again. A success's body only: any other response has none, and gives FALSE at once. len = 0 reads nothing. Halts (128) if buf[pos..pos+len-1] isn't within buf.

#### ReadAll

```oberon
PROCEDURE (r: Response) ReadAll*(VAR body: Chars; VAR len: LONGINT): BOOLEAN;
```

The whole of the body, or what there is of it, in body[0..len-1], with 0X after it: TRUE if it is complete, else FALSE, and error says why. Read before it is not included.

### The fetch

#### Fetch

```oberon
PROCEDURE Fetch*(w: Waiter; link-: ARRAY OF CHAR; VAR opts: Options; VAR r: Response): BOOLEAN;
```

Fetches the URL in link with opts, waiting through w: TRUE when the header has come, with r's status and meta; then a success's body is to be read (Read, ReadAll), and any other response has been read to its end. FALSE, with r.error, if the fetch failed before a whole header came, with r closed. Either way r is a new Response.
