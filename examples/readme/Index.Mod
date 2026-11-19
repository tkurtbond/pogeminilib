MODULE Index; (* writes index.gmi, a page linking to the files named *)

IMPORT Args, Out, Files, GeminiTextWriter;

VAR
  f: Files.File; r: Files.Rider; w: GeminiTextWriter.FileWriter;
  i: INTEGER; name: ARRAY 256 OF CHAR; why: ARRAY 128 OF CHAR; ok: BOOLEAN;

BEGIN
  f := Files.New("index.gmi"); Files.Set(r, f, 0);
  w := GeminiTextWriter.NewFile(r);
  ok := GeminiTextWriter.Heading(w, 1, "Index", why);
  i := 1;
  WHILE ok & (i < Args.argc) DO
    Args.Get(i, name);
    (* NameLink percent-encodes the name, so "a b?.gmi" is a file's name *)
    ok := GeminiTextWriter.NameLink(w, name, name, why); INC(i)
  END;
  IF ok THEN Files.Register(f) ELSE Out.String(why); Out.Ln END
END Index.
