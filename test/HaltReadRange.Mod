MODULE HaltReadRange; (* Response.Read given a range past its array halts, code 128 *)

IMPORT R := GeminiResponses;

VAR r: R.Response; buf: ARRAY 8 OF CHAR; n: LONGINT;

BEGIN
  NEW(r);
  IF r.Read(buf, 4, 5, n) THEN END
END HaltReadRange.
