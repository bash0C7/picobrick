# Picobrick::Request。request line・header・Content-Lengthのbodyを読む。
#
# PicoRuby POSIX buildのsocketで実機確認した制約(旧app/admin/backend/http_server.rb
# から引き継ぐ):
# - `gets`は引数(読み取り上限)を渡すとTypeErrorになる。引数無しでのみ使う。
# - `Struct`が無い。`Data.define`はフィールド名`method`が`Object#method`を
#   上書きしない。属性は普通のattr_readerで持つ。
module Picobrick
  class Request
    MAX_HEADER_LINES = 100

    attr_reader :method, :target, :path, :query, :version, :headers, :body

    def initialize
      @headers = {}
      @body = ""
    end

    # request lineを読めずに相手が閉じていたらfalseを返す(keep-aliveの
    # 接続で次のrequestが来なかった場合の正常な終わり方)。
    def parse(socket)
      line = socket.gets
      return false if line.nil?

      @method, @target, @path, @query, @version = self.class.parse_request_line(line)
      raise BadRequest, "bad request line" if @method.nil? || @path.nil? || @path.empty?

      @headers = self.class.parse_headers(read_header_lines(socket))
      @body = read_body(socket)
      true
    end

    def self.parse_request_line(line)
      method, target, version = line.to_s.strip.split(" ")
      path, query = target.to_s.split("?", 2)
      [method, target, path, query, version || "HTTP/1.0"]
    end

    def self.parse_headers(lines)
      headers = {}
      lines.each do |line|
        break if line.nil? || line == "\r\n" || line == "\n"

        key, value = line.split(":", 2)
        next if value.nil?

        headers[key.strip.downcase] = value.strip
      end
      headers
    end

    def [](name)
      @headers[name.to_s.downcase]
    end

    def keep_alive?
      connection = self["connection"].to_s.downcase
      if @version == "HTTP/1.1"
        connection != "close"
      else
        connection == "keep-alive"
      end
    end

    private

    def read_header_lines(socket)
      lines = []
      while (line = socket.gets)
        break if line == "\r\n" || line == "\n"

        lines << line
        raise BadRequest, "too many header lines" if lines.size > MAX_HEADER_LINES
      end
      lines
    end

    def read_body(socket)
      if self["transfer-encoding"].to_s.downcase.include?("chunked")
        raise LengthRequired, "chunked request body is not supported"
      end

      length = self["content-length"].to_i
      return "" unless length > 0

      data = socket.read(length).to_s
      raise BadRequest, "request body ended early" if data.bytesize < length

      data
    end
  end
end
