MODULE GeminiResponses; (* a request made and its response read, waiting through a Waiter *)

(* What GeminiClient (in tasks) and GeminiFetch (blocking) share: a
   request's Options, the Response read through it, and its Error, and
   every step of a fetch but the waiting, so the two can't drift
   (PLAN.md, "The client"). A program uses one of those two modules to
   fetch, and this one for the types; it calls Fetch here only with a
   Waiter of its own.

   A fetch: the URL is parsed and its request line made (GeminiUrls);
   a connection is made to its host and port within the deadline; TLS
   with SNI for a host name (libtls sends none for an IP address, as
   the specification says), the server's certificate checked as the
   options say, before the request is sent, so a URL and its query
   never reach a server the program doesn't trust; the request sent;
   the header read and parsed (GeminiHeaders). A success's body is then
   the program's to read, as a stream (Read) or whole (ReadAll); any
   other response has no body, so it is read to its end at once.

   A response is complete only if the server ended it with TLS
   close_notify: an end without one may be an attacker cutting it short
   (P "Responses", "Closing connections"). A body cut short is an
   error, kind truncated, and what came before it has been read.

   Every socket is non-blocking, and every TLS call is made
   non-blocking; where one would block, the Waiter waits until the
   socket is ready or the deadline passes. That is the only difference
   between the two APIs: GeminiClient's waits through Tasks, so other
   tasks run meanwhile, and GeminiFetch's in the kernel (posockets'
   Sockets.Await).

   Outside data never halts: a server's response, a bad URL, a key
   file that won't load come back as FALSE and an Error. A program's
   mistakes halt (PLAN.md, "Halt codes"). Fetch ignores SIGPIPE for
   the whole program (Sockets.IgnoreBrokenPipe), since a server that
   goes away while the request is written would otherwise end it. *)

IMPORT Sockets, Tls, GeminiPunycode, GeminiUrls, GeminiHeaders, GeminiStatus;

