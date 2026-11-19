# GeminiIdentities: certificates: a client's made, listed, and chosen for a URL; a server's kept

<!-- Made by doc/mkref.py from GeminiIdentities.Mod; edit the source, then make doc. -->

An identity is a client certificate and its key, which a capsule knows a user by (status 60): the files <name>.crt and <name>.key in a directory the program gives. Make makes one, through polibtls's TlsMake; List and Load read them, each with its certificate's hash, as a server sees it ("SHA256:" and hex, polibtls's TlsCerts.CertHash, the same as Tls.Connection.PeerCertHash), and its validity (TlsCerts.Validity), all in Oberon. Use puts one in a fetch's options.

The specification forbids making or using a certificate without the user taking part (P "Status 60"), so nothing here is called by a fetch: a 60 comes back to the program, which asks its user, and then calls Make, or picks one.

Make makes the pair through polibtls's TlsMake, with the libcrypto libtls loads, so no openssl command is needed (PLAN.md, "Client certificates"): an ECDSA P-256 key, mode 600, then a self-signed certificate, SHA-256, mode 644, each file written whole or not at all, the key first, so an identity exists exactly when its .crt does. A .key without its .crt, as an interrupted Make leaves, is given its certificate. A name is letters, digits, ".", "_" and "-", not starting with ".", so it can't name a file outside the directory.

Ensure is the same for a server: the certificate a capsule presents, made the first time and kept from then on, since Gemini clients pin the certificate they first see (TOFU), and a new one at every start would look like an attack. It is pogemini's, moved here so every server on GeminiServer can make its own (PLAN.md, "A server's certificate").

Scopes says which identity to offer for a URL, by the common rule (as Lagrange and Amfora have it, and as P scopes a certificate made for a 60): an identity attached to a host, port and path is offered for that path and every one below it, the longest such path winning. It is kept in a file the program names, a line per attachment:

<name> <host>:<port> <path>

the host lower case, ASCII (punycode), an IPv6 address in brackets; the path as the URL has it, "/" for none. Other lines are kept as they are and otherwise ignored. The file is written as GeminiTrust's is: whole, to a temporary name, synced and renamed.

Outside data never halts: a file that can't be read or written, or a pair that can't be made, comes back as FALSE and a reason.

## Constants

```oberon
MaxName* = 64;        (* an identity's name, and its common name, at most *)
DefaultDays* = 7300;  (* 20 years: a capsule knows its user by the hash *)
MaxDays* = 36500;
```

## Types

```oberon
Name* = ARRAY MaxName + 1 OF CHAR;
```

```oberon
Identity* = POINTER TO IdentityDesc;
IdentityDesc* = RECORD
  next-: Identity;
  name-: Name;
  certFile-, keyFile-: GeminiResponses.Path;
  hash-: ARRAY MaxHash OF CHAR;
  notBefore-, notAfter-: HUGEINT
END;
```

An identity in a directory: its name, its files, its certificate's hash ("SHA256:" and hex) and validity (Unix seconds). next is the next one List found.

```oberon
Scopes* = POINTER TO ScopesDesc;
ScopesDesc* = RECORD
END;
```

Which identity for which URL, kept in a file.

## Procedures

### Texts

#### ValidName

```oberon
PROCEDURE ValidName*(name-: ARRAY OF CHAR): BOOLEAN;
```

Whether name can be an identity's: 1..MaxName of letters, digits, ".", "_" and "-", not starting with ".", so neither a path nor a hidden file.

### Identities

#### Load

```oberon
PROCEDURE Load*(dir-, name-: ARRAY OF CHAR; VAR id: Identity; VAR why: ARRAY OF CHAR): BOOLEAN;
```

The identity name in dir, read from its files: FALSE, with why, if it isn't there, or its certificate can't be read.

#### Make

```oberon
PROCEDURE Make*(dir-, name-, commonName-: ARRAY OF CHAR; days: LONGINT; VAR id: Identity;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

Makes the identity name in dir, which must exist, with commonName as its certificate's (name if ""), valid for days days from now (1.. MaxDays; DefaultDays is long, as an identity should be): id, or FALSE, with why, if the name or common name can't be one, the identity exists already, or the pair can't be made.

#### Ensure

```oberon
PROCEDURE Ensure*(dir-, name-, names-: ARRAY OF CHAR; days: LONGINT; VAR id: Identity;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

The server certificate name in dir, in id: the pair made before, or, the first time, a new one, with name as its common name and names (name if "") as its subject alternative names, separated by spaces, which libtls matches SNI against, valid for days days (1..MaxDays) from when it is made. The name is ValidName's, but may hold ':', as an IPv6 address does. dir is made if it isn't there, its owner's only (700 octal); one that is is left as it is, since whoever made it chose its mode. A .crt without its .key is refused, never replaced. FALSE, with why, if the pair can't be had.

#### List

```oberon
PROCEDURE List*(dir-: ARRAY OF CHAR; VAR first: Identity; VAR why: ARRAY OF CHAR): BOOLEAN;
```

The identities in dir, by name, in first (NIL for none): FALSE, with why, if dir can't be read. A missing dir has none. A .crt that can't be read, or has no .key, is passed over.

#### Use

```oberon
PROCEDURE Use*(id: Identity; VAR opts: GeminiResponses.Options);
```

Puts id in opts, to be presented by the fetches made with them.

### Scopes

#### OpenScopes

```oberon
PROCEDURE OpenScopes*(path-: ARRAY OF CHAR; VAR s: Scopes; VAR why: ARRAY OF CHAR): BOOLEAN;
```

The scopes kept in the file path, read now: none if it doesn't exist yet. FALSE, with why, s NIL, if it can't be read.

#### Attach

```oberon
PROCEDURE (s: Scopes) Attach*(name-: ARRAY OF CHAR; VAR url: GeminiUrls.URL;
    VAR why: ARRAY OF CHAR): BOOLEAN;
```

Attaches the identity name to url's host, port and path, so it is offered there and below (an attachment there before is replaced): FALSE, with why, if the name can't be one, the URL has no host, or the file can't be written, s then as it was.

#### Detach

```oberon
PROCEDURE (s: Scopes) Detach*(VAR url: GeminiUrls.URL; VAR why: ARRAY OF CHAR): BOOLEAN;
```

Detaches whatever identity is attached to url's host, port and path exactly: TRUE if none was, or it is detached; FALSE, with why, if the file can't be written.

#### For

```oberon
PROCEDURE (s: Scopes) For*(VAR url: GeminiUrls.URL; VAR name: ARRAY OF CHAR): BOOLEAN;
```

The name of the identity to offer for url, in name: the one attached to its host and port and the longest path that it is, or is below; FALSE, name "", if there is none.

#### Covering

```oberon
PROCEDURE (s: Scopes) Covering*(VAR url: GeminiUrls.URL; VAR name, path: ARRAY OF CHAR): BOOLEAN;
```

As For, and the path the identity is attached at, in path, which url's is or is below: for a program to detach it from a page beneath (with url's host and port and that path), or to say where it applies. FALSE, both "", if none covers url.
