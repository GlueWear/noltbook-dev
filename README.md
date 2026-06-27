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
| `set-app-notification` | top-level `app` + `{ id, title, body?, href?, noteId?, artifactId?, level?, ttl? }` | `app-notification-set` / `missing-app` / `invalid-id` / `invalid-title` / `invalid-level` |
| `clear-app-notification` | top-level `app` + `{ id }` | `app-notification-cleared` / `missing-app` / `invalid-id` |

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

**App notifications** (`set-app-notification` / `clear-app-notification`) are
app-owned high-level notifications for Noltbook's Grimoire/inbox surface. They require
top-level `app` attribution; Noltbook stamps the real `desk`, app title, and
publisher from that app object instead of trusting payload text. Rows are keyed by
`[desk,id]`, so setting the same id updates that app's existing notification while
preserving its original `createdAt`; clear is idempotent. `level` is one of
`info`/`success`/`warning`/`error` (default `info`). `ttl` is optional and
caps at 604800 seconds; expired rows are omitted from reads/snapshots and pruned on
normal app-notification activity. `href` is stored as an opaque app hint; the main
frontend only opens safe same-origin plugin hrefs, while `noteId` deep-links to a
visible note. Live snapshots arrive as additive `%app-notifications-updated` facts on
`/notes`, and the stable read is `/api/app-notifications`.

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
| `edit-actor-message` | top-level `app` + `actor` + `{ noteId, eid?, msgId?, text }` | `actor-edited` (local host) / `accepted` (forwarded to remote host) / `actor-invalid` / `actor-missing` / `actor-mismatch` / `actor-not-participant` / `unsupported` / `app-not-granted` / `app-disabled` / `actor-suspended` / `actor-revoked` / `missing-note` / `missing-target` / `rejected` |
| `delete-actor-message` | top-level `app` + `actor` + `{ noteId, eid?, msgId? }` | `actor-deleted` (local host) / `accepted` (forwarded to remote host) / (same failure codes as `edit-actor-message`) |

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
| `update-actor` | `{ desk, id, name, kind, caps? }` (requires app grant with `%manage-actors`) | `actor-updated` / `app-not-granted` / `actor-invalid` |

Model: the **host planet** grants/disables an app (`set-app-grant`) and suspends/revokes
individual actors (`set-actor-status`). An app may register/rename its own actors via
`update-actor` only if its grant includes `%manage-actors`. **An app cannot grant itself
powers** — the grant path is separate from posting, and the post path never writes grants.
First attributed post from an unknown `[desk id]` under a granted app **auto-registers**
the actor as `active` (TOFU). Revoking stops future posts; **history stays attributed**.

**Capabilities (Phase C).** `caps` on a grant is the set of `app-cap` values the host
allows the app. The full enum: `attribute`, `manage-actors`, `post-message`,
`edit-own-message`, `delete-own-message`, `create-note`, `configure-note`,
`create-artifact`, `edit-own-artifact`, `delete-own-artifact`, `set-active`, `pin-note`
(not all wired yet — the model carries them all). The **app grant is the ceiling.**
Each actor may be narrowed *within* it via `update-actor`'s `caps`, which is three-state:
**absent** = keep existing actor caps; **`null`** = clear (inherit the app grant);
**array** = an explicit per-actor subset. An actor can **never exceed** the app grant; an
unknown string is dropped. `/api/actors` shows `caps: null` (inherit) or an array.

**Message gates wired this phase:** actor `post-message`/`post-app-ref` require
`attribute` + `post-message`; `edit-actor-message` requires `attribute` +
`edit-own-message`; `delete-actor-message` requires `attribute` + `delete-own-message`.
A missing cap (at the app *or* actor level) returns **`cap-missing`** with a message like
`app lacks %edit-own-message` / `actor lacks %edit-own-message`. `suspended`/`revoked`
still block everything. Non-actor `edit-message`/`delete-message` are unchanged (ship-author scoped).

> **Security caveat — desk grants are cooperative, not authenticated.** `%noltbook-api` is
> same-ship only, and **Gall does not expose the calling local agent** — Noltbook sees
> `src.bowl` (the ship), not `%skiff`. So `app.desk` is an app-supplied name, not an
> authenticated caller identity. Phase A gives the host **revocation + audit**, not hard
> isolation from a malicious local agent (which already holds `our.bowl` authority). The
> real protection remains: only install trusted local agents.

### Actor Tools — edit/delete own messages (Phase B)

`edit-actor-message` / `delete-actor-message` let an app actor edit or delete **only
the messages it originally attributed**. They require top-level `app` + `actor` (unlike
`edit-message`/`delete-message`, which are ship-author scoped and unchanged). The gate:
resolve the target (eid-first, `msgId` fallback) → require `meta.eid` → look up the
stored `actor-by-eid` row → it must match `[host=our, desk=app.desk, id=actor.id]`
(`actor-mismatch` otherwise) → then run the normal grant/registry governance
(`gate-actor`) → and (Phase G2) require current note **ownership/participation** via
`actor-note-access` (`actor-not-participant` / `unsupported` for an ineligible type). A
normal ship message has no actor row → `actor-missing`; another actor's message →
`actor-mismatch`. `our.bowl` always remains the real Urbit author.

**Local vs remote (Phase G3B).** Eligible notes are `%notebook`/`%group` the actor owns or
participates in (DMs stay `unsupported` until actor DMs exist). The action re-enters the
**same** internal `%edit-message`/`%delete-message`, and the host of the note decides what
happens — **no new wire shape is added**:

- **Local-hosted** (`our.bowl == note.creator`): the edit/delete is applied durably here and
  broadcast to members. Result **`actor-edited`** / **`actor-deleted`** (with `noteId`,
  resolved `msgId`, `eid`). A local delete also prunes that message's `via`/`actor`
  attribution rows; pin-prune is unchanged.
- **Remote-hosted** (`our.bowl != note.creator`, a participated `%group`): after all local
  ownership/capability/participation checks pass, the internal handler forwards the existing
  **`%remote-edit-msg`/`%remote-delete-msg`** poke to the note's creator. This is
  **handed-off, not host-confirmed** → result **`accepted`** ("actor edit/delete forwarded to
  host"), never `actor-edited`/`actor-deleted`. The remote host may still reject (membership,
  mute, missing target, authorship). For a forwarded **delete** we **keep** the local message
  and its `via`/`actor` rows until the host's authoritative `%message-deleted` (carrying the
  `eid`) arrives — the subscriber path then prunes them, so the message renders with the right
  actor while in flight. A forwarded **edit** never rewrites `actor-by-eid`, so the host's
  `%message-edited` (same `eid`) re-renders as the same actor. Read back the note after
  propagation to see the durable result.

**Trust boundary.** `%remote-edit-msg`/`%remote-delete-msg` are **unchanged** and remain fully
ship-authenticated on the host: the source ship must be a current member, not blocked/muted,
the target resolves eid-first, and **`message.author == src.bowl`** (and the host owns the
note). The host does **not** trust any client-supplied actor identity — the message is
cryptographically authored by the sending **host ship**, and *local* Noltbook governance is
what decides which actor under that ship was allowed to request the mutation. A mismatch never
falls back to a host-authored edit/delete.

### Actor Notes — create/configure owned notes (Phase D)

| action | data | result |
|---|---|---|
| `create-actor-note` | top-level `app` + `actor` + `{ name }` | `actor-note-created` / `actor-invalid` / `invalid-name` / `app-not-granted` / `app-disabled` / `actor-suspended` / `actor-revoked` / `cap-missing` |
| `configure-actor-note` | top-level `app` + `actor` + `{ noteId, name?, visibility?, writable?, headline?, iconUrl? }` | `actor-note-configured` / `missing-note` / `actor-invalid` / `actor-not-owner` / `invalid-name` / `invalid-visibility` / `rejected` / governance codes above |
| `delete-actor-note` (Phase G1) | top-level `app` + `actor` + `{ noteId }` | `actor-note-deleted` (with `noteId`) / `missing-note` / `actor-invalid` / `actor-not-owner` / `rejected` / governance codes above |

An app actor can **create** a note and **configure notes it owns**. The note's real
`creator` **stays the host ship** (`our.bowl`); Noltbook *separately* records the actor as
the note's durable owner in `note-actor-owners`, keyed by note id.

- **Stable authority is `[host, desk, id]`.** The mutable `name`/`kind`/`status` are never
  used for authorization — only resolved for display at read time.
