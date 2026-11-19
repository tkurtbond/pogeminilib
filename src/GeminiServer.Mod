MODULE GeminiServer; (* A Gemini server's engine: listeners, and a task per connection *)

(* Moved from pogemini's GemServer (PLAN.md, Phase 8), which grew from
   polibtls's examples/GeminiHello: a server listens on one port, IPv6
   and IPv4, with an accept task per listener, and serves each
   connection in a task of its own (poc's cooperative Tasks), so one
   thread serves them all and a slow or stalled client holds up no
   other. Each connection has a deadline for the whole exchange,
   handshake to close_notify.

   A connection's task makes the TLS handshake, reads the request line
   and hands it, as an Exchange, to the server's Responder, which
   answers with Header and then, after a 2x header, the body by Write,
   WriteString or a Writer of gemtext. Then the task ends the response
   with TLS close_notify, which is how a Gemini client knows it has the
   whole of it, drains the socket (SocketTasks.LingeringClose) and
   closes it. A request with no CR LF in its first MaxRequest + 2 bytes
   is answered 59 without the Responder.

   What the request means, and whether it is allowed (GeminiUrls.
   CheckRequest; the host and port this server's), is the Responder's
   to say: the engine only reads the line.

   The server tells the program what happens through its Logger, if it
   has one (SetLog): a connection served or failed, an accept that
   failed, and stopping on a signal. What a line of log looks like, and
   whether it has the time, is the program's.

   At most a server's limit of connections are served at once
   (SetLimit); at the limit, the next waits in the kernel's queue until
   one ends.

   SIGTERM or SIGINT stops it cleanly: it stops accepting, closes its
   listeners, so that a new client is refused at once, and waits for
   the connections in progress, which their deadline bounds. A second
   signal of the same kind ends it at once. The signals are caught by
   poc's StopRequests, from Listen on.

   A program that serves ignores SIGPIPE, which Serve does for it, so a
   client that goes away makes a write fail rather than end it. *)

IMPORT Tasks, StopRequests, Sockets, SocketTasks, Tls, TlsTasks, GeminiUrls,
  GeminiHeaders, GeminiTextWriter;

CONST
  MaxRequest* = GeminiUrls.MaxURL;  (* a request's URL at most, by the specification *)
  DefaultDeadline* = 10000;  (* ms a connection has, at most *)
  DefaultLimit* = 256;       (* connections at once, at most *)

  (* A Logger's events *)
  served* = 0;        (* x answered, and closed with close_notify *)
  failed* = 1;        (* x's connection failed, why says how; x.request
                         is "" if it failed before the request was read *)
  acceptFailed* = 2;  (* accepting a connection failed (why); the server
                         goes on *)
  stopping* = 3;      (* a signal (s.signal) stops the server; s.active
                         connections are still in progress *)
  stopped* = 4;       (* they have ended, and Serve is returning *)

  Tick = 200;          (* ms an accept waits before looking at stop *)
  Linger = 2000;       (* ms a closed connection is drained for *)

  (* Halt codes (PLAN.md, "Halt codes") *)
  SecondHeader = 130;  (* Header: a header sent already *)
  NoBody = 131;        (* Write: no 2x header first *)
  NoHeader = 132;      (* a Responder returned without a header *)
  NotListening = 133;  (* Serve before Listen *)

TYPE
  Server* = POINTER TO ServerDesc;

  (* One connection's request, and its response so far. *)
  Exchange* = POINTER TO ExchangeDesc;
  ExchangeDesc* = RECORD
    server-: Server;          (* serving it: a program's extension of
                                 Server carries its own state *)
    peer-: Sockets.Address;   (* the client's *)
    request-: ARRAY MaxRequest + 1 OF CHAR;  (* the line, without CR LF *)
    certHash-: Tls.String;    (* the client certificate's, NIL for none *)
    notBefore-, notAfter-: HUGEINT;  (* its dates, seconds since 1970;
                                 -1 for none *)
    status-: INTEGER;         (* the header's, 0 until sent *)
    failed-: BOOLEAN;         (* a write failed; the rest do nothing *)
    conn: Tls.Connection
  END;

  (* Answers x.request: Header once, then, after a 2x header only, the
     body. Called in the connection's task, so it may wait, within the
     task's stack (TlsTasks.stackSize): nothing large on it. *)
  Responder* = PROCEDURE (x: Exchange);

  (* Told what happens (served .. stopped), in the task it happens in:
     x for served and failed, NIL otherwise; why for failed and
     acceptFailed, "" otherwise. It should write a line of log without
     waiting between its parts, so the lines of tasks never mix. *)
  Logger* = PROCEDURE (s: Server; event: INTEGER; x: Exchange; why-: ARRAY OF CHAR);

  (* Writes gemtext to an exchange's body, after its 2x header. *)
  Writer* = POINTER TO WriterDesc;
  WriterDesc* = RECORD (GeminiTextWriter.WriterDesc)
    x-: Exchange
  END;

  Handler = POINTER TO RECORD (Tasks.TaskDesc)
    server: Server;
    s: Sockets.Socket;
    peer: Sockets.Address;
    next: Handler
  END;
  Acceptor = POINTER TO RECORD (Tasks.TaskDesc)
    server: Server;
    l: Sockets.Socket
  END;
  ServerDesc* = RECORD
    port-: INTEGER;           (* listened on, once Listen succeeds *)
    active-: LONGINT;         (* connections being served *)
    signal-: INTEGER;         (* the one that stopped it: 2 (SIGINT) or
                                 15 (SIGTERM), 0 if none *)
    ctx: Tls.Context;
    respond: Responder;
    log: Logger;              (* NIL: nothing told *)
    deadline: LONGINT;
    limit: LONGINT;           (* connections at once, at most *)
    ended: Tasks.Condition;   (* signalled as each connection ends *)
    listeners: ARRAY 2 OF Sockets.Socket;
    n: INTEGER;               (* listeners *)
    count, accepted: LONGINT; (* connections to serve (0: no end), so far *)
    stop: BOOLEAN;
    handlers: Handler         (* the connections' tasks not yet seen done *)
  END;

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END; RETURN n
END Length;

PROCEDURE Log(s: Server; event: INTEGER; x: Exchange; why-: ARRAY OF CHAR);
BEGIN IF s.log # NIL THEN s.log(s, event, x, why) END
END Log;

(* Writes the response header, status and meta, "" for none, as
   GeminiHeaders.WriteHeader makes it, and so halting as it does on a
   status the specification doesn't name (124) or a meta it forbids
   (125); a second header halts (130). FALSE if the write failed. *)
PROCEDURE (x: Exchange) Header*(status: INTEGER; meta-: ARRAY OF CHAR): BOOLEAN;
  VAR line: GeminiHeaders.Line; len, m: LONGINT;
BEGIN
  ASSERT(x.status = 0, SecondHeader);
  GeminiHeaders.WriteHeader(status, meta, line, len);
  x.status := status;
  IF ~x.failed & ~TlsTasks.WriteAll(x.conn, line, 0, len, m) THEN x.failed := TRUE END;
  RETURN ~x.failed
END Header;

(* Writes buf[pos..pos+len-1] of the body; halts (131) unless a 2x
   header was sent. FALSE if this write, or one before, failed. *)
PROCEDURE (x: Exchange) Write*(buf-: ARRAY OF CHAR; pos, len: LONGINT): BOOLEAN;
  VAR m: LONGINT;
BEGIN
  ASSERT(x.status DIV 10 = 2, NoBody);
  IF ~x.failed & ~TlsTasks.WriteAll(x.conn, buf, pos, len, m) THEN x.failed := TRUE END;
  RETURN ~x.failed
END Write;

(* Writes s, up to its 0X, of the body, as Write. *)
PROCEDURE (x: Exchange) WriteString*(s-: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN x.Write(s, 0, Length(s))
END WriteString;

PROCEDURE (w: Writer) Put*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
BEGIN RETURN w.x.Write(s, 0, n)
END Put;

(* A writer of gemtext to x's body, at the start of a page: each line
   is written as it is given (Write), so it halts (131) unless x has
   sent a 2x header. *)
PROCEDURE NewWriter*(x: Exchange): Writer;
  VAR w: Writer;
BEGIN
  NEW(w); GeminiTextWriter.Init(w); w.x := x;
  RETURN w
END NewWriter;

(* Reads the request line, up to the first CR LF, into x.request without
   them: FALSE if reading failed, or, with x.request "", if there was no
   CR LF in the first MaxRequest + 2 bytes. Anything after the CR LF is
   ignored. *)
PROCEDURE ReadRequest(x: Exchange): BOOLEAN;
  VAR buf: ARRAY MaxRequest + 2 OF CHAR; n, m, i: LONGINT;
BEGIN
  n := 0; i := 0; x.request[0] := 0X;
  LOOP
    IF ~TlsTasks.Read(x.conn, buf, n, LEN(buf) - n, m) THEN RETURN FALSE END;
    INC(n, m);
    WHILE (i < n - 1) & ~((buf[i] = 0DX) & (buf[i + 1] = 0AX)) DO INC(i) END;
    IF i < n - 1 THEN
      m := 0; WHILE m < i DO x.request[m] := buf[m]; INC(m) END;
      x.request[i] := 0X;
      RETURN TRUE
    ELSIF n = LEN(buf) THEN
      RETURN TRUE
    END
  END
END ReadRequest;

(* Serves one connection: handshake, request, response, close_notify,
   all within the server's deadline; then tells the Logger how it went. *)
PROCEDURE (h: Handler) Run*;
  VAR x: Exchange; ok, closed: BOOLEAN; s: Server;
BEGIN
  s := h.server; closed := FALSE;
  NEW(x); x.server := s; x.peer := h.peer; x.request[0] := 0X; x.status := 0;
  x.failed := FALSE; x.certHash := NIL; x.notBefore := -1; x.notAfter := -1;
  IF ~s.ctx.AcceptSocket(h.s.fd, x.conn) THEN
    Log(s, failed, x, s.ctx.error.text^)
  ELSE
    x.conn.SetDeadline(s.deadline);
    ok := TlsTasks.Handshake(x.conn) & ReadRequest(x);
    IF ok THEN
      x.certHash := x.conn.PeerCertHash();
      IF x.certHash # NIL THEN
        x.notBefore := x.conn.PeerCertNotBefore(); x.notAfter := x.conn.PeerCertNotAfter()
      END;
      IF x.request = "" THEN
        IF x.Header(59, "request too long, or no CR LF") THEN END
      ELSE
        s.respond(x);
        ASSERT(x.status # 0, NoHeader)
      END;
      ok := ~x.failed & TlsTasks.Close(x.conn);
      (* A client may send its own close_notify straight after the
         request (gnutls-cli does), which is never read; closing a
         socket with unread data makes the kernel reset the connection,
         and a client that gets the reset before it has read the
         response loses it. So read and discard until the client closes,
         for Linger at most (polibtls's PLAN.md, Phase 8). *)
      IF ok THEN closed := TRUE; IF SocketTasks.LingeringClose(h.s, Linger) THEN END END
    END;
    IF ok THEN Log(s, served, x, "")
    ELSE Log(s, failed, x, x.conn.error.text^); x.conn.Discard
    END
  END;
  IF ~closed THEN Sockets.Close(h.s) END;
  DEC(s.active); Tasks.Broadcast(s.ended)
END Run;

(* Whether a signal has asked the server to stop; StopRequests reads
   what its handler wrote every time. *)
PROCEDURE Stopping(): BOOLEAN;
BEGIN RETURN StopRequests.Latest() # StopRequests.none
END Stopping;

(* The number of the signal that asked the server to stop: SIGINT and
   SIGTERM are 2 and 15 on Linux and the BSDs alike. *)
PROCEDURE Signal(): INTEGER;
BEGIN
  IF StopRequests.Latest() = StopRequests.interrupt THEN RETURN 2
  ELSE RETURN 15
  END
END Signal;

(* Drops from s.handlers those whose tasks are done, so that the list
   holds only those running, however long the server runs. *)
PROCEDURE Prune(s: Server);
  VAR h, prev: Handler;
BEGIN
  prev := NIL; h := s.handlers;
  WHILE h # NIL DO
    IF Tasks.Done(h) THEN
      IF prev = NIL THEN s.handlers := h.next ELSE prev.next := h.next END
    ELSE prev := h
    END;
    h := h.next
  END
END Prune;

(* Accepts connections on l, starting a Handler for each, until stop. *)
PROCEDURE (a: Acceptor) Run*;
  VAR h: Handler; err: Sockets.Error; s: Server;
BEGIN
  s := a.server;
  WHILE ~s.stop DO
    (* at the limit, until a connection ends *)
    WHILE s.active >= s.limit DO Tasks.Wait(s.ended) END;
    NEW(h); h.server := s;
    Sockets.SetDeadline(a.l, Tick);
    IF Stopping() THEN s.stop := TRUE
    ELSIF SocketTasks.Accept(a.l, h.s, h.peer, err) THEN
      Prune(s);
      h.next := s.handlers; s.handlers := h; INC(s.active);
      Tasks.Start(h, TlsTasks.stackSize);
      INC(s.accepted);
      IF s.accepted = s.count THEN s.stop := TRUE END
    ELSIF err.kind # Sockets.timedOut THEN
      (* EMFILE, or a connection reset while queued: report it, back
         off, go on *)
      Log(s, acceptFailed, NIL, err.text); Tasks.Sleep(10)
    END
  END;
  Sockets.Close(a.l)
END Run;

(* Makes s a server with the key pairs in ctx, answering requests by
   respond: for a program's extension of ServerDesc, which New is not. *)
PROCEDURE Init*(s: Server; ctx: Tls.Context; respond: Responder);
BEGIN
  s.ctx := ctx; s.respond := respond; s.log := NIL; s.deadline := DefaultDeadline;
  s.n := 0; s.port := 0; s.count := 0; s.accepted := 0; s.stop := FALSE;
  s.limit := DefaultLimit; s.active := 0; s.signal := 0;
  s.handlers := NIL
END Init;

(* A server with the key pairs in ctx, answering requests by respond. *)
PROCEDURE New*(ctx: Tls.Context; respond: Responder): Server;
  VAR s: Server;
BEGIN NEW(s); Init(s, ctx, respond); RETURN s
END New;

(* What the server tells of what happens, NIL for nothing (as at first). *)
PROCEDURE (s: Server) SetLog*(log: Logger);
BEGIN s.log := log
END SetLog;

(* Each connection's time, handshake to close_notify, in ms. *)
PROCEDURE (s: Server) SetDeadline*(ms: LONGINT);
BEGIN s.deadline := ms
END SetDeadline;

(* The most connections served at once, at least 1. *)
PROCEDURE (s: Server) SetLimit*(n: LONGINT);
BEGIN IF n < 1 THEN s.limit := 1 ELSE s.limit := n END
END SetLimit;

(* Listens on port at host, "" for every local address (IPv6 and IPv4
   alike), port 0 for one the kernel chooses: s.port says which. It
   catches SIGTERM and SIGINT from here on, not only in Serve, so a
   signal sent as soon as the port is known (by a program that started
   the server on port 0) stops it cleanly rather than killing it. *)
PROCEDURE (s: Server) Listen*(host-: ARRAY OF CHAR; port: INTEGER;
    VAR err: Sockets.Error): BOOLEAN;
  VAR a: Sockets.Address; h: ARRAY 256 OF CHAR;
BEGIN
  StopRequests.Catch;
  COPY(host, h);
  (* A backlog of 16 overflowed under 32 and 64 clients at once, and a
     dropped client waited 1 or 3 s for its SYN to be retried; 128 held
     them all (pogemini's docs/mild-load-test.md). *)
  IF ~Sockets.Listen(h, port, 128, TRUE, s.listeners, s.n, err)
    OR ~Sockets.LocalAddress(s.listeners[0], a, err) THEN
    RETURN FALSE
  END;
  (* With port 0, Listen gives both families the same port. *)
  s.port := a.port;
  RETURN TRUE
END Listen;

(* Closes the listeners, for a program that listens and then finds it
   can't serve, as pogemini when it fails to become another user once
   it listens as root: exiting with them open leaves them to the
   kernel, which pogemini's make valgrind reports. Serve then halts
   (133), as before Listen; nothing if not listening. *)
PROCEDURE (s: Server) Close*;
  VAR i: INTEGER;
BEGIN
  FOR i := 0 TO s.n - 1 DO Sockets.Close(s.listeners[i]) END;
  s.n := 0
END Close;

(* Serves count connections (0: until a signal stops it), then waits for
   them to end, having closed the listeners. Call it from the program's
   main body: it runs every task. A signal caught since Listen stops it
   at once. Halts (133) unless listening. *)
PROCEDURE (s: Server) Serve*(count: LONGINT);
  VAR as: ARRAY 2 OF Acceptor; i: INTEGER; signalled: BOOLEAN;
BEGIN
  ASSERT(s.n > 0, NotListening);
  s.count := count;
  Sockets.IgnoreBrokenPipe;
  FOR i := 0 TO s.n - 1 DO
    NEW(as[i]); as[i].server := s; as[i].l := s.listeners[i];
    Tasks.Start(as[i], TlsTasks.stackSize)
  END;
  FOR i := 0 TO s.n - 1 DO Tasks.Join(as[i]) END;
  signalled := Stopping();
  IF signalled THEN s.signal := Signal(); Log(s, stopping, NIL, "") END;
  WHILE s.handlers # NIL DO Tasks.Join(s.handlers); s.handlers := s.handlers.next END;
  IF signalled THEN Log(s, stopped, NIL, "") END;
  s.n := 0
END Serve;

END GeminiServer.
