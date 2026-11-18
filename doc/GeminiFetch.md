# GeminiFetch: fetching gemini URLs, blocking, without tasks

<!-- Made by doc/mkref.py from GeminiFetch.Mod; edit the source, then make doc. -->

A fetch for a program without tasks: each call blocks until it is done, or the deadline (Options.deadline) passes. It does exactly what GeminiClient's does, through GeminiResponses, with a Waiter that waits in the kernel (Sockets.ConnectWithin, Sockets.Await), so this module doesn't import Tasks. Its types are GeminiResponses': Options, Response and Error.

## Procedures

#### Connect

```oberon
PROCEDURE (w: Waiter) Connect*(host-: ARRAY OF CHAR; port: INTEGER; ms: LONGINT;
    VAR s: Sockets.Socket; VAR err: Sockets.Error): BOOLEAN;
```

#### Await

```oberon
PROCEDURE (w: Waiter) Await*(s: Sockets.Socket; want: INTEGER; ms: LONGINT;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

#### Fetch

```oberon
PROCEDURE Fetch*(link-: ARRAY OF CHAR; VAR opts: GeminiResponses.Options;
    VAR r: GeminiResponses.Response): BOOLEAN;
```

Fetches the URL in link with opts, blocking, as GeminiResponses.Fetch: TRUE when the header has come, with r's status and meta, and a success's body to be read (r.Read, r.ReadAll); FALSE with r.error if the fetch failed before then.
