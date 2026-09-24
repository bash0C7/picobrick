# picobrick

A small development HTTP server for [PicoRuby](https://github.com/picoruby/picoruby).
It doesn't aim to be compatible with any existing server - it does only
what a development loop needs:

- read an HTTP/1.1 request line, headers, and a `Content-Length` body (a
  chunked body is rejected with 411)
- write a status line, headers, and body (with `Content-Length`, honoring
  keep-alive or close)
- run each connection on its own [`Task`](https://github.com/picoruby/picoruby),
  cooperatively, so one slow or silent connection never blocks the others
  (the head-of-line blocking a straight accept-loop server has)

Like CRuby's Puma, it owns both the server and its own Rack handler
(`Rackup::Handler::Picobrick`, registered with
[picoruby-rackup](https://github.com/bash0C7/picoruby-rackup)) and the
part that builds a Rack `env` and shapes the response
(`Picobrick::RackEnv`). `picoruby-rackup` doesn't know picobrick exists;
picobrick registers itself the same way any other server would
(`Rackup::Handler.register("picobrick", Rackup::Handler::Picobrick)`).

## Installation

```ruby
conf.gem github: 'bash0C7/picobrick', branch: 'main'
```

## Dependencies

- `picoruby-socket` (`TCPServer`/`TCPSocket`)
- [`picoruby-rackup`](https://github.com/bash0C7/picoruby-rackup) (`Rackup::Handler.register`)

## Usage

An app is anything that responds to `call(env)` and returns a Rack triple
(`[status, headers, body]`). Run it through the Rack handler, same as any
other Rackup-registered server:

```ruby
Rackup::Handler.pick(["picobrick"]).run(app, Host: "127.0.0.1", Port: 8080) do |server|
  # server is the running Picobrick::Server; keep it if you need to shut it down later
end
```

Or drive `Picobrick::Server` directly, without going through Rackup:

```ruby
server = Picobrick::Server.new(
  app: app,                        # call(request) -> [status, headers, body_string]
  host: "127.0.0.1",
  port: 8080,
  keep_alive_timeout: 5,
  max_keep_alive_requests: 100,
  request_timeout: 30
)
server.start     # blocks the caller's Task; accepts on its own Task, one Task per connection
server.shutdown  # closes the listener; alias `stop`
```

| `Picobrick::Server` | |
|---|---|
| `#start` | Opens the listener and runs the accept loop on its own Task; blocks until `shutdown` |
| `#shutdown` (alias `#stop`) | Closes the listener; in-flight connections finish on their own Tasks |
| `#running?` | `true` while the accept loop is live |
| `#status` | `:stopped`, `:running`, or `:stopping` |

### Standalone: an echo server

No Sinatra, no Rack env - just `Picobrick::Server` and an app that
responds to `call(request)` with a `Picobrick::Request`:

```ruby
app = lambda do |request|
  [200, { "content-type" => "text/plain" }, "#{request.method} #{request.path}\n#{request.body}"]
end

Picobrick::Server.new(app: app, port: 8899).start
```

```sh
$ picoruby echo.rb &
$ curl -X POST -d "hello" http://127.0.0.1:8899/echo
POST /echo
hello
```

`Picobrick::RackEnv` fills in the Rack SPEC pieces a server is responsible
for (`rack.input`, `rack.errors`, `rack.url_scheme`,
`rack.response_finished`, `SCRIPT_NAME`, `PATH_INFO`), normalizes a
response's headers and body, and calls any `rack.response_finished`
callbacks. `Picobrick::Error` (and its subclasses `BadRequest`,
`LengthRequired`) carry the HTTP status a malformed request should get
back; `Picobrick.reason_phrase(status)` looks up the standard reason
phrase for a status code.

## Testing

```
rake test
```

Fetches and builds a PicoRuby VM into `vendor/` (git-ignored, not pinned
to any particular version) on first run, then runs `test/` against it
with [picoruby-picotest](https://github.com/picoruby/picoruby/tree/master/mrbgems/picoruby-picotest).
`rake clean` removes `vendor/`; `rake clean_test` runs both in sequence.

`rake test` covers `Picobrick::Request`, `Picobrick::Response`, and
`Picobrick::RackEnv` - the pure-Ruby layer with deterministic input and
output. `Picobrick::Server` and `Picobrick::NonblockSocket` open a real
socket and run on a `Task`; they aren't covered here and need a
real-socket check in whatever app embeds this gem.

## License

MIT
