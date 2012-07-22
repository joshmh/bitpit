#!/usr/bin/expect -f
log_user 0

set timeout 120
set tmp /tmp/scratch
set vault $tmp/vault.dat
set seed_path "$vault.seed"
set pass $env(GPG_PASS)

send_user "Creating Electrum wallet and seed...\r\n"

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

set seed_file [open $seed_path r]
set seed_str [read $seed_file]

send_user "Done.\r\n\r\n"
send_user "Splitting seed...\r\n"

spawn ssss-split -t 2 -n 3
expect "Enter the secret"
send "$seed_str\r\n"
expect eof

set file [open $tmp/splitted.dat w]
puts $file $expect_out(buffer)
close $file

send_user "Done.\r\n"

send_user "\r\nEncrypting seed with gpg...\r\n"
spawn gpg -ca --no-use-agent $tmp/vault.dat.seed
expect "Enter passphrase"
send "$pass\r"
expect "Repeat passphrase"
send "$pass\r"
expect eof
send_user "Done.\r\n"