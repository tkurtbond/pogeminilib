MODULE HaltHeaderStatus; (* GeminiHeaders.WriteHeader of 15, a status the specification doesn't name, halts, code 124 *)

IMPORT H := GeminiHeaders;

VAR line: H.Line; n: LONGINT;

BEGIN H.WriteHeader(15, "x", line, n)
END HaltHeaderStatus.
