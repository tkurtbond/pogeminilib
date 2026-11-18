MODULE HaltTextLevel; (* GeminiTextWriter.Heading of level 4 halts, code 123 *)

IMPORT W := GeminiTextWriter;

TYPE Null = POINTER TO RECORD (W.WriterDesc) END;

VAR w: Null; why: ARRAY 64 OF CHAR;

PROCEDURE (w: Null) Put*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
BEGIN RETURN TRUE
END Put;

BEGIN
  NEW(w); W.Init(w);
  IF W.Heading(w, 4, "x", why) THEN END
END HaltTextLevel.
