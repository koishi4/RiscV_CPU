# Batch run all testbenches in sim_1 with a simple retry on launch.
set tbs {
    tb_rv32i_basic
    tb_trap_smoke
    tb_lw_sw_stall
    tb_addi_dual
    muldiv_tb
    dma_tb
    mem_concurrency_tb
}

proc safe_close_sim {} {
    catch {close_sim -force}
}

proc safe_reset_run {} {
    catch {reset_run sim_1}
}

proc run_tb {tb} {
    puts "\n===== Running $tb ====="
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sim_1

    set attempt 0
    set launched 0
    while {$attempt < 2 && !$launched} {
        incr attempt
        if {$attempt == 2} {
            safe_reset_run
            set cmd {launch_simulation -clean}
        } else {
            set cmd {launch_simulation}
        }
        if {[catch $cmd err]} {
            puts "WARN: launch_simulation failed for $tb (attempt $attempt): $err"
            safe_close_sim
            after 1000
        } else {
            set launched 1
        }
    }
    if {!$launched} {
        return -code error "launch_simulation failed for $tb after retries"
    }

    if {[catch {run all} err]} {
        puts "ERROR: run failed for $tb: $err"
        safe_close_sim
        return -code error $err
    }
    safe_close_sim
}

foreach tb $tbs {
    if {[catch {run_tb $tb} err]} {
        puts "ERROR: $err"
        return -code error $err
    }
}

puts "\nAll simulations completed."
