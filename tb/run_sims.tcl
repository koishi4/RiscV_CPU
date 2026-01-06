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

set tests [list \
    tb_ex_stage \
    tb_custom0_ex_stage \
    tb_custom0_cpu \
    tb_custom1_cpu \
    tb_hazard_fwd \
    tb_forwarding \
    tb_demo_dual_hart \
    tb_rv32i_basic \
    tb_addi_dual \
    tb_lw_sw_stall \
    tb_trap_smoke \
    tb_demo_muldiv \
    tb_demo_mem_wait \
    tb_demo_dma_irq \
    muldiv_tb \
    dma_tb \
    led_uart_mmio_tb \
    mmio_decode_tb \
    mem_concurrency_tb \
]

set failed {}

foreach tb $tests {
    puts "=== RUN $tb ==="
    if {[catch {exec xelab -debug typical -s ${tb}_sim work.$tb} msg]} {
        puts "ELAB FAIL: $msg"
        lappend failed $tb
        continue
    }
    if {[catch {exec xsim ${tb}_sim -R} msg]} {
        puts "SIM FAIL: $msg"
        lappend failed $tb
        continue
    }
}

if {[llength $failed] > 0} {
    puts "FAILED: $failed"
    exit 1
} else {
    puts "ALL PASSED"
    exit 0
}
