MODULE TestRedirects; (* FetchFollowing, against test/TestServer *)

(* Redirects followed, relative and absolute; a loop, too many, another
   scheme, an empty location refused; another host asked about. Through
   GeminiFetch, and once through GeminiClient, whose waiting is all that
   differs. *)

IMPORT Check, Server, ClientCases, GeminiUrls, GeminiResponses, GeminiFetch, GeminiClient;

VAR
  port: INTEGER;
  asked: INTEGER;
  fromHost, toHost: ARRAY 256 OF CHAR;

PROCEDURE Refuse(VAR from, to: GeminiUrls.URL): BOOLEAN;
BEGIN INC(asked); COPY(from.host, fromHost); COPY(to.host, toHost); RETURN FALSE
END Refuse;

PROCEDURE Allow(VAR from, to: GeminiUrls.URL): BOOLEAN;
BEGIN INC(asked); COPY(from.host, fromHost); COPY(to.host, toHost); RETURN TRUE
END Allow;

PROCEDURE Body(r: GeminiResponses.Response; part: ARRAY OF CHAR): BOOLEAN;
  VAR b: GeminiResponses.Chars; n: LONGINT;
BEGIN RETURN r.ReadAll(b, n) & ClientCases.Has(b^, n, part)
END Body;

(* Follows path on the test server, at most max, with policy: ok, and r.
   The r before is closed first: a success not read stays open. *)
PROCEDURE Follow(path: ARRAY OF CHAR; max: INTEGER; policy: GeminiResponses.RedirectPolicy;
    VAR r: GeminiResponses.Response): BOOLEAN;
  VAR opts: GeminiResponses.Options; url: ARRAY 512 OF CHAR;
BEGIN
  IF r # NIL THEN r.Close END;
  GeminiResponses.InitOptions(opts);
  ClientCases.Url("localhost", port, path, url);
  RETURN GeminiFetch.FetchFollowing(url, opts, max, policy, r)
END Follow;

PROCEDURE Refused(ok: BOOLEAN; r: GeminiResponses.Response; text: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN ~ok & (r.error.kind = GeminiResponses.redirect) & (r.status DIV 10 = 3)
    & Check.Contains(r.error.text, text)
END Refused;

PROCEDURE Cases;
  VAR r: GeminiResponses.Response; ok: BOOLEAN; path, abs: ARRAY 512 OF CHAR;
    opts: GeminiResponses.Options;
BEGIN
  r := NIL;
  GeminiResponses.InitOptions(opts);
  ClientCases.Url("localhost", port, "/r/to?target", path);
  Check.Check(GeminiFetch.Fetch(path, opts, r) & (r.status = 30) & (r.meta = "target"),
    "Fetch gives a redirect as it came");

  ok := Follow("/r/to?target", 0, NIL, r);
  Check.Check(ok & (r.status = 20) & (r.url.path = "/r/target") & ~r.url.hasQuery
    & Body(r, "url gemini://localhost"), "a relative redirect followed, the old query left behind");
  ok := Follow("/r/to?../top?q", 0, NIL, r);
  Check.Check(ok & (r.status = 20) & (r.url.path = "/top") & (r.url.query = "q"),
    "... resolved against the URL that gave it");
  ClientCases.Url("localhost", port, "/abs", abs);
  path := "/r/to?"; ClientCases.Append(path, abs);
  ok := Follow(path, 0, NIL, r);
  Check.Check(ok & (r.status = 20) & (r.url.path = "/abs"), "an absolute redirect followed");
  ok := Follow("/r/to?//localhost:1/x", 0, NIL, r);
  Check.Check(Refused(ok, r, "another host"), "another port is another host");

  ok := Follow("/r/chain/5", 0, NIL, r);
  Check.Check(ok & (r.status = 20) & Body(r, "chain end"), "5 redirects followed, the most by default");
  ok := Follow("/r/chain/6", 0, NIL, r);
  Check.Check(Refused(ok, r, "too many") & (r.url.path = "/r/chain/1"), "a 6th not followed");
  ok := Follow("/r/chain/6", 99, NIL, r);
  Check.Check(Refused(ok, r, "too many"), "... even when more are asked for");
  ok := Follow("/r/chain/2", 1, NIL, r);
  Check.Check(Refused(ok, r, "too many") & (r.url.path = "/r/chain/1"), "a max of 1 follows 1");
  ok := Follow("/r/chain/1", 1, NIL, r);
  Check.Check(ok & (r.status = 20), "... and only 1");

  ok := Follow("/r/self", 0, NIL, r);
  Check.Check(Refused(ok, r, "loop"), "a redirect to itself: a loop");
  ok := Follow("/r/to?https://example.org/", 0, NIL, r);
  Check.Check(Refused(ok, r, "isn't gemini"), "a redirect to another scheme: refused");
  ok := Follow("/r/to?", 0, NIL, r);
  Check.Check(~ok & (r.error.kind = GeminiResponses.header) & Check.Contains(r.error.text, "no URL"),
    "an empty location: a malformed header, not followed");

  path := "/r/to?"; ClientCases.Url("127.0.0.1", port, "/there", abs); ClientCases.Append(path, abs);
  ok := Follow(path, 0, NIL, r);
  Check.Check(Refused(ok, r, "another host"), "another host, no policy: refused");
  asked := 0;
  ok := Follow(path, 0, Refuse, r);
  Check.Check(Refused(ok, r, "another host") & (asked = 1)
    & (fromHost = "localhost") & (toHost = "127.0.0.1"),
    "another host: the policy asked, and refusing");
  asked := 0;
  ok := Follow(path, 0, Allow, r);
  Check.Check(ok & (asked = 1) & (r.status = 20) & (r.url.host = "127.0.0.1") & (r.url.path = "/there"),
    "... and allowing");
  asked := 0;
  ok := Follow("/r/to?target", 0, Refuse, r);
  Check.Check(ok & (asked = 0), "the policy isn't asked about the same host");

  r.Close;
  ClientCases.Url("localhost", port, "/r/chain/3", path);
  ok := GeminiClient.FetchFollowing(path, opts, 0, NIL, r);
  Check.Check(ok & (r.status = 20) & Body(r, "chain end"), "GeminiClient follows them too")
END Cases;

BEGIN
  port := Server.Start();
  IF port > 0 THEN Cases; Server.Stop END;
  Check.Summary
END TestRedirects.
