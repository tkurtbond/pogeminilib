MODULE HaltTrustStore; (* a GeminiTrust.Store whose Check isn't overridden halts, code 129 *)

IMPORT GeminiTrust;

VAR s: GeminiTrust.Store; why: ARRAY 64 OF CHAR;

BEGIN
  NEW(s);
  IF s.Check("example.org", 1965, "", 0, 0, why) = GeminiTrust.known THEN END
END HaltTrustStore.
