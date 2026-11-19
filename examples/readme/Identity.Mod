MODULE Identity; (* fetches a URL with the identity attached to it, made if need be *)

IMPORT Args, Out, GeminiUrls, GeminiResponses, GeminiIdentities, GeminiFetch;

VAR
  link: ARRAY 1100 OF CHAR; name: GeminiIdentities.Name; why: ARRAY 256 OF CHAR;
  url: GeminiUrls.URL; scopes: GeminiIdentities.Scopes; id: GeminiIdentities.Identity;
  opts: GeminiResponses.Options; r: GeminiResponses.Response; body: GeminiResponses.Chars;
  len: LONGINT; ok: BOOLEAN;

BEGIN
  Args.Get(1, link);
  ok := GeminiUrls.Parse(link, url, why) & GeminiIdentities.OpenScopes("scopes", scopes, why);
  IF ok THEN
    IF scopes.For(url, name) THEN ok := GeminiIdentities.Load("ids", name, id, why)
    ELSE
      (* None yet: one made, and attached to the URL and every page
         below it. A real client asks its user first (status 60). *)
      name := "me";
      ok := (GeminiIdentities.Load("ids", name, id, why)
             OR GeminiIdentities.Make("ids", name, "", GeminiIdentities.DefaultDays, id, why))
        & scopes.Attach(name, url, why)
    END
  END;
  IF ~ok THEN Out.String(why); Out.Ln
  ELSE
    Out.String("as "); Out.String(id.name); Out.String(", "); Out.String(id.hash); Out.Ln;
    GeminiResponses.InitOptions(opts); GeminiIdentities.Use(id, opts);
    IF ~GeminiFetch.Fetch(link, opts, r) THEN Out.String(r.error.text); Out.Ln
    ELSIF (r.status DIV 10 = 2) & r.ReadAll(body, len) THEN Out.String(body^)   (* its own line ends *)
    ELSE Out.Int(r.status, 0); Out.String(" "); Out.String(r.meta); Out.Ln
    END
  END
END Identity.
