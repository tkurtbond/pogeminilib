MODULE HaltServerHeader; (* a second Header halts, code 130 *)

IMPORT ServeOnce, GeminiServer;

PROCEDURE Respond(x: GeminiServer.Exchange);
BEGIN
  IF x.Header(20, "text/gemini") & x.Header(20, "text/gemini") THEN END
END Respond;

BEGIN
  ServeOnce.Run(Respond)
END HaltServerHeader.
