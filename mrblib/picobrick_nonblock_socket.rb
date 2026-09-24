# TCPSocket#readpartialを、mruby-taskのTaskに譲りながら待つ形にする。
#
# picoruby-socketのPOSIX buildでは`readpartial`がC実装で、データが届くまで
# OSのrecvでプロセスごと止まる。`BasicSocket#gets`・`#read`はこれを呼ぶので、
# 1本の接続がrequestを送らずに黙っているだけで、他の接続を扱うTaskまで
# 止まってしまう(旧HttpServerでkeep-aliveを撤回したhead-of-line blocking)。
#
# 実機で確かめた`read_nonblock`の性質(test/admin_vm_premise_test.rb):
# データが無ければnil、相手が閉じていればEOFError。nilのあいだは短く
# sleepしてTaskを譲る(`Task.pass`だけだと、他に動くTaskが無いときに
# CPUを空回しする)。
#
# 待ちの上限は`read_timeout_ms`(未設定ならBasicSocket::READ_TIMEOUT_MS)。
# 過ぎたらpicoruby-socketのevent queue版と同じくSocketErrorを投げ、socketは
# 閉じない(呼び出し側が閉じる)。
#
# picoruby-socketの振る舞いの差し替えだとわかるよう、このファイルは他に依存させない。
class TCPSocket
  READ_POLL_MS = 1

  attr_accessor :read_timeout_ms

  def readpartial(maxlen)
    limit = @read_timeout_ms || BasicSocket::READ_TIMEOUT_MS
    waited = 0
    while true
      data = read_nonblock(maxlen)
      return data if data

      raise SocketError, "read timeout" if waited >= limit

      sleep_ms READ_POLL_MS
      waited += READ_POLL_MS
    end
  end
end
