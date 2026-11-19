MODULE GeminiClient; (* fetching gemini URLs in poc's Tasks *)

(* A fetch in a task: while it waits for the network, the program's
   other tasks run, so a program fetches several URLs at once, one task
   each, and a server that stalls holds up only its own, as does a
   name server slow to answer for its host. Each wait is cut short at
   the fetch's deadline (Options.deadline).

   The work is GeminiResponses', which GeminiFetch shares: this module
   gives it a Waiter that waits through Tasks (SocketTasks.Connect,
   Tasks.AwaitReadableFor and AwaitWritableFor). Its types are
   GeminiResponses': Options, Response and Error. Fetch must be called
   from a task, whose stack has room for it: stackSize, or more for the
   task's own needs. *)

IMPORT Tasks, Sockets, SocketTasks, GeminiResponses;

CONST
  (* A task's stack enough for a fetch, as polibtls's TlsTasks.stackSize
     is for a TLS connection, whose handshake is the most of it. A fetch
     with an RSA client certificate and a CA file ran in 24 KiB on
     amd64, and not in 16 KiB (PLAN.md, Phase 4). *)
  stackSize* = 65536;

TYPE
  Waiter = POINTER TO WaiterDesc;
  WaiterDesc = RECORD (GeminiResponses.WaiterDesc) END;

VAR
  waiter: Waiter;

PROCEDURE (w: Waiter) Connect*(host-: ARRAY OF CHAR; port: INTEGER; ms: LONGINT;
    VAR s: Sockets.Socket; VAR err: Sockets.Error): BOOLEAN;
BEGIN RETURN SocketTasks.Connect(host, port, ms, s, err)
END Connect;

PROCEDURE (w: Waiter) Await*(s: Sockets.Socket; want: INTEGER; ms: LONGINT;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR ready: BOOLEAN;
BEGIN
  IF want = Sockets.wantWrite THEN
    IF ms < 0 THEN Tasks.AwaitWritable(s.fd); ready := TRUE
    ELSE ready := Tasks.AwaitWritableFor(s.fd, ms)
    END
  ELSIF ms < 0 THEN Tasks.AwaitReadable(s.fd); ready := TRUE
  ELSE ready := Tasks.AwaitReadableFor(s.fd, ms)
  END;
  why[0] := 0X;
  RETURN ready
END Await;

(* Fetches the URL in link with opts, in the calling task, as
   GeminiResponses.Fetch: TRUE when the header has come, with r's
   status and meta, and a success's body to be read (r.Read,
   r.ReadAll); FALSE with r.error if the fetch failed before then. *)
PROCEDURE Fetch*(link-: ARRAY OF CHAR; VAR opts: GeminiResponses.Options;
    VAR r: GeminiResponses.Response): BOOLEAN;
BEGIN RETURN GeminiResponses.Fetch(waiter, link, opts, r)
END Fetch;

(* Fetches the URL in link with opts, in the calling task, following at most max
   redirects, those to another host only if policy says so, as
   GeminiResponses.FetchFollowing. *)
PROCEDURE FetchFollowing*(link-: ARRAY OF CHAR; VAR opts: GeminiResponses.Options;
    max: INTEGER; policy: GeminiResponses.RedirectPolicy; VAR r: GeminiResponses.Response): BOOLEAN;
BEGIN RETURN GeminiResponses.FetchFollowing(waiter, link, opts, max, policy, r)
END FetchFollowing;

BEGIN
  NEW(waiter)
END GeminiClient.
