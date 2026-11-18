# GeminiTextWriter: gemtext, written

<!-- Made by doc/mkref.py from GeminiTextWriter.Mod; edit the source, then make doc. -->

Writes gemtext a line at a time, each ended by LF, to a file (FileWriter) or to anything a Writer's extension writes to, as a server's exchange will.

Gemtext has no escape, so what would read back as something else is refused (FALSE, and why), not written, and the program chooses what to do instead: a text line that another kind would claim (one that begins "=>", "#", "* ", ">" or three backticks), a line end in any line, a line of the wrong kind for where it is (preformatted text outside a block, any other inside one), whitespace that a reader drops (before a heading's text or a link's label, or a byte order mark beginning the page), and a link whose URL is empty or holds a space or a control character.

What is written reads back through GeminiText as the same lines.

## Types

```oberon
Writer* = POINTER TO WriterDesc;
WriterDesc* = RECORD
  pre-: BOOLEAN;
END;
```

Writes gemtext. An extension overrides Put; pre is whether a preformatted block is open.

```oberon
FileWriter* = POINTER TO FileWriterDesc;
FileWriterDesc* = RECORD (WriterDesc)
  r*: Files.Rider
END;
```

Writes to r, which is left after the last byte written.

## Procedures

#### Put

```oberon
PROCEDURE (w: Writer) Put*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
```

Writes s[0..n-1]: FALSE if it couldn't. An extension's own; this one halts. (w is never NIL here: poc refuses an ASSERT that is always FALSE, and HALT would exit with another status than every other halt here.)

#### Put

```oberon
PROCEDURE (w: FileWriter) Put*(s-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
```

#### Init

```oberon
PROCEDURE Init*(w: Writer);
```

Makes w a writer at the start of a page.

#### NewFile

```oberon
PROCEDURE NewFile*(VAR r: Files.Rider): FileWriter;
```

A writer to r, which it copies: the rider w.r then goes on.

#### Text

```oberon
PROCEDURE Text*(w: Writer; s-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
```

A text line: refused if another kind would claim it.

#### Link

```oberon
PROCEDURE Link*(w: Writer; url-, label-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
```

A link to url, as written, with label (or none, if "").

#### NameLink

```oberon
PROCEDURE NameLink*(w: Writer; name-, label-: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

A link to name, a relative path of one segment, every byte of it percent-encoded but RFC 3986's unreserved (letters, digits, "-._~"), as pogemini's listings write them: so "a:b" is a name, not a scheme, and "a?b" not a query.

#### Heading

```oberon
PROCEDURE Heading*(w: Writer; level: INTEGER; s-: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

A heading of level 1..3; any other level halts.

#### ListItem

```oberon
PROCEDURE ListItem*(w: Writer; s-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
```

#### Quote

```oberon
PROCEDURE Quote*(w: Writer; s-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
```

A quote; whitespace at the start of s is kept, as a reader keeps it.

#### Open

```oberon
PROCEDURE Open*(w: Writer; alt-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
```

Opens a preformatted block, with alt text (or none, if "").

#### Close

```oberon
PROCEDURE Close*(w: Writer; VAR why: ARRAY OF CHAR): BOOLEAN;
```

#### Preformatted

```oberon
PROCEDURE Preformatted*(w: Writer; s-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR): BOOLEAN;
```

A line inside a block, as it is: refused if it would close it.
