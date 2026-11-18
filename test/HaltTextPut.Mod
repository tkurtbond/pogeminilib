MODULE HaltTextPut; (* a GeminiTextWriter.Writer whose Put isn't overridden halts, code 122 *)

IMPORT W := GeminiTextWriter;

VAR w: W.Writer; why: ARRAY 64 OF CHAR;

BEGIN
  NEW(w); W.Init(w);
  IF W.Text(w, "x", why) THEN END
END HaltTextPut.
