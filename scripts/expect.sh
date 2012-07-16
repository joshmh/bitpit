#!/usr/bin/expect -f
log_user 0
set tmp /tmp/scratch
set vault $tmp/vault.dat
set pass $env(GPG_PASS)

send "Creating Electrum wallet and seed...\r\n"

spawn electrum -w $vault create
expect "Password"
send "\r"
expect "server"
send "\r"
expect "port"
send "\r"
expect "protocol"
send "\r"
expect "fee"
send "\r"
expect "gap"
send "\r"
expect eof

spawn electrum -w $vault deseed
expect "Are you sure"
send "y\r"
expect eof

send_user "Done.\r\n"

send_user "\r\nEncrypting seed with gpg...\r\n"
spawn gpg -ca --no-use-agent $tmp/vault.dat.seed
expect "Enter passphrase"
send "$pass\r"
expect "Repeat passphrase"
send "$pass\r"
expect eof
send_user "Done.\r\n"