# %noltbook-dev — Noltbook Developer API Harness

## What it is

A tiny **same-ship** example app and test harness for the **`%noltbook-api`** veneer
— the stable developer surface over Noltbook, spoken over Eyre. It does not depend on
Noltbook internals.

- One gall agent (`app/noltbook-dev.hoon`) binds Eyre at `/apps/noltbook-dev` and
  serves `lib/noltbook-dev/index.html` (the same self-serving trick Noltbook uses —
  no docket/glob).
- The page talks to the local `%noltbook` agent through the normal Eyre channel.
- The same agent also serves a **Noltbook app manifest** at
  `/apps/noltbook-dev/noltbook.json` (see *Noltbook app manifest* below).

## Noltbook app manifest

`app/noltbook-dev.hoon` serves a small read-only JSON manifest at
**`/apps/noltbook-dev/noltbook.json`** (`content-type: application/json`). This is the
first real Noltbook app manifest. Noltbook treats any installed desk that serves
`/apps/<desk>/noltbook.json` as **Noltbook-capable**: its Grimoire → Apps tab fetches
the manifest per desk, groups manifest-bearing apps under **NOLTBOOK APPS**, and shows
a **NOLTBOOK APP** capability panel (title, summary, advertised actions) in the app
detail view. `kind:"open"` actions render an active OPEN button; note-template actions
are displayed as future capability affordances. The bare `/apps/noltbook-dev` route still
serves the harness unchanged.

Served manifest:

```json
{
  "noltbook": 1,
  "title": "Noltbook Dev",
  "summary": "Developer harness for testing the Noltbook API surface.",
  "actions": [
    { "id": "api-harness",  "kind": "open",          "label": "Open API Harness", "description": "Inspect notes, post messages, test artifacts, pins, calls, forks, and developer attribution.", "href": "/apps/noltbook-dev" },
    { "id": "example-note", "kind": "note-template", "label": "Example Note",     "description": "A future template action for creating an app-shaped Noltbook note." }
  ]
}
```

## Quick start

```
::  in dojo on the ship that runs %noltbook
|commit %noltbook-dev
|install our %noltbook-dev
```

Open `http://<your-ship-url>/apps/noltbook-dev`. On load the page resolves your ship
from `/~/host`. The result stream is **manual**: click **Connect Result Stream** when
you want live `/api/results` facts. This keeps the harness usable for read-after-write
testing even after a stale browser channel or ship restart.

First pass:
1. **Create / Find** → `find-or-create-note` makes the `api-test` note and selects it.
2. **Post Text Message** → `post-message` into it.
3. **Read Recent** → `/api/notes/<id>` shows the message and any artifacts.
4. Optional: **Connect Result Stream**, then run one small write again and confirm the
   result line shows `OK [...]` or `FAIL [...]`.

## Eyre basics

Reads are scries; writes are pokes of the `noltbook-api` mark; results arrive on a
channel subscription.

```js
// read
const res = await api.scry('noltbook', '/api/notes');         // GET /~/scry/noltbook/api/notes.json

// write — { action, requestId?, app?, data }
await api.poke('noltbook', 'noltbook-api', {
  action: 'post-message',
  requestId: nextReq(),                  // optional; see Result facts
  data: { noteId: '<id>', text: 'hi' }
});

// results (optional; the harness exposes this as "Connect Result Stream")
await api.subscribe('noltbook', '/api/results');              // then read facts off the channel
```

`app` is an optional top-level attribution object (see *Notes on semantics → via*).
`actor` is an optional top-level app-scoped identity object (see *Notes on semantics → actor*).

## Result facts

Include a numeric **`requestId`** on a poke and the agent emits one result fact on
`/api/results`. Omit it and the poke is fire-and-forget (no fact). Facts are
**live-only** — there's no backlog, so connect the result stream before the poke whose
fact you want to see. The harness shows each result plus a small log. If the stream
drops, the harness closes it instead of auto-reconnecting forever; reload or click
**Connect Result Stream** again when the ship is stable.