- **`create-actor-note`** requires `attribute` + `create-note`; creates a **root
  `%notebook`** only (no parent/child, no actor find-or-create this phase). Configure it
  afterward.
- **`configure-actor-note`** requires `attribute` + `configure-note`; checks owner match
  **first** — a missing owner (ordinary host-created note) or a different actor sharing the
  same desk/host → **`actor-not-owner`**. It reuses the same internal rename/meta/headline
  handlers and validation as `set-note-config` (empty name → `invalid-name`; visibility
  `public`/`private`/`secret`; omitted field kept; `iconUrl:""`/`headline:""` clear).
- **`delete-actor-note`** (Phase G1) requires `attribute` + **`delete-own-note`**; deletes a
  note the **exact** actor owns. Ownership (`note-actor-owners[noteId] == [our.bowl, app.desk,
  actor.id]`) is checked **first** — a different actor under the same app, an ordinary
  host-created note, a note owned through another app desk, or a remote-hosted note all →
  **`actor-not-owner`** (and never TOFU-register the actor). It **reuses Noltbook's internal
  `%delete-note`**, so it inherits the host deletion behavior verbatim. For every id in the
  deleted **subtree** (root + descendants) it removes the specific maps the internal path
  handles — `notes`, `messages`, `mentions`, `active-calls`, `gossip-envelopes`, `headlines`,
  `seq-counters`, `join-requests`, `note-admins`, `note-muted`, `artifact-envelopes`,
  `artifacts`, and the **`note-actor-owners` + `actor-note-participation` rows** — and fires
  `%note-deleted`/remote-delete cards. (It does **not** sweep some newer per-note maps such as
  `note-pins`, `note-apps`, and `note-active`, which may retain harmless stale rows; reads
  always filter against the live `notes` map.) The host stays the real `@p` `creator`; this is
  the *actor* path, not a new host-deletion surface.
- The **app grant is the ceiling**; per-actor caps may narrow it (`cap-missing` reports
  "app lacks %x" or "actor lacks %x"). Suspended/revoked actors and disabled apps are
  blocked. **No host fallback** — a missing/invalid actor returns `actor-invalid`, never a
  host action.
- **Host authority is unchanged:** the host user can still create/configure/delete any
  note via the normal `create-note` / `set-note-config` / delete APIs, including
  actor-owned ones.
- **Ownership is host-local this phase.** It is **not** propagated; remote members read
  `actorOwner: null`. Deleting a note (host `delete-note`) drops its ownership row. **No
  actor artifact access.**

Read shape — `actorOwner` appears on `/api/notes/<id>` and `/api/notes/<id>/meta`:
```json
"actorOwner": null | { "host":"~zod", "desk":"noltbook-dev", "id":"rick",
                       "name":"Rick", "kind":"user", "status":"active" }
```
`host`/`desk`/`id` are authoritative (from `note-actor-owners`); `name`/`kind`/`status` are
resolved from the actor registry at read time (null if the registry row is gone). It is
**not** on the `/api/notes` list this phase.

### Actor Notes — mandatory participation (Phase G2)

Actors **no longer inherit access to every note their host planet holds.** An actor
`[app.desk, actorId]` may use a **regular** note only when it **owns** the note
(`note-actor-owners`) or has a **participation** row for it (`actor-note-participation`).
The host **@p** remains the real `note.users` member; **actors never enter `note.users`.**

**Enforced (own-or-participate)** on `post-message`, `post-app-ref`, `edit-actor-message`,
and `delete-actor-message` whenever a valid actor is attributed. A valid actor without
access → **`actor-not-participant`**; a valid actor on an **excluded** type
(`%dm`/`%gossip`/`%cover`/`%ars-rumors`) → **`unsupported`**; it never silently falls back to
a host-authored post. **No-actor host posts are unchanged.** Eligible types are
`%notebook`/`%group`. For edit/delete the existing exact `actor-by-eid` ownership check is
retained **and** current ownership/participation is also required — an actor that no longer
participates cannot edit/delete its earlier messages through the actor API.

> **Behavior change:** existing historical actor messages are untouched, but actors can no
> longer create new activity in arbitrary host-accessible notes until participation is
> explicitly granted. (`%delete-own-message` etc. remain independently revocable.)

| action | data | result |
|---|---|---|
| `actor-join-note` | `app`+`actor` + `{ noteId }` | `actor-note-joined` / `missing-note` / `unsupported` (type) / `rejected` (host does not hold the note) / `actor-invalid` / governance |
| `actor-add-participant` | `app`+`actor` + `{ noteId, targetId }` | `actor-participant-added` / `actor-not-owner` / `actor-invalid` (target empty/not registered) / `actor-revoked` (target revoked) / `missing-note` / governance |
| `actor-remove-participant` | `app`+`actor` + `{ noteId, targetId }` | `actor-participant-removed` / `actor-not-owner` / `missing-target` (not a participant) / `rejected` (own row) / `missing-note` / `unsupported` (type) / governance |
| `actor-leave-note` (Phase G3) | `app`+`actor` + `{ noteId }` | `actor-note-left` (with `noteId`) / `missing-note` / `unsupported` (type) / `rejected` (owner must delete) / `actor-not-participant` (incl. repeat) / `actor-invalid` / governance |

The first three require `%attribute` + **`%participate-note`** (the app grant is the ceiling;
per-actor caps narrow). **`%participate-note` gates only changing participation** — removing
it does not erase existing rows, and `%post-message`/`%edit-own-message`/`%delete-own-message`
stay independently revocable.

- **`actor-join-note`** — the app associates **its own active actor** with a note the host
  already holds (`our.bowl ∈ note.users`), type `%notebook`/`%group`. Idempotent.
- **`actor-add-participant`** — the **owner** actor grants another **same-desk** actor a row.
  The target must already exist in `actor-registry` under the same app desk (the key is
  `[app.desk, targetId]`, so cross-desk targets are structurally impossible); a **revoked**
  target is rejected, a **suspended** target may be recorded (but stays unable to act).
  Idempotent.
- **`actor-add-participant`/`actor-remove-participant`** require the caller to **exactly own**
  the note (`actor-not-owner` otherwise, checked **before** the gate so a non-owner never
  TOFU-registers). The owner **cannot remove its own required row** (`rejected`); removing the
  last row deletes the map entry. **This is not leave** (see `actor-leave-note` below).
- **Atomic:** governance runs first and the candidate registry is **held**; a failed note/owner/
  target check commits nothing (no TOFU, no `last-seen` bump). Every `requestId` emits a
  visible `/api/results` fact.
- **Seeding/cleanup:** a new `create-actor-note` registers its owner as a participant
  automatically (state-59 migration seeds participation from every existing
  `note-actor-owners` row — nothing inferred from message history or host membership).
  `%delete-note` and the internal **ship-level** `%leave-note` paths prune participation for
  every removed id; reads always filter against the live `notes` map, so any stale row on an
  exotic removal path is harmless. Multiple local actors may participate in the same note.

#### Actor leave (Phase G3)

**`actor-leave-note { app, actor, data:{ noteId } }`** lets an actor leave a note it
**participates** in by removing **only** its own `[app.desk, actor.id]` row (requires
`%attribute` + **`%leave-note`**). On success → **`actor-note-left`** (with `noteId`).

**This is the *actor* leave — NOT Noltbook's internal ship-level `%leave-note`.** The internal
handler removes the host **@p** from a note (unsubscribe, `%remote-leave`, drop the subtree);
`actor-leave-note` **never invokes it.** It does **not** touch `note.users`/`note.removed`,
does not unsubscribe, sends **no `%remote-leave` or any wire traffic**, deletes no
messages/artifacts, never removes the note from the host's `notes` map, never touches
`note-actor-owners`, and never affects another actor's participation. **Historical actor
messages stay stored** in the host's note.

