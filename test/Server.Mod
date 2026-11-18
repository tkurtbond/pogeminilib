MODULE Server; (* test/TestServer run as a child, for the client's tests *)

(* Starts build/TestServer with the server's certificate, as a child,
   and reads the port it listens on; Stop ends it. Outside tasks
   (Child). *)

IMPORT Check, Child;

VAR
  c: Child.Child;

(* Starts it: its port, or 0 if it didn't start. *)
PROCEDURE Start*(): INTEGER;
  VAR line: ARRAY 64 OF CHAR; i, port: INTEGER;
BEGIN
  port := 0;
  IF Child.Spawn("exec ../build/TestServer ../build/certs/server-ec.crt ../build/certs/server-ec.key",
      "", 0, c)
    & Child.ReadLine(c, line, 5000) & (line[0] = "p") THEN
    i := 5;
    WHILE (line[i] >= "0") & (line[i] <= "9") DO port := 10 * port + ORD(line[i]) - ORD("0"); INC(i) END
  END;
  Check.Check(port > 0, "the test server starts");
  RETURN port
END Start;

(* Ends it, which must exit as it was asked. *)
PROCEDURE Stop*;
  VAR out: ARRAY 4096 OF CHAR; n: LONGINT;
BEGIN
  Child.Kill(c);
  Check.Check(Child.Wait(c, out, n) = 0, "the test server stops")
END Stop;

END Server.
