# Worker script for queue parallel test
# Usage: tclsh queue_worker.tcl writer|reader dbfile iterations id
package require sqlite3

if {$argc < 4} {
    puts "usage: queue_worker.tcl writer|reader dbfile iterations id"
    exit 2
}

set role [lindex $argv 0]
set dbfile [lindex $argv 1]
set iterations [expr {[lindex $argv 2]}]
set wid [lindex $argv 3]
set runfile "test/queue_writer_${wid}.running"
set errfile "test/queue_worker_${wid}.err"

proc safe_delete {f} {
    if {[file exists $f]} {catch {file delete -force $f} msg}
}

# Ensure no stale run/err files
safe_delete $runfile
safe_delete $errfile

# Open DB
sqlite3 db $dbfile

if {$role eq "writer"} {
    # create own runfile so readers know writers are active
    set fh [open $runfile w]
    close $fh
    for {set i 1} {$i <= $iterations} {incr i} {
        if {[catch {db eval "INSERT INTO queue(payload) VALUES('w${wid}_${i}')"} msg]} {
            puts "writer $wid error: $msg"
            set ef [open $errfile w]
            puts $ef "writer error: $msg"
            close $ef
            safe_delete $runfile
            db close
            exit 1
        }
        # small yield
        if {$i % 100 == 0} {after 1}
    }
    safe_delete $runfile
    db close
    exit 0
} elseif {$role eq "reader"} {
    while {1} {
        # Try to fetch oldest row
        set r [db eval "SELECT id FROM queue ORDER BY id LIMIT 1"]
        if {[llength $r] == 0} {
            # no rows; if no writers running, exit
            set writers [glob -nocomplain test/queue_writer_*.running]
            if {[llength $writers] == 0} {
                db close
                exit 0
            }
            # otherwise wait briefly and retry
            after 1
            continue
        }
        set rid [lindex $r 0]
        if {[catch {db eval "DELETE FROM queue WHERE id=$rid"} msg]} {
            puts "reader $wid delete error: $msg"
            set ef [open $errfile w]
            puts $ef "reader error: $msg"
            close $ef
            db close
            exit 2
        }
    }
} else {
    puts "unknown role: $role"
    db close
    exit 2
}
