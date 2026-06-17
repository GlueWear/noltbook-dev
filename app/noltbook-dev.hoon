::  noltbook-dev — minimal same-ship harness agent.
::
::  Sole job: bind Eyre at /apps/noltbook-dev and serve lib/noltbook-dev/index.html
::  (a static page). The page itself talks to %noltbook over the normal Eyre
::  channel (api.scry / api.poke) using ONLY existing public-ish surfaces — it
::  does NOT modify or depend on noltbook internals. This mirrors how noltbook
::  serves its own SPA, so no docket/glob is needed.
/+  default-agent, dbug, server
|%
+$  versioned-state  $%([%0 ~])
+$  card  card:agent:gall
--
%-  agent:dbug
=|  [%0 ~]
=*  state  -
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
++  on-init
  ^-  (quip card _this)
  :_  this
  ~[[%pass /eyre-bind %arvo %e %connect [~ /apps/noltbook-dev] %noltbook-dev]]
++  on-save   !>(state)
++  on-load   |=(=vase `this)
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+  mark  (on-poke:def mark vase)
      %handle-http-request
    =+  !<([eyre-id=@ta =inbound-request:eyre] vase)
    ::  all routes require an authenticated session (same-ship user).
    ?.  authenticated.inbound-request
      :_  this
      %+  give-simple-payload:app:server  eyre-id
      (login-redirect:gen:server request.inbound-request)
    ::  Noltbook app manifest (read-only discovery). Noltbook's Apps tab fetches
    ::  /apps/<desk>/noltbook.json per installed desk; a valid manifest groups the
    ::  app under NOLTBOOK APPS and shows the NOLTBOOK APP capability panel. This
    ::  is display-only — Noltbook does not execute these actions yet.
    =/  url-tape=tape  (trip url.request.inbound-request)
    =/  path-tape=tape
      =/  q  (find "?" url-tape)
      ?~  q  url-tape
      (scag u.q url-tape)
    ?:  =(path-tape "/apps/noltbook-dev/noltbook.json")
      =/  manifest=@t
        '{"noltbook":1,"title":"Noltbook Dev","summary":"Developer harness for testing the Noltbook API surface.","actions":[{"id":"api-harness","kind":"open","label":"Open API Harness","description":"Inspect notes, post messages, test artifacts, pins, calls, forks, and developer attribution.","href":"/apps/noltbook-dev"},{"id":"example-note","kind":"note-template","label":"Example Note","description":"A future template action for creating an app-shaped Noltbook note."}]}'
      =/  =simple-payload:http
        :-  [200 ~[['content-type' 'application/json']]]
        `(as-octs:mimes:html manifest)
      [(give-simple-payload:app:server eyre-id simple-payload) this]
    =/  html-path=path
      :*  (scot %p our.bowl)
          q.byk.bowl
          (scot %da now.bowl)
          /lib/noltbook-dev/index/html
      ==
    =/  html-bytes=octs  (as-octs:mimes:html .^(@ %cx html-path))
    =/  =simple-payload:http
      :-  [200 ~[['content-type' 'text/html; charset=utf-8']]]
      `html-bytes
    [(give-simple-payload:app:server eyre-id simple-payload) this]
  ==
++  on-arvo
  |=  [=wire =sign-arvo]
  ^-  (quip card _this)
  ?+  wire  (on-arvo:def wire sign-arvo)
      [%eyre-bind ~]
    `this
  ==
++  on-peek   on-peek:def
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?+  path  (on-watch:def path)
      [%http-response @ ~]
    `this
  ==
++  on-leave  on-leave:def
++  on-agent  on-agent:def
++  on-fail   on-fail:def
--
