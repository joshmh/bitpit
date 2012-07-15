#!/usr/bin/expect -f
log_user 0
set pass $env(GPG_PASS)
set encrypted_seed vault/vault.dat.seed.asc

spawn gpg --no-mdc-warning --no-use-agent $encrypted_seed
expect "Enter passphrase"
send "$pass\r\n"
expect eof
