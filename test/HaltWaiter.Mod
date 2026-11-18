MODULE HaltWaiter; (* a Waiter that doesn't override its methods halts, code 127 *)

IMPORT R := GeminiResponses;

TYPE W = POINTER TO RECORD (R.WaiterDesc) END;

VAR w: W; o: R.Options; r: R.Response;

BEGIN
  NEW(w); R.InitOptions(o);
  IF R.Fetch(w, "gemini://localhost/", o, r) THEN END
END HaltWaiter.
