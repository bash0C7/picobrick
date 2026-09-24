# picobrickのresponse書き出し(mrblib/picobrick_response.rb)。
class PicobrickResponseTest < Picotest::Test
  # `write`の返り値(書けたbyte数・0・例外)を台本どおりに返すsocket。
  # 台本が尽きたら、渡されたものを全部書けたことにする。
  class ScriptedSocket
    attr_reader :written

    def initialize(script = [])
      @script = script
      @written = ""
    end

    def write(data)
      step = @script.shift
      raise "send failed" if step == :raise

      size = step.nil? ? data.bytesize : (step < data.bytesize ? step : data.bytesize)
      @written << data.byteslice(0, size)
      size
    end
  end

  def test_head_has_status_headers_length_and_connection
    head = Picobrick::Response.head(200, { "content-type" => "text/plain" }, 5, true)
    assert_equal("HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ncontent-length: 5\r\nconnection: keep-alive\r\n\r\n", head)
  end

  def test_head_drops_app_given_length_and_connection
    head = Picobrick::Response.head(404, { "Content-Length" => "999", "Connection" => "x" }, 3, false)
    assert_equal("HTTP/1.1 404 Not Found\r\ncontent-length: 3\r\nconnection: close\r\n\r\n", head)
  end

  def test_head_splits_multi_value_headers
    head = Picobrick::Response.head(200, { "set-cookie" => "a=1\nb=2" }, 0, false)
    assert(head.include?("set-cookie: a=1\r\nset-cookie: b=2\r\n"))
  end

  def test_write_sends_head_and_body
    socket = ScriptedSocket.new
    Picobrick::Response.write(socket, 200, {}, "hi", keep_alive: false)
    assert(socket.written.end_with?("\r\n\r\nhi"))
  end

  def test_head_only_skips_the_body_but_keeps_the_length
    socket = ScriptedSocket.new
    Picobrick::Response.write(socket, 200, {}, "hello", head_only: true)
    assert(socket.written.include?("content-length: 5\r\n"))
    assert(socket.written.end_with?("\r\n\r\n"))
  end

  # 実機で起きた「文字数<bytesizeのバイナリで書き込みが進まなくなる」の再発検査
  def test_binary_body_is_cut_by_bytes_and_fully_written
    body = "\xE3\x81\x82\xFF\xFEabc"
    socket = ScriptedSocket.new([2, 1, 3])
    Picobrick::Response.safe_write(socket, body)
    assert_equal(body.bytesize, socket.written.bytesize)
    assert_equal(body.bytes, socket.written.bytes)
  end

  def test_zero_writes_are_retried
    socket = ScriptedSocket.new([0, 0, 2])
    Picobrick::Response.safe_write(socket, "abcd")
    assert_equal("abcd", socket.written)
  end

  def test_a_few_write_errors_are_retried
    socket = ScriptedSocket.new([:raise, :raise])
    Picobrick::Response.safe_write(socket, "ok")
    assert_equal("ok", socket.written)
  end

  def test_persistent_write_errors_are_raised
    socket = ScriptedSocket.new([:raise] * 10)
    assert_raise(RuntimeError) { Picobrick::Response.safe_write(socket, "x") }
  end
end
