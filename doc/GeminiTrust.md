# GeminiTrust: trust on first use: the keys of the servers a program knows

<!-- Made by doc/mkref.py from GeminiTrust.Mod; edit the source, then make doc. -->

Gemini servers mostly sign their own certificates, so a client trusts a server on first use (TOFU), as ssh does: the first time it meets a host and port it keeps the server's key, and later it accepts only that key. What is kept is the SHA-256 of the certificate's public key (its SubjectPublicKeyInfo, as polibtls's Connection.PeerKeyHash gives it), not of the certificate, so a server that renews its certificate but keeps its key is still known, as Lagrange does (PLAN.md, "Trust"). With the key goes the certificate's expiry: a different key before it is changed, which is refused; after it, the old certificate has expired, and the new key replaces the old one only if the store's replaceExpired says so.

A Store's Check is what a fetch calls (GeminiResponses.Options.trust) after the TLS handshake and before the request is sent, so a URL and its query never reach a server that isn't trusted. Hosts is the store this module gives, in memory (New) or kept in a file (Open); a program may extend Store to keep hosts elsewhere.

The file is text, a line per host and port:

<host>:<port> spki-sha256 <fingerprint> <notAfter>

the host lower case, ASCII (punycode, as it went to the server), an IPv6 address in brackets; the fingerprint 64 lowercase hex digits; notAfter the certificate's expiry in Unix seconds; the fields separated by blanks. A line that can't be read as one, or names another algorithm, is kept as it is when the file is written and otherwise ignored, so a newer program's lines survive an older one's rewriting, and so do comments. The library chooses no path: the program gives it.

The file is read once, by Open, and written whenever a host is added or its entry changes: in full, to a temporary name in the same directory, synced and renamed over it, so a crash leaves the old file or the new one, never half of one. Two programs sharing a file each write what they have read and changed, so the last to write wins. A file that can't be written fails the check (failed), and the host is as it was, so trust that can't be kept isn't given.

Outside data never halts: a file that can't be read or written comes back as FALSE or failed and a reason. A Store whose Check isn't overridden halts (129).

## Constants

```oberon
known* = 0;      (* the key is the one known (its expiry updated if
added* = 1;      (* first contact: the host is now known *)
replaced* = 2;   (* another key, the known certificate expired, and
changed* = 3;    (* another key, the known certificate not expired:
expired* = 4;    (* another key, the known certificate expired, and
failed* = 5;     (* not checked: the hash isn't a SHA-256, the host or
```

Check's results

```oberon
HashLen* = 64;       (* hex digits of a SHA-256 *)
MaxHash* = 7 + HashLen;   (* "SHA256:" and the digits *)
```

## Types

```oberon
Store* = POINTER TO StoreDesc;
StoreDesc* = RECORD
  replaceExpired*: BOOLEAN
END;
```

Where the hosts are kept. replaceExpired: a new key replaces the known one once the known certificate has expired (FALSE by default, as gmni does; many clients allow it).

```oberon
Hosts* = POINTER TO HostsDesc;
HostsDesc* = RECORD (StoreDesc)
END;
```

The hosts, in memory, and in a file if path isn't NIL.

## Procedures

### Texts

#### Now

```oberon
PROCEDURE Now*(): HUGEINT;
```

The time now, in Unix seconds.

### Store

#### Check

```oberon
PROCEDURE (s: Store) Check*(host-: ARRAY OF CHAR; port: LONGINT; hash-: ARRAY OF CHAR;
    notAfter, now: HUGEINT; VAR why: ARRAY OF CHAR): INTEGER;
```

Checks the key whose hash (as polibtls gives it, "SHA256:" and hex) the server at host (ASCII, as it was asked for) and port gave, its certificate's expiry notAfter, at the time now (both Unix seconds): known, added or replaced to trust the server; changed, expired or failed to refuse it, with why saying so.

### Reading the file

#### New

```oberon
PROCEDURE New*(): Hosts;
```

The hosts kept in memory only, none yet.

#### Open

```oberon
PROCEDURE Open*(path-: ARRAY OF CHAR; VAR h: Hosts; VAR why: ARRAY OF CHAR): BOOLEAN;
```

The hosts kept in the file path, read now: none if it doesn't exist yet (it is made when one is added). FALSE, with why, h NIL, if it can't be read, or is over 4 MiB.

### Hosts

#### Check

```oberon
PROCEDURE (h: Hosts) Check*(host-: ARRAY OF CHAR; port: LONGINT; hash-: ARRAY OF CHAR;
    notAfter, now: HUGEINT; VAR why: ARRAY OF CHAR): INTEGER;
```

The Store's check, keeping hosts in h (and its file).

#### Lookup

```oberon
PROCEDURE (h: Hosts) Lookup*(host-: ARRAY OF CHAR; port: LONGINT; VAR hash: ARRAY OF CHAR;
    VAR notAfter: HUGEINT): BOOLEAN;
```

The key known for host and port, as polibtls gives it ("SHA256:" and hex), in hash, and its certificate's expiry: FALSE if none is known.

#### Trust

```oberon
PROCEDURE (h: Hosts) Trust*(host-: ARRAY OF CHAR; port: LONGINT; hash-: ARRAY OF CHAR;
    notAfter: HUGEINT; VAR why: ARRAY OF CHAR): BOOLEAN;
```

Makes hash, with its certificate's expiry notAfter, the key known for host and port, whatever was known before: for a program whose user has decided to trust a changed key. FALSE, with why, if the host, port or hash is malformed, or the file can't be written.

#### Forget

```oberon
PROCEDURE (h: Hosts) Forget*(host-: ARRAY OF CHAR; port: LONGINT; VAR why: ARRAY OF CHAR): BOOLEAN;
```

Forgets host and port, so its next key is trusted on first use again: TRUE if it wasn't known, or is forgotten; FALSE, with why, if the file can't be written. Every entry for it goes, if the file had several.
