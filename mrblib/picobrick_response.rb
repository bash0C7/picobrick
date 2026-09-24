# Picobrick::Response。status line・header・bodyを書き出す。
#
# 書き込みは旧app/admin/backend/http_server.rbの`safe_write`で実機確認した
# 規則を引き継ぐ:
# 1. `File.read`で読んだバイナリは、UTF-8として見たときの文字数が`bytesize`より
#    小さくなることがある。`String#[](offset, len)`は文字offsetで切るので、
#    byte数で進めながら使うと途中からnilが返り、書き込みが進まなくなる。
#    切り出しは必ず`byteslice`で行う。
# 2. 送信バッファが埋まっているだけの`write`は、例外を投げずに0を返すことが
#    ある。相手が生きている前提で、間を置いて(`MAX_WRITE_RETRIES`回まで)再試行する。
# 3. SIGPIPEを無視している(src/sigpipe.c)ので、相手が接続を切ったときの
#    `write`は`RuntimeError`を投げる。これは相手が戻ってこないので、短い
#    `MAX_WRITE_EXCEPTION_RETRIES`で諦めて投げ直す。
module Picobrick
  module Response
    CHUNK = 16_384
    MAX_WRITE_RETRIES = 2000
    MAX_WRITE_EXCEPTION_RETRIES = 5
    WRITE_RETRY_INTERVAL_MS = 10
    # 書き出し側が決めるheader。appが渡しても捨てる
    OWN_HEADERS = %w[content-length connection transfer-encoding]

    # headersの値に`\n`があれば、同じ名前のheaderを複数行に分けて書く
    # (Rack 3の複数値。set-cookie等)。
    def self.head(status, headers, body_size, keep_alive)
      text = "HTTP/1.1 #{status} #{Picobrick.reason_phrase(status)}\r\n"
      headers.each do |name, value|
        key = name.to_s.downcase
        next if OWN_HEADERS.include?(key)

        value.to_s.split("\n").each { |v| text << "#{key}: #{v}\r\n" }
      end
      text << "content-length: #{body_size}\r\n"
      text << "connection: #{keep_alive ? 'keep-alive' : 'close'}\r\n\r\n"
      text
    end

    # HEADではContent-Lengthだけ本来の長さを書き、bodyは送らない。
    def self.write(socket, status, headers, body, keep_alive: false, head_only: false)
      body = body.to_s
      safe_write(socket, head(status, headers, body.bytesize, keep_alive))
      safe_write(socket, body) unless head_only
    end

    def self.safe_write(socket, data)
      offset = 0
      offset += write_chunk(socket, data, offset) while offset < data.bytesize
    end

    def self.write_chunk(socket, data, offset)
      zero_retries = 0
      exception_retries = 0
      while true
        written = begin
          socket.write(data.byteslice(offset, CHUNK)).to_i
        rescue RuntimeError => e
          exception_retries += 1
          raise e if exception_retries > MAX_WRITE_EXCEPTION_RETRIES

          sleep_ms WRITE_RETRY_INTERVAL_MS
          nil
        end
        next unless written
        return written if written > 0

        zero_retries += 1
        if zero_retries > MAX_WRITE_RETRIES
          raise "send stalled after #{zero_retries} retries at offset #{offset}/#{data.bytesize}"
        end

        sleep_ms WRITE_RETRY_INTERVAL_MS
      end
    end
  end
end
