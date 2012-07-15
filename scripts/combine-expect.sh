#!/usr/bin/expect -f
log_user 0

set key1 [read [open "split-keys/key1.dat" r]]
set key2 [read [open "split-keys/key2.dat" r]]

spawn ssss-combine -t 2
expect "1/2"
send $key1
expect "2/2"
send $key2
expect "Resulting secret: "
expect eof

send_user $expect_out(buffer)
