MODULE HaltTextBuffer; (* GeminiText.New with a buffer under MinBuffer halts, code 120 *)

IMPORT T := GeminiText;

VAR p: T.Parser;

BEGIN
  p := T.New(T.MinBuffer - 1)
END HaltTextBuffer.
