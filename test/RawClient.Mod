MODULE RawClient; (* A Gemini client for the server's tests *)

(* pogemini's test/GemClient, so a test can send what no real client
   would, and GeminiClient won't: an over-long request, one without CR
   LF, or nothing at all. It runs in a task (TlsTasks), with a deadline
   on every connection, so a server that misbehaves fails a check
   rather than hanging the tests. It verifies nothing of the server's
   certificate: the tests' server's is self-signed, and what a server
   presents is not what these test. *)

IMPORT Sockets, SocketTasks, Tls, TlsTasks;

CONST
  Deadline* = 5000;   (* ms a connection has, at most *)
  MaxResponse = 16 * 1024 * 1024;
  ErrorLen = 256;

TYPE
  Conn* = POINTER TO RECORD
    s: Sockets.Socket;
    c: Tls.Connection
  END;

  Data* = POINTER TO ARRAY OF CHAR;

  Response* = POINTER TO RECORD
    ok-: BOOLEAN;      (* read to the server's close_notify *)
    data-: Data;  (* the response, 0X-terminated *)
    len-: LONGINT;
    error-: ARRAY ErrorLen OF CHAR;   (* why not ok *)
    serverHash-: ARRAY 80 OF CHAR     (* the server certificate's, "" if none *)
  END;

VAR
  servername*: ARRAY 256 OF CHAR;  (* sent as SNI; "localhost" at first *)

(* A TLS connection to host and port, handshake made, presenting the
   client certificate in cert and key, or none for "". *)
PROCEDURE Open*(host: ARRAY OF CHAR; port: INTEGER; cert, key: ARRAY OF CHAR;
    VAR c: Conn; VAR error: ARRAY OF CHAR): BOOLEAN;
  VAR cfg: Tls.Config; s: Sockets.Socket; conn: Tls.Connection; err: Sockets.Error;
BEGIN
  c := NIL;
  cfg := Tls.NewConfig();
  cfg.InsecureNoVerifyCert; cfg.InsecureNoVerifyName;
  IF (cert # "") & ~cfg.SetKeypairFile(cert, key) THEN
    COPY(cfg.error.text^, error); cfg.Close; RETURN FALSE
  END;
  IF ~SocketTasks.Connect(host, port, Deadline, s, err) THEN
    COPY(err.text, error); cfg.Close; RETURN FALSE
  END;
  IF ~Tls.ConnectSocket(cfg, s.fd, servername, conn) THEN
    COPY(conn.error.text^, error); cfg.Close; Sockets.Close(s); RETURN FALSE
  END;
  cfg.Close;
  conn.SetDeadline(Deadline);
  IF ~TlsTasks.Handshake(conn) THEN
    COPY(conn.error.text^, error); conn.Discard; Sockets.Close(s); RETURN FALSE
  END;
  NEW(c); c.s := s; c.c := conn;
  RETURN TRUE
END Open;

(* Sends buf[0..len-1]. *)
PROCEDURE Send*(c: Conn; buf-: ARRAY OF CHAR; len: LONGINT;
    VAR error: ARRAY OF CHAR): BOOLEAN;
  VAR m: LONGINT;
BEGIN
  IF TlsTasks.WriteAll(c.c, buf, 0, len, m) THEN RETURN TRUE END;
  COPY(c.c.error.text^, error); RETURN FALSE
END Send;

(* Reads the response, to its end, growing r.data as it comes, up to
   MaxResponse bytes. *)
PROCEDURE Receive*(c: Conn): Response;
  VAR r: Response; m, i: LONGINT; d: Data;
BEGIN
  NEW(r); NEW(r.data, 65536 + 1); r.len := 0; r.ok := FALSE; r.error := ""; r.serverHash := "";
  LOOP
    IF r.len = LEN(r.data^) - 1 THEN
      IF r.len >= MaxResponse THEN r.error := "response too long"; EXIT END;
      NEW(d, 2 * r.len + 1);
      FOR i := 0 TO r.len - 1 DO d[i] := r.data[i] END;
      r.data := d
    END;
    IF TlsTasks.Read(c.c, r.data^, r.len, LEN(r.data^) - 1 - r.len, m) THEN INC(r.len, m)
    ELSIF c.c.error.kind = Tls.closed THEN r.ok := TRUE; EXIT
    ELSE COPY(c.c.error.text^, r.error); EXIT
    END
  END;
  r.data[r.len] := 0X;
  RETURN r
END Receive;

(* Closes c and its socket, whatever state it is in. *)
PROCEDURE Close*(c: Conn);
BEGIN
  IF TlsTasks.Close(c.c) THEN END;
  Sockets.Close(c.s)
END Close;

(* Sends request[0..len-1] and reads the response, on a connection of
   its own. *)
PROCEDURE Fetch*(host: ARRAY OF CHAR; port: INTEGER; request: ARRAY OF CHAR;
    len: LONGINT; cert, key: ARRAY OF CHAR): Response;
  VAR c: Conn; r: Response; h: Tls.String;
BEGIN
  NEW(r); r.ok := FALSE; r.len := 0; NEW(r.data, 1); r.data[0] := 0X; r.serverHash := "";
  IF Open(host, port, cert, key, c, r.error) THEN
    IF Send(c, request, len, r.error) THEN r := Receive(c) END;
    h := c.c.PeerCertHash(); IF h # NIL THEN COPY(h^, r.serverHash) ELSE r.serverHash := "" END;
    Close(c)
  END;
  RETURN r
END Fetch;

BEGIN
  servername := "localhost"
END RawClient.