Two fact shapes (both inside a `noltbook-update` diff):

**`api-result`** — the scalar result for most actions:
```json
{ "api-result": { "requestId", "ok", "code", "message",
    "noteId", "msgId", "eid", "artifactId", "callId" } }
```
Unused fields are null. `msgId` is a `@da` string; `eid` a `@uv` string; `noteId`/
`artifactId`/`callId` are id strings.

**`api-search-result`** — `search-messages` only:
```json
{ "api-search-result": { "requestId", "query", "capped",
    "hits": [ { "noteId", "msgId", "eid", "author", "timestamp", "preview" } ] } }
```

### Durable vs. handed-off result codes

These distinctions matter when testing across ships:

- **`posted` / `edited` / `deleted` / `created` / `artifact-created` / `call-started`**
  — the change was applied **locally and durably** on this ship; ids/eids returned are
  confirmed.
- **`forwarded`** — a message to a **remote-hosted** note was sent to the host; the
  `msgId`/`eid` are the values we minted and sent, not yet host-confirmed. Read it
  back to confirm.
- **`accepted`** — handed to the internal handler or forwarded to a host where the
  durable outcome isn't locally known (e.g. a mod op you perform as an admin on a note
  you don't host; a non-creator `start-call`; a `create-note` with a parent). Treat as
  best-effort until you read state back.
- **`found`** — an idempotent find matched existing state.

`msgId`/`eid`/`artifactId`/`callId` are only set where they're meaningful and
available.

## API reference by category

All writes are `poke('noltbook','noltbook-api', { action, requestId?, app?, data })`.
Ship/host arguments are raw text, parsed server-side — a bad value returns
`invalid-ship`, never a crash.

### Notes

| action | data | result |
|---|---|---|
| `create-note` | `{ name, parent? }` | `created` (root note) / `accepted` (with `parent` — the internal create may no-op on perms) |
| `find-or-create-note` | `{ name, parent? }` | `found` (existing our-owned note, exact name) / `created` |
| `set-note-config` | `{ noteId, name?, visibility?, writable?, headline?, iconUrl? }` | `configured` / `missing-note` / `invalid-name` / `invalid-visibility` / `rejected` |
| `set-note-app` | `{ noteId, app: null \| { desk, title?, publisher?, tag?, template? } }` | `app-set` / `app-cleared` / `missing-note` / `invalid-desk` / `invalid-publisher` / `invalid-template` / `invalid-app` / `rejected` / `unsupported` |
| `set-note-pin` | `{ noteId, target, kind:"message"\|"artifact" }` | `pin-set` / `missing-note` / `invalid-target` / `missing-target` / `unsupported` / `rejected` |
| `clear-note-pin` | `{ noteId }` | `pin-cleared` / `missing-note` / `unsupported` / `rejected` |
| `set-note-active` | top-level `app` + `{ noteId, label?, count?, ttl? }` | `active-set` / `missing-app` / `missing-note` / `unsupported` / `rejected` |
| `clear-note-active` | `{ noteId }` | `active-cleared` / `missing-note` / `unsupported` / `rejected` |

`set-note-config` changes only the fields you include (fans out to `rename-note` /
`set-note-meta` / `set-headline`, one result fact). `visibility` is `public`/`private`/
`secret` (setting public/private on a `%notebook` converts it to `%group`). `headline:""`
and `iconUrl:""` clear those fields; `iconUrl` is a URL string only. Permission mirrors
`set-note-meta`: the creator (or a DM member, local-only) and not write-blocked. On a
DM, only the local `name`/icon take visible effect — other fields run but no-op, and
still report `configured`.

To make a configured note: `create-note` then `set-note-config`.

