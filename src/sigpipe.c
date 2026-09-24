#include <mruby.h>
#include <signal.h>

/*
 * VM起動時にSIGPIPEを無視する。
 *
 * write()の相手が既に接続を切っていると、PicoRuby(mruby engine)の
 * POSIXビルドはSIGPIPEをデフォルト動作(プロセス終了)のまま受けてしまい、
 * Rubyのrescueでは一切捕まえられない。CRuby自身も起動時にSIGPIPEを無視し、
 * write()の失敗をシグナルによる強制終了でなくEPIPEに変えている。
 * self-hostするサーバーなら必ず要るので、picobrickが持つ。
 *
 * 無視されたSIGPIPEは、write(2)のsyscallレベルで-1・errno=EPIPEを返す
 * ようになるだけ。Ruby側の見え方(picoruby-socketの`send`が投げる
 * RuntimeError)はPicobrick::Responseの書き込みで扱う。
 */
void
mrb_picobrick_gem_init(mrb_state *mrb)
{
  (void)mrb;
  signal(SIGPIPE, SIG_IGN);
}

void
mrb_picobrick_gem_final(mrb_state *mrb)
{
  (void)mrb;
}
