MODULE Hello; (* a Gemini server: a page at "/", 51 for anything else *)

(* Usage: Hello [port], 1965 if not given, 0 for one the kernel chooses *)

IMPORT Args, Out, Sockets, Tls, GeminiUrls, GeminiTextWriter, GeminiServer;

VAR
  c: Tls.Config; ctx: Tls.Context; s: GeminiServer.Server; err: Sockets.Error;
  port: LONGINT;

PROCEDURE Respond(x: GeminiServer.Exchange);
  VAR r: GeminiUrls.Request; w: GeminiServer.Writer; why: ARRAY 128 OF CHAR; status: INTEGER;
BEGIN
  status := GeminiUrls.CheckRequest(x.request, r, why);
  IF status # GeminiUrls.Ok THEN
    IF x.Header(status, why) THEN END
  ELSIF r.path # "/" THEN
    IF x.Header(51, "not found") THEN END
  ELSIF x.Header(20, "text/gemini") THEN
    w := GeminiServer.NewWriter(x);
    IF GeminiTextWriter.Heading(w, 1, "Hello", why)
      & GeminiTextWriter.Text(w, "Served by GeminiServer.", why) THEN
    END
  END
END Respond;

BEGIN
  port := 1965; IF Args.argc > 1 THEN Args.GetInt(1, port) END;
  c := Tls.NewConfig();
  IF ~c.SetKeypairFile("server.crt", "server.key") THEN Out.String(c.error.text^); Out.Ln
  ELSE
    ctx := Tls.NewServer();
    IF ~ctx.Configure(c) THEN Out.String(ctx.error.text^); Out.Ln
    ELSE
      c.Close;
      s := GeminiServer.New(ctx, Respond);
      IF ~s.Listen("localhost", SHORT(port), err) THEN Out.String(err.text); Out.Ln
      ELSE
        Out.String("port "); Out.Int(s.port, 0); Out.Ln;
        s.Serve(0)   (* until SIGINT or SIGTERM *)
      END
    END
  END
END Hello.
