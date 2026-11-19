MODULE GeminiFetch; (* fetching gemini URLs, blocking, without tasks *)

(* A fetch for a program without tasks: each call blocks until it is
   done, or the deadline (Options.deadline) passes. It does exactly
   what GeminiClient's does, through GeminiResponses, with a Waiter
   that waits in the kernel (Sockets.ConnectWithin, Sockets.Await), so
   this module doesn't import Tasks. Its types are GeminiResponses':
   Options, Response and Error. *)

IMPORT Sockets, GeminiResponses;

TYPE
  Waiter = POINTER TO WaiterDesc;
  WaiterDesc = RECORD (GeminiResponses.WaiterDesc) END;

VAR
  waiter: Waiter;

PROCEDURE (w: Waiter) Connect*(host-: ARRAY OF CHAR; port: INTEGER; ms: LONGINT;
    VAR s: Sockets.Socket; VAR err: Sockets.Error): BOOLEAN;
BEGIN RETURN Sockets.ConnectWithin(host, port, ms, TRUE, s, err)
END Connect;

PROCEDURE (w: Waiter) Await*(s: Sockets.Socket; want: INTEGER; ms: LONGINT;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR err: Sockets.Error; ready: BOOLEAN;
BEGIN
  IF ms < 0 THEN Sockets.SetDeadline(s, 0) ELSE Sockets.SetDeadline(s, ms) END;
  ready := Sockets.Await(s, want, "wait", err);
  Sockets.SetDeadline(s, 0);
  IF ready OR (err.kind = Sockets.timedOut) THEN why[0] := 0X
  ELSE COPY(err.text, why)
  END;
  RETURN ready
END Await;

(* Fetches the URL in link with opts, blocking, as
   GeminiResponses.Fetch: TRUE when the header has come, with r's
   status and meta, and a success's body to be read (r.Read,
   r.ReadAll); FALSE with r.error if the fetch failed before then. *)
PROCEDURE Fetch*(link-: ARRAY OF CHAR; VAR opts: GeminiResponses.Options;
    VAR r: GeminiResponses.Response): BOOLEAN;
BEGIN RETURN GeminiResponses.Fetch(waiter, link, opts, r)
END Fetch;

(* Fetches the URL in link with opts, blocking, following at most max
   redirects, those to another host only if policy says so, as
   GeminiResponses.FetchFollowing. *)
PROCEDURE FetchFollowing*(link-: ARRAY OF CHAR; VAR opts: GeminiResponses.Options;
    max: INTEGER; policy: GeminiResponses.RedirectPolicy; VAR r: GeminiResponses.Response): BOOLEAN;
BEGIN RETURN GeminiResponses.FetchFollowing(waiter, link, opts, max, policy, r)
END FetchFollowing;

BEGIN
  NEW(waiter)
END GeminiFetch.
