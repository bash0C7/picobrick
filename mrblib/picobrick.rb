# picobrick: PicoRubyの開発用HTTPサーバー。
#
# 既存のサーバーの互換は目指さない。今必要なことだけを満たす:
# - HTTP/1.1のrequest line・header・Content-Lengthのbodyを読む(chunkedは411)
# - status line・header・bodyを書く(Content-Lengthつき、keep-alive/close)
# - 接続ごとにmruby-taskのTaskを立て、1本の遅い接続が他の接続を止めない
#
# appは`call(request)`で`[status, headers, body文字列]`を返すもの。Rackのappは
# picobrick_rack_handler.rbの`Rackup::Handler::Picobrick`を通して動かす。
#
# mrblibはファイル名順にcompileされるので、このファイルが最初に来て名前空間と
# 例外を用意し、picobrick_*.rbが続く。
module Picobrick
  VERSION = "0.1.0"

  # requestを読んでいる途中で分かった、返すべき4xx。
  class Error < StandardError
    def status
      400
    end
  end

  class BadRequest < Error
  end

  class LengthRequired < Error
    def status
      411
    end
  end

  REASONS = {
    100 => "Continue", 101 => "Switching Protocols",
    200 => "OK", 201 => "Created", 202 => "Accepted", 204 => "No Content",
    206 => "Partial Content",
    301 => "Moved Permanently", 302 => "Found", 303 => "See Other", 304 => "Not Modified",
    307 => "Temporary Redirect", 308 => "Permanent Redirect",
    400 => "Bad Request", 401 => "Unauthorized", 403 => "Forbidden", 404 => "Not Found",
    405 => "Method Not Allowed", 408 => "Request Timeout", 409 => "Conflict",
    411 => "Length Required", 413 => "Payload Too Large", 415 => "Unsupported Media Type",
    422 => "Unprocessable Content", 429 => "Too Many Requests",
    500 => "Internal Server Error", 501 => "Not Implemented", 502 => "Bad Gateway",
    503 => "Service Unavailable"
  }

  def self.reason_phrase(status)
    REASONS[status.to_i] || ""
  end
end
