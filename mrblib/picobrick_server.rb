# Picobrick::Server。acceptを1つのTaskで回し、接続ごとに処理Taskを立てる。
#
# 旧app/admin/backend/http_server.rbは1接続ずつ順に処理していたので、
# keep-aliveで接続を握るとブラウザの並行接続が飢えた(head-of-line blocking)。
# ここでは接続ごとにTaskが立ち、読み取りはpicobrick_nonblock_socket.rbで
# Taskに譲りながら待つので、1本が黙っていても他の接続は進む。
#
# picorubyのbinaryではmainのscript自体が1つのTaskで、`start`はaccept loopを
# 回すTaskの終わり(`shutdown`)を`join`で待つ。
#
# appは`call(request)`で`[status, headers, body文字列]`を返すもの。
module Picobrick
  class Server
    ACCEPT_POLL_MS = 10

    attr_reader :host, :port, :status

    def initialize(app:, host: "127.0.0.1", port: 8080, keep_alive_timeout: 5,
                   max_keep_alive_requests: 100, request_timeout: 30)
      @app = app
      @host = host
      @port = port
      @keep_alive_timeout = keep_alive_timeout
      @max_keep_alive_requests = max_keep_alive_requests
      @request_timeout = request_timeout
      @status = :stopped
      @listener = nil
    end

    def start
      # `TCPServer#addr`が無いので、portは渡された値を覚えておくだけ
      @listener = TCPServer.new(@host, @port)
      @status = :running
      server = self
      Task.new(name: "picobrick-accept") { server.accept_loop }.join
      @status = :stopped
    end

    def shutdown
      @status = :stopping
      listener = @listener
      @listener = nil
      listener.close if listener && !listener.closed?
    end

    alias stop shutdown

    def running?
      @status == :running
    end

    def accept_loop
      while running?
        listener = @listener
        break unless listener

        client = begin
          listener.accept_nonblock
        rescue StandardError => e
          break unless running?

          $stderr.puts "picobrick: accept failed: #{e.class}: #{e.message}"
          nil
        end
        if client
          spawn_connection(client)
        else
          sleep_ms ACCEPT_POLL_MS
        end
      end
    end

    def spawn_connection(client)
      server = self
      Task.new { server.serve(client) }
    end

    # 1本の接続を、keep-aliveのあいだ繰り返し処理する。1接続の異常は
    # その接続だけを閉じて終わらせ、サーバー全体は道連れにしない
    # (StandardErrorまで拾う。旧HttpServer#startと同じ境界)。
    def serve(client)
      count = 0
      while running?
        client.read_timeout_ms = (count == 0 ? @request_timeout : @keep_alive_timeout) * 1000
        request = read_request(client)
        break unless request

        client.read_timeout_ms = @request_timeout * 1000
        count += 1
        keep_alive = request.keep_alive? && count < @max_keep_alive_requests && running?
        status, headers, body = call_app(request)
        Response.write(client, status, headers, body,
                       keep_alive: keep_alive, head_only: request.method == "HEAD")
        break unless keep_alive
      end
    rescue SocketError, EOFError
      # idle timeout・相手が閉じた。keep-aliveの正常な終わり方
      nil
    rescue StandardError => e
      $stderr.puts "picobrick: dropped a connection: #{e.class}: #{e.message}"
    ensure
      client.close unless client.closed?
    end

    private

    # 読めなければnil。4xxにあたるものは返してからnil。
    def read_request(client)
      request = Request.new
      return nil unless request.parse(client)

      request
    rescue Error => e
      Response.write(client, e.status, { "content-type" => "text/plain" }, e.message.to_s)
      nil
    end

    def call_app(request)
      @app.call(request)
    rescue StandardError => e
      $stderr.puts "picobrick: app raised: #{e.class}: #{e.message}"
      [500, { "content-type" => "text/plain" }, "internal server error"]
    end
  end
end
