MODULE HaltHeaderRange; (* GeminiHeaders.Parse given a length past its array halts, code 126 *)

IMPORT H := GeminiHeaders;

VAR h: H.Header; why: ARRAY 64 OF CHAR; buf: ARRAY 8 OF CHAR;

BEGIN
  buf := "20 x"; buf[4] := 0DX; buf[5] := 0AX;
  IF H.Parse(buf, 9, h, why) THEN END
END HaltHeaderRange.
