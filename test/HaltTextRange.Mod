MODULE HaltTextRange; (* GeminiText.Feed given an end past its array halts, code 121 *)

IMPORT T := GeminiText;

VAR p: T.Parser; l: T.Line; buf: ARRAY 4 OF CHAR; pos: LONGINT;

BEGIN
  p := T.New(T.MinBuffer); buf := "abc"; pos := 0;
  IF T.Feed(p, buf, pos, 5, l) THEN END
END HaltTextRange.
