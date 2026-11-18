MODULE GeminiPunycode; (* Internationalised host names, as punycode *)

(* A host written in letters beyond ASCII (an IRI's, or a link's in a
   page) has to reach DNS, SNI and a request line as ASCII. IDNA does
   that label by label: a label that is not ASCII becomes "xn--"
   followed by its punycode (RFC 3492), and ToAscii does that. ToUnicode
   goes back, for a program to show the name.

   This is the first of IDNA's three levels (PLAN.md, "Internationalised
   host names"): punycode only. It does not fold the case of letters
   beyond ASCII (so "BÜCHER.example" gives a name that won't resolve),
   normalise (NFC), or check which characters IDNA2008 allows. A
   program that shows a decoded host is responsible for what it shows
   (homographs).

   Nothing here halts: input that can't be converted, or a result that
   doesn't fit, gives FALSE and the reason in why. *)

CONST
  MaxLabel* = 63;   (* bytes in a label, once ASCII (RFC 1035) *)
  MaxHost* = 253;   (* bytes in a host, once ASCII, without a final "." *)
  (* Code points in one label Encode or Decode takes or gives: more
     than any label that fits in MaxLabel bytes once encoded. *)
  MaxCodePoints = 256;

  (* RFC 3492, section 5. *)
  Base = 36; TMin = 1; TMax = 26; Skew = 38; Damp = 700;
  InitialBias = 72; InitialN = 128;
  (* Section 6.4: its overflow checks, against a 32-bit maxint, so that
     what this decodes is what any other decoder does. *)
  MaxInt = 7FFFFFFFH;

TYPE
  CodePoints = ARRAY MaxCodePoints OF LONGINT;

PROCEDURE Length(s-: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END; RETURN n
END Length;

PROCEDURE Lower(c: CHAR): CHAR;
BEGIN
  IF (c >= "A") & (c <= "Z") THEN RETURN CHR(ORD(c) + 32) ELSE RETURN c END
END Lower;

PROCEDURE Fail(VAR why: ARRAY OF CHAR; reason: ARRAY OF CHAR): BOOLEAN;
BEGIN COPY(reason, why); RETURN FALSE
END Fail;

(* Decodes s[from..to-1], UTF-8, into cp[0..n-1]: FALSE if it is not
   well-formed (RFC 3629: no overlong forms, no surrogates, nothing over
   U+10FFFF) or has more than MaxCodePoints. *)
PROCEDURE FromUtf8(s-: ARRAY OF CHAR; from, to: LONGINT; VAR cp: CodePoints;
    VAR n: LONGINT; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR i, k, c: LONGINT; lo, hi: CHAR;
BEGIN
  i := from; n := 0;
  WHILE i < to DO
    c := ORD(s[i]); lo := 80X; hi := 0BFX;
    IF c < 80H THEN k := 0
    ELSIF (c >= 0C2H) & (c <= 0DFH) THEN k := 1; c := c - 0C0H
    ELSIF c = 0E0H THEN k := 2; lo := 0A0X; c := 0
    ELSIF c = 0EDH THEN k := 2; hi := 9FX; c := 0DH
    ELSIF (c >= 0E1H) & (c <= 0EFH) THEN k := 2; c := c - 0E0H
    ELSIF c = 0F0H THEN k := 3; lo := 90X; c := 0
    ELSIF c = 0F4H THEN k := 3; hi := 8FX; c := 4
    ELSIF (c >= 0F1H) & (c <= 0F3H) THEN k := 3; c := c - 0F0H
    ELSE RETURN Fail(why, "not UTF-8")
    END;
    INC(i);
    IF k > 0 THEN
      IF (i >= to) OR (s[i] < lo) OR (s[i] > hi) THEN RETURN Fail(why, "not UTF-8") END;
      c := c * 64 + ORD(s[i]) - 80H; INC(i); DEC(k);
      WHILE k > 0 DO
        IF (i >= to) OR (s[i] < 80X) OR (s[i] > 0BFX) THEN RETURN Fail(why, "not UTF-8") END;
        c := c * 64 + ORD(s[i]) - 80H; INC(i); DEC(k)
      END
    END;
    IF n = MaxCodePoints THEN RETURN Fail(why, "too long") END;
    cp[n] := c; INC(n)
  END;
  RETURN TRUE
END FromUtf8;

(* Appends c to s at s[p], as UTF-8, moving p on: FALSE if it doesn't
   fit with a 0X after it. *)
PROCEDURE PutUtf8(c: LONGINT; VAR s: ARRAY OF CHAR; VAR p: LONGINT): BOOLEAN;
  VAR k, lead: LONGINT;
BEGIN
  IF c < 80H THEN k := 0; lead := 0
  ELSIF c < 800H THEN k := 1; lead := 0C0H
  ELSIF c < 10000H THEN k := 2; lead := 0E0H
  ELSE k := 3; lead := 0F0H
  END;
  IF p + k + 1 >= LEN(s) THEN RETURN FALSE END;
  s[p] := CHR(lead + ASH(c, -6 * k)); INC(p);
  WHILE k > 0 DO
    DEC(k); s[p] := CHR(80H + ASH(c, -6 * k) MOD 64); INC(p)
  END;
  RETURN TRUE
END PutUtf8;

(* Appends c to s at s[p], moving p on: FALSE if it doesn't fit with a
   0X after it. *)
PROCEDURE Put(c: CHAR; VAR s: ARRAY OF CHAR; VAR p: LONGINT): BOOLEAN;
BEGIN
  IF p + 1 >= LEN(s) THEN RETURN FALSE END;
  s[p] := c; INC(p); RETURN TRUE
END Put;

(* Section 6.1. *)
PROCEDURE Adapt(delta, numPoints: LONGINT; first: BOOLEAN): LONGINT;
  VAR k: LONGINT;
BEGIN
  IF first THEN delta := delta DIV Damp ELSE delta := delta DIV 2 END;
  INC(delta, delta DIV numPoints);
  k := 0;
  WHILE delta > ((Base - TMin) * TMax) DIV 2 DO
    delta := delta DIV (Base - TMin); INC(k, Base)
  END;
  RETURN k + (Base - TMin + 1) * delta DIV (delta + Skew)
END Adapt;

(* The threshold for the digit at k (section 6.2's t). *)
PROCEDURE Threshold(k, bias: LONGINT): LONGINT;
BEGIN
  IF k <= bias THEN RETURN TMin
  ELSIF k >= bias + TMax THEN RETURN TMax
  ELSE RETURN k - bias
  END
END Threshold;

(* Digit d, 0..35, as "a".."z", "0".."9": lower case, as every encoder
   writes it. *)
PROCEDURE Digit(d: LONGINT): CHAR;
BEGIN
  IF d < 26 THEN RETURN CHR(ORD("a") + d) ELSE RETURN CHR(ORD("0") + d - 26) END
END Digit;

(* The value of digit c, either case, or -1. *)
PROCEDURE Value(c: CHAR): LONGINT;
BEGIN
  IF (c >= "a") & (c <= "z") THEN RETURN ORD(c) - ORD("a")
  ELSIF (c >= "A") & (c <= "Z") THEN RETURN ORD(c) - ORD("A")
  ELSIF (c >= "0") & (c <= "9") THEN RETURN ORD(c) - ORD("0") + 26
  ELSE RETURN -1
  END
END Value;

(* Encodes cp[0..n-1] by section 6.3, appending to out at p. *)
PROCEDURE EncodePoints(VAR cp: CodePoints; n: LONGINT; VAR out: ARRAY OF CHAR;
    VAR p: LONGINT; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR i, b, h, m, cn, delta, bias, q, k, t: LONGINT;
BEGIN
  b := 0; i := 0;
  WHILE i < n DO
    IF cp[i] < 80H THEN
      IF ~Put(CHR(cp[i]), out, p) THEN RETURN Fail(why, "too long for the buffer") END;
      INC(b)
    END;
    INC(i)
  END;
  IF (b > 0) & ~Put("-", out, p) THEN RETURN Fail(why, "too long for the buffer") END;
  h := b; cn := InitialN; delta := 0; bias := InitialBias;
  WHILE h < n DO
    m := MaxInt; i := 0;
    WHILE i < n DO IF (cp[i] >= cn) & (cp[i] < m) THEN m := cp[i] END; INC(i) END;
    IF m - cn > (MaxInt - delta) DIV (h + 1) THEN RETURN Fail(why, "overflow") END;
    INC(delta, (m - cn) * (h + 1)); cn := m;
    i := 0;
    WHILE i < n DO
      IF cp[i] < cn THEN
        IF delta = MaxInt THEN RETURN Fail(why, "overflow") END;
        INC(delta)
      ELSIF cp[i] = cn THEN
        q := delta; k := Base;
        LOOP
          t := Threshold(k, bias);
          IF q < t THEN EXIT END;
          IF ~Put(Digit(t + (q - t) MOD (Base - t)), out, p) THEN
            RETURN Fail(why, "too long for the buffer")
          END;
          q := (q - t) DIV (Base - t); INC(k, Base)
        END;
        IF ~Put(Digit(q), out, p) THEN RETURN Fail(why, "too long for the buffer") END;
        bias := Adapt(delta, h + 1, h = b); delta := 0; INC(h)
      END;
      INC(i)
    END;
    INC(delta); INC(cn)
  END;
  RETURN TRUE
END EncodePoints;

(* Decodes s[from..to-1] by section 6.2 into cp[0..n-1]. *)
PROCEDURE DecodePoints(s-: ARRAY OF CHAR; from, to: LONGINT; VAR cp: CodePoints;
    VAR n: LONGINT; VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR b, j, in, i, oldi, w, k, d, t, cn, bias: LONGINT;
BEGIN
  (* The basic code points are those before the last "-", if any. *)
  b := from; j := from;
  WHILE j < to DO IF s[j] = "-" THEN b := j END; INC(j) END;
  n := 0; j := from;
  WHILE j < b DO
    IF s[j] >= 80X THEN RETURN Fail(why, "not ASCII") END;
    IF n = MaxCodePoints THEN RETURN Fail(why, "too long") END;
    cp[n] := ORD(s[j]); INC(n); INC(j)
  END;
  IF b > from THEN in := b + 1 ELSE in := from END;
  cn := InitialN; i := 0; bias := InitialBias;
  WHILE in < to DO
    oldi := i; w := 1; k := Base;
    LOOP
      IF in >= to THEN RETURN Fail(why, "ends in the middle of a number") END;
      d := Value(s[in]); INC(in);
      IF d < 0 THEN RETURN Fail(why, "not a punycode digit") END;
      IF d > (MaxInt - i) DIV w THEN RETURN Fail(why, "overflow") END;
      INC(i, d * w);
      t := Threshold(k, bias);
      IF d < t THEN EXIT END;
      IF w > MaxInt DIV (Base - t) THEN RETURN Fail(why, "overflow") END;
      w := w * (Base - t); INC(k, Base)
    END;
    bias := Adapt(i - oldi, n + 1, oldi = 0);
    IF i DIV (n + 1) > MaxInt - cn THEN RETURN Fail(why, "overflow") END;
    INC(cn, i DIV (n + 1)); i := i MOD (n + 1);
    (* cn starts at 128 and only grows, so it is never ASCII (section
       6.2's check); what isn't a character can't be written as UTF-8. *)
    IF (cn >= 0D800H) & (cn <= 0DFFFH) OR (cn > 10FFFFH) THEN
      RETURN Fail(why, "encodes something not a character")
    END;
    IF n = MaxCodePoints THEN RETURN Fail(why, "too long") END;
    j := n; WHILE j > i DO cp[j] := cp[j - 1]; DEC(j) END;
    cp[i] := cn; INC(n); INC(i)
  END;
  RETURN TRUE
END DecodePoints;

(* Encodes label, UTF-8 to its 0X, into out as RFC 3492's punycode,
   with no "xn--" and its ASCII letters' case kept: FALSE, with why, if
   label is not UTF-8, is too long, or the result doesn't fit out. It
   is the bare algorithm, for a program that needs it, and to test
   against the RFC's samples; a host goes through ToAscii. *)
PROCEDURE Encode*(label-: ARRAY OF CHAR; VAR out: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR cp: CodePoints; n, p: LONGINT;
BEGIN
  why[0] := 0X; p := 0;
  IF LEN(out) > 0 THEN out[0] := 0X END;
  IF ~FromUtf8(label, 0, Length(label), cp, n, why) OR ~EncodePoints(cp, n, out, p, why) THEN
    IF LEN(out) > 0 THEN out[0] := 0X END;
    RETURN FALSE
  END;
  out[p] := 0X; RETURN TRUE
END Encode;

(* Decodes puny, RFC 3492's punycode with no "xn--", into out as UTF-8:
   FALSE, with why, if it isn't punycode or the result doesn't fit out.
   Digits are taken in either case, and ASCII letters keep theirs. *)
PROCEDURE Decode*(puny-: ARRAY OF CHAR; VAR out: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR cp: CodePoints; n, p, i: LONGINT;
BEGIN
  why[0] := 0X; p := 0;
  IF LEN(out) > 0 THEN out[0] := 0X END;
  IF ~DecodePoints(puny, 0, Length(puny), cp, n, why) THEN RETURN FALSE END;
  i := 0;
  WHILE i < n DO
    IF ~PutUtf8(cp[i], out, p) THEN out[0] := 0X; RETURN Fail(why, "too long for the buffer") END;
    INC(i)
  END;
  out[p] := 0X; RETURN TRUE
END Decode;

(* host is an IPv6 address (it has a ":"), which has no labels. *)
PROCEDURE IPv6(host-: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE (i < n) & (host[i] # ":") DO INC(i) END;
  RETURN i < n
END IPv6;

(* s[from..to-1] begins "xn--", either case. *)
PROCEDURE Prefixed(s-: ARRAY OF CHAR; from, to: LONGINT): BOOLEAN;
BEGIN
  RETURN (to - from >= 4) & (Lower(s[from]) = "x") & (Lower(s[from + 1]) = "n")
    & (s[from + 2] = "-") & (s[from + 3] = "-")
END Prefixed;

(* Sets why to "label <n>: <reason>". *)
PROCEDURE LabelWhy(n: LONGINT; reason-: ARRAY OF CHAR; VAR why: ARRAY OF CHAR);
  VAR s: ARRAY 128 OF CHAR; p, i: LONGINT; d: ARRAY 12 OF CHAR;
BEGIN
  s := "label "; p := 6;
  i := 0; REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  WHILE i > 0 DO DEC(i); s[p] := d[i]; INC(p) END;
  s[p] := ":"; s[p + 1] := " "; INC(p, 2);
  i := 0; WHILE (reason[i] # 0X) & (p < LEN(s) - 1) DO s[p] := reason[i]; INC(p); INC(i) END;
  s[p] := 0X;
  COPY(s, why)
END LabelWhy;

(* ToAscii's work; ToAscii clears ascii if it fails. *)
PROCEDURE Ascii(host-: ARRAY OF CHAR; VAR ascii: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR n, i, j, k, m, p, start, label, end: LONGINT; plain: BOOLEAN; cp: CodePoints;
    reason: ARRAY 64 OF CHAR;
BEGIN
  why[0] := 0X; p := 0;
  IF LEN(ascii) > 0 THEN ascii[0] := 0X END;
  n := Length(host);
  IF n = 0 THEN RETURN Fail(why, "no host") END;
  IF IPv6(host, n) THEN
    IF n >= LEN(ascii) THEN RETURN Fail(why, "too long for the buffer") END;
    i := 0; WHILE i < n DO ascii[i] := Lower(host[i]); INC(i) END;
    ascii[n] := 0X; RETURN TRUE
  END;
  end := n;
  IF (n > 1) & (host[n - 1] = ".") THEN DEC(end) END;
  i := 0; label := 0;
  WHILE i <= end DO
    INC(label);
    j := i; plain := TRUE;
    WHILE (j < end) & (host[j] # ".") DO
      IF (host[j] <= " ") OR (host[j] = 7FX) THEN
        LabelWhy(label, "a space or control character", why); RETURN FALSE
      END;
      IF host[j] >= 80X THEN plain := FALSE END;
      INC(j)
    END;
    IF j = i THEN LabelWhy(label, "empty", why); RETURN FALSE END;
    IF label > 1 THEN
      IF ~Put(".", ascii, p) THEN RETURN Fail(why, "too long for the buffer") END
    END;
    start := p;
    IF plain THEN
      k := i;
      WHILE k < j DO
        IF ~Put(Lower(host[k]), ascii, p) THEN RETURN Fail(why, "too long for the buffer") END;
        INC(k)
      END
    ELSE
      IF ~FromUtf8(host, i, j, cp, m, reason) THEN LabelWhy(label, reason, why); RETURN FALSE END;
      k := 0;
      WHILE k < m DO
        IF (cp[k] >= ORD("A")) & (cp[k] <= ORD("Z")) THEN INC(cp[k], 32) END;
        INC(k)
      END;
      IF ~Put("x", ascii, p) OR ~Put("n", ascii, p) OR ~Put("-", ascii, p) OR ~Put("-", ascii, p) THEN
        RETURN Fail(why, "too long for the buffer")
      END;
      IF ~EncodePoints(cp, m, ascii, p, reason) THEN LabelWhy(label, reason, why); RETURN FALSE END
    END;
    IF p - start > MaxLabel THEN
      LabelWhy(label, "over 63 bytes", why); RETURN FALSE
    END;
    i := j + 1
  END;
  IF p > MaxHost THEN RETURN Fail(why, "the host is over 253 bytes") END;
  IF end < n THEN
    IF ~Put(".", ascii, p) THEN RETURN Fail(why, "too long for the buffer") END
  END;
  ascii[p] := 0X;
  RETURN TRUE
END Ascii;

(* Converts host, UTF-8 to its 0X, to its ASCII form in ascii, for DNS,
   SNI, a request line and the known-hosts file. Each label, between
   "."s, that is ASCII is lowered (one already "xn--" is taken as it
   is); any other has its ASCII letters lowered and becomes "xn--" and
   its punycode. A host with a ":" is an IPv6 address and is only
   lowered, and an IPv4 address is ASCII, so an IP address comes back
   as it was, but lowered. One "." at the end is kept, as DNS allows.

   FALSE, with why naming the label (counted from 1) if it is one
   label's fault: no host, an empty label, a space or control
   character, malformed UTF-8, a label over MaxLabel bytes or a host
   over MaxHost once converted, or a result that doesn't fit ascii. *)
PROCEDURE ToAscii*(host-: ARRAY OF CHAR; VAR ascii: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
BEGIN
  why[0] := 0X;
  IF Ascii(host, ascii, why) THEN RETURN TRUE END;
  IF LEN(ascii) > 0 THEN ascii[0] := 0X END;
  RETURN FALSE
END ToAscii;

(* Converts host, an ASCII host as ToAscii gives, to the text it stands
   for in text, UTF-8, for a program to show: each "xn--" label (either
   case) decoded, every other label copied as it is. A label that does
   not decode is copied as it is too, and reported: FALSE, with text
   still the whole host and why naming the first such label. FALSE with
   text empty if it doesn't fit text. *)
PROCEDURE ToUnicode*(host-: ARRAY OF CHAR; VAR text: ARRAY OF CHAR;
    VAR why: ARRAY OF CHAR): BOOLEAN;
  VAR n, i, j, k, p, label, m: LONGINT; ok: BOOLEAN; cp: CodePoints;
    reason: ARRAY 64 OF CHAR;
BEGIN
  why[0] := 0X; p := 0; ok := TRUE;
  IF LEN(text) > 0 THEN text[0] := 0X END;
  n := Length(host);
  i := 0; label := 0;
  WHILE i < n DO
    INC(label);
    j := i; WHILE (j < n) & (host[j] # ".") DO INC(j) END;
    IF Prefixed(host, i, j) & DecodePoints(host, i + 4, j, cp, m, reason) THEN
      k := 0;
      WHILE k < m DO
        IF ~PutUtf8(cp[k], text, p) THEN text[0] := 0X; RETURN Fail(why, "too long for the buffer") END;
        INC(k)
      END
    ELSE
      IF Prefixed(host, i, j) & ok THEN LabelWhy(label, reason, why); ok := FALSE END;
      k := i;
      WHILE k < j DO
        IF ~Put(host[k], text, p) THEN text[0] := 0X; RETURN Fail(why, "too long for the buffer") END;
        INC(k)
      END
    END;
    IF j < n THEN
      IF ~Put(".", text, p) THEN text[0] := 0X; RETURN Fail(why, "too long for the buffer") END
    END;
    i := j + 1
  END;
  text[p] := 0X;
  RETURN ok
END ToUnicode;

END GeminiPunycode.
