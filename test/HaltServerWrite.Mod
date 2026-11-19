MODULE HaltServerWrite; (* Write after a header other than 2x halts, code 131 *)

IMPORT ServeOnce, GeminiServer;

PROCEDURE Respond(x: GeminiServer.Exchange);
BEGIN
  IF x.Header(51, "not found") THEN END;
  IF x.WriteString("no body after 51") THEN END
END Respond;

BEGIN
  ServeOnce.Run(Respond)
END HaltServerWrite.
