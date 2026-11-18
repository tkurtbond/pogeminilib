MODULE TestPunycode; (* GeminiPunycode: RFC 3492's samples, ToAscii, ToUnicode *)

(* The samples are RFC 3492's section 7.1, (A) to (S), taken from the
   RFC's text by a script, each with the encoding Python's punycode
   codec gives, an implementation independent of this one: they differ
   only in (I), where the RFC writes one letter of the encoding in
   upper case (its "mixed-case annotation"), which an encoder without
   annotations writes in lower case, and a decoder takes either way.
   Their own ASCII letters keep their case: Encode is the bare
   algorithm. The other expected values are Python's too. *)

IMPORT C := Check, P := GeminiPunycode;

VAR
  out, why: ARRAY 512 OF CHAR;
  small: ARRAY 8 OF CHAR;
  s: ARRAY 300 OF CHAR;

PROCEDURE Sample(label, text, rfc, encoder: ARRAY OF CHAR);
  VAR o, w: ARRAY 512 OF CHAR; l: ARRAY 64 OF CHAR;
BEGIN
  l := "sample ("; l[8] := label[0]; l[9] := ")"; l[10] := 0X;
  C.Check(P.Encode(text, o, w) & (o = encoder), l);
  C.Check(P.Decode(rfc, o, w) & (o = text), l);
  C.Check(P.Decode(encoder, o, w) & (o = text), l)
END Sample;

(* ToAscii(host) gives ascii, and ToUnicode gives text back: a round
   trip, the host lowered where ToAscii lowers it. *)
PROCEDURE Both(host, ascii, text, label: ARRAY OF CHAR);
  VAR o, w: ARRAY 512 OF CHAR;
BEGIN
  C.Check(P.ToAscii(host, o, w) & (o = ascii) & (w = ""), label);
  C.Check(P.ToUnicode(ascii, o, w) & (o = text) & (w = ""), label)
END Both;

(* ToAscii(host) fails, with why containing reason and ascii empty. *)
PROCEDURE Bad(host, reason, label: ARRAY OF CHAR);
  VAR o, w: ARRAY 512 OF CHAR;
BEGIN
  o := "junk";
  C.Check(~P.ToAscii(host, o, w) & (o = "") & C.Contains(w, reason), label)
END Bad;

(* s := n copies of c. *)
PROCEDURE Fill(VAR s: ARRAY OF CHAR; c: CHAR; n: INTEGER);
  VAR i: INTEGER;
BEGIN i := 0; WHILE i < n DO s[i] := c; INC(i) END; s[n] := 0X
END Fill;

BEGIN
  Sample("A", "ليهمابتكلموشعربي؟",
    "egbpdaj6bu4bxfgehfvwxn", "egbpdaj6bu4bxfgehfvwxn");
  Sample("B", "他们为什么不说中文",
    "ihqwcrb4cv8a8dqg056pqjye", "ihqwcrb4cv8a8dqg056pqjye");
  Sample("C", "他們爲什麽不說中文",
    "ihqwctvzc91f659drss3x8bo0yb", "ihqwctvzc91f659drss3x8bo0yb");
  Sample("D", "Pročprostěnemluvíčesky",
    "Proprostnemluvesky-uyb24dma41a", "Proprostnemluvesky-uyb24dma41a");
  Sample("E", "למההםפשוטלאמדבריםעברית",
    "4dbcagdahymbxekheh6e0a7fei0b", "4dbcagdahymbxekheh6e0a7fei0b");
  Sample("F", "यहलोगहिन्दीक्योंनहींबोलसकतेहैं",
    "i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd", "i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd");
  Sample("G", "なぜみんな日本語を話してくれないのか",
    "n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa", "n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa");
  Sample("H", "세계의모든사람들이한국어를이해한다면얼마나좋을까",
    "989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c", "989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c");
  Sample("I", "почемужеонинеговорятпорусски",
    "b1abfaaepdrnnbgefbaDotcwatmq2g4l", "b1abfaaepdrnnbgefbadotcwatmq2g4l");
  Sample("J", "PorquénopuedensimplementehablarenEspañol",
    "PorqunopuedensimplementehablarenEspaol-fmd56a", "PorqunopuedensimplementehablarenEspaol-fmd56a");
  Sample("K", "TạisaohọkhôngthểchỉnóitiếngViệt",
    "TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g", "TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g");
  Sample("L", "3年B組金八先生",
    "3B-ww4c5e180e575a65lsy2b", "3B-ww4c5e180e575a65lsy2b");
  Sample("M", "安室奈美恵-with-SUPER-MONKEYS",
    "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n", "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n");
  Sample("N", "Hello-Another-Way-それぞれの場所",
    "Hello-Another-Way--fc4qua05auwb3674vfr0b", "Hello-Another-Way--fc4qua05auwb3674vfr0b");
  Sample("O", "ひとつ屋根の下2",
    "2-u9tlzr9756bt3uc0v", "2-u9tlzr9756bt3uc0v");
  Sample("P", "MajiでKoiする5秒前",
    "MajiKoi5-783gue6qz075azm5e", "MajiKoi5-783gue6qz075azm5e");
  Sample("Q", "パフィーdeルンバ",
    "de-jg4avhby1noc0d", "de-jg4avhby1noc0d");
  Sample("R", "そのスピードで",
    "d9juau41awczczp", "d9juau41awczczp");
  Sample("S", "-> $1.00 <-",
    "-> $1.00 <--", "-> $1.00 <--");

  (* The bare algorithm's edges. *)
  C.Check(P.Encode("", out, why) & (out = ""), "Encode: nothing");
  C.Check(P.Encode("abc", out, why) & (out = "abc-"), "Encode: ASCII only, a - after it");
  C.Check(P.Decode("", out, why) & (out = ""), "Decode: nothing");
  C.Check(~P.Decode("b", out, why) & C.Contains(why, "middle"), "Decode: ends inside a number");
  C.Check(~P.Decode("ab!", out, why) & C.Contains(why, "digit"), "Decode: not a digit");
  C.Check(~P.Decode("99999999999999", out, why) & C.Contains(why, "overflow"), "Decode: overflow");
  s := "ab-c"; s[1] := 0C3X;
  C.Check(~P.Decode(s, out, why) & C.Contains(why, "ASCII"), "Decode: non-ASCII before the -");
  s := "b-"; s[1] := 0FFX;
  C.Check(~P.Encode(s, out, why) & C.Contains(why, "UTF-8"), "Encode: malformed UTF-8");
  C.Check(~P.Encode("bücher", small, why) & (small = "") & C.Contains(why, "buffer"),
    "Encode: the result too long for the buffer");

  (* Hosts. *)
  Both("bücher.example", "xn--bcher-kva.example", "bücher.example", "a host half ASCII, half not");
  Both("例え.テスト", "xn--r8jz45g.xn--zckzah", "例え.テスト", "a host of two non-ASCII labels");
  Both("Gemini.café.EXAMPLE", "gemini.xn--caf-dma.example", "gemini.café.example",
    "ASCII lowered, in every label");
  Both("CaFé.example", "xn--caf-dma.example", "café.example",
    "ASCII letters in a non-ASCII label lowered");
  (* Not folded: level 1 (the module's comment). *)
  Both("BÜCHER.example", "xn--bcher-2pa.example", "bÜcher.example",
    "a non-ASCII capital not folded");
  Both("example.org", "example.org", "example.org", "an ASCII host as it is");
  Both("bücher.example.", "xn--bcher-kva.example.", "bücher.example.", "a final . kept");
  Both("192.0.2.1", "192.0.2.1", "192.0.2.1", "an IPv4 address untouched");
  Both("::1", "::1", "::1", "an IPv6 address untouched");
  C.Check(P.ToAscii("FE80::A", out, why) & (out = "fe80::a"), "an IPv6 address lowered");
  C.Check(P.ToAscii("XN--BCHER-KVA.example", out, why) & (out = "xn--bcher-kva.example"),
    "an xn-- label lowered, not checked");
  C.Check(P.ToUnicode("XN--bcher-KVA.example", out, why) & (out = "bücher.example"),
    "ToUnicode: xn-- and digits in either case");

  (* Refusals. *)
  Bad("", "no host", "no host");
  Bad(".", "label 1: empty", "a host of only .");
  Bad(".example", "label 1: empty", "an empty first label");
  Bad("a..example", "label 2: empty", "an empty label in the middle");
  Bad("example..", "label 2: empty", "two final .s");
  Bad("exa mple.org", "label 1: a space", "a space");
  s := "a.b"; s[1] := 9X; Bad(s, "control", "a tab");
  s := "ok.b-.org"; s[4] := 0C3X; Bad(s, "label 2: not UTF-8", "malformed UTF-8 (a lead byte alone)");
  s := "ok.ab.org"; s[3] := 0C0X; s[4] := 0AFX; Bad(s, "label 2: not UTF-8", "malformed UTF-8 (overlong)");
  s := "abc.org"; s[0] := 0EDX; s[1] := 0A0X; s[2] := 80X; Bad(s, "label 1: not UTF-8", "malformed UTF-8 (a surrogate)");
  Fill(s, "a", 63);
  C.Check(P.ToAscii(s, out, why) & (out = s), "a label of 63 bytes");
  Fill(s, "a", 64); Bad(s, "label 1: over 63", "a label of 64 bytes");
  Fill(s, "a", 55); s[55] := 0C3X; s[56] := 0BCX; s[57] := 0X;
  C.Check(P.ToAscii(s, out, why) & (out[62] = "f") & (out[63] = 0X), "a non-ASCII label of 63 bytes encoded");
  Fill(s, "a", 56); s[56] := 0C3X; s[57] := 0BCX; s[58] := 0X;
  Bad(s, "label 1: over 63", "a non-ASCII label of 64 bytes encoded");
  (* 4 labels: 63 + 63 + 63 + 61 and 3 .s is 253. *)
  Fill(s, "a", 253); s[63] := "."; s[127] := "."; s[191] := ".";
  C.Check(P.ToAscii(s, out, why) & (out = s), "a host of 253 bytes");
  s[253] := "."; s[254] := 0X;
  C.Check(P.ToAscii(s, out, why) & (out = s), "a host of 253 bytes and a final .");
  Fill(s, "a", 254); s[63] := "."; s[127] := "."; s[191] := ".";
  Bad(s, "over 253", "a host of 254 bytes");
  C.Check(~P.ToAscii("bücher.example", small, why) & (small = "") & C.Contains(why, "buffer"),
    "ToAscii: too long for the buffer");

  (* ToUnicode's reports. *)
  C.Check(~P.ToUnicode("ok.xn--b.example", out, why) & (out = "ok.xn--b.example")
    & C.Contains(why, "label 2: ends in the middle"), "ToUnicode: a label that doesn't decode kept, reported");
  C.Check(~P.ToUnicode("xn--b.xn--bcher-kva", out, why) & (out = "xn--b.bücher")
    & C.Contains(why, "label 1"), "ToUnicode: decodes the rest after one that doesn't");
  C.Check(~P.ToUnicode("xn--bcher-kva.example", small, why) & (small = "") & C.Contains(why, "buffer"),
    "ToUnicode: too long for the buffer");
  C.Check(P.ToUnicode("", out, why) & (out = ""), "ToUnicode: nothing");
  C.Summary
END TestPunycode.
