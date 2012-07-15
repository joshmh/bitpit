#!/usr/bin/expect -f
log_user 0
set tmp scratch
set pass $env(GPG_PASS)

spawn ssss-split -t 2 -n 3
expect "Enter the secret"
send "$pass\r\n"
expect eof

set file [open $tmp/splitted.dat w]
puts $file $expect_out(buffer)
close $file
