MODULE GeminiStatus; (* a response's status: its class, and its name *)

(* The status codes of the protocol specification, 0.24.1 ("Status
   codes"). A status is two digits, 10..69; its first digit is its
   class. A client MUST refuse any other (GeminiHeaders.Parse does), and
   SHOULD take one the specification doesn't name as its class's first
   (14 as 10, 22 as 20): Effective gives that.

   A status outside 10..69 given here halts: GeminiHeaders.Parse never
   gives one, so it is the program's mistake (PLAN.md, "Halt codes"). *)

CONST
  (* The statuses, by the specification's names *)
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

  (* The classes: a status's first digit *)
  InputClass* = 1;
  SuccessClass* = 2;
  RedirectClass* = 3;
  TemporaryClass* = 4;             (* temporary failure *)
  PermanentClass* = 5;             (* permanent failure *)
  CertificateClass* = 6;           (* client certificates *)

  BadStatus = 124;                 (* a status outside 10..69 *)

(* Whether s is a status at all: 10..69. *)
PROCEDURE Valid*(s: INTEGER): BOOLEAN;
BEGIN RETURN (s >= 10) & (s <= 69)
END Valid;

(* Whether the specification names s. *)
PROCEDURE Known*(s: INTEGER): BOOLEAN;
BEGIN
  RETURN (s = Input) OR (s = SensitiveInput) OR (s = Success)
    OR (s = TemporaryRedirect) OR (s = PermanentRedirect)
    OR (s >= TemporaryFailure) & (s <= SlowDown)
    OR (s >= PermanentFailure) & (s <= ProxyRequestRefused) OR (s = BadRequest)
    OR (s >= CertificateRequired) & (s <= CertificateNotValid)
END Known;

(* s's class, InputClass..CertificateClass. *)
PROCEDURE Class*(s: INTEGER): INTEGER;
BEGIN
  ASSERT(Valid(s), BadStatus);
  RETURN s DIV 10
END Class;

(* The status to act on: s if the specification names it, else its
   class's first (x0). *)
PROCEDURE Effective*(s: INTEGER): INTEGER;
BEGIN
  ASSERT(Valid(s), BadStatus);
  IF ~Known(s) THEN s := s DIV 10 * 10 END;
  RETURN s
END Effective;

(* The specification's name for Effective(s), as its section titles
   give it ("not found"), for a program to show. *)
PROCEDURE Name*(s: INTEGER; VAR name: ARRAY OF CHAR);
BEGIN
  CASE Effective(s) OF
  | Input: COPY("input", name)
  | SensitiveInput: COPY("sensitive input", name)
  | Success: COPY("success", name)
  | TemporaryRedirect: COPY("temporary redirection", name)
  | PermanentRedirect: COPY("permanent redirection", name)
  | TemporaryFailure: COPY("temporary failure", name)
  | ServerUnavailable: COPY("server unavailable", name)
  | CgiError: COPY("CGI error", name)
  | ProxyError: COPY("proxy error", name)
  | SlowDown: COPY("slow down", name)
  | PermanentFailure: COPY("permanent failure", name)
  | NotFound: COPY("not found", name)
  | Gone: COPY("gone", name)
  | ProxyRequestRefused: COPY("proxy request refused", name)
  | BadRequest: COPY("bad request", name)
  | CertificateRequired: COPY("client certificate required", name)
  | CertificateNotAuthorized: COPY("certificate not authorized", name)
  | CertificateNotValid: COPY("certificate not valid", name)
  END
END Name;

END GeminiStatus.
