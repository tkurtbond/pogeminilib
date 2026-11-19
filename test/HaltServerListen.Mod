MODULE HaltServerListen; (* Serve before Listen halts, code 133 *)

IMPORT Tls, GeminiServer;

PROCEDURE Respond(x: GeminiServer.Exchange);
BEGIN
  IF x.Header(51, "not found") THEN END
END Respond;

VAR s: GeminiServer.Server;

BEGIN
  s := GeminiServer.New(Tls.NewServer(), Respond);
  s.Serve(1)
END HaltServerListen.
