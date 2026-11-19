MODULE Outline; (* prints a gemtext file's headings and links *)

IMPORT Args, Out, Files, GeminiText;

VAR
  f: Files.File; r: Files.Rider; p: GeminiText.Parser; l: GeminiText.Line;
  buf: POINTER TO ARRAY 4096 OF CHAR; name: ARRAY 1024 OF CHAR;
  pos, end: LONGINT;

PROCEDURE Show(VAR l: GeminiText.Line);
BEGIN
  IF (l.kind = GeminiText.Heading) & l.first THEN
    Out.Int(l.level, 0); Out.String(" "); Out.String(l.text^); Out.Ln
  ELSIF (l.kind = GeminiText.Link) & l.first & ~l.noUrl THEN
    Out.String("  => "); Out.String(l.url^); Out.Ln
  END
END Show;

BEGIN
  Args.Get(1, name); f := Files.Old(name);
  IF f = NIL THEN Out.String("no file "); Out.String(name); Out.Ln
  ELSE
    (* Lines longer than 256 bytes come in pieces: only the first is shown. *)
    p := GeminiText.New(256); NEW(buf); Files.Set(r, f, 0);
    REPEAT
      Files.ReadBytes(r, buf^, LEN(buf^)); end := LEN(buf^) - r.res; pos := 0;
      WHILE GeminiText.Feed(p, buf^, pos, end, l) DO Show(l) END
    UNTIL r.eof OR (end = 0);
    WHILE GeminiText.Finish(p, l) DO Show(l) END
  END
END Outline.
