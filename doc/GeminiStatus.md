# GeminiStatus: a response's status: its class, and its name

<!-- Made by doc/mkref.py from GeminiStatus.Mod; edit the source, then make doc. -->

The status codes of the protocol specification, 0.24.1 ("Status codes"). A status is two digits, 10..69; its first digit is its class. A client MUST refuse any other (GeminiHeaders.Parse does), and SHOULD take one the specification doesn't name as its class's first (14 as 10, 22 as 20): Effective gives that.

A status outside 10..69 given here halts: GeminiHeaders.Parse never gives one, so it is the program's mistake (PLAN.md, "Halt codes").

## Constants

```oberon
Input* = 10;
SensitiveInput* = 11;            (* input not to be echoed *)
Success* = 20;
TemporaryRedirect* = 30;
PermanentRedirect* = 31;
TemporaryFailure* = 40;
ServerUnavailable* = 41;
CgiError* = 42;
ProxyError* = 43;
SlowDown* = 44;                  (* back off, exponentially *)
PermanentFailure* = 50;
NotFound* = 51;
Gone* = 52;
ProxyRequestRefused* = 53;
BadRequest* = 59;
CertificateRequired* = 60;
CertificateNotAuthorized* = 61;
CertificateNotValid* = 62;
```

The statuses, by the specification's names

```oberon
InputClass* = 1;
SuccessClass* = 2;
RedirectClass* = 3;
TemporaryClass* = 4;             (* temporary failure *)
PermanentClass* = 5;             (* permanent failure *)
CertificateClass* = 6;           (* client certificates *)
```

The classes: a status's first digit

## Procedures

#### Valid

```oberon
PROCEDURE Valid*(s: INTEGER): BOOLEAN;
```

Whether s is a status at all: 10..69.

#### Known

```oberon
PROCEDURE Known*(s: INTEGER): BOOLEAN;
```

Whether the specification names s.

#### Class

```oberon
PROCEDURE Class*(s: INTEGER): INTEGER;
```

s's class, InputClass..CertificateClass.

#### Effective

```oberon
PROCEDURE Effective*(s: INTEGER): INTEGER;
```

The status to act on: s if the specification names it, else its class's first (x0).

#### Name

```oberon
PROCEDURE Name*(s: INTEGER; VAR name: ARRAY OF CHAR);
```

The specification's name for Effective(s), as its section titles give it ("not found"), for a program to show.