- **Validation order:** app → actor → kind → note exists (`missing-note`) → eligible type
  `%notebook`/`%group` (`unsupported`) → exact owner → **`rejected`** ("owner must delete the
  note rather than leave", *not* `actor-not-owner`) → must currently participate, else
  **`actor-not-participant`** (a **repeated** leave hits the same no-row state and also returns
  `actor-not-participant`) → governance `{%attribute %leave-note}`. Ownership and participation
  are checked **before** the gate, so a non-participant is **never** TOFU-registered and gets no
  `last-seen` update; the candidate registry is committed only on success.
- **After leaving:** the actor-scoped list no longer includes the note, the actor-scoped detail
  returns 404, and new actor **post/edit/delete** return `actor-not-participant`. **Host-wide
  note access is unchanged**, and **another participating actor keeps access**.

**Actor-scoped reads** (ergonomic views for apps like Skiff — *not* hard isolation from a
malicious local agent; host-wide APIs are unchanged). Both routes run the **same
`actor-note-access`** gate as enforcement, so they expose **only eligible `%notebook`/`%group`
notes** the actor owns or participates in — a stale ownership/participation row pointing at a
`%dm`/`%gossip`/`%cover` note is **never** surfaced:

- `/api/actors/<desk>/<id>/notes` → `{ notes: [ { id, name, type, creator, visibility,
  writable, userCount, lastAuthor, lastPreview, actorOwner, owned, participant } ] }` — only
  eligible notes the actor **owns or participates in**, filtered to live notes; 404 if the
  actor is not registered. **No artifact data.**
- `/api/actors/<desk>/<id>/notes/<noteId>` → `{ noteId, note: {…summary…}, messages: [ …with
  `actor`/`via` attribution… ] }` — 404 if the actor/note is missing, the type is ineligible,
  or the actor neither owns nor participates. **No artifact details, versions, URLs, or
  pin/artifact-target data.**

> **Remote actor edit/delete (Phase G3B):** the old host-local rejection is **removed** — a
> participating actor may now edit/delete its own message in a **remote-hosted `%group`** note.
> Local-hosted ops return `actor-edited`/`actor-deleted`; remote-hosted ops **forward** the
> existing `%remote-edit-msg`/`%remote-delete-msg` (no new wire shape) and return **`accepted`**
> (handed-off, not host-confirmed — read back after propagation). DMs stay `unsupported` for
> actors until actor DMs exist. See *Actor Tools (Phase B / G3B)* above.

No actor **forks / notifications / artifacts** in G2/G3. (Actor leave landed in G3; actor DMs
land in G5A — see below.)

### Actor DMs — private actor-owned conversations (Phase G5A)

An **actor DM** is a **secret two-ship `%group` note** (NOT a canonical `%dm`): hosted by the
actor's host planet, durably **owned** by the actor (`note-actor-owners`), **marked** as an
actor DM (`actor-dm-notes` → `actor-dm-meta`), and containing **exactly** the host ship + one
remote target. Isolation comes from the **unique note id + message store**: Rick→`~wet` and
Alice→`~wet` are **different notes**. Canonical ship DMs (`%create-dm`/`find-dm-root`) are
**untouched** and remain **`unsupported` for actors**.

| action | data | result |
|---|---|---|
| `find-or-create-actor-dm` | top-level `app`+`actor` + `{ ship }` | `actor-dm-created` (new, with `noteId`) / `found` (existing) / `invalid-ship` / `rejected` (self / blocked) / `actor-invalid` / governance |
| `actor-adopt-dm` | top-level `app`+`actor` + `{ noteId }` | `actor-dm-adopted` (incl. idempotent) / `unsupported` (not an actor-DM note) / `rejected` (not addressed to us / invariant broken / already adopted by another local actor) / `missing-note` / governance |

- **`%send-dm`** is a new `app-cap` (app-grant ceiling + per-actor narrowing). The specialized
  DM API gates `%attribute` + `%send-dm`. Inside a **marked** actor-DM note, ordinary message
  actions require their existing cap **plus `%send-dm`**: send → `post-message`+`send-dm`; edit
  → `edit-own-message`+`send-dm`; delete → `delete-own-message`+`send-dm`. Revoking `%send-dm`
  **disables actor activity in existing actor-DM notes without deleting them**.
- **Idempotent** per `[owner.host=our, owner.desk, owner.id, target]`: a live valid conversation
  is returned (no re-create/invite). A marker whose note is gone/invalid is treated as **stale**,
  pruned, and a new conversation is created. **Creation** mints the note id with the normal
  formula, **reuses** the internal `%create-note` (secret `%notebook`) + `%invite-to-note` (the
  notebook→`%group` normalization and remote invite are not duplicated), writes
  owner/participation/marker, and sends the **new** `%remote-actor-dm-meta` after the invite. The
  note **name** is the canonical actor display name, e.g. `Rick (DM with ~wet)`.
- **Membership invariant** (`actor-dm-valid`): `type==%group`, `visibility==%secret`,
  `creator==owner.host`, `users == {owner.host, target}`. If host UI or another path breaks it,
  actor-DM actions **reject/`unsupported`** — never silently treated as an ordinary actor note.
  Actor member-management APIs **cannot add a third ship**.
- **Manual actor-to-actor adoption.** Automatic actor→actor destination routing is **not**
  available (the remote invite carries no destination actor). On the **target** host, **one**
  local actor calls `actor-adopt-dm` to claim the conversation (adds its participation row);
  duplicate adoption by the same actor is idempotent, a different local actor → **occupied/
  rejected**. After adopting, the actor reads/posts through the normal actor-scoped paths.
- **Isolation enforcement.** On the **owner** host only the exact owner actor may act; on the
  **target** host only the single adopted actor. `actor-note-access` is DM-aware: it validates
  the invariant and grants only owner/participant. **Generic participation never bypasses DM
  isolation** — `actor-join-note`, `actor-add-participant`, `actor-remove-participant`,
  `configure-actor-note`, the actor **member-management** actions, and **`post-app-ref` as an
  actor** all return **`unsupported`** on a marked actor-DM note. No artifact actions.
- **Messages use normal `%group` transport** (no destination-actor wire field is added).
  Remote-hosted adopted actors still use **G3B `accepted` forwarding** for edit/delete.
- **Remote metadata** (`%remote-actor-dm-meta`, sent after the invite) is validated by the
  receiver: `meta.owner.host == src.bowl`, `meta.target == our.bowl`, actor-id cap; if the note
  already exists it must be `src.bowl`'s secret `%group` containing both ships; a marker claiming
  **another host is rejected**. Metadata arriving before the invite may be stored provisionally —
  all reads/access re-verify against the **live note** via `actor-dm-valid`. **req-id has no
  durable pending map; the host can only assert markers under its authenticated `src.bowl`.**
  These are **new** variants — **all ships must run matching code** before remote actor-DM testing.
- **Cleanup.** `delete-actor-note` on the owner host removes the marker through the reused
  internal `%delete-note` (which prunes `actor-dm-notes` for the whole subtree and emits
  `%actor-dm-updated noteId null`). `actor-leave-note` on an **adopted** remote actor DM removes
  **only** the local participation row — the note + marker stay (another local actor may then
  adopt). When the **remote host deletes** a note but Noltbook keeps a **host-deleted archive**,
  the marker is **retained** (useful, and reads re-validate). *Known harmless:* the ship-level
  `%leave-note` / convert-to-dm paths may leave a stale marker for a removed note; reads and the
  on-watch snapshot filter against the live `notes` map, so it never surfaces.

Reads (`actorDm` = the marker object `{ host, desk, id, ownerName, ownerKind, target, createdAt }`):
- `/api/actors/<desk>/<id>/dms` → `{ dms: [ { noteId, actorDm, target, counterpart, createdAt,
  lastAuthor, lastPreview, owned, adopted } ] }` — only **valid live** actor-DM notes the actor
  **owns or adopted**; the owner host's `counterpart` is the **target ship**, an adopted target's
  `counterpart` is the **owner actor**. No artifacts. 404 if the actor is unregistered.
- `actorDm` is added to `/api/notes/<id>`, `/api/notes/<id>/meta`, and the actor-scoped note
  summary/detail (null when the note is not a marked actor DM).

**Main frontend (G5A + G5B):** the marker is hydrated into `state.actorDms` (live
`%actor-dm-updated` fact + on-watch snapshot + note-deleted cleanup), and **G5B renders a
valid marked actor DM as a direct conversation** (it stays technically a `%group`). A shared
`actorDmView(note)` resolver returns a presentation object **only** when the durable marker is
present **and** the full invariant holds (secret two-ship `%group`, `creator==owner.host`,
`users == {owner.host, target}`, current ship is owner.host or target) — a "two-person group"
alone is never an actor DM. Presentation is **perspective-aware**:

- **Owner host:** the conversation shows the **target ship**'s display name + ship avatar/sigil,
  with the context line *"Rick via %noltbook-dev"* in the actor color (`#65a9e8`). Context menu:
  **Profile (target ship)** + **Delete**.
- **Target host:** the conversation shows the **owner actor**'s resolved display name + actor
  avatar (first-letter fallback, **never** a sigil), with the context line *"%noltbook-dev on
  ~zod"*. Context menu: **Actor Profile** + **Leave**.

Actor DMs stay in **SHARED NOTES** (no new section), keep normal unread/attention/call/preview
behavior, and resolve the owner profile through the **G4 cache** (`requestActorProfile`), so the
sidebar/header update without a refresh. The chat header gains a compact, clickable actor-DM
context element (opening `viewActorProfile` via the delegated `data-*` path — no actor value in
inline JS). **SHARE** and **file/artifact upload** controls are **hidden** (actors have no
artifact access). If the marker is cleared or its invariant breaks (e.g. `note-users-updated`
adds a third ship), `actorDmView` returns null and the note **immediately falls back to ordinary
group presentation**. Canonical `%dm` notes and ordinary groups are visually/behaviorally
unchanged. No actor creation/adoption/governance controls are added to Noltbook — those remain
app/API responsibilities.

### Actor Notifications — read/unread state (Phase G6A)

Each actor has an **independent per-note message read cursor** (`actor-note-read`, keyed
`[app.desk, actor.id] -> (map noteId @da)`, **state-62**). Reading as Rick **never** marks the
note read for Alice or for the host ship, and the host ship's own unread cursor (`note-read`) is
**never touched**.

> **Message-only activity.** Actor unread is the newest **message** visible through the
> actor-scoped API vs the actor's cursor — it does **not** use the host-wide `note-activity` map
> (which also advances for artifacts). **Actors have no artifact access, so an artifact never
> makes an actor note unread.**

| action | data | result |
|---|---|---|
| `actor-mark-note-read` | top-level `app`+`actor` + `{ noteId }` | `actor-note-read` (with `noteId`) / `missing-note` / `unsupported` (type) / `actor-not-participant` / `rejected` (actor-DM invariant) / `actor-invalid` / governance |

Requires `%attribute` + the new additive cap **`%manage-own-notifications`** (app-grant ceiling
+ per-actor narrowing). It runs **`actor-note-access`** (so owner/participate + actor-DM
host-role rules + honest codes are inherited), holds the candidate registry until every check
passes, then **monotonically advances** only this actor's cursor to the newest stored message
(never decreasing; no messages → no row but still success). It **never** calls the internal
`%mark-note-read`.

- **Seeding (no retroactive unread).** A cursor is seeded to the current newest message only when
  a **new** participation row is established — `create-actor-note` owner, `actor-join-note`,
  `actor-add-participant` target, `find-or-create-actor-dm` owner (newly created), and
  `actor-adopt-dm` adopter — so joining an existing note does **not** mark its history unread.
  A **duplicate** `actor-join-note`/`actor-add-participant` (the row already exists) is still
  idempotent success but does **not** reseed — an existing actor's cursor and unread state are
  left byte-for-byte unchanged, so re-adding an actor can never silently clear its unread. A
  genuine rejoin after `actor-leave-note`/`actor-remove-participant` (which delete the cursor)
  reseeds to current. The **state-62 migration** seeds every existing participating actor through
  the newest stored message per note (notes with no messages get no row).
- **Own posts.** An actor's own successful `post-message`/`post-app-ref` advances **its** cursor
  (to the local message time); the subscribed `%new-message` receipt advances it again to the
  exact host-restamped id when `actor.host == our.bowl` (covers remote-hosted notes). A
  host-authored or remote-ship message advances **no** actor cursor — other actors stay unread.
- **Cleanup.** The cursor is removed on `actor-remove-participant`, `actor-leave-note`, and
  every `prune-participation` / `%delete-note`-subtree path (via `actor-read-prune`, which drops
  the deleted note ids from **every** actor's nested map and removes emptied inner maps).
  Suspend/revoke **retains** cursors for reactivation.

Reads — `/api/actors/<desk>/<id>/notes`, `…/notes/<noteId>`, and `…/dms` each now include
**`activity`** (newest visible message time in ms, or null), **`read`** (this actor's cursor in
ms, or null), and **`unread`** (`activity > read`). These reads use `actor-note-access` exactly as
before, never mutate state, omit inaccessible notes, and stay **message-only**. Host-wide
`/api/notes` and the main Noltbook unread state are unchanged. (No actor reply notifications or
mentions in G6A.)

### Actor Notifications — directed reply notifications (Phase G6B)

Each actor has a durable list of **directed reply notifications** (`actor-notifications`, keyed
`[app.desk, actor.id] -> (list actor-notification)`, **state-63**). When a new **message** replies
directly to a message attributed to an actor, that exact `[host desk id]` actor gets a notification
— and **no host attention is created for an actor-owned parent**. The parent is resolved by
`reply-to-eid` first, then the legacy `reply-to` (`@da`) fallback for old text replies, then looked
up in `actor-by-eid`; a parent with no actor row keeps the existing host reply/send attention
unchanged. **Reply-only** — actor mentions and artifact replies remain deferred.

- **Cross-ship.** Notifications are computed independently wherever a message is stored (local
  post, host `%remote-message`, subscribed `%new-message`; actor-DM messages flow through those
  same group paths). A notification is created **only on the target actor's host** (`actor.host ==
  our.bowl`) and only if that actor currently **owns or participates** per `actor-note-access` (so
  actor-DM owner/adopter rules are enforced). A remote host storing the same message never notifies
  an actor hosted elsewhere. No extra remote wire field is added.
- **Canonical registry required.** The target actor must have an **existing, non-revoked**
  `actor-registry` row. A **missing** row — historical `actor-by-eid` attribution can predate the
  registry migration — creates **no** notification and is never silently TOFU-registered; a
  **revoked** target creates none either. An actor-attributed parent **still suppresses host
  attention** even when its registry row is missing or revoked (it does not fall back to host
  reply attention).
- **Sender identity.** If the reply carries an actor, the sender is `[%actor host desk id]`;
  otherwise `[%ship author]`. A reply from the **exact same actor to itself** creates nothing; a
  host-ship reply is a **distinct** identity from an actor under that host (so a normal `~zod` reply
  to Rick **does** notify Rick), and different actors under the same host/app are distinct.
- **Preferences.** The target actor's `actor-preferences` apply: a sender in **muted** OR
  **blocked** suppresses the notification — but the message still posts, and host
  pal/block/mute/attention state is never touched. **Active and suspended** actors accumulate
  notifications (suspension does not lose activity); **revoked** actors receive none. Existing
  history may remain after suspension/revocation.
- **Durable read + live event.** `GET /api/actors/<desk>/<id>/notifications` returns
  `{ host, desk, id, notifications: [ { kind, noteId, eid, msgId, author, actor|null, preview,
  timestamp } ] }`, **newest-first**, resolving `author`/`actor`/`preview` from current state (so an
  edited message shows its current preview; rows whose replying message is gone are dropped). The
  **`timestamp` is the replying message's own `timestamp`** (identical on every ship), not the local
  receipt time; the durable record keeps an internal `created-at` for append-order/audit only.
  Ordering stays newest-first by stored append order (the timestamp correction did not change it).
  Live `%actor-notifications-updated desk id notifications full` facts arrive on `/api/results`:
  `full=false` is a **delta** (the new reply); `full=true` is the **authoritative remaining list**
  (after a clear or any deletion/note-removal prune). `/api/results` is live-only; the read route is
  the durable recovery surface after reconnect.
- **Clearing.** `actor-clear-notification {noteId, eid}` drops one row (missing → `missing-target`);
  `actor-clear-notifications` drops all (idempotent success). Both gate **`%attribute` +
  `%manage-own-notifications`** (candidate registry held until validation succeeds). **mark-read and
  clear are independent** — clearing never marks the note read, and `actor-mark-note-read` never
  clears notifications. Clearing never touches host mentions/attention/note-read.
- **Cleanup (live).** Deleting the replying message drops notifications targeting its `eid` (host +
  member paths, so a missed fact can't strand a row); `actor-remove-participant` / `actor-leave-note`
  drop that actor's notifications for the note; note/subtree deletion and ship-level note removal
  prune notifications for the removed note ids; empty per-actor rows are deleted. **Every** pruning
  path emits an authoritative `full=%.y` event to each actor whose list actually changed (a shared
  old-vs-new diff resolves remaining rows against the post-mutation state and stays silent when
  nothing changed), so live `/api/results` clients drop stale rows without rereading — including
  member-side deletes (apps may not watch `/notes`). Message **edits** keep notifications (the read
  shows the current edited preview).
- **state-63 migration** initializes `actor-notifications` **empty** — no retroactive notifications;
  messages, actors, cursors, and host attention are not rewritten.

**Harness smoke (sec. 3 + sec. 8c2).** The harness sends replies by stable `eid`, so a reply must be
posted with the **Reply to Selected Message** button (the normal **Send** button always posts a root
message with `replyToEid:null` and never inherits the selected message):

1. Rick and Alice are both **active** with app/actor caps for `attribute`, `post-message`, and
   `manage-own-notifications`, and each **owns or participates** in the selected note.
2. Post a **root** message as Rick with **Send** (sec. 3).
3. Click Rick's message row to select it — the **"Reply target"** line shows Rick's actor/eid.
4. Change **Actor Identity** to Alice.
5. Click **Reply to Selected Message** — Alice posts a reply carrying `replyToEid = Rick's eid`; the
   reply target clears to "none" on success.
6. Change **Actor Identity** back to Rick.
7. **Read Actor Notifications** (sec. 8c2) — the row identifies **Alice** as the replying actor.

| Action | Params | Success / failure codes |
| --- | --- | --- |
| `actor-clear-notification` | top-level `app`+`actor` + `{ noteId, eid }` | `actor-notification-cleared` / `missing-target` / `actor-invalid` / governance |
| `actor-clear-notifications` | top-level `app`+`actor` | `actor-notifications-cleared` (idempotent) / `actor-invalid` / governance |

### Actor → host notification parity (Phase A)

An actor is a **distinct behavioral sender** even though its host `@p` is the cryptographic
author. For regular notebook/group notes (including actor-DM `%group` notes), on the actor's host:

- A **locally hosted actor post** behaves as **incoming activity** for the host: it advances
  `note-activity` (host unread shows) but **does not** advance host `note-read` and emits no
  `note-read` fact. An **ordinary host post** (no actor) is unchanged — it advances `note-read` and
  emits the fact as before. (Predicate: `host-self = author==our && actor absent`.)
- An actor **reply to a normal host-authored message** may create host `%reply` attention; an actor
  writing **`@~host`** may create host `%mention` attention (ordinary host self-mentions stay
  ignored; `cleared-mentions` tombstones + eid-first identity preserved).
- A reply **to** an actor parent stays in that actor's G6B notifications and **never** falls back to
  host attention (G6B `parent-is-actor` suppression preserved); an actor replying to **itself** is
  still suppressed (G6B self-reply rule).
- Remote-ship messages and ordinary host posts are unchanged. Same behavioral-sender rule applies on
  the host `%remote-message` receiver and the subscribed `%new-message` rebroadcast path.
- **Default ON.** Per-actor / per-user **mute/block** controls are **not** part of Phase A (they
  arrive in Phase B). No state bump, no new caps, no wire change in Phase A.

**Harness smoke (sec. 3 + main Noltbook):** with `api-test` **closed** in main Noltbook, post a root
message as **Rick** (sec. 3) → `api-test` shows **unread** for the host; **open/view** it → normal
delayed mark-read clears it. Post as **ordinary host** (Actor Identity off) → **no** self-unread.
Post a normal host parent, close the note, reply to it as **Rick** → host gets reply attention; an
`@~host` mention from Rick → host gets mention attention. Alice→Rick reply → Rick's G6B notification
only (host gets nothing).

### Real-user actor mute/block + separate unread activity (Phase B)

The **real ship user** has ONE notification-preference system for **any** actor — local or remote —
keyed by the full stable `[host,desk,id]` (display name is never authority). Notifications are **ON by
default**; absence from the sets = on.

- **Recency vs unread are separate signals.** `note-activity` still drives sidebar **ordering** for
  every real message; a new durable `note-unread-activity` drives the **green unread dot** (durable
  unread = `note-unread-activity > note-read`). The **state-64 migration** seeds `note-unread-activity`
  from `note-activity` so existing unread is preserved. Muting never advances `note-read` to clear a
  dot (that would clear unrelated senders' unread).
- **Mute actor:** suppresses that actor's host green-unread **contribution** + host reply/@~host
  mention attention for the real user. The message is still stored, delivered, attributed, and still
  advances the actor's own G6A read cursor and (separately) any actor-owned **G6B** notifications.
  Recency (`note-activity`) still advances. The post is never rejected; the actor is never
  suspended/revoked; other users are unaffected.
- **Block actor:** mute **plus** the frontend hides that actor's message/pin **content** behind a
  compact *blocked actor* placeholder with a session-only **VIEW** (reveal is per session, not
  persisted). Blocking an actor **never** adds the actor's host ship to `pal-blocked`, never removes
  it from group membership, and never disables the app/actor. Block and mute are independent
  (`unblock` ≠ `unmute`); effective suppression = muted **OR** blocked.
- **Preference timing.** Changes apply to **future** unread/attention. Muting does **not**
  retroactively clear an existing unread dot — open/mark the note read normally. Blocking hides
  existing actor content immediately.

| Action (API `noltbook-api`) | Input | Result codes |
| --- | --- | --- |
| `mute-actor` / `unmute-actor` | `{ host, desk, id }` | `user-actor-muted` / `user-actor-unmuted` · `invalid-ship` / `invalid-actor` / `missing-target` (unmute of an un-muted) |
| `block-actor` / `unblock-actor` | `{ host, desk, id }` | `user-actor-blocked` / `user-actor-unblocked` · `invalid-ship` / `invalid-actor` / `missing-target` (unblock of an un-blocked) |

Internal `noltbook-action` equivalents (`mute-actor`/…`/unblock-actor`) carry a typed `actor-ref`.
Targets need **not** exist locally (remote actors are valid; no TOFU/last-seen). Read
`GET /api/user/actor-preferences` → `{ muted:[{host,desk,id}], blocked:[{host,desk,id}] }` (stable
identity only; profile/display resolution stays client-side). Every mutation + the `/notes` watch
replay a single authoritative `%user-actor-preferences` snapshot; the API also mirrors it on
`/api/results`. The main-Noltbook actor profile modal has **MUTE/UNMUTE** + **BLOCK/UNBLOCK**
buttons. Harness: **sec. 2.95 Host/User Actor Preferences** (separate from the actor's own sec. 2.9
preferences). Suppression is enforced on all three actor message paths (local `%send-message`, host
`%remote-message`, subscribed `%new-message`); canonical `%dm`/gossip/cover/rumor/envelope/artifact
paths are outside actor suppression.

### Actor Member Management (Phase E)

An app actor may manage the **real `@p` members** of notes it owns. Members stay ships —
actors are never inserted into `note.users`. Each action carries top-level `app` + `actor`
+ `{ noteId, ship }` and requires the `%manage-members` capability.

| action | data | result |
|---|---|---|
| `actor-add-member` | `{ noteId, ship }` | `actor-member-added` / `rejected` (already a member) / failures below |
| `actor-remove-member` | `{ noteId, ship }` | `actor-member-removed` / `missing-target` (not a member) / `rejected` (admin) |
| `actor-approve-join` | `{ noteId, ship }` | `actor-approved` / `missing-target` (no pending request) |
| `actor-deny-join` | `{ noteId, ship }` | `actor-denied` / `missing-target` |
| `actor-mute-member` | `{ noteId, ship }` | `actor-muted` / `missing-target` (not a member) / `rejected` (admin) |
| `actor-unmute-member` | `{ noteId, ship }` | `actor-unmuted` / `missing-target` (not muted) |

Common failures: `actor-invalid`, `actor-not-owner`, `invalid-ship`, `missing-note`,
`cap-missing`, `app-not-granted`, `app-disabled`, `actor-suspended`, `actor-revoked`,
`rejected`.

Authorization (shared gate): note exists → `app`+`actor` valid → **exact owner match**
`[host=our, desk=app.desk, id=actor.id]` (else `actor-not-owner`) → `gate-actor-cap`
with `{attribute, manage-members}` → parse ship → write-blocked/DM `rejected` →
**target ≠ host** `rejected` → per-action target-state check → reuse the existing internal
handler.

- **Exact ownership only.** Alice cannot manage Rick's note even via the same desk/host;
  an ordinary host-created note has no owner → `actor-not-owner`.
- The **app grant is the ceiling**; per-actor caps may narrow it (`cap-missing` → "app
  lacks %manage-members" / "actor lacks %manage-members").
- **Durable host-local.** Because actor-owned notes have `creator=our.bowl`, all successes
  are durable (never `accepted`/forwarded); the **host ship sends the real remote
  invite/kick pokes**, best-effort exactly as the internal handlers already do.
- **`actor-add-member` converts an actor-owned `%notebook` to `%group`** on the first
  member (the only way to have members). It never creates a DM — actor DM creation is a
  separate, deferred action.
- **Host & admins are protected.** An actor can never target the host ship, and
  `actor-remove-member` / `actor-mute-member` reject any ship in `note-admins` — admin
  assignment stays host-controlled.
- **Host-only (not exposed to actors):** `make-admin` / `remove-admin` (privilege
  escalation) and `deny-block-join` (its host path mutates global `pal-blocked`). The
  existing host membership/admin APIs are unchanged.
- **No durable actor audit this phase.** The actor is validated during the request, but
  *which* actor performed a membership action is **not persisted**; the result fact is
  live-only and remote members see the **host ship** as the authority. No actor artifact
  access.

### Actor Social — profile & status (Phase F1)

An actor maintains its own **profile**: a mutable display name plus avatar, bio, and
free-form status text. Requires `%attribute` + `%update-own-profile`.

| action | data | result |
|---|---|---|
| `update-actor-profile` | top-level `app`+`actor` + `{ displayName?, avatar?, bio?, statusText? }` | `actor-profile-updated` / `actor-invalid` / `invalid-name` / `invalid-avatar` / `cap-missing` / `app-not-granted` / `app-disabled` / `actor-suspended` / `actor-revoked` |

Every field is **three-state**: *absent* = keep, *`null`* = clear/reset, *value* = set.

- **`displayName`** is stored in **`actor-record.name`** (the canonical name), not in the
  profile. `null` resets it to the actor **id**; a string is capped to 64 bytes; empty
  after capping → `invalid-name`.
- **`avatar`** is `{ type, url }` with `type` ∈ `s3`/`ipfs`/`external` — **`%urbit` is not
  allowed** (an actor is not a native Urbit identity; verified sigil binding is a future
  capability). Unknown type or empty/over-2048-byte url → `invalid-avatar`. `null` clears.
- **`bio`** (cap 280) and **`statusText`** (cap 64) are free-form. `statusText` is profile
  text — **not** online presence and **not** the governance lifecycle `status`.

**Canonical identity hardening.** New actor actions/messages now stamp the **registry's**
current `name`/`kind`, not the values supplied on each poke. So after Rick sets his
display name to "Richard", a later post that still carries `actor.name:"Rick"` is stamped
**"Richard"**; **older messages keep their stamped "Rick".** `update-actor` (app-managed)
and `update-actor-profile` (actor's own) are the explicit ways to change the name; history
is never rewritten.

**Authentication honesty.** Gall does not authenticate the local app desk or an Earth-user
session. Noltbook scopes the data to `[desk, id]` and enforces the host grant; the trusted
app (e.g. Skiff) is responsible for authenticating **Rick vs Alice** — Noltbook cannot
independently prove which Earth user supplied the actor id.

**Host-local / same-ship only.** No propagation; remote ships still see only the
message-stamped name. No contacts/mute/block/presence/remote resolution and **no actor
artifact access** in this phase. An all-empty profile row reads identically to no row.

Reads (same-ship):
- `/api/actors/<desk>/<id>` → the registry record `{ desk, id, name, kind, status, caps, …timestamps }` (404 if no such actor).
- `/api/actors/<desk>/<id>/profile` →
```json
{ "host":"~zod", "desk":"skiff", "id":"rick", "displayName":"Rick", "kind":"user",
  "lifecycleStatus":"active",
  "avatar": null | { "type":"external", "url":"..." }, "bio": null|"...", "statusText": null|"..." }
```
`displayName`/`kind`/`lifecycleStatus` come from the registry; `avatar`/`bio`/`statusText`
from `actor-profiles` (null when no profile row).

### Actor Social — profile/avatar rendering & remote resolution (Phase G4)

Actor identities now render visually in the **main Noltbook frontend** — avatar images on
messages and pinned messages, and a dedicated **actor profile modal** (not the host's ship
profile) — for **local and remote** actors. The host ship and app desk stay visibly attached;
the first-letter glyph remains the fallback; **no Urbit sigils are ever drawn for actors.**

**Public profile** is the only actor data that crosses ships / is cached. It is presentation
only — `{ host, desk, id, displayName, kind, lifecycleStatus, avatar, bio, statusText }` —
and **never** carries grants, capability sets, contacts, preferences, or private registry
internals. `host` is **stamped** from `src.bowl`/`our.bowl` at the boundary, never trusted
from the payload. Suspended/revoked actors are still returned so historical attributed
messages remain inspectable.

**Local vs remote resolution.** A local actor resolves directly from `actor-registry` +
`actor-profiles`. A remote actor is fetched once per host via the **new** wire variants
`%remote-actor-profile-request` / `%remote-actor-profile-response` and cached in
`remote-actor-profiles` keyed `[host desk id]` with a `fetchedAt` stamp. Freshness window is
**~m10 (10 min)**: a fresh cache answers immediately; a stale entry triggers a refresh and is
**kept as stored fallback** (served by the read with `stale:true`) but is **not** re-echoed
until the fresh response arrives.

| action | data | result |
|---|---|---|
| `request-actor-profile` (API) | `{ requestId (required), host, desk, id }` | immediate `actor-profile-requested` / `invalid-ship` / `invalid-desk` / `actor-invalid`; then an async **`actor-profile-result`** on `/api/results` |

The async result (`actor-profile-result`, also emitted on the FE `/notes` stream — one stable
encoder for both) is:
```json
{ "requestId": 7, "host":"~wet", "desk":"skiff", "id":"alice",
  "status": "ok" | "missing" | "unreachable" | "invalid-response",
  "fetchedAt": 1718900000000 | null,
  "profile": { …public profile… } | null }
```
- **ok** → profile present + cached. **missing** → host has no such actor (cache nothing).
  **invalid-response** → the host returned a profile whose `desk`/`id` did **not** match the
  request; it is **rejected and NOT cached** (a host may only assert profiles under its own
  authenticated `src.bowl` namespace — a mismatched Alice payload is never normalized into a
  Rick cache key). **unreachable** → the host poke **nacked** (host down / old peer that can't
  parse the new variant). A reachable-but-silent host (e.g. one that blocks the requester) is
  **not** turned into `unreachable` by the backend — that would need a durable pending-request
  map, which does not exist; the **frontend/harness timeout** covers that case. We never
  fabricate a confirmation. There is **no req-id pending map** server-side: correlation is the
  caller's job, and the host can only answer under its own `src.bowl`.
- **`fetchedAt`** (ms, or `null`) reflects backend cache age so the FE freshness is honest:
  `null` for a local result, a new remote response (cached at *now*), or any negative result;
  the **stored fetch time** for a fresh-cache hit.

There is **also** a local frontend-internal action `request-actor-profile { host, desk, actorId,
reqId }` (poked as `noltbook-action`) that the main UI uses to resolve unique actors it sees.
**Frontend freshness:** a resolved profile is **fresh for 10 min** (skipped while fresh); after
10 min a **refresh is requested while the stale data keeps displaying**; `missing`/
`invalid-response` get a **5 min** negative cooldown and `unreachable` a **2 min** cooldown, so
render cycles never re-poke a dead/missing host. In-flight requests are deduplicated, and the
flow **never reloads the message timeline**. A local profile stays cached until an
`actor-profile-updated` fact arrives. The **actor profile modal has an explicit RETRY** button
that bypasses freshness + cooldown.

**Security — delegated clicks:** actor avatars/names carry the identity in `data-*` attributes
(`data-actor-profile`/`data-host`/`data-desk`/`data-id`/`data-name`/`data-kind`); a single
**capture-phase** delegated listener reads `dataset` and calls `viewActorProfile`. **No
actor-controlled value is ever interpolated into an inline JavaScript expression**, so quotes in
an actor name can't break out into script. Applies to both normal and pinned actor messages;
`stopPropagation` behavior is preserved.

**`update-actor-profile`** additionally emits an **`actor-profile-updated`** fact on `/notes`
(public profile only) so the main UI refreshes immediately. Profiles are **not** pushed to
remote ships — they re-resolve through the cache/TTL.

**Wire compatibility:** these are **new** remote variants (no existing ship-profile wire shape
changed). An **old peer cannot answer** them, so all participating ships must run matching code
before remote actor-profile testing; until then the fallback is the message-carried `name`/
`kind` + initial glyph. No actor **DMs** are added (the modal has no DM button), and there are
no sigils, pals, contacts, SEND, block, wallet, or plugin controls on an actor.

Reads:
- `/api/actors/<desk>/<id>/profile` — unchanged (same-ship actor-management tooling).
- `/api/actor-profiles/<host>/<desk>/<id>` → the public profile JSON **+ `fetchedAt`/`stale`**.
  Local host resolves the current local profile (`stale:false`, `fetchedAt:null`); a remote
  host returns the **cached** profile (`stale` = older than ~m10); unknown/uncached → 404.

### Actor Social — contact books (Phase F2)

Each actor has its **own contact book** of **identity references** — a real ship or
another actor. Requires `%attribute` + `%manage-own-contacts`.

| action | data | result |
|---|---|---|
| `actor-add-contact` | top-level `app`+`actor` + `{ ref }` | `actor-contact-added` / `actor-invalid` / `invalid-ref` / `invalid-ship` / `rejected` (self) / `cap-missing` / governance codes |
| `actor-remove-contact` | top-level `app`+`actor` + `{ ref }` | `actor-contact-removed` / `missing-target` / (same failures) |

**`identity-ref`** (`ref`) is a tagged object — a **ship** or an **actor**:
```json
{ "kind":"ship",  "ship":"~wet" }
{ "kind":"actor", "host":"~wet", "desk":"skiff", "id":"alice" }
```

- **Contacts are not pals** — no trust, Ames, membership, wallet, or plugin authority;
  adding a contact grants nothing. The book is scoped to `[app.desk, actor.id]` and
  **never touches the host's `contacts=(set @p)`** or `/api/contacts`.
- **Validation:** a bad ship/host `@p` → `invalid-ship`; a bad desk-term, empty/over-128-byte
  id, or malformed structure → `invalid-ref`. A `null`/non-object/unknown-kind `ref` parses
  to `%invalid` (→ `invalid-ref`), never a crash.
- **Self-contact:** an *actor* ref equal to your own `[our, app.desk, actor.id]` → `rejected`.
  A *ship* ref to the host is allowed (a distinct real identity).
- **Remote refs are stored unresolved** — a valid `[host, desk, id]` is saved immediately;
  current name/avatar of a remote actor is **not** resolved (deferred). Reads return only
  the stable tagged reference — no invented names/profile fields.
- **Duplicate `actor-add-contact` is idempotent success** (set membership). **`actor-remove-contact`
  of a non-member → `missing-target`**; removing the last entry **deletes the map row**.
- **Atomic:** an invalid/missing-target request does **not** TOFU-register the actor or bump
  last-seen — the candidate registry is committed only on success.
- **Same-ship / cooperative.** Noltbook scopes storage and enforces the host grant, but Gall
  cannot authenticate which Earth user supplied the actor id — **Skiff** must authenticate
  Rick vs Alice. The book is durable app data, not a hard private vault against the host.
- Suspend/revoke rejects writes but **retains** the contact data. **No** profile propagation,
  mute, block, presence, wallet, artifact, or gossip access in this phase.

Read: `/api/actors/<desk>/<id>/contacts` (404 if no such actor) →
```json
{ "host":"~zod", "desk":"noltbook-dev", "id":"rick",
  "contacts": [ { "kind":"ship", "ship":"~wet" },
                { "kind":"actor", "host":"~wet", "desk":"skiff", "id":"alice" } ] }
```

### Actor Social — identity mute & block preferences (Phase F3)

Each actor has its **own stored-only identity mute/block book** consumed by the
**plugin**. Requires `%attribute` + `%manage-own-preferences`. Every action carries a
tagged `ref` (the same `identity-ref` shape as contacts).

| action | data | result |
|---|---|---|
| `actor-block-identity` | `app`+`actor` + `{ ref }` | `actor-identity-blocked` / `invalid-ref` / `invalid-ship` / `rejected` (self) / `cap-missing` / governance |
| `actor-unblock-identity` | `app`+`actor` + `{ ref }` | `actor-identity-unblocked` / `missing-target` (not blocked) / (same) |
| `actor-mute-identity` | `app`+`actor` + `{ ref }` | `actor-identity-muted` / (same as block) |
| `actor-unmute-identity` | `app`+`actor` + `{ ref }` | `actor-identity-unmuted` / `missing-target` (not muted) / (same) |

**`actor-preferences`** stores two independent sets per `[app.desk, actor.id]`:
```
blocked : set of identity-ref   — hide that identity's content in the plugin
muted   : set of identity-ref   — suppress that identity's notifications/attention
```

- **Identity mute vs identity block are independent.** Block = *hide content*;
  mute = *suppress notifications* (content stays visible). Blocking never adds/removes
  mute and vice versa — unblocking leaves any mute in place, and unmuting leaves any
  block in place.
- **Stored-only / plugin-applied.** Noltbook only **stores and authorizes** preferences;
  it does **not** filter API reads or prevent posts in this phase. A blocked/muted target
  stays free to post. The plugin (Skiff) owns rendering/filtering in v1.
- **Never mutates host state** — `pal-blocked`, `blocked-by`, `contacts`, `note-muted`,
  note members/admins, and host attention/read state are all untouched. Block/mute are
  not pals, Ames controls, or moderator actions.
- **Validation** mirrors contacts: bad ship/host `@p` → `invalid-ship`; bad desk-term,
  empty/over-128-byte id, or malformed structure → `invalid-ref` (never a crash);
  an *actor* ref equal to your own `[our, app.desk, actor.id]` → `rejected` (a *ship*
  ref to the host is allowed). **Remote actor refs are stored unresolved** (no name/profile).
- **Idempotent / missing-target:** duplicate block/mute is success; unblocking/unmuting a
  ref that isn't present → `missing-target`. When both sets become empty the map row is
  deleted.
- **Atomic:** any failed action (governance, `invalid-ref`/`invalid-ship`, `rejected`,
  `missing-target`) does **not** TOFU-register the actor or bump last-seen — the candidate
  registry is committed only on success — and still emits a visible `/api/results` fact
  when a `requestId` is supplied.
- **Same-ship / cooperative.** Skiff must authenticate Rick vs Alice; Gall cannot. Suspend/revoke
  rejects writes but **retains** preferences for reactivation. **No** profile propagation,
  presence, wallet, artifact, pals, or gossip actor access in this phase.

Read: `/api/actors/<desk>/<id>/preferences` (404 if no such actor) →
```json
{ "host":"~zod", "desk":"noltbook-dev", "id":"rick",
  "blocked": [ { "kind":"ship", "ship":"~wet" },
               { "kind":"actor", "host":"~wet", "desk":"skiff", "id":"alice" } ],
  "muted":   [ { "kind":"ship", "ship":"~sampel-palnet" } ] }
```

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
| `/api/notes/<id>` | `{ noteId, messages: [ { id, msgId, author, text, timestamp, edited, eid, replyToEid, via, actor } ], artifacts: [ { id, name, type, creator, noteId, eid, replyToEid, created, updated, versionCount, latestVersion, latestEditor, latestTimestamp, mime, kind, size, url, downloadUrl, via } ], app, pin, active, actorOwner }` |
| `/api/artifacts/<id>` | `{ artifact: { …artifact fields…, via, versions: [ { version, content, editor, timestamp } ] } }` |
| `/api/actor-grants` | `{ grants: [ { desk, enabled, caps, grantedBy, grantedAt, updatedAt, revokedAt } ] }` |
| `/api/actors` | `{ actors: [ { desk, id, name, kind, status, createdAt, updatedAt, revokedAt, lastSeen, caps } ] }` (`caps`: `null` = inherit app grant, else array) |
| `/api/actors/<desk>` | same as `/api/actors`, filtered to one desk |
| `/api/actors/<desk>/<id>` | one actor's registry record (404 if absent) |
| `/api/actors/<desk>/<id>/profile` | `{ host, desk, id, displayName, kind, lifecycleStatus, avatar, bio, statusText }` (same-ship management read) |
| `/api/actor-profiles/<host>/<desk>/<id>` | public profile `+ { fetchedAt, stale }` (G4): local host = current profile (`stale:false`); remote host = cached (`stale` if >~m10); 404 if unknown/uncached |
| `/api/actors/<desk>/<id>/contacts` | `{ host, desk, id, contacts: [ {kind:"ship",ship} \| {kind:"actor",host,desk,id} ] }` |
| `/api/actors/<desk>/<id>/preferences` | `{ host, desk, id, blocked: [identity-ref], muted: [identity-ref] }` (stored-only; no filtering) |
| `/api/actors/<desk>/<id>/notes` | `{ notes: [ { id, name, type, creator, visibility, writable, userCount, lastAuthor, lastPreview, actorOwner, owned, participant, activity, read, unread } ] }` (owned or participated, live notes only; no artifacts; `activity`/`read`/`unread` are G6A message-only actor read state; 404 if actor absent) |
| `/api/actors/<desk>/<id>/notes/<noteId>` | `{ noteId, note (incl. activity/read/unread), messages: [ …with actor/via… ] }` (404 unless the actor owns or participates; no artifacts) |
| `/api/actors/<desk>/<id>/dms` (G5A) | `{ dms: [ { noteId, actorDm, target, counterpart, createdAt, lastAuthor, lastPreview, owned, adopted, activity, read, unread } ] }` (valid live actor DMs the actor owns/adopted; no artifacts; 404 if actor absent) |
| `/api/actors/<desk>/<id>/notifications` (G6B) | `{ host, desk, id, notifications: [ { kind, noteId, eid, msgId, author, actor, preview, timestamp } ] }` (directed reply notifications, newest-first; resolved live; reply-only; 404 if actor absent) |
| `/api/profile/<ship>` | `{ ship, known, displayName, avatar, walletAddress, azimuthAddress, palStatus, isContact, isBlocked }` |
| `/api/contacts` | `{ contacts: [ …profile fields… ] }` |
| `/api/notes/<id>/members` | `{ noteId, members: [ …profile fields…, role, muted, removed ] }` |
| `/api/notes/<id>/meta` | `{ id, name, type, creator, visibility, writable, parent, children, userCount, removedCount, iconUrl, headline, lastAuthor, lastPreview, hostStatus, activity, read, forkOrigin, forkVersion, forkOf, memberRev, app, pin, active, capabilities: {…}, actorOwner }` |
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
  - **Actor permissions (Phase C):** use the **app caps** checkboxes on the grant to set
    the app ceiling, and the **actor permissions** checklist for the current Actor Identity
    id — leave **Inherit app permissions** checked to inherit the grant, or uncheck it to
    toggle `attribute` / `post-message` / `edit-own-message` / `delete-own-message`
    independently, then **Save Actor Permissions** (no need to type capability names).
    To test the ceiling: give Rick `edit-own-message` but uncheck it on the app grant →
    Edit as Actor returns `cap-missing` ("app lacks %edit-own-message"). To test actor
    narrowing: keep it on the grant but uncheck it for Rick → `cap-missing` ("actor lacks
    %edit-own-message").
- **Artifacts** — Create Artifact (code/app); Detail; Edit / Delete on the selected artifact.
- **Pin** — in Read Recent, Pin a message or `%file`/`%app` artifact row (one pin per note); the pinned-item block shows kind/target/pinnedBy with Clear Pin. Verify: pin a message, pin a `%file`/`%app` artifact (`%code` has no Pin button), setting a new target **replaces** the pin, `clear-note-pin` clears it, a non-creator is `rejected`, and deleting the pinned target auto-clears the pin. Read Meta shows the `pin` line.
- **Active** — *Active* card: Set Active (label/count/ttl; sends top-level `app:APP`) → `active-set`; Read Recent/Meta show the `active` line and the sidebar shows the same green in-progress style as calls. Verify: the compact sidebar badge shows the count only when present (the label is in the title), after `ttl` seconds the read shows `active:null` (expiry filter), Clear Active → `active-cleared`. A `set-note-active` without `app` returns `missing-app` (the harness always sends `APP`, so test that path via the debug console/docs); a non-creator returns `rejected`.
- **App Notifications** — *App Notifications* card: Set App Notification (id/title/body/level/ttl; sends top-level `app:APP`) → `app-notification-set`; Read App Notifications shows the row from `/api/app-notifications`, and the main Noltbook Grimoire/Inbox shows an APP row with OPEN/CLEAR where applicable. Clear App Notification → `app-notification-cleared`; setting the same id updates the row; short `ttl` values expire from reads/snapshots.
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

## A2 — Actor membership, requests, and note-level mute (single-ship)

Backend reads + the noltbook-dev **A2 Actor Membership** card. **Local-only**; the remote
actor join/install/carrier protocol and main-Noltbook ACTORS Members UI are **deferred to A3**.

### Visibility / join semantics
- **Public** note → an actor `actor-join-note` joins directly → result `actor-joined`.
- **Private / Secret** note → `actor-join-note` creates a durable request → `actor-join-requested`.
  Secret stays undiscoverable; a known-ID request never changes discovery. The note ID field is
  editable precisely because an actor can know a private/secret ID it cannot select.
- The note's **owner actor** (via its app, `%manage-members`) approves / denies / invites /
  removes / mutes / unmutes. Approval + invite convert a `%notebook` to `%group`.

### Note-level actor mute
`note-actor-muted` is per-actor (never the carrier ship). A muted actor's **post / app-ref /
edit / delete** fail with `note-actor-muted`; it can still **read, manage notifications, and
leave**. A muted **owner** also cannot configure/delete/moderate (emergency mute neutralizes
a rogue owner). Codes: set=`note-actor-mute-set`, clear=`note-actor-mute-cleared`,
blocked-write=`note-actor-muted`.

### Authority families
- **Owner-actor** (app-attributed API): `actor-approve-request` / `actor-deny-request` /
  `actor-add-participant` / `actor-remove-participant` / `actor-mute-participant` /
  `actor-unmute-participant`. `targetDesk` is the strict three-state spec (omitted ⇒ owner app
  desk for add/remove; required for approve/deny/mute/unmute; malformed ⇒ `actor-invalid`).
- **Ordinary host/admin** (`manage-note-actor {op,noteId,targetHost,targetDesk,targetId}`):
  ordinary (non-actor-owned) notes only; host/admin authority; ops approve/deny/invite/remove/
  mute/unmute. Remote-admin forwarding is deferred to A3 (`unsupported`).
- **Explicit host emergency** (`emergency-manage-note-actor {op,…}`): actor-owned notes only;
  ops **mute / unmute / remove**; remove rejects the exact owner; mute may target the owner;
  never approves/denies/invites and never a silent fallback. Codes `emergency-actor-*`.

### Read shapes (cooperative same-ship developer scries — NOT hard app auth)
- `GET /api/notes/<noteId>/actors` → `{noteId, owner, actors:[{host,desk,id,name,kind,
  lifecycleStatus,role,muted}]}` — member-safe; requires the local human to logically see the
  note; owner first, deduped; **no pending requests**.
- `GET /api/notes/<noteId>/actor-requests` → `{noteId, requests:[…]}` — ordinary locally-hosted
  note + real host/admin authority only (NOT merely `human-sees-note`); hidden actor-owned
  requests never appear; actor-DM ⇒ 404.
- `GET /api/actors/<desk>/<id>/notes/<noteId>` → adds `membership:{owner,actors,mutedActors,
  pendingRequests}` — `mutedActors`/`pendingRequests` populated **only for the exact owner
  actor**; participating non-owners get member-safe roster only.

The **mutation handlers are the real authority boundary**; a scry cannot prove app/actor identity.

### Harness card
Edit the note ID (or `⟵ from selected`), set target host/desk/id, then use Self / Owner-Actor /
Host-Admin / **Host Emergency** rows, or the three Read buttons. Mutations are request-correlated
(require the result stream; duplicate-guarded; OK silently refreshes the read; FAIL preserves
inputs and shows the exact code; stream drop ⇒ reported unconfirmed). Live `actor-roster-updated`
/`actor-request-updated`/`note-actor-muted-updated` facts are handled if/when the backend emits
them (A2 currently refreshes by re-reading).
