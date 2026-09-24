# picobrick: PicoRubyの開発用HTTPサーバー。既存のサーバーの互換は目指さず、
# 今必要なこと(HTTP/1.1の読み書き・keep-alive・
# 接続ごとのTaskで1本の遅い接続が他を止めないこと)だけを満たす。
# CRubyのPumaと同じく、Rackのappを動かすhandler(`Rackup::Handler::Picobrick`)と、
# Rack SPECどおりにenvを作りresponseを整える部品(`Picobrick::RackEnv`)を自分で持ち、
# picoruby-rackupの`Rackup::Handler`へ登録する(picoruby-rackupはpicobrickを知らない)。
#
MRuby::Gem::Specification.new("picobrick") do |spec|
  spec.license = "MIT"
  spec.author = "bash0C7"
  spec.summary = "picobrick: a small development HTTP server for PicoRuby"
  spec.add_dependency "picoruby-socket"   # TCPServer・TCPSocket
  spec.add_dependency "picoruby-rackup"   # Rackup::Handler.register

  # PicoRubyはmrubyのcore gemをpicoruby-mrubyの下に持つ
  mruby_gems = File.join(MRUBY_ROOT, "mrbgems", "picoruby-mruby", "lib", "mruby", "mrbgems")
  spec.add_dependency "mruby-task", gemdir: File.join(mruby_gems, "mruby-task")  # Task・sleep_ms
  spec.add_dependency "mruby-io", gemdir: File.join(mruby_gems, "mruby-io")      # $stderr
end
