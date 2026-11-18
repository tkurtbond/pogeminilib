MODULE TestCheck; (* Check's own procedures, before any module of the library *)

(* Phase 0's test: it shows the build and make test working before the
   library has a module, and that Contains, which later tests lean on,
   is right at its edges. *)

IMPORT C := Check;

VAR s: ARRAY 8 OF CHAR;

BEGIN
  C.Check(C.Contains("gemini", "gem"), "Contains: a prefix");
  C.Check(C.Contains("gemini", "ini"), "Contains: a suffix");
  C.Check(C.Contains("gemini", "gemini"), "Contains: the whole string");
  C.Check(C.Contains("gemini", ""), "Contains: the empty string");
  C.Check(C.Contains("", ""), "Contains: the empty string in itself");
  C.Check(~C.Contains("gemini", "geminis"), "Contains: longer than the string");
  C.Check(~C.Contains("gemini", "x"), "Contains: absent");
  C.Check(~C.Contains("", "x"), "Contains: in the empty string");
  (* An array filled to its end, with no 0X: Contains must stop at LEN. *)
  s := "abcdefg"; s[7] := "h";
  C.Check(C.Contains(s, "gh"), "Contains: an array with no 0X, at its end");
  C.Check(~C.Contains(s, "hi"), "Contains: an array with no 0X, not past its end");
  C.Summary
END TestCheck.
