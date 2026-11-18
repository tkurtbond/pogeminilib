MODULE HaltHeaderEmpty; (* GeminiHeaders.WriteHeader of a success with no MIME type halts, code 125 *)

IMPORT H := GeminiHeaders;

VAR line: H.Line; n: LONGINT;

BEGIN H.WriteHeader(20, "", line, n)
END HaltHeaderEmpty.
