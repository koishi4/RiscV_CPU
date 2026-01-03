set script_dir [file dirname [info script]]
set repo_dir [file normalize [file join $script_dir ".."]]

set incdir [file join $repo_dir "rtl"]

set rtl_dirs [list \
    [file join $repo_dir "rtl"] \
    [file join $repo_dir "rtl" "core"] \
    [file join $repo_dir "rtl" "accel"] \
    [file join $repo_dir "rtl" "periph"] \
    [file join $repo_dir "rtl" "mem"]]

set tb_dirs [list [file join $repo_dir "tb"]]

set sv_files {}
set v_files {}

foreach dir [concat $rtl_dirs $tb_dirs] {
    foreach file [glob -nocomplain -directory $dir *.sv *.v] {
        if {[file extension $file] eq ".sv"} {
            lappend sv_files $file
        } else {
            lappend v_files $file
        }
    }
}

if {[llength $sv_files] > 0} {
    puts "xvlog -sv (SystemVerilog) files: [llength $sv_files]"
    if {[catch {exec xvlog -sv -i $incdir {*}$sv_files} msg]} {
        puts $msg
        exit 1
    } else {
        if {$msg ne ""} {
            puts $msg
        }
    }
}

if {[llength $v_files] > 0} {
    puts "xvlog (Verilog) files: [llength $v_files]"
    if {[catch {exec xvlog -i $incdir {*}$v_files} msg]} {
        puts $msg
        exit 1
    } else {
        if {$msg ne ""} {
            puts $msg
        }
    }
}

set tb tb_demo_sync_mem_hazard
puts "=== RUN $tb ==="
if {[catch {exec xelab -debug typical -s ${tb}_sim work.$tb} msg]} {
    puts "ELAB FAIL: $msg"
    exit 1
}
set sim_out ""
if {[catch {set sim_out [exec xsim ${tb}_sim -R]} msg]} {
    puts "SIM FAIL: $msg"
    exit 1
}
if {[string match "*Fatal:*" $sim_out] || [string match "*FATAL:*" $sim_out]} {
    puts "SIM FAIL (fatal detected):"
    puts $sim_out
    exit 1
}

puts "ALL PASSED"
exit 0
