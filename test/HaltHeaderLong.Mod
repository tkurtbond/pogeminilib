MODULE HaltHeaderLong; (* GeminiHeaders.WriteHeader of a meta of 1025 bytes halts, code 125 *)

IMPORT H := GeminiHeaders;

VAR line: H.Line; n: LONGINT; meta: ARRAY H.MaxMeta + 2 OF CHAR;

BEGIN
  FOR n := 0 TO H.MaxMeta DO meta[n] := "x" END; meta[H.MaxMeta + 1] := 0X;
  H.WriteHeader(20, meta, line, n)
END HaltHeaderLong.
