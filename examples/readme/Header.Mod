MODULE Header; (* says what a response header means *)

IMPORT Args, Out, GeminiStatus, GeminiHeaders;

VAR
  line: GeminiHeaders.Line; h: GeminiHeaders.Header; m: GeminiHeaders.Mime;
  n: LONGINT; name: ARRAY 64 OF CHAR; cs: ARRAY 64 OF CHAR; why: ARRAY 128 OF CHAR;

BEGIN
  Args.Get(1, line); n := 0; WHILE line[n] # 0X DO INC(n) END;
  line[n] := 0DX; line[n + 1] := 0AX; INC(n, 2);   (* as it comes, CR LF *)
  IF ~GeminiHeaders.Parse(line, n, h, why) THEN Out.String(why)
  ELSE
    GeminiStatus.Name(h.status, name);
    Out.Int(h.status, 0); Out.String(": "); Out.String(name);
    IF GeminiStatus.Class(h.status) = GeminiStatus.SuccessClass THEN
      IF ~GeminiHeaders.ParseMime(h.meta, m, why) THEN Out.String(", "); Out.String(why)
      ELSE
        GeminiHeaders.Charset(m, cs);
        Out.String(", "); Out.String(m.type); Out.String("/"); Out.String(m.subtype);
        IF cs # "" THEN Out.String(" in "); Out.String(cs) END;
        IF GeminiHeaders.Is(m, "text", "gemini") THEN Out.String(", gemtext") END
      END
    ELSIF h.meta # "" THEN Out.String(", "); Out.String(h.meta)
    END
  END;
  Out.Ln
END Header.