**App-note metadata** (`set-note-app`) is durable note-level metadata associating a note
with a Noltbook-capable app — it is **not a new note type** (types stay
notebook/group/gossip/dm/cover). `app:null` clears; an `app` object sets it. `desk` is
required and must be a valid term; `publisher` (a `@p`) and `template` (a term) are
validated when present; `tag` is free text capped at 128 chars; `createdBy`/`createdAt`
are server-stamped (the client cannot set them). Only an explicit `app:null` clears —
an absent or non-object `app` is rejected with `invalid-app` (never a silent clear).
Gate: the note must exist, be **notebook/group/gossip** (cover/ars-rumors/DM are
`unsupported`), not be write-blocked, and the caller must be the note **creator**
(admins are rejected this phase because the metadata is local-only/unpropagated). Stored
**locally on the host only this phase** — no live broadcast yet; read it back via the
`app` field on `/api/notes`, `/api/notes/<id>`, and `/api/notes/<id>/meta` (`null` when
absent). Noltbook does not execute `template` actions yet.

**Pin** (`set-note-pin` / `clear-note-pin`) is the **one pin per note** — an
optional placement that renders in the stable pinned surface above the chat, **not a new
artifact/note type**. The target is either a **message** (`kind:"message"`, by the
message's `meta.eid`) or a **`%file`/`%app` artifact** (`kind:"artifact"`, by the
artifact's `meta.eid`); `%code` is excluded. `invalid-target` = the eid or `kind` didn't
parse; `missing-target` = a valid eid with no matching message / file-app artifact in that
note. Gate: note exists, is **notebook/group/gossip** (DM/cover/ars-rumors are
`unsupported`), not write-blocked, and the caller is the note **creator/host**
(admins/members rejected). **Setting replaces** the existing pin; `clear-note-pin` clears
it (the target is not deleted). Pins **broadcast live** (`%note-pin-updated`) and a
re-subscribing member gets a snapshot; deleting the pinned message/artifact auto-clears
the pin. Read it back via the `pin` field on `/api/notes/<id>` and `/api/notes/<id>/meta`
(`null` when absent):

```text
pin: null
  | { target, kind, pinnedBy, pinnedAt, messageId, author, preview, timestamp }
  | { target, kind, pinnedBy, pinnedAt, artifactId, artifactName, artifactType }
```

Resolved fields are filled at read time and may be `null` if the target is gone.

**Active** (`set-note-active` / `clear-note-active`) is a developer/API-only note "live"
status (e.g. "5 listening", "playing", "live") — separate from calls, with **one active
status per note**. `set-note-active` **requires top-level `app` attribution** (the
`{ app: { desk, … } }` on the poke) and returns `missing-app` without it; `desk`/`title`/
`publisher` are server-stamped from it, as are `setBy`/`updatedAt`/`expiresAt`. Gate: note
exists, is **notebook/group/gossip** (`unsupported` otherwise), not write-blocked, and the
caller is the note **creator/host** (admins/members rejected). It's a **TTL heartbeat**:
`ttl` is seconds (default 120, capped 600) — apps re-set before expiry, and a stopped app
auto-expires. `label` defaults to `"live"` and caps at 32 chars; `count` is optional and
caps at 999. Active **broadcasts live** (`%note-active-updated`) and a re-subscribing
member gets a snapshot of unexpired entries. Read it back via the `active` field on
`/api/notes`, `/api/notes/<id>`, and `/api/notes/<id>/meta` (`null` when absent **or
expired**):

```text
active: null | { desk, title, publisher, label, count, setBy, updatedAt, expiresAt }
```

### Messages

| action | data | result |
|---|---|---|
| `post-message` | `{ noteId, text, replyToEid? }` | `posted` / `forwarded` / `missing-note` / `rejected` |
| `edit-message` | `{ noteId, text, eid?, msgId? }` | `edited` / `accepted` / `missing-note` / `missing-target` / `rejected` |
| `delete-message` | `{ noteId, eid?, msgId? }` | `deleted` / `accepted` / `missing-note` / `missing-target` / `rejected` |
| `post-app-ref` | `{ noteId, publisher, desk, name }` | `posted` / `forwarded` / `invalid-publisher` / `invalid-desk` — posts an `~app[…]` reference as a message |

`edit-message`/`delete-message` resolve the target **eid-first, `msgId` fallback** (at
least one required, else `missing-target`). Edit is author-only; delete is author-only
except a group note's host may delete any message. The result carries the resolved
`msgId`+`eid`. `post-message`/`post-app-ref` to a note you host are `posted`; to a
remote-hosted note they're `forwarded` (see *Durable vs. handed-off*).

`post-message` and `post-app-ref` also accept an optional top-level **`actor`**
`{ id, name, kind }` (app-scoped identity inside `via` — see *Notes on semantics →
actor*). It is honored only when a valid top-level `app` is present and only on
regular notes and DMs; cover/gossip/ars-rumors omit it. Display/attribution only.
Since **Actor Control (Phase A)**, a well-formed actor must also pass the host's app
grant + actor registry — a governance-denied actor **rejects** the post (codes
`app-not-granted` / `app-disabled` / `actor-suspended` / `actor-revoked`) rather than
silently posting as the host.

### Actor Control (Phase A)

Host-only governance over which **local** app desks may attribute actors and the
lifecycle of each actor. These mutate grant/registry state only; they never post
content, and the actor-bearing post path cannot reach them.

| action | data | result |
|---|---|---|
| `set-app-grant` | `{ desk, enabled, caps? }` (`caps` string array, default `["attribute"]`) | `app-granted` / `app-disabled` / `actor-invalid` |
| `set-actor-status` | `{ desk, id, status }` (`status` = `active`/`suspended`/`revoked`) | `actor-active` / `actor-suspended` / `actor-revoked` / `actor-invalid` |
| `update-actor` | `{ desk, id, name, kind }` (requires app grant with `%manage-actors`) | `actor-updated` / `app-not-granted` / `actor-invalid` |

Model: the **host planet** grants/disables an app (`set-app-grant`) and suspends/revokes
individual actors (`set-actor-status`). An app may register/rename its own actors via
`update-actor` only if its grant includes `%manage-actors`. **An app cannot grant itself
powers** — the grant path is separate from posting, and the post path never writes grants.
First attributed post from an unknown `[desk id]` under a granted app **auto-registers**
the actor as `active` (TOFU). Revoking stops future posts; **history stays attributed**.

> **Security caveat — desk grants are cooperative, not authenticated.** `%noltbook-api` is
> same-ship only, and **Gall does not expose the calling local agent** — Noltbook sees
> `src.bowl` (the ship), not `%skiff`. So `app.desk` is an app-supplied name, not an
> authenticated caller identity. Phase A gives the host **revocation + audit**, not hard
> isolation from a malicious local agent (which already holds `our.bowl` authority). The
> real protection remains: only install trusted local agents.

### Artifacts

Code and app artifacts (content lives in the artifact's versions). File-byte artifacts
are not created through this surface.

| action | data | result |
|---|---|---|
| `create-artifact` | `{ noteId, name, type:"code"\|"app", content, replyToEid? }` | `artifact-created` / `invalid-type` / `invalid-name` / `missing-note` / `unsupported` (cover/gossip) / `rejected` |
| `edit-artifact` | `{ id, content }` | `artifact-edited` / `missing-target` / `missing-note` / `rejected` |
| `delete-artifact` | `{ id }` | `artifact-deleted` / `missing-target` / `missing-note` / `rejected` |

`create-artifact` returns the new `artifactId` and `eid`, both confirmed (artifacts are
stored locally on the author ship). `edit-artifact` adds a new version. **Edit/delete
are creator-only via the API** — the veneer requires `artifact.creator == our` before
re-entering (the internal handlers check only write-blocked). Delete removes the
artifact's attribution row; edit preserves it.

### Membership / admin

`{ noteId, ship }` unless noted. These route through Noltbook's handlers, so ownership
and host rules apply.

| action | data | success code |
|---|---|---|
| `request-join` | `{ noteId, host? }` | `joined-requested` (`host` defaults to the local note's creator) |
| `add-member` | `{ noteId, ship }` | `member-added` |
| `remove-member` | `{ noteId, ship }` | `member-removed` |
| `approve-join` / `deny-join` / `deny-block-join` | `{ noteId, ship }` | `approved` / `denied` / `blocked` |
| `mute-member` / `unmute-member` | `{ noteId, ship }` | `muted` / `unmuted` |
| `make-admin` / `remove-admin` | `{ noteId, ship }` | `admin-added` / `admin-removed` |

Failures: `invalid-ship`, `missing-note`, `missing-target` (e.g. `request-join` with no
resolvable host), `rejected` (not allowed for this note/user). Mod ops
(approve/deny/remove/mute) require creator-or-admin on a non-DM note; performed as an
**admin on a note you don't host** they forward to the host and return **`accepted`**;
as the **creator** they apply locally and return the durable code. `make-admin`/
`remove-admin` are creator-only. The target ship is named in the result `message`.


### Profile / contacts / pals

| action | data | success code |
|---|---|---|
| `update-profile` | `{ displayName?, avatar?, walletAddress?, azimuthAddress? }` | `profile-updated` |
| `add-contact` / `remove-contact` | `{ ship }` | `contact-added` / `contact-removed` |
| `add-pal` / `remove-pal` | `{ ship }` | `pal-requested` / `pal-removed` |
| `block-pal` / `unblock-pal` | `{ ship }` | `pal-blocked` / `pal-unblocked` |

`update-profile` is a **partial** update: a field **omitted** keeps the current value,
explicit **`null`** clears it, a **value** sets it. `avatar` is `null` to clear or
`{ type:"urbit"|"s3"|"ipfs"|"external", url? }` to set; an unparseable avatar returns
`invalid-avatar` and changes nothing. Ship actions return `invalid-ship` on a bad ship
and `rejected` for `ship == our`. `add-pal` sends a request (it becomes mutual only if
the other ship already requested). Verify effects via `/api/profile/<ship>`
(`palStatus`/`isBlocked`).

### DMs and gossip notes

| action | data | result |
|---|---|---|
| `find-or-create-dm` | `{ ship }` | `found` / `dm-created` / `invalid-ship` / `rejected` |
| `find-or-create-gossip-note` | `{ name, headline? }` | `found` / `gossip-created` / `invalid-name` |

Both are idempotent and return the `noteId`. `find-or-create-dm` reuses `%create-dm`
(so the invite + pal-request side effects fire once); `rejected` for `ship == our` or a
blocked ship. `find-or-create-gossip-note` matches an existing note by exact `name` +
`creator == our` + `type == %gossip`, else creates a user-gossip note (`headline`
defaults to `""`). Post into either with the normal `post-message`.

### Search

| action | data | result |
|---|---|---|
| `search-messages` | `{ query, limit?, noteId? }` | `api-search-result` fact / `invalid-query` |

**`requestId` is required** (the result is a fact, not a scry). Case-insensitive
substring; `limit` defaults to and caps at 50; `noteId` restricts to one note (a missing
note yields zero hits). Excludes cover, ars-rumors, missing notes, and pal-blocked
authors; user-gossip notes are searchable. An empty query returns `invalid-query`. In a
hit, `msgId` is the `@da` string (matching `/api/notes`) and `timestamp` is a ms number.

### Forks

| action | data | result |
|---|---|---|
| `fork-note` | `{ noteId, name? }` | `fork-created` / `missing-note` / `rejected` |
| `accept-fork-invite` | `{ rootId }` | `fork-fetch-requested` / `missing-target` / `rejected` |
| `decline-fork-invite` | `{ rootId }` | `fork-invite-declined` / `missing-target` |

`fork-note` works on `%group` notes you're a member of (or a removed archive holder
of); the **creator cannot fork their own active note** (`rejected`, matching the UI).
It returns the new fork's `noteId`. The fork starts with **only you** as a member;
the other eligible source members are *invited*, and become fork members when they
accept (decline notifies you and drops them — they're never silently added).

**`accept-fork-invite` is async** — it requests a remote fetch and marks the invite
`fetching`; the subtree installs later (only if the forker has actually added you as a
member), hence `fork-fetch-requested` rather than a durable code. For accept/decline
the `rootId` is returned in the result's `noteId` field.

### Calls

Noltbook call **state** only — no audio/video or WebRTC signaling. `{ noteId }`.

| action | data | result |
|---|---|---|
| `start-call` | `{ noteId }` | `call-started` (creator, with `callId`) / `accepted` (non-creator, forwarded to host) / `missing-note` / `rejected` |
| `join-call` | `{ noteId }` | `call-joined` (with `callId`) / `missing-note` / `missing-target` / `rejected` |
| `leave-call` | `{ noteId }` | `call-left` (with `callId`) / `missing-note` / `missing-target` / `rejected` |

`active-calls` is keyed by note id (at most one call per note). `start-call` as the note
creator creates the call locally and returns `callId`; as a non-creator it forwards to
the host (`accepted`). `join`/`leave` return `missing-target` when there's no active
call and `rejected` for already-in / not-in. Leaving as the last participant ends the
call.

## Read paths

Stable JSON owned by the API (`GET /~/scry/noltbook<path>.json`). Decoupled from the
internal `/notes` update shapes so they stay stable across UI changes.

| path | returns |
|---|---|
| `/api/notes` | `{ notes: [ { id, name, type, creator, visibility, userCount, lastPreview, app, active } ] }` |
| `/api/notes/<id>` | `{ noteId, messages: [ { id, msgId, author, text, timestamp, edited, eid, replyToEid, via, actor } ], artifacts: [ { id, name, type, creator, noteId, eid, replyToEid, created, updated, versionCount, latestVersion, latestEditor, latestTimestamp, mime, kind, size, url, downloadUrl, via } ], app, pin, active }` |
| `/api/artifacts/<id>` | `{ artifact: { …artifact fields…, via, versions: [ { version, content, editor, timestamp } ] } }` |
| `/api/actor-grants` | `{ grants: [ { desk, enabled, caps, grantedBy, grantedAt, updatedAt, revokedAt } ] }` |
| `/api/actors` | `{ actors: [ { desk, id, name, kind, status, createdAt, updatedAt, revokedAt, lastSeen } ] }` |
| `/api/actors/<desk>` | same as `/api/actors`, filtered to one desk |
| `/api/profile/<ship>` | `{ ship, known, displayName, avatar, walletAddress, azimuthAddress, palStatus, isContact, isBlocked }` |
| `/api/contacts` | `{ contacts: [ …profile fields… ] }` |
| `/api/notes/<id>/members` | `{ noteId, members: [ …profile fields…, role, muted, removed ] }` |
| `/api/notes/<id>/meta` | `{ id, name, type, creator, visibility, writable, parent, children, userCount, removedCount, iconUrl, headline, lastAuthor, lastPreview, hostStatus, activity, read, forkOrigin, forkVersion, forkOf, memberRev, app, pin, active, capabilities: {…} }` |
| `/api/notes/<id>/capabilities` | `{ noteId, …capability flags… }` |
| `/api/fork-invites` | `{ forkInvites: [ { rootId, sourceName, sourceVersion, forker, fetching } ] }` |
| `/api/calls` | `{ calls: [ <call> ] }` |
| `/api/notes/<id>/calls` | `{ noteId, calls: [ <call> ] }` |

`<call>` = `{ callId, noteId, startedBy, started, participants:[…], status }`
(`status` = `active`/`ended`). A missing note for `/meta`, `/capabilities`, or
`/members`, an unknown artifact, or an invalid ship returns no cage (404). Empty
list-shaped reads return `[]`.

**Capabilities** mirror Noltbook's real handler guards: `canRead` (always true for a
local note), `canPost`/`canEditOwnMessages`/`canDeleteOwnMessages` (true unless
write-blocked — the message handlers gate only on write-blocked),
`canUploadArtifact`, `canManageMembers`/`canMuteMembers` (creator-or-admin on a shared
non-DM note), `canManageAdmins` (creator only), `canChangeSettings`; plus flags
`isCreator`/`isAdmin`/`isMuted`/`isRemoved`/`isHostDeleted`/`isHostUnreachable` and a
`reason` (first post blocker: `removed`/`host-deleted`/`host-unreachable`/`none`).

**Profile fields**: `known` is true when we hold a profile/contact/pal record (or the
ship is in the note, for members); a valid-but-unknown ship returns `known:false` with
null fields. `palStatus` is `mutual`/`requesting`/`requested`/`blocked`/`none`. Members
add `role` (`admin` if creator or note-admin), `muted`, and `removed`.

## Testing checklist

The harness is laid out section-by-section; each maps to one part of the API:

- **Notes** — List Notes; Create / Find `api-test`; Read Recent / Meta / Capabilities.
- **Messages** — Post Text Message; per-row Edit / Delete; Post App Reference.
- **Actor** — *Actor Identity* card (id/name/kind + "Send actor", on by default; sends top-level `actor` alongside `app:APP`). Verify: Post Text Message with actor on → Read Recent row shows `actor Rick (user) via %noltbook-dev on ~zod` and the Noltbook chat renders an actor header; Post App Reference with actor on → same actor header. Turn "Send actor" off → posts render as the normal ship/`via` row (no actor). The `kind` select constrains to user/bot/app (a console poke with a bad kind omits actor but still posts). Select a **gossip** note and post with actor on → read shows `actor:null` (backend excludes gossip in v1); a **DM** note with actor on → actor appears. Actor requires a valid `app`; with no `app` it is omitted.
- **Actor Control** — *Actor Control* card (host governance, Phase A). For live result
  codes, click **Connect Result Stream** first; otherwise confirm by re-reading state.
  Flow: with no grant, Post Text Message (actor on) → no new message and, with the stream
  connected, `FAIL [app-not-granted]`. Click **Grant** (desk `noltbook-dev`) →
  `app-granted`; post again → succeeds and **List Grants/Actors** shows the actor
  auto-registered `[active]` (TOFU). **Suspend** → next actor post `FAIL
  [actor-suspended]`; **Revoke** → `FAIL [actor-revoked]`; **Activate** → posting works
  again. **Disable** the app → `FAIL [app-disabled]`. Past attributed messages stay
  attributed after revoke. Remember: desk grants are **cooperative**, not authenticated
  (Gall hides the calling agent) — governance/audit, not isolation.
- **Artifacts** — Create Artifact (code/app); Detail; Edit / Delete on the selected artifact.
- **Pin** — in Read Recent, Pin a message or `%file`/`%app` artifact row (one pin per note); the pinned-item block shows kind/target/pinnedBy with Clear Pin. Verify: pin a message, pin a `%file`/`%app` artifact (`%code` has no Pin button), setting a new target **replaces** the pin, `clear-note-pin` clears it, a non-creator is `rejected`, and deleting the pinned target auto-clears the pin. Read Meta shows the `pin` line.
- **Active** — *Active* card: Set Active (label/count/ttl; sends top-level `app:APP`) → `active-set`; Read Recent/Meta show the `active` line and the sidebar shows the same green in-progress style as calls. Verify: the compact sidebar badge shows the count only when present (the label is in the title), after `ttl` seconds the read shows `active:null` (expiry filter), Clear Active → `active-cleared`. A `set-note-active` without `app` returns `missing-app` (the harness always sends `APP`, so test that path via the debug console/docs); a non-creator returns `rejected`.
- **Profile / Contacts / Pals** — Read Profile / Contacts / Members; Update Profile (null checkbox per field); Add/Remove Contact; Add/Remove/Block/Unblock Pal.
- **Membership / Admin** — request join, add/remove member, approve/deny/deny+block, mute/unmute, make/remove admin.
- **Note Config** — name / visibility / writable / headline → Set Selected Note Config.
- **Search** — query / limit / "selected note only"; click a hit to open its note.
- **DM** — Find / Create DM; Post DM test message.
- **Gossip Note** — Find / Create Gossip Note; Post Gossip Test Message.
- **Forks** — Fork Selected Note; Read Fork Invites (Accept/Decline rows); accept/decline by rootId.
- **Calls** — Read Calls / Read Selected Note Calls; Start / Join / Leave Call.

After a write the page re-scries to show current state — result facts report
acceptance/failure, not the full post-state.

## Notes on semantics

- **Same-ship trust.** The page authenticates as the user; pokes/scries hit the local
  `%noltbook` as `our`. The API still applies Noltbook's per-note membership/write
  checks. Non-local pokes are rejected by the same-ship guard.
- **`accepted`/`forwarded` are not always durable confirmation.** When an action is
  forwarded to a host or handed off async, read state back to confirm (see *Durable vs.
  handed-off result codes*).
- **Result facts are live-only.** No backlog — click **Connect Result Stream** before
  the poke whose result you want to see. The stream is intentionally manual in the
  harness so stale browser channels do not reconnect forever after a ship restart.
- **`via` is attribution, not authorship.** Pass `app:{ desk, title?, publisher? }` on a
  poke and the agent records "posted via app X". The author stays the user/ship; the
  stored `ship` is `our`, stamped server-side — never client-supplied. A malformed `app`
  is ignored (the action still runs). `via` travels with normal message delivery
  (local, remote-hosted, DM, and cover/gossip), so the host and members see the same
  `{ desk, title, publisher, ship }`. A normal Noltbook UI message reads `via:null`;
  anonymous `%ars-rumors` posts are never attributed. Reads expose a nullable `via` on
  messages and artifacts.
- **`actor` is app-scoped identity inside `via`.** Pass an optional top-level
  `actor:{ id, name, kind }` on `post-message`/`post-app-ref` and the agent records an
  app-scoped speaker — e.g. *Rick via %skiff on ~zod*. `kind` is one of
  `user`/`bot`/`app`. The stored `host` and `desk` are stamped server-side (`host=our`,
  `desk=app.desk`) — never client-supplied; the client only supplies `id`/`name`/`kind`.
  Rules:
  - **Requires a valid top-level `app`.** No `app` ⇒ actor omitted (message still posts).
  - **Invalid actor is omitted, never rejected** — empty `id`/`name`, an out-of-range
    `kind`, or over-cap (`id` > 128 / `name` > 64 bytes) drops the actor; the message
    still posts.
  - **Display/attribution only in v1.** It does **not** change the Urbit author
    (`message.author` stays the real ship), permissions, membership, edit/delete
    ownership, or note ownership. The real ship remains the authority; `actor` is the
    identity inside `via`.
  - **Support matrix:** regular notes — yes; DMs — yes; cover/gossip/ars-rumors — no
    (actor is `null` everywhere there, on sender and peers); artifacts/active/note-app/
    pins — no actor in v1.
  - On remote delivery the receiver keeps `actor` only when it arrives tied to valid
    same-source `via` (`actor.host == via.ship == src` and `actor.desk == via.desk`),
    else it is dropped. Reads expose a nullable `actor` `{ host, desk, id, name, kind }`
    on messages.
- **The call API controls Noltbook call state, not media.** No audio/video/WebRTC.
- **`walletAddress` is profile metadata only** — stored and read back, with no wallet
  validation or transaction logic.

## History

The API was built in numbered phases; each numbered section above corresponds to a
slice of that work. The behavior documented here is current; phase numbers are kept
only where they pin a wire/state version detail (e.g. cross-ship `via` requires every
participating ship to run the matching code).
