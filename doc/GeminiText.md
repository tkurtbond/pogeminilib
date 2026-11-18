# GeminiText: gemtext, parsed: a line at a time, or a whole page

<!-- Made by doc/mkref.py from GeminiText.Mod; edit the source, then make doc. -->

Gemtext (text/gemini) as the gemtext specification defines it: each line's type from its first three bytes and whether a preformatted block is open.

A Parser takes a page's bytes as they come and gives its lines, in memory fixed when it is made: a line longer than its buffer comes out in pieces, as much as fits each time, so no line is too long and no page too large. A piece never ends inside a UTF-8 character unless the bytes there aren't UTF-8. Parse gives a whole page's lines, joined, for a program that has the page in memory.

Nothing here halts on what a page holds: bytes that aren't UTF-8 are kept, and flagged; a link with no URL is flagged. A link's URL is kept as written, for the program to resolve (GeminiUrls.Resolve). Halts are for a program's mistakes (PLAN.md, "Halt codes").

## Constants

```oberon
Text* = 0;          (* any line no other kind claims; an empty one too *)
Link* = 1;          (* "=>", a URL, perhaps a label *)
Heading* = 2;       (* "#", "##" or "###" *)
ListItem* = 3;      (* "* " *)
Quote* = 4;         (* ">" *)
Toggle* = 5;        (* three backticks: opens or closes a block *)
Preformatted* = 6;  (* a line inside a block *)
```

The kinds of line

```oberon
MinBuffer* = 8;
```

The smallest buffer a parser takes. A piece holds a byte less than the buffer (its 0X) and may stop up to three bytes short of that, so as not to split a character: eight leaves room for a four-byte character after a cut, so every piece makes progress.

```oberon
MaxURL* = 1024;
```

The longest URL kept: a request is at most 1024 bytes (GeminiUrls.MaxURL), so a longer URL can never be fetched.

## Types

```oberon
Chars* = POINTER TO ARRAY OF CHAR;
```

```oberon
Line* = RECORD
  kind-, level-: INTEGER;
  first-, last-: BOOLEAN;
  malformed-, noUrl-, urlTooLong-: BOOLEAN;
  text-: Chars;
  len-: LONGINT;
  url-: Chars;
  urlLen-: LONGINT
END;
```

A line, or a piece of one. text[0..len-1] is its text, 0X after: a heading's without its "#"s and the spaces or tabs after them; a list item's without "* "; a quote's without ">", any whitespace after it kept; a link's label, without the whitespace before it; an opening toggle's alt text, without the backticks; empty for a closing toggle. A page's bytes may hold 0X, so len, not the 0X, is the length.

A line longer than a parser's buffer comes in pieces: first is set in the first, last in the last (both in a line of one piece). kind and level (1..3 for a heading, else 0) hold for every piece; url, noUrl and urlTooLong are a link's first piece's.

malformed: the piece's text, or a link's URL, holds bytes that aren't UTF-8, kept as they came. noUrl: "=>" and nothing more but whitespace, a link to show as text or leave out, never to fetch. urlTooLong: the URL was longer than MaxURL bytes and url has its first MaxURL.

```oberon
Parser* = POINTER TO ParserDesc;
```

```oberon
Lines* = POINTER TO ARRAY OF Line;
```

```oberon
Document* = POINTER TO DocumentDesc;
DocumentDesc* = RECORD
  lines-: Lines;
  count-: LONGINT;
  title-: LONGINT
END;
```

A page: lines[0..count-1], each whole (first and last both set). title is the index of the first heading, -1 if none.

## Procedures

#### New

```oberon
PROCEDURE New*(size: LONGINT): Parser;
```

A parser whose pieces are at most size - 1 bytes; size at least MinBuffer, or it halts.

#### Feed

```oberon
PROCEDURE Feed*(p: Parser; buf-: ARRAY OF CHAR; VAR pos: LONGINT; end: LONGINT;
    VAR l: Line): BOOLEAN;
```

Takes bytes from buf[pos..end-1], advancing pos, until a piece is ready, which it gives in l (TRUE), or the bytes are used up (FALSE). Call it again, with the same bytes and pos, until it gives FALSE, then with the next bytes; then Finish. Every byte is used, so the parser keeps none of the caller's. l's text and url are made once, and given again: copy a piece to keep it.

#### Finish

```oberon
PROCEDURE Finish*(p: Parser; VAR l: Line): BOOLEAN;
```

At the page's end: gives any piece still to come (TRUE), and is called until it gives FALSE. A last line need not end in LF, and a preformatted block need not be closed. The parser is then ready for another page.

#### Parse

```oberon
PROCEDURE Parse*(text-: ARRAY OF CHAR; len: LONGINT): Document;
```

The page text[0..len-1], its lines whole.

#### NextLink

```oberon
PROCEDURE NextLink*(d: Document; i: LONGINT): LONGINT;
```

The index of the first link after line i, -1 if none: NextLink(d, -1) gives the first.
