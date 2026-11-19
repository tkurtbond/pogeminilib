MODULE HaltServerNoHeader; (* a Responder that returns without a header halts, code 132 *)

IMPORT ServeOnce, GeminiServer;

PROCEDURE Respond(x: GeminiServer.Exchange);
BEGIN
END Respond;

BEGIN
  ServeOnce.Run(Respond)
END HaltServerNoHeader.
