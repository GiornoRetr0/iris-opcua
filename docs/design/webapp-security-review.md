# Escalation: configuration and credential storage

**Status:** open. Needs a security review, not a design decision.

This is the escalation R26 / F8 asks for. It is deliberately a statement of facts
rather than a recommendation — judging credential storage is outside a design
pass's remit, and the audit says so explicitly. What follows is what the code
does, so somebody qualified can decide what it should do.

## What is stored, and where

All webapp configuration lives in one cleartext `localStorage` entry under
`opcua-console::config` (`src/app/core/services/config.service.ts`). That blob
includes:

- **every OPC UA server password**, one per configured server
  (`ServerProfile.password`)
- **the IRIS REST API password** (`AppConfig.apiPassword`)
- server URLs, security modes, and certificate/key paths

No encryption, no expiry, no separate credential store.

## The shipped default credential

`DEFAULTS` in `config.service.ts` sets `apiUsername: 'SuperUser'` and
`apiPassword: 'SYS'`. Revision 1 of the audit guessed the 3-character password
visible in a screenshot was a demo artifact. It is not — it is a shipped default,
and was reclassified upward accordingly.

## Consequences that are squarely design problems

These three are in the design pass's remit, and two are now addressed:

1. **Config is per-browser, not per-user.** Two operators at one workstation share
   it; the same operator at a different workstation has none of it. Nothing in the
   UI communicated this. → **Addressed:** the settings modal now states that
   settings are stored in this browser only, including passwords, and that anyone
   using the browser profile can see them.
2. **The storage key carried internal branding** from an earlier iteration of the
   product (`precisionArchitect::config`) and would eventually appear in a support
   call. → **Addressed:** renamed to `opcua-console::config`, with a one-time read
   of the old key so no one loses their servers.
3. **No attribution and no change history.** Every pipeline write goes through the
   same production and the same REST identity, so two operators are
   indistinguishable in `Ens_Util.Log` — in a tool that reconfigures connections to
   physical equipment. → **Not addressed.** This needs a backend identity model,
   not a UI change.

## What a reviewer needs to decide

- Is cleartext credential storage in `localStorage` acceptable for the deployment
  context? If not, the alternatives all involve a backend: a server-side
  credential store, a token exchange, or delegating to IRIS authentication.
- Should `SuperUser` / `SYS` ship as a default at all, versus an empty field that
  forces a deliberate choice?
- Is per-operator attribution required for changes that reach physical equipment?
  That is a compliance question as much as a technical one.

## What was deliberately *not* done here

No attempt was made to obfuscate or encrypt the stored blob. Client-side
encryption with a client-side key is not a security control — it would make the
problem harder to see without making it smaller, and would likely stop this
escalation from being read.
