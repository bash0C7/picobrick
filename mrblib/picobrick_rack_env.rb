# Rack SPECのサーバー側の義務: requestからenvを作り、appの返り値を書き出せる形に
# 整える。CRubyでは各サーバー(Puma等)が自分で持つ仕事なので、picobrickが持つ
# (`Rackup::Handler::Picobrick`が使う)。細かい規則はudzura/picoruby-cloudflare-worker-wasm
# の`RackAdapter`の振る舞いに合わせる(response headerは小文字、1xx/204/304では
# bodyを捨てる、`rack.response_finished`を用意する)。HEADのbodyは捨てない:
# Content-LengthをGETと同じにするため、bodyを送らない判断はサーバーに任せる。
#
# PicoRubyに無いメソッド(`each_with_object`・`max_by`等)は使わない。
module Picobrick
  module RackEnv
    # `rack.input`。bodyは読み切った文字列で受ける(streamingはしない)。
    class Input
      def initialize(data)
        @data = data.to_s
        @pos = 0
      end

      def read(length = nil, buffer = nil)
        rest = @data.bytesize - @pos
        if length.nil?
          chunk = @data.byteslice(@pos, rest) || ""
          @pos = @data.bytesize
        else
          return nil if rest <= 0 && length > 0
          return "" if length == 0

          size = length < rest ? length : rest
          chunk = @data.byteslice(@pos, size) || ""
          @pos += size
        end
        if buffer
          buffer.replace(chunk)
          return buffer
        end
        chunk
      end

      def gets
        return nil if @pos >= @data.bytesize

        rest = @data.byteslice(@pos, @data.bytesize - @pos)
        index = rest.index("\n")
        line = index ? rest[0, index + 1] : rest
        @pos += line.bytesize
        line
      end

      def each
        while (line = gets)
          yield line
        end
      end

      def rewind
        @pos = 0
        0
      end

      def close
        nil
      end
    end

    # `rack.errors`。書かれたものを$stderrへ流す。
    class Errors
      def puts(message)
        $stderr.puts(message)
      end

      def write(message)
        $stderr.print(message.to_s)
      end

      def flush
        self
      end
    end

    # CGI形式のmeta_varsにRackのkeyを足してenvを作る。
    def self.build(meta_vars, input:, url_scheme: "http")
      env = {}
      meta_vars.each { |k, v| env[k] = v }
      env["SCRIPT_NAME"] = ""
      path = env["PATH_INFO"].to_s
      env["PATH_INFO"] = path.empty? ? "/" : path
      env["QUERY_STRING"] = env["QUERY_STRING"].to_s
      env["SERVER_PROTOCOL"] ||= "HTTP/1.1"
      env["rack.url_scheme"] = url_scheme
      env["rack.input"] = input
      env["rack.errors"] = Errors.new
      env["rack.multithread"] = false
      env["rack.multiprocess"] = false
      env["rack.run_once"] = false
      env["rack.hijack?"] = false
      env["rack.response_finished"] = []
      env
    end

    # appの返り値を[status, 小文字化したheaders, bodyを連結した文字列]にする。
    # headerの値が配列なら改行区切りの複数値(Rack 3)として`\n`で繋いで返す
    # (書き出し側が行に分ける)。
    def self.normalize_response(env, status, headers, body)
      status = status.to_i
      normalized = {}
      (headers || {}).each do |name, value|
        key = name.to_s.downcase
        normalized[key] = value.is_a?(Array) ? value.join("\n") : value.to_s
      end
      content = drop_body?(env, status) ? "" : join_body(body)
      body.close if body.respond_to?(:close)
      [status, normalized, content]
    end

    # 部品が1つなら、その文字列をそのまま使う(複製しない)。PicoRubyのheapは固定
    # (picoruby binaryは6.4MB)で、File.readの文字列は4KBずつ継ぎ足して伸ばした確保量を
    # 抱えたまま(2.17MBのpicoruby.wasmで約3.5MB)になる。これを連結で複製すると、
    # 連続した空きが足りずNoMemoryErrorになった(管理画面をheadless Chromeで開いて発見)。
    def self.join_body(body)
      return body if body.is_a?(String)
      return body.to_s unless body.respond_to?(:each)

      parts = []
      body.each { |part| parts << part.to_s }
      return "" if parts.empty?
      return parts[0] if parts.size == 1

      parts.join
    end

    def self.drop_body?(_env, status)
      return true if status >= 100 && status < 200

      status == 204 || status == 304
    end

    # env["rack.response_finished"]に積まれたcallbackを呼ぶ。1つが投げても
    # 残りは呼ぶ(Rack SPEC)。
    def self.run_response_finished(env, status, headers, error)
      callbacks = env["rack.response_finished"]
      return unless callbacks.is_a?(Array)

      callbacks.each do |callback|
        begin
          callback.call(env, status, headers, error)
        rescue StandardError => e
          $stderr.puts "picobrick: response_finished callback failed: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
