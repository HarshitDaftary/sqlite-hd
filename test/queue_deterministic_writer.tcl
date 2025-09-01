# Deterministic writer: begin immediate, insert, sleep, commit
# Usage: tclsh queue_deterministic_writer.tcl dbfile hold_secs
package require sqlite3

if {$argc < 2} {
    puts "usage: queue_deterministic_writer.tcl dbfile hold_secs"
    exit 2
}
set dbfile [lindex $argv 0]
set hold [lindex $argv 1]

sqlite3 db $dbfile
# Use WAL to allow concurrent readers
db eval {PRAGMA journal_mode=WAL}
# Acquire write lock
db eval {BEGIN IMMEDIATE}
# Insert and hold before commit
db eval "INSERT INTO queue(payload) VALUES('writer_hold')"
# signal running
set runfile "test/queue_det_writer.running"
set fh [open $runfile w]
puts $fh "running"
close $fh
# Sleep to hold the lock
exec sleep $hold
# Commit and finish
db eval {COMMIT}
file delete -force $runfile
db close
exit 0
