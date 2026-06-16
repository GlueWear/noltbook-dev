# %noltbook-dev — Noltbook Developer API Harness

## What it is

A tiny **same-ship** example app and test harness for the **`%noltbook-api`** veneer
— the stable developer surface over Noltbook, spoken over Eyre. It does not depend on
Noltbook internals.

- One gall agent (`app/noltbook-dev.hoon`) binds Eyre at `/apps/noltbook-dev` and
  serves `lib/noltbook-dev/index.html` (the same self-serving trick Noltbook uses —
  no docket/glob).
- The page talks to the local `%noltbook` agent through the normal Eyre channel.

## Quick start

```
::  in dojo on the ship that runs %noltbook
|commit %noltbook-dev
|install our %noltbook-dev
```

Open `http://<your-ship-url>/apps/noltbook-dev`. On load the page resolves your ship
from `/~/host` and subscribes to `/api/results` (status line shows
"subscribed · /api/results (live)").

First pass:
1. **Create / Find** → `find-or-create-note` makes the `api-test` note and selects it.
2. **Post Text Message** → `post-message` into it.
3. **Read Recent** → `/api/notes/<id>` shows the message and any artifacts.

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

// results
await api.subscribe('noltbook', '/api/results');              // then read facts off the channel
```

`app` is an optional top-level attribution object (see *Notes on semantics → via*).

## Result facts

Include a numeric **`requestId`** on a poke and the agent emits one result fact on
`/api/results`. Omit it and the poke is fire-and-forget (no fact). Facts are
**live-only** — there's no backlog, so subscribe before you poke. The harness shows
each result plus a small log.

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

`set-note-config` changes only the fields you include (fans out to `rename-note` /
`set-note-meta` / `set-headline`, one result fact). `visibility` is `public`/`private`/
`secret` (setting public/private on a `%notebook` converts it to `%group`). `headline:""`
and `iconUrl:""` clear those fields; `iconUrl` is a URL string only. Permission mirrors
`set-note-meta`: the creator (or a DM member, local-only) and not write-blocked. On a
DM, only the local `name`/icon take visible effect — other fields run but no-op, and
still report `configured`.

To make a configured note: `create-note` then `set-note-config`.

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

### Pins

Generic pinned entries: a host/admin pins a message or a real `%file`/`%app` artifact
to the top of a **notebook/group** note. `target` is the entry's `eid` (`%uv` string).
Everyone who can see the note sees the pins; only host/admin manage them. Capped at 5
per note. `%code` artifacts, DMs, cover, gossip, and rumors are not pinnable in Phase 1.

| action | data | result |
|---|---|---|
| `pin-entry` | `{ noteId, target, kind:"message"\|"artifact" }` | `pinned` / `accepted` / `missing-note` / `unsupported` / `invalid-target` / `missing-target` / `pin-limit` / `rejected` |
| `unpin-entry` | `{ noteId, target }` | `unpinned` / `accepted` / `missing-note` / `unsupported` / `invalid-target` / `rejected` |

`invalid-target` = the `target` string didn't parse (or `kind` was bad); `missing-target`
= a valid eid that doesn't resolve to a pinnable entry in that note; `unsupported` = the
note type can't hold pins; `pin-limit` = already 5 pins (the 6th is rejected, state
unchanged). Re-pinning an already-pinned target is idempotent (`pinned`, no duplicate).
Host is authoritative: on a note **you host**, the change applies locally and returns the
durable `pinned`/`unpinned`. As an **admin on a member ship** the action is forwarded to
the host (which re-validates) and returns `accepted` — read `/api/notes/<id>` back to
confirm. The result `eid` field echoes the target. Pins ride a `pins-updated` fact to the
frontend and remote members; deleting a pinned message/artifact prunes the pin
automatically.

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
| `/api/notes` | `{ notes: [ { id, name, type, creator, visibility, userCount, lastPreview } ] }` |
| `/api/notes/<id>` | `{ noteId, messages: [ { id, msgId, author, text, timestamp, edited, eid, replyToEid, via } ], artifacts: [ { id, name, type, creator, noteId, eid, replyToEid, created, updated, versionCount, latestVersion, latestEditor, latestTimestamp, mime, kind, size, url, downloadUrl, via } ], pins: [ { target, kind, pinnedBy, pinnedAt, resolved, summary, author } ] }` |
| `/api/artifacts/<id>` | `{ artifact: { …artifact fields…, via, versions: [ { version, content, editor, timestamp } ] } }` |
| `/api/profile/<ship>` | `{ ship, known, displayName, avatar, walletAddress, azimuthAddress, palStatus, isContact, isBlocked }` |
| `/api/contacts` | `{ contacts: [ …profile fields… ] }` |
| `/api/notes/<id>/members` | `{ noteId, members: [ …profile fields…, role, muted, removed ] }` |
| `/api/notes/<id>/meta` | `{ id, name, type, creator, visibility, writable, parent, children, userCount, removedCount, iconUrl, headline, lastAuthor, lastPreview, hostStatus, activity, read, forkOrigin, forkVersion, forkOf, memberRev, capabilities: {…} }` |
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
- **Artifacts** — Create Artifact (code/app); Detail; Edit / Delete on the selected artifact.
- **Pins** — in Read Recent, Pin/Unpin a message or `%file`/`%app` artifact row; the pins block lists current pins (oldest first) with Unpin. Verify: pin message/file/app, multiple pins order oldest-first, the 6th pin returns `pin-limit`, re-pin is idempotent, a plain member is `rejected`, an admin succeeds, deleting a pinned target removes the pin.
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
- **Result facts are live-only.** No backlog — subscribe to `/api/results` before you
  poke.
- **`via` is attribution, not authorship.** Pass `app:{ desk, title?, publisher? }` on a
  poke and the agent records "posted via app X". The author stays the user/ship; the
  stored `ship` is `our`, stamped server-side — never client-supplied. A malformed `app`
  is ignored (the action still runs). `via` travels with normal message delivery
  (local, remote-hosted, DM, and cover/gossip), so the host and members see the same
  `{ desk, title, publisher, ship }`. A normal Noltbook UI message reads `via:null`;
  anonymous `%ars-rumors` posts are never attributed. Reads expose a nullable `via` on
  messages and artifacts.
- **The call API controls Noltbook call state, not media.** No audio/video/WebRTC.
- **`walletAddress` is profile metadata only** — stored and read back, with no wallet
  validation or transaction logic.

## History

The API was built in numbered phases; each numbered section above corresponds to a
slice of that work. The behavior documented here is current; phase numbers are kept
only where they pin a wire/state version detail (e.g. cross-ship `via` requires every
participating ship to run the matching code).
