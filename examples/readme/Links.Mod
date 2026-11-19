MODULE Links; (* resolves links against a page's URL, as a client does *)

IMPORT Args, Out, GeminiUrls, GeminiPunycode;

VAR
  base, u: GeminiUrls.URL; i: INTEGER;
  arg, line: GeminiUrls.Text; host: ARRAY 256 OF CHAR; why: ARRAY 256 OF CHAR;

BEGIN
  Args.Get(1, arg);
  IF ~GeminiUrls.Parse(arg, base, why) THEN Out.String(why); Out.Ln
  ELSE
    FOR i := 2 TO Args.argc - 1 DO
      Args.Get(i, arg);
      IF ~GeminiUrls.Resolve(base, arg, u, why)
        OR ~GeminiUrls.RequestLine(u, line, why) THEN
        Out.String(arg); Out.String(": "); Out.String(why)
      ELSE
        Out.String(line);   (* what goes to the server, ASCII *)
        IF GeminiPunycode.ToUnicode(u.host, host, why) THEN
          Out.String(" (host "); Out.String(host); Out.String(")")
        END
      END;
      Out.Ln
    END
  END
END Links.
