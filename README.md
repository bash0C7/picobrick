# picobrick

A small development HTTP server for [PicoRuby](https://github.com/picoruby/picoruby).
It doesn't aim to be compatible with any existing server - it does only
what a development loop needs: read and write HTTP/1.1, keep-alive, and
one slow connection (its own [`Task`](https://github.com/picoruby/picoruby))
never blocking the others.

Like CRuby's Puma, it owns both the server and its own Rack handler
(`Rackup::Handler::Picobrick`, registered with
[picoruby-rackup](https://github.com/bash0C7/picoruby-rackup)) and the
part that builds a Rack `env` and shapes the response
(`Picobrick::RackEnv`). `picoruby-rackup` doesn't know picobrick exists;
picobrick registers itself the same way any other server would.

Extracted from [bash0C7-homepage](https://github.com/bash0C7/bash0c7-homepage),
where it's the default server behind a self-hosted
[Sinatra](https://github.com/udzura/picoruby-sinatra-covers) admin
console.

## Dependencies

- `picoruby-socket` (`TCPServer`/`TCPSocket`)
- [`picoruby-rackup`](https://github.com/bash0C7/picoruby-rackup) (`Rackup::Handler.register`)

## Usage

```ruby
MRuby::Gem::Specification.new("your-gem") do |spec|
  spec.add_dependency "picobrick", github: "bash0C7/picobrick"
end
```

## License

MIT
