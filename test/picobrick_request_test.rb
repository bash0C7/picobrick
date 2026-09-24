# picobrickのrequest読み取り(mrblib/picobrick_request.rb)。
class PicobrickRequestTest < Picotest::Test
  # `gets`・`read`だけを持つ、台本どおりに読ませるsocket
  class FakeSocket
    def initialize(data)
      @data = data
      @pos = 0
    end

    def gets
      return nil if @pos >= @data.length

      index = @data.index("\n", @pos)
      stop = index ? index + 1 : @data.length
      line = @data[@pos, stop - @pos]
      @pos = stop
      line
    end

    def read(length)
      chunk = @data[@pos, length]
      @pos += chunk.to_s.length
      chunk
    end
  end

  def parse(text)
    request = Picobrick::Request.new
    result = request.parse(FakeSocket.new(text))
    [result, request]
  end

  def test_parse_request_line_splits_method_path_and_query
    method, target, path, query, version = Picobrick::Request.parse_request_line("GET /api/entries?x=1 HTTP/1.1\r\n")
    assert_equal("GET", method)
    assert_equal("/api/entries?x=1", target)
    assert_equal("/api/entries", path)
    assert_equal("x=1", query)
    assert_equal("HTTP/1.1", version)
  end

  def test_parse_request_line_with_no_query
    _method, _target, path, query, _version = Picobrick::Request.parse_request_line("POST /api/jobs HTTP/1.1\r\n")
    assert_equal("/api/jobs", path)
    assert_nil(query)
  end

  def test_parse_headers_lowercases_keys_and_stops_at_blank_line
    headers = Picobrick::Request.parse_headers(["Host: 127.0.0.1:8001\r\n", "X-CSRF-Token: abc\r\n", "\r\n", "Late: x\r\n"])
    assert_equal("127.0.0.1:8001", headers["host"])
    assert_equal("abc", headers["x-csrf-token"])
    assert_nil(headers["late"])
  end

  def test_parse_reads_the_body_by_content_length
    ok, request = parse("POST /p HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhelloEXTRA")
    assert(ok)
    assert_equal("POST", request.method)
    assert_equal("hello", request.body)
    assert_equal("x", request["host"])
  end

  def test_parse_returns_false_when_nothing_arrives
    ok, _request = parse("")
    assert_false(ok)
  end

  def test_short_body_is_a_bad_request
    assert_raise(Picobrick::BadRequest) { parse("POST /p HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc") }
  end

  def test_chunked_body_is_length_required
    error = nil
    begin
      parse("POST /p HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")
    rescue Picobrick::LengthRequired => e
      error = e
    end
    assert_not_nil(error)
    assert_equal(411, error.status)
  end

  def test_keep_alive_rules
    _ok, http11 = parse("GET / HTTP/1.1\r\n\r\n")
    _ok, http11_close = parse("GET / HTTP/1.1\r\nConnection: close\r\n\r\n")
    _ok, http10 = parse("GET / HTTP/1.0\r\n\r\n")
    _ok, http10_keep = parse("GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n")
    assert(http11.keep_alive?)
    assert_false(http11_close.keep_alive?)
    assert_false(http10.keep_alive?)
    assert(http10_keep.keep_alive?)
  end
end
