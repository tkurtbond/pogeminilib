# GeminiPunycode: Internationalised host names, as punycode

<!-- Made by doc/mkref.py from GeminiPunycode.Mod; edit the source, then make doc. -->

A host written in letters beyond ASCII (an IRI's, or a link's in a page) has to reach DNS, SNI and a request line as ASCII. IDNA does that label by label: a label that is not ASCII becomes "xn--" followed by its punycode (RFC 3492), and ToAscii does that. ToUnicode goes back, for a program to show the name.

This is the first of IDNA's three levels (PLAN.md, "Internationalised host names"): punycode only. It does not fold the case of letters beyond ASCII (so "BÜCHER.example" gives a name that won't resolve), normalise (NFC), or check which characters IDNA2008 allows. A program that shows a decoded host is responsible for what it shows (homographs).

Nothing here halts: input that can't be converted, or a result that doesn't fit, gives FALSE and the reason in why.

## Constants

```oberon
MaxLabel* = 63;   (* bytes in a label, once ASCII (RFC 1035) *)
MaxHost* = 253;   (* bytes in a host, once ASCII, without a final "." *)
```

## Procedures

#### Encode

```oberon
PROCEDURE Encode*(label-: ARRAY OF CHAR; VAR out: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

Encodes label, UTF-8 to its 0X, into out as RFC 3492's punycode, with no "xn--" and its ASCII letters' case kept: FALSE, with why, if label is not UTF-8, is too long, or the result doesn't fit out. It is the bare algorithm, for a program that needs it, and to test against the RFC's samples; a host goes through ToAscii.

#### Decode

```oberon
PROCEDURE Decode*(puny-: ARRAY OF CHAR; VAR out: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

Decodes puny, RFC 3492's punycode with no "xn--", into out as UTF-8: FALSE, with why, if it isn't punycode or the result doesn't fit out. Digits are taken in either case, and ASCII letters keep theirs.

#### ToAscii

```oberon
PROCEDURE ToAscii*(host-: ARRAY OF CHAR; VAR ascii: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

Converts host, UTF-8 to its 0X, to its ASCII form in ascii, for DNS, SNI, a request line and the known-hosts file. Each label, between "."s, that is ASCII is lowered (one already "xn--" is taken as it is); any other has its ASCII letters lowered and becomes "xn--" and its punycode. A host with a ":" is an IPv6 address and is only lowered, and an IPv4 address is ASCII, so an IP address comes back as it was, but lowered. One "." at the end is kept, as DNS allows.

FALSE, with why naming the label (counted from 1) if it is one label's fault: no host, an empty label, a space or control character, malformed UTF-8, a label over MaxLabel bytes or a host over MaxHost once converted, or a result that doesn't fit ascii.

#### ToUnicode

```oberon
PROCEDURE ToUnicode*(host-: ARRAY OF CHAR; VAR text: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

Converts host, an ASCII host as ToAscii gives, to the text it stands for in text, UTF-8, for a program to show: each "xn--" label (either case) decoded, every other label copied as it is. A label that does not decode is copied as it is too, and reported: FALSE, with text still the whole host and why naming the first such label. FALSE with text empty if it doesn't fit text.
