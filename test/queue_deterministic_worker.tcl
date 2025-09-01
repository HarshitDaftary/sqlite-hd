# Deterministic worker: attempt to insert immediately; report success or error
# Usage: tclsh queue_deterministic_worker.tcl dbfile
package require sqlite3

if {$argc < 1} {
    puts "usage: queue_deterministic_worker.tcl dbfile"
    exit 2
}
set dbfile [lindex $argv 0]
sqlite3 db $dbfile
# Try a single INSERT and report
if {[catch {db eval "INSERT INTO queue(payload) VALUES('worker_try')"} msg]} {
    puts "WORKER_ERROR: $msg"
    db close
    exit 1
} else {
    puts "WORKER_OK"
    db close
    exit 0
}
