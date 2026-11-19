# GeminiServer: A Gemini server's engine: listeners, and a task per connection

<!-- Made by doc/mkref.py from GeminiServer.Mod; edit the source, then make doc. -->

Moved from pogemini's GemServer (PLAN.md, Phase 8), which grew from polibtls's examples/GeminiHello: a server listens on one port, IPv6 and IPv4, with an accept task per listener, and serves each connection in a task of its own (poc's cooperative Tasks), so one thread serves them all and a slow or stalled client holds up no other. Each connection has a deadline for the whole exchange, handshake to close_notify.

A connection's task makes the TLS handshake, reads the request line and hands it, as an Exchange, to the server's Responder, which answers with Header and then, after a 2x header, the body by Write, WriteString or a Writer of gemtext. Then the task ends the response with TLS close_notify, which is how a Gemini client knows it has the whole of it, drains the socket (SocketTasks.LingeringClose) and closes it. A request with no CR LF in its first MaxRequest + 2 bytes is answered 59 without the Responder.

What the request means, and whether it is allowed (GeminiUrls. CheckRequest; the host and port this server's), is the Responder's to say: the engine only reads the line.

The server tells the program what happens through its Logger, if it has one (SetLog): a connection served or failed, an accept that failed, and stopping on a signal. What a line of log looks like, and whether it has the time, is the program's.

At most a server's limit of connections are served at once (SetLimit); at the limit, the next waits in the kernel's queue until one ends.

SIGTERM or SIGINT stops it cleanly: it stops accepting, closes its listeners, so that a new client is refused at once, and waits for the connections in progress, which their deadline bounds. A second signal of the same kind ends it at once. The signals are caught by poc's StopRequests, from Listen on.

A program that serves ignores SIGPIPE, which Serve does for it, so a client that goes away makes a write fail rather than end it.

## Constants

```oberon
MaxRequest* = GeminiUrls.MaxURL;  (* a request's URL at most, by the specification *)
DefaultDeadline* = 10000;  (* ms a connection has, at most *)
DefaultLimit* = 256;       (* connections at once, at most *)
```

```oberon
served* = 0;        (* x answered, and closed with close_notify *)
failed* = 1;        (* x's connection failed, why says how; x.request
acceptFailed* = 2;  (* accepting a connection failed (why); the server
stopping* = 3;      (* a signal (s.signal) stops the server; s.active
stopped* = 4;       (* they have ended, and Serve is returning *)
```

A Logger's events

## Types

```oberon
Server* = POINTER TO ServerDesc;
```

```oberon
Exchange* = POINTER TO ExchangeDesc;
ExchangeDesc* = RECORD
  server-: Server;          (* serving it: a program's extension of
  peer-: Sockets.Address;   (* the client's *)
  request-: ARRAY MaxRequest + 1 OF CHAR;  (* the line, without CR LF *)
  certHash-: Tls.String;    (* the client certificate's, NIL for none *)
  notBefore-, notAfter-: HUGEINT;  (* its dates, seconds since 1970;
  status-: INTEGER;         (* the header's, 0 until sent *)
  failed-: BOOLEAN;         (* a write failed; the rest do nothing *)
END;
```

One connection's request, and its response so far.

```oberon
Responder* = PROCEDURE (x: Exchange);
```

Answers x.request: Header once, then, after a 2x header only, the body. Called in the connection's task, so it may wait, within the task's stack (TlsTasks.stackSize): nothing large on it.

```oberon
Logger* = PROCEDURE (s: Server; event: INTEGER; x: Exchange; why-: ARRAY OF CHAR);
```

Told what happens (served .. stopped), in the task it happens in: x for served and failed, NIL otherwise; why for failed and acceptFailed, "" otherwise. It should write a line of log without waiting between its parts, so the lines of tasks never mix.

```oberon
Writer* = POINTER TO WriterDesc;
WriterDesc* = RECORD (GeminiTextWriter.WriterDesc)
  x-: Exchange
END;
```

Writes gemtext to an exchange's body, after its 2x header.

```oberon
ServerDesc* = RECORD
  port-: INTEGER;           (* listened on, once Listen succeeds *)
  active-: LONGINT;         (* connections being served *)
  signal-: INTEGER;         (* the one that stopped it: 2 (SIGINT) or
END;
```

## Procedures

#### Header

```oberon
PROCEDURE (x: Exchange) Header*(status: INTEGER; meta-: ARRAY OF CHAR): BOOLEAN;
```

Writes the response header, status and meta, "" for none, as GeminiHeaders.WriteHeader makes it, and so halting as it does on a status the specification doesn't name (124) or a meta it forbids (125); a second header halts (130). FALSE if the write failed.

#### Write

```oberon
PROCEDURE (x: Exchange) Write*(buf-: ARRAY OF CHAR; pos, len: LONGINT): BOOLEAN;
```

Writes buf[pos..pos+len-1] of the body; halts (131) unless a 2x header was sent. FALSE if this write, or one before, failed.

#### WriteString

```oberon
PROCEDURE (x: Exchange) WriteString*(s-: ARRAY OF CHAR): BOOLEAN;
```

Writes s, up to its 0X, of the body, as Write.

#### Put

```oberon
PROCEDURE (w: Writer) Put*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
```

#### NewWriter

```oberon
PROCEDURE NewWriter*(x: Exchange): Writer;
```

A writer of gemtext to x's body, at the start of a page: each line is written as it is given (Write), so it halts (131) unless x has sent a 2x header.

#### Run

```oberon
PROCEDURE (h: Handler) Run*;
```

Serves one connection: handshake, request, response, close_notify, all within the server's deadline; then tells the Logger how it went.

#### Run

```oberon
PROCEDURE (a: Acceptor) Run*;
```

Accepts connections on l, starting a Handler for each, until stop.

#### Init

```oberon
PROCEDURE Init*(s: Server; ctx: Tls.Context; respond: Responder);
```

Makes s a server with the key pairs in ctx, answering requests by respond: for a program's extension of ServerDesc, which New is not.

#### New

```oberon
PROCEDURE New*(ctx: Tls.Context; respond: Responder): Server;
```

A server with the key pairs in ctx, answering requests by respond.

#### SetLog

```oberon
PROCEDURE (s: Server) SetLog*(log: Logger);
```

What the server tells of what happens, NIL for nothing (as at first).

#### SetDeadline

```oberon
PROCEDURE (s: Server) SetDeadline*(ms: LONGINT);
```

Each connection's time, handshake to close_notify, in ms.

#### SetLimit

```oberon
PROCEDURE (s: Server) SetLimit*(n: LONGINT);
```

The most connections served at once, at least 1.

#### Listen

```oberon
PROCEDURE (s: Server) Listen*(host-: ARRAY OF CHAR; port: INTEGER;
    VAR err: Sockets.Error): BOOLEAN;
```

Listens on port at host, "" for every local address (IPv6 and IPv4 alike), port 0 for one the kernel chooses: s.port says which. It catches SIGTERM and SIGINT from here on, not only in Serve, so a signal sent as soon as the port is known (by a program that started the server on port 0) stops it cleanly rather than killing it.

#### Serve

```oberon
PROCEDURE (s: Server) Serve*(count: LONGINT);
```

Serves count connections (0: until a signal stops it), then waits for them to end, having closed the listeners. Call it from the program's main body: it runs every task. A signal caught since Listen stops it at once. Halts (133) unless listening.
