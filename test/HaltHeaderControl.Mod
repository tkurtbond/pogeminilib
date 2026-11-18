MODULE HaltHeaderControl; (* GeminiHeaders.WriteHeader of a meta with a line end halts, code 125 *)

IMPORT H := GeminiHeaders;

VAR line: H.Line; n: LONGINT; meta: ARRAY 8 OF CHAR;

BEGIN
  meta := "a"; meta[1] := 0DX; meta[2] := 0AX; meta[3] := "b"; meta[4] := 0X;
  H.WriteHeader(51, meta, line, n)
END HaltHeaderControl.
