# GeminiHeaders: a response's header: read, and written

<!-- Made by doc/mkref.py from GeminiHeaders.Mod; edit the source, then make doc. -->

A response header (protocol specification, 0.24.1, "Responses"): two digits, the status; a space and the meta, which input (1x), success (2x) and redirects (3x) must have and failures (4x..6x) may leave out; CR LF. The header is UTF-8, with no byte order mark and no control character. The specification sets no limit on its length; ours is pogemini's, a meta of at most 1024 bytes, so a header is at most 1029.

Parse refuses (FALSE, and why) what the specification forbids, and never halts on what a server sends. It is lenient in two ways, each what servers send: a success with no MIME type ("20" or "20 "), which 0.24.1 forbids but earlier versions took as "text/gemini; charset=utf-8", as ParseMime does; and a space after a failure's status with no message after it.

WriteHeader is a server's, and halts on what it may not send: those are the program's mistakes (PLAN.md, "Halt codes").

## Constants

```oberon
MaxMeta* = 1024;               (* a meta at most, as pogemini's *)
MaxHeader* = MaxMeta + 5;      (* a header at most: status, space, meta, CR LF *)
MaxName* = 127;                (* a MIME type or subtype at most (RFC 6838) *)
```

## Types

```oberon
Header* = RECORD
  status-: INTEGER;
  meta-: ARRAY MaxMeta + 1 OF CHAR
END;
```

A header, as Parse gives it: meta is "" when it had none.

```oberon
Line* = ARRAY MaxHeader + 1 OF CHAR;
```

A header as WriteHeader writes it, 0X after.

```oberon
Chars* = POINTER TO ARRAY OF CHAR;
```

```oberon
Parameter* = RECORD
  name-, value-: Chars
END;
```

A MIME parameter: its name in lower case, its value as written (unquoted, if it was quoted).

```oberon
Parameters* = POINTER TO ARRAY OF Parameter;
```

```oberon
Mime* = RECORD
  type-, subtype-: ARRAY MaxName + 1 OF CHAR;
  params-: Parameters;
  count-: INTEGER;
  assumed-, skipped-: BOOLEAN
END;
```

A MIME type, as ParseMime gives it: type and subtype in lower case, params[0..count-1] in order. assumed: the meta was empty, so it is "text/gemini; charset=utf-8". skipped: something after the subtype wasn't a parameter, and was left out, as the specification says to leave out parameters not understood.

## Procedures

#### Ended

```oberon
PROCEDURE Ended*(buf-: ARRAY OF CHAR; len: LONGINT; VAR n: LONGINT): BOOLEAN;
```

Whether buf[0..len-1] holds as much as Parse needs: a header's end within MaxHeader bytes, n the bytes up to and including its LF; or MaxHeader bytes without one, n MaxHeader, which Parse refuses. A client reads until it gives TRUE, then gives buf[0..n-1] to Parse; the body begins at n.

#### Parse

```oberon
PROCEDURE Parse*(line-: ARRAY OF CHAR; len: LONGINT; VAR h: Header;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

The header line[0..len-1], CR LF and all: its status and meta in h, or FALSE and why, h's status 0.

#### WriteHeader

```oberon
PROCEDURE WriteHeader*(status: INTEGER; meta-: ARRAY OF CHAR; VAR line: Line;
    VAR len: LONGINT);
```

The header for status and meta ("" for none) in line[0..len-1], 0X after. Halts on a status the specification doesn't name (servers MUST NOT send one), and on a meta the specification forbids: longer than MaxMeta, not UTF-8, with a control character, or empty after a status of input, success or a redirect.

#### ParseMime

```oberon
PROCEDURE ParseMime*(meta-: ARRAY OF CHAR; VAR m: Mime; VAR why: ARRAY OF CHAR): BOOLEAN;
```

meta as a MIME type (RFC 2045, "type/subtype; name=value; ..."), as a success's header gives it: FALSE, and why, if it has no type and subtype. An empty meta is "text/gemini; charset=utf-8" (assumed).

#### Is

```oberon
PROCEDURE Is*(m-: Mime; type-, subtype-: ARRAY OF CHAR): BOOLEAN;
```

Whether m is type/subtype, case aside: Is(m, "text", "gemini").

#### Param

```oberon
PROCEDURE Param*(m-: Mime; name-: ARRAY OF CHAR; VAR value: ARRAY OF CHAR): BOOLEAN;
```

The value of m's first parameter called name (case aside), cut to fit value, or FALSE if it has none.

#### Charset

```oberon
PROCEDURE Charset*(m-: Mime; VAR cs: ARRAY OF CHAR);
```

m's charset, in lower case: its parameter's, or "utf-8" for a text type without one, as the specification says ("Success"); "" for any other type without one.
