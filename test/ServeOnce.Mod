MODULE ServeOnce; (* One exchange with a GeminiServer, for the halt tests *)

(* Runs a GeminiServer in this process, with the tests' self-signed
   pair, answering by respond, and one RawClient request to it from a
   task: so a halt test's Responder runs as a server's would, and
   halts there. Exits 1 if the server can't start, which no halt test
   expects. Run from test/. *)

IMPORT Platform, Err, Tasks, Sockets, Tls, RawClient, GeminiServer;

CONST
  Crt = "../build/certs/self-ec.crt";
  Key = "../build/certs/self-ec.key";
  StackSize = 1024 * 1024;

TYPE
  Client = POINTER TO RECORD (Tasks.TaskDesc) port: INTEGER END;

PROCEDURE (c: Client) Run*;
  VAR r: RawClient.Response; req: ARRAY 64 OF CHAR;
BEGIN
  req := "gemini://localhost/"; req[19] := 0DX; req[20] := 0AX; req[21] := 0X;
  r := RawClient.Fetch("127.0.0.1", c.port, req, 21, "", "")
END Run;

PROCEDURE Fail(why: ARRAY OF CHAR);
BEGIN Err.String("ServeOnce: "); Err.String(why); Err.Ln; Platform.Exit(1)
END Fail;

PROCEDURE Run*(respond: GeminiServer.Responder);
  VAR cfg: Tls.Config; ctx: Tls.Context; s: GeminiServer.Server;
    err: Sockets.Error; c: Client;
BEGIN
  cfg := Tls.NewConfig();
  IF ~cfg.SetKeypairFile(Crt, Key) THEN Fail(cfg.error.text^) END;
  ctx := Tls.NewServer();
  IF ~ctx.Configure(cfg) THEN Fail(ctx.error.text^) END;
  cfg.Close;
  s := GeminiServer.New(ctx, respond);
  IF ~s.Listen("127.0.0.1", 0, err) THEN Fail(err.text) END;
  NEW(c); c.port := s.port; Tasks.Start(c, StackSize);
  s.Serve(1)
END Run;

END ServeOnce.