CONST
  (* Error kinds *)
  none* = 0;
  request* = 1;      (* the URL isn't a gemini URL that can be requested *)
  resolve* = 2;      (* the host's name doesn't resolve *)
  connect* = 3;      (* no connection could be made *)
  tls* = 4;          (* TLS: a key pair that won't load, a handshake that
                        fails, the server's certificate not verified by
                        the CA file, the request not sent *)
  untrusted* = 5;    (* the trust store refuses the server (Phase 5) *)
  changed* = 6;      (* the server's key isn't the one known (Phase 5) *)
  header* = 7;       (* the header is malformed, or the response ended in it *)
  truncated* = 8;    (* the body ended without close_notify *)
  timedOut* = 9;     (* the deadline passed *)
  tooLong* = 10;     (* the body is over Options.maxBody *)

  DefaultDeadline* = 10000;   (* ms, from connecting to close_notify *)
  MaxPath* = 1023;            (* a key, certificate or CA file's name at most *)
  MaxText = 255;

  Abstract = 127;    (* a Waiter's method not overridden *)
  BadRange = 128;    (* Read: pos or len outside buf *)

TYPE
  (* What went wrong: kind, and a text saying so, for a person. *)
  Error* = RECORD
    kind-: INTEGER;
    text-: ARRAY MaxText + 1 OF CHAR
  END;

  Path* = ARRAY MaxPath + 1 OF CHAR;

  (* A request's options; InitOptions gives the defaults.
     deadline: ms for everything from connecting to the response's end
     (close_notify), 0 for none; DefaultDeadline by default.
     certFile, keyFile: a client certificate and its key, PEM files,
     "" for none (both or neither).
     caFile: CA certificates, PEM, that must have signed the server's,
     which must also name the URL's host; "" to check nothing (the
     trust store of Phase 5 will be the usual choice).
     maxBody: the most bytes of body accepted, 0 for no limit, the
     default: a program that reads a stream needs none. *)
  Options* = RECORD
    deadline*: LONGINT;
    certFile*, keyFile*, caFile*: Path;
    maxBody*: LONGINT
  END;

  (* How a fetch waits: GeminiClient's through Tasks, GeminiFetch's in
     the kernel. An extension overrides both methods.

     The field is there only so that the record isn't empty: poc
     0.14.0's collector, on 64-bit hosts, frees an object of a record
     with no fields while it is still reachable, since its data starts
     where its block ends, so a pointer to it marks the next block
     instead (PLAN.md, Phase 4). *)
  Waiter* = POINTER TO WaiterDesc;
  WaiterDesc* = RECORD notEmpty: LONGINT END;

  (* A response. url is what was fetched; status and meta its header;
     version the TLS version agreed ("TLSv1.3"), for a program to warn
     when a client certificate went over TLS 1.2, as the specification
     asks; peerHash the server certificate's fingerprint ("SHA256:" and
     hex). bodyRead counts the body's bytes read so far. complete: the
     response has ended with close_notify; while it is FALSE after the
     end, error says why. *)
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
    w: Waiter;
    s: Sockets.Socket;          (* NIL once closed *)
    conn: Tls.Connection;       (* NIL once closed *)
    end: LONGINT;               (* the deadline, Sockets.Now's, 0 for none *)
    maxBody: LONGINT;
    head: POINTER TO ARRAY GeminiHeaders.MaxHeader OF CHAR;
    rest, restEnd: LONGINT      (* head[rest..restEnd-1]: body read with the header *)
  END;

  Chars* = POINTER TO ARRAY OF CHAR;

(* Waiter *)

(* Connects to host (a name, ASCII, or an address) and port as a
   non-blocking s, within ms milliseconds (0: no limit). FALSE, s NIL,
   with err as posockets gives it. *)
PROCEDURE (w: Waiter) Connect*(host-: ARRAY OF CHAR; port: INTEGER; ms: LONGINT;
    VAR s: Sockets.Socket; VAR err: Sockets.Error): BOOLEAN;
BEGIN ASSERT(w = NIL, Abstract); RETURN FALSE
END Connect;

(* Waits until s is ready for want (Sockets.wantRead or wantWrite), at
   most ms milliseconds (ms > 0), or with no limit (ms < 0): TRUE when
   it is ready; FALSE when the time passed, why ""; or FALSE when the
   wait itself failed, and why says how. *)
PROCEDURE (w: Waiter) Await*(s: Sockets.Socket; want: INTEGER; ms: LONGINT;
    VAR why: ARRAY OF CHAR): BOOLEAN;
BEGIN ASSERT(w = NIL, Abstract); RETURN FALSE
END Await;

(* Texts *)

(* s := s + t, cut short if s is full. *)
PROCEDURE Append(VAR s: ARRAY OF CHAR; t-: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE (i < LEN(s) - 1) & (s[i] # 0X) DO INC(i) END;
  j := 0;
  WHILE (j < LEN(t)) & (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; n: LONGINT);
  VAR d: ARRAY 24 OF CHAR; i: INTEGER; t: ARRAY 2 OF CHAR;
BEGIN
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  t[1] := 0X;
  WHILE i > 0 DO DEC(i); t[0] := d[i]; Append(s, t) END
END AppendInt;

PROCEDURE ClearError(VAR e: Error);
BEGIN e.kind := none; e.text := ""
END ClearError;

(* r.error := kind, what and, if not "", ": " why. *)
PROCEDURE Fail(r: Response; kind: INTEGER; what-, why-: ARRAY OF CHAR);
BEGIN
  r.error.kind := kind; r.error.text := "";
  Append(r.error.text, what);
  IF why[0] # 0X THEN Append(r.error.text, ": "); Append(r.error.text, why) END
END Fail;

(* Options *)

PROCEDURE InitOptions*(VAR o: Options);
BEGIN
  o.deadline := DefaultDeadline;
  o.certFile := ""; o.keyFile := ""; o.caFile := "";
  o.maxBody := 0
END InitOptions;

(* Closing *)

(* Ends r's connection: with close_notify if polite (and it can be sent
   without waiting), else without; then closes the socket. *)
PROCEDURE Finish(r: Response; polite: BOOLEAN);
BEGIN
  IF r.conn # NIL THEN
    IF ~polite OR ~r.conn.Close() THEN r.conn.Discard END;
    r.conn := NIL
  END;
  IF r.s # NIL THEN Sockets.Close(r.s); r.s := NIL END
END Finish;

(* Closes r's connection, if it is still open, as a program does that
   has read as much of the body as it wants: the server is sent
   close_notify, which a client MAY send early (P "Responses"). Later
   calls do nothing. *)
PROCEDURE (r: Response) Close*;
BEGIN Finish(r, TRUE)
END Close;

(* Waiting *)

(* ms left until r's deadline: -1 if it has none, 0 if it has passed. *)
PROCEDURE Left(r: Response): LONGINT;
  VAR left: LONGINT;
BEGIN
  IF r.end = 0 THEN RETURN -1 END;
  left := r.end - Sockets.Now();
  IF left < 0 THEN left := 0 END;
  RETURN left
END Left;

(* Waits on r's socket for want (Tls.wantRead or wantWrite), while
   doing what: FALSE, with r.error, if the deadline passed or the wait
   failed. *)
PROCEDURE Wait(r: Response; want: INTEGER; what-: ARRAY OF CHAR): BOOLEAN;
  VAR left: LONGINT; why: ARRAY MaxText + 1 OF CHAR; sw: INTEGER;
BEGIN
  IF want = Tls.wantWrite THEN sw := Sockets.wantWrite ELSE sw := Sockets.wantRead END;
  left := Left(r);
  IF left = 0 THEN Fail(r, timedOut, what, "timed out"); RETURN FALSE END;
  why := "";
  IF r.w.Await(r.s, sw, left, why) THEN RETURN TRUE END;
  IF why[0] = 0X THEN Fail(r, timedOut, what, "timed out")
  ELSE Fail(r, connect, what, why)
  END;
  RETURN FALSE
END Wait;

(* The TLS steps, each repeated after waiting while libtls would block *)

PROCEDURE Handshake(r: Response): BOOLEAN;
BEGIN
  LOOP
    IF r.conn.Handshake() THEN RETURN TRUE
    ELSIF r.conn.error.kind # Tls.wouldBlock THEN
      Fail(r, tls, "TLS handshake", r.conn.error.text^); RETURN FALSE
    ELSIF ~Wait(r, r.conn.error.want, "TLS handshake") THEN RETURN FALSE
    END
  END
END Handshake;

PROCEDURE Send(r: Response; VAR buf: ARRAY OF CHAR; len: LONGINT): BOOLEAN;
  VAR pos, n: LONGINT;
BEGIN
  pos := 0;
  LOOP
    IF r.conn.WriteAll(buf, pos, len, n) THEN RETURN TRUE
    ELSIF r.conn.error.kind # Tls.wouldBlock THEN
      Fail(r, tls, "sending the request", r.conn.error.text^); RETURN FALSE
    END;
    INC(pos, n); DEC(len, n);
    IF ~Wait(r, r.conn.error.want, "sending the request") THEN RETURN FALSE END
  END
END Send;

(* Reads up to len bytes into buf[pos..] from the connection, at least
   one, in n: TRUE; or FALSE at the end, with n = 0, r.complete if it
   was close_notify, and if not r.error of kind ended (truncated for
   the body, header for the header); or FALSE with r.error on failure.
   The connection is closed at the end and on failure; afterwards,
   FALSE, with r as it was. *)
PROCEDURE Receive(r: Response; VAR buf: ARRAY OF CHAR; pos, len: LONGINT;
    VAR n: LONGINT; ended: INTEGER; what-: ARRAY OF CHAR): BOOLEAN;
BEGIN
  n := 0;
  IF r.conn = NIL THEN RETURN FALSE END;
  LOOP
    IF r.conn.Read(buf, pos, len, n) THEN RETURN TRUE
    ELSIF r.conn.error.kind = Tls.closed THEN
      r.complete := TRUE; ClearError(r.error); Finish(r, TRUE); RETURN FALSE
    ELSIF r.conn.error.kind # Tls.wouldBlock THEN
      Fail(r, ended, what, r.conn.error.text^); Finish(r, FALSE); RETURN FALSE
    ELSIF ~Wait(r, r.conn.error.want, what) THEN
      Finish(r, FALSE); RETURN FALSE
    END
  END
END Receive;

(* The body *)

(* Up to len bytes of body into buf[pos..], from what came with the
   header first, as Receive. *)
PROCEDURE Get(r: Response; VAR buf: ARRAY OF CHAR; pos, len: LONGINT; VAR n: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  IF r.rest < r.restEnd THEN
    n := r.restEnd - r.rest;
    IF n > len THEN n := len END;
    FOR i := 0 TO n - 1 DO buf[pos + i] := r.head[r.rest + i] END;
    INC(r.rest, n);
    RETURN TRUE
  END;
  RETURN Receive(r, buf, pos, len, n, truncated, "reading the body")
END Get;

(* Reads up to len bytes of the body into buf[pos..], waiting for them,
   and n says how many, at least one: TRUE. FALSE at the end, n = 0:
   then complete says whether the server ended with close_notify, and
   if not error says why (truncated, timedOut, tooLong, ...); the
   connection is closed then, and later calls give FALSE again. A
   success's body only: any other response has none, and gives FALSE at
   once. len = 0 reads nothing. Halts (128) if buf[pos..pos+len-1]
   isn't within buf. *)
PROCEDURE (r: Response) Read*(VAR buf: ARRAY OF CHAR; pos, len: LONGINT;
    VAR n: LONGINT): BOOLEAN;
  VAR one: ARRAY 1 OF CHAR; m: LONGINT;
BEGIN
  ASSERT((pos >= 0) & (len >= 0) & (pos <= LEN(buf) - len), BadRange);
  n := 0;
  IF len = 0 THEN RETURN (r.rest < r.restEnd) OR (r.conn # NIL) END;
  IF (r.maxBody > 0) & (len > r.maxBody - r.bodyRead) THEN
    len := r.maxBody - r.bodyRead;
    IF len = 0 THEN
      (* As much as is allowed has been read: one byte more is too
         much, and the end is complete. *)
      IF Get(r, one, 0, 1, m) THEN
        Fail(r, tooLong, "the body is over the limit", "");
        Append(r.error.text, " of "); AppendInt(r.error.text, r.maxBody);
        Append(r.error.text, " bytes");
        Finish(r, TRUE)
      END;
      RETURN FALSE
    END
  END;
  IF Get(r, buf, pos, len, n) THEN INC(r.bodyRead, n); RETURN TRUE END;
  RETURN FALSE
END Read;

(* The whole of the body, or what there is of it, in body[0..len-1],
   with 0X after it: TRUE if it is complete, else FALSE, and error says
   why. Read before it is not included. *)
PROCEDURE (r: Response) ReadAll*(VAR body: Chars; VAR len: LONGINT): BOOLEAN;
  VAR n, i: LONGINT; more: Chars;
BEGIN
  NEW(body, 4096); len := 0;
  LOOP
    IF len = LEN(body^) - 1 THEN
      NEW(more, 2 * LEN(body^));
      FOR i := 0 TO len - 1 DO more[i] := body[i] END;
      body := more
    END;
    IF ~r.Read(body^, len, LEN(body^) - 1 - len, n) THEN EXIT END;
    INC(len, n)
  END;
  body[len] := 0X;
  RETURN r.complete
END ReadAll;

(* The fetch *)

PROCEDURE Start(r: Response; w: Waiter; VAR opts: Options);
BEGIN
  r.w := w; r.status := 0; r.meta := ""; r.version := ""; r.peerHash := "";
  r.bodyRead := 0; r.complete := FALSE; ClearError(r.error);
  r.s := NIL; r.conn := NIL; r.end := 0; r.maxBody := opts.maxBody;
  NEW(r.head); r.rest := 0; r.restEnd := 0
END Start;

(* The configuration the options ask for: NIL, with r.error, if a file
   won't load. *)
PROCEDURE NewConfig(r: Response; VAR opts: Options): Tls.Config;
  VAR c: Tls.Config;
BEGIN
  c := Tls.NewConfig();
  IF ((opts.certFile # "") OR (opts.keyFile # ""))
    & ~c.SetKeypairFile(opts.certFile, opts.keyFile) THEN
    Fail(r, tls, "the client certificate", c.error.text^); c.Close; RETURN NIL
  END;
  IF opts.caFile # "" THEN
    IF ~c.SetCaFile(opts.caFile) THEN
      Fail(r, tls, "the CA file", c.error.text^); c.Close; RETURN NIL
    END
  ELSE
    c.InsecureNoVerifyCert; c.InsecureNoVerifyName; c.InsecureNoVerifyTime
  END;
  RETURN c
END NewConfig;

(* Connects, makes the TLS connection, and completes its handshake,
   which checks the server's certificate as the options say. *)
PROCEDURE Open(r: Response; VAR opts: Options): BOOLEAN;
  VAR host: ARRAY 256 OF CHAR; why: ARRAY MaxText + 1 OF CHAR;
    c: Tls.Config; err: Sockets.Error; s: Tls.String; port: LONGINT; kind: INTEGER;
BEGIN
  IF ~GeminiPunycode.ToAscii(r.url.host, host, why) THEN
    Fail(r, request, "the host", why); RETURN FALSE
  END;
  c := NewConfig(r, opts);
  IF c = NIL THEN RETURN FALSE END;
  port := GeminiUrls.Port(r.url);
  IF opts.deadline > 0 THEN r.end := Sockets.Now() + opts.deadline END;
  IF ~r.w.Connect(host, SHORT(port), opts.deadline, r.s, err) THEN
    IF err.kind = Sockets.name THEN kind := resolve
    ELSIF err.kind = Sockets.timedOut THEN kind := timedOut
    ELSE kind := connect
    END;
    Fail(r, kind, err.text, ""); r.s := NIL; c.Close; RETURN FALSE
  END;
  (* The host is the name sent by SNI and the one a CA-signed
     certificate must name; for an IP address libtls sends no SNI, as
     the specification asks, and checks the certificate's IP names. *)
  IF ~Tls.ConnectSocket(c, r.s.fd, host, r.conn) THEN
    Fail(r, tls, "TLS", r.conn.error.text^); r.conn := NIL; c.Close; Finish(r, FALSE);
    RETURN FALSE
  END;
  c.Close;
  IF ~Handshake(r) THEN Finish(r, FALSE); RETURN FALSE END;
  s := r.conn.Version(); IF s # NIL THEN COPY(s^, r.version) END;
  s := r.conn.PeerCertHash(); IF s # NIL THEN COPY(s^, r.peerHash) END;
  RETURN TRUE
END Open;

(* Reads the header, and the body that came with it, into r.head, and
   parses it. *)
PROCEDURE ReadHeader(r: Response): BOOLEAN;
  VAR len, n, m: LONGINT; h: GeminiHeaders.Header; why: ARRAY MaxText + 1 OF CHAR;
BEGIN
  len := 0;
  WHILE ~GeminiHeaders.Ended(r.head^, len, n) DO
    IF ~Receive(r, r.head^, len, LEN(r.head^) - len, m, header, "reading the header") THEN
      IF r.complete THEN
        r.complete := FALSE;
        IF len = 0 THEN Fail(r, header, "the response has no header", "")
        ELSE Fail(r, header, "the response ended in its header", "")
        END
      END;
      RETURN FALSE
    END;
    INC(len, m)
  END;
  IF ~GeminiHeaders.Parse(r.head^, n, h, why) THEN
    Fail(r, header, "the header", why); Finish(r, FALSE); RETURN FALSE
  END;
  r.status := h.status; COPY(h.meta, r.meta);
  r.rest := n; r.restEnd := len;
  RETURN TRUE
END ReadHeader;

(* A response other than a success has no body: it is read to its end,
   so complete says whether it ended with close_notify, and anything
   after the header is ignored; but not for ever. *)
PROCEDURE ReadEnd(r: Response);
  CONST Most = 65536;
  VAR n, total: LONGINT;
BEGIN
  r.rest := r.restEnd; total := 0;
  WHILE Receive(r, r.head^, 0, LEN(r.head^), n, truncated, "reading the response") DO
    INC(total, n);
    IF total > Most THEN
      Fail(r, tooLong, "over 64 KiB after a header that has no body", "");
      Finish(r, FALSE)
    END
  END
END ReadEnd;

(* Fetches the URL in link with opts, waiting through w: TRUE when the
   header has come, with r's status and meta; then a success's body is
   to be read (Read, ReadAll), and any other response has been read to
   its end. FALSE, with r.error, if the fetch failed before a whole
   header came, with r closed. Either way r is a new Response. *)
PROCEDURE Fetch*(w: Waiter; link-: ARRAY OF CHAR; VAR opts: Options; VAR r: Response): BOOLEAN;
  VAR line: ARRAY GeminiUrls.MaxURL + 3 OF CHAR; why: ARRAY MaxText + 1 OF CHAR; n: LONGINT;
BEGIN
  NEW(r); Start(r, w, opts);
  Sockets.IgnoreBrokenPipe;
  (* Parsed straight into the heap, so r.url is whole, padding and all,
     for the collector (AGENTS.md, "Test"). *)
  IF ~GeminiUrls.Parse(link, r.url, why) THEN Fail(r, request, "the URL", why); RETURN FALSE END;
  IF r.url.scheme # "gemini" THEN Fail(r, request, "not a gemini URL", ""); RETURN FALSE END;
  IF ~GeminiUrls.RequestLine(r.url, line, why) THEN Fail(r, request, "the URL", why); RETURN FALSE END;
  n := 0; WHILE line[n] # 0X DO INC(n) END;
  line[n] := 0DX; line[n + 1] := 0AX;
  IF ~Open(r, opts) OR ~Send(r, line, n + 2) OR ~ReadHeader(r) THEN
    Finish(r, FALSE); RETURN FALSE
  END;
  IF GeminiStatus.Class(r.status) # GeminiStatus.SuccessClass THEN ReadEnd(r) END;
  RETURN TRUE
END Fetch;

END GeminiResponses.
