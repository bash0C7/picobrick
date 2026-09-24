# Rackup::Handler::Picobrick。picobrickのrequestをRack SPECのenvへ、
# appの返り値をpicobrickのresponseへ橋渡しする。CRubyのPumaが自分のgemで
# `Rackup::Handler::Puma`を定義・登録するのと同じく、picobrickが自分で持つ。
# envとresponseの規則は`Picobrick::RackEnv`(picobrick_rack_env.rb)。登録先の
# `Rackup::Handler`はpicoruby-rackupのもので、picoruby-rackupはpicobrickを知らない
# (依存はpicobrick→picoruby-rackupの一方向)。
#
# 形はCRubyのrackupのhandler(`run(app, **options) { |server| }`・`shutdown`)に
# 合わせる。`::Picobrick::Server`は`run`を呼んだときに引く。
module Rackup
  module Handler
    class Picobrick
      def self.run(app, **options)
        adapter = new(app, (options[:Port] || 8080).to_i)
        @server = ::Picobrick::Server.new(
          app: adapter,
          host: (options[:Host] || "127.0.0.1").to_s,
          port: (options[:Port] || 8080).to_i
        )
        yield @server if block_given?
        @server.start
      end

      def self.shutdown
        server = @server
        @server = nil
        server.shutdown if server
      end

      def initialize(app, port)
        @app = app
        @port = port
      end

      def call(request)
        env = ::Picobrick::RackEnv.build(meta_vars(request), input: ::Picobrick::RackEnv::Input.new(request.body))
        status, headers, body = @app.call(env)
        status, headers, content = ::Picobrick::RackEnv.normalize_response(env, status, headers, body)
        ::Picobrick::RackEnv.run_response_finished(env, status, headers, nil)
        [status, headers, content]
      end

      # picobrickのrequestを、CGI形式の変数にする。
      def meta_vars(request)
        host, given_port = request["host"].to_s.split(":", 2)
        vars = {
          "REQUEST_METHOD" => request.method.to_s,
          "PATH_INFO" => request.path.to_s,
          "QUERY_STRING" => request.query.to_s,
          "REQUEST_URI" => request.target.to_s,
          "SERVER_NAME" => host.to_s.empty? ? "127.0.0.1" : host.to_s,
          "SERVER_PORT" => (given_port || @port).to_s,
          "SERVER_PROTOCOL" => request.version.to_s,
          "SERVER_SOFTWARE" => "picobrick/#{::Picobrick::VERSION}"
        }
        vars["CONTENT_TYPE"] = request["content-type"] if request["content-type"]
        vars["CONTENT_LENGTH"] = request["content-length"] if request["content-length"]
        request.headers.each do |name, value|
          next if name == "content-type" || name == "content-length"

          vars["HTTP_" + name.upcase.tr("-", "_")] = value
        end
        vars
      end
    end
  end
end

Rackup::Handler.register("picobrick", Rackup::Handler::Picobrick)
