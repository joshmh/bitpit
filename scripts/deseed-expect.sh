#!/usr/bin/expect -f
log_user 0

set vault_dir $env(HOME)/vault
set wallet $vault_dir/vault.dat

spawn electrum -w $wallet deseed
expect "Are you sure"
send "y\r"
expect eof
