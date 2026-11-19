MODULE Child; (* A command run as a child process, for the tests *)

(* A command, such as test/TestServer, pogemini or GeminiServe, run as
   a child process for the tests (copied from polibtls's test/, with
   pogemini's Interrupt), through pounix's UnixProcesses, with
   UnixFiles' WaitReadable for ReadLine's time limit. Spawn, Wait and
   ReadLine wait in the kernel and so stop every task: call them
   outside tasks. *)

IMPORT UnixErrors, UnixFiles, UnixProcesses;

TYPE
  Child* = RECORD p: UnixProcesses.Process END;

(* Runs command with /bin/sh -c as a child process, giving it
   input[0..inputlen-1] (at most 64 KiB) on its standard input and then
   end of file. FALSE if it couldn't start. Its output, standard error
   included, must fit 64 KiB until Wait reads it, since nothing reads it
   before. *)
PROCEDURE Spawn*(command, input: ARRAY OF CHAR; inputlen: LONGINT;
    VAR c: Child): BOOLEAN;
  VAR cmd: UnixProcesses.Command; err: UnixErrors.Error; pos, n: LONGINT;
BEGIN
  cmd := UnixProcesses.NewCommand("/bin/sh");
  UnixProcesses.Add(cmd, "-c"); UnixProcesses.Add(cmd, command);
  UnixProcesses.SetInput(cmd, UnixProcesses.pipe);
  UnixProcesses.SetOutput(cmd, UnixProcesses.pipe);
  UnixProcesses.SetError(cmd, UnixProcesses.toOutput);
  c.p := NIL;
  IF ~UnixProcesses.Start(cmd, c.p, err) THEN c.p := NIL; RETURN FALSE END;
  pos := 0;
  WHILE pos < inputlen DO
    IF ~UnixFiles.Write(c.p.in, input, pos, inputlen - pos, n, err) THEN
      UnixProcesses.Close(c.p);
      IF UnixProcesses.Wait(c.p, err) THEN END;
      c.p := NIL;
      RETURN FALSE
    END;
    INC(pos, n)
  END;
  UnixProcesses.CloseInput(c.p);
  RETURN TRUE
END Spawn;

(* Waits for c to end: its output, standard error included, as much as
   fits in got, with a 0X after it, and how much there was in all; its
   exit status, or -1 if it didn't exit normally or never started. *)
PROCEDURE Wait*(VAR c: Child; VAR got: ARRAY OF CHAR; VAR gotlen: LONGINT): INTEGER;
  VAR err: UnixErrors.Error; rest: ARRAY 4096 OF CHAR; keep, n: LONGINT;
BEGIN
  gotlen := 0; keep := LEN(got) - 1; got[0] := 0X;
  IF c.p = NIL THEN RETURN -1 END;
  LOOP
    IF gotlen < keep THEN
      IF ~UnixFiles.Read(c.p.out, got, gotlen, keep - gotlen, n, err) THEN EXIT END
    ELSIF ~UnixFiles.Read(c.p.out, rest, 0, LEN(rest), n, err) THEN EXIT
    END;
    IF n = 0 THEN EXIT END;
    INC(gotlen, n)
  END;
  IF gotlen < keep THEN got[gotlen] := 0X ELSE got[keep] := 0X END;
  UnixProcesses.Close(c.p);
  IF UnixProcesses.Wait(c.p, err) & c.p.exited THEN RETURN c.p.status END;
  RETURN -1
END Wait;

(* Reads c's next line of output, while it runs, into line, the newline
   included, waiting at most ms for each byte; FALSE if its output ended
   or ms passed first, or c never started. A byte at a time, so it
   never reads past the line: Wait gets what is left. *)
PROCEDURE ReadLine*(VAR c: Child; VAR line: ARRAY OF CHAR; ms: LONGINT): BOOLEAN;
  VAR err: UnixErrors.Error; i, n: LONGINT; ready: BOOLEAN;
BEGIN
  i := 0; line[0] := 0X;
  IF c.p = NIL THEN RETURN FALSE END;
  LOOP
    IF i = LEN(line) - 1 THEN EXIT END;
    IF ~UnixFiles.WaitReadable(c.p.out, ms, ready, err) OR ~ready
      OR ~UnixFiles.Read(c.p.out, line, i, 1, n, err) OR (n = 0) THEN
      line[i] := 0X; RETURN FALSE
    END;
    INC(i);
    IF line[i - 1] = 0AX THEN EXIT END
  END;
  line[i] := 0X;
  RETURN TRUE
END ReadLine;

(* Ends c, as for a server that won't finish by itself, by SIGTERM;
   Wait for it afterwards. Nothing for a child that never started. *)
PROCEDURE Kill*(VAR c: Child);
  VAR err: UnixErrors.Error;
BEGIN
  IF (c.p # NIL) & UnixProcesses.Signal(c.p, UnixProcesses.terminate, err) THEN END
END Kill;

(* Sends c SIGINT, as Control-C would; nothing for a child that never
   started. *)
PROCEDURE Interrupt*(VAR c: Child);
  VAR err: UnixErrors.Error;
BEGIN
  IF (c.p # NIL) & UnixProcesses.Signal(c.p, UnixProcesses.interrupt, err) THEN END
END Interrupt;

END Child.
