# picobrickのRack SPECのenv/response規則(mrblib/picobrick_rack_env.rb)。
class PicobrickRackEnvTest < Picotest::Test
  class ClosableBody
    attr_reader :closed

    def initialize(parts)
      @parts = parts
      @closed = false
    end

    def each
      @parts.each { |part| yield part }
    end

    def close
      @closed = true
    end
  end

  def env_for(meta = {})
    Picobrick::RackEnv.build(meta, input: Picobrick::RackEnv::Input.new(""))
  end

  def test_env_adds_rack_keys
    env = env_for("REQUEST_METHOD" => "GET", "PATH_INFO" => "/x", "QUERY_STRING" => "a=1")
    assert_equal("GET", env["REQUEST_METHOD"])
    assert_equal("/x", env["PATH_INFO"])
    assert_equal("a=1", env["QUERY_STRING"])
    assert_equal("", env["SCRIPT_NAME"])
    assert_equal("http", env["rack.url_scheme"])
    assert_equal([], env["rack.response_finished"])
    assert_not_nil(env["rack.errors"])
  end

  def test_env_fills_empty_path_and_query
    env = env_for("REQUEST_METHOD" => "GET", "PATH_INFO" => "")
    assert_equal("/", env["PATH_INFO"])
    assert_equal("", env["QUERY_STRING"])
  end

  def test_input_reads_in_parts_and_rewinds
    input = Picobrick::RackEnv::Input.new("abcdef")
    assert_equal("abc", input.read(3))
    assert_equal("def", input.read)
    assert_nil(input.read(1))
    assert_equal("", input.read)
    input.rewind
    assert_equal("abcdef", input.read)
  end

  def test_input_read_into_a_buffer
    buffer = "old"
    Picobrick::RackEnv::Input.new("new").read(3, buffer)
    assert_equal("new", buffer)
  end

  def test_input_gets_and_each
    input = Picobrick::RackEnv::Input.new("a\nb\nc")
    assert_equal("a\n", input.gets)
    lines = []
    input.each { |line| lines << line }
    assert_equal(["b\n", "c"], lines)
    assert_nil(input.gets)
  end

  def test_normalize_lowercases_headers_and_joins_body
    status, headers, body = Picobrick::RackEnv.normalize_response({ "REQUEST_METHOD" => "GET" }, 200,
                                                        { "Content-Type" => "text/plain" }, ["a", "b"])
    assert_equal(200, status)
    assert_equal("text/plain", headers["content-type"])
    assert_equal("ab", body)
  end

  def test_normalize_joins_multi_value_headers_with_newline
    _status, headers, _body = Picobrick::RackEnv.normalize_response({ "REQUEST_METHOD" => "GET" }, 200,
                                                          { "set-cookie" => ["a=1", "b=2"] }, [])
    assert_equal("a=1\nb=2", headers["set-cookie"])
  end

  # 数MBのbodyを複製しない(PicoRubyのheapではNoMemoryErrorになる)
  def test_normalize_does_not_copy_a_single_part_body
    part = "big body"
    _status, _headers, body = Picobrick::RackEnv.normalize_response({ "REQUEST_METHOD" => "GET" }, 200, {}, [part])
    assert(body.equal?(part))
  end

  def test_normalize_keeps_the_head_body_for_content_length
    _status, _headers, body = Picobrick::RackEnv.normalize_response({ "REQUEST_METHOD" => "HEAD" }, 200, {}, ["abc"])
    assert_equal("abc", body)
  end

  def test_normalize_drops_body_for_204_and_304
    assert_equal("", Picobrick::RackEnv.normalize_response({ "REQUEST_METHOD" => "GET" }, 204, {}, ["x"])[2])
    assert_equal("", Picobrick::RackEnv.normalize_response({ "REQUEST_METHOD" => "GET" }, 304, {}, ["x"])[2])
  end

  def test_normalize_closes_the_body
    body = ClosableBody.new(["a"])
    Picobrick::RackEnv.normalize_response({ "REQUEST_METHOD" => "GET" }, 200, {}, body)
    assert(body.closed)
  end

  def test_response_finished_callbacks_all_run_even_if_one_raises
    calls = []
    env = env_for("REQUEST_METHOD" => "GET")
    env["rack.response_finished"] << ->(_e, _s, _h, _err) { raise "boom" }
    env["rack.response_finished"] << ->(_e, status, _h, _err) { calls << status }
    Picobrick::RackEnv.run_response_finished(env, 200, {}, nil)
    assert_equal([200], calls)
  end
end
