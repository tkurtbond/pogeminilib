MODULE HaltStatusClass; (* GeminiStatus.Class of 70, no status, halts, code 124 *)

IMPORT S := GeminiStatus;

VAR c: INTEGER;

BEGIN c := S.Class(70)
END HaltStatusClass.
