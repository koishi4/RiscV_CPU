# Batch run all testbenches in sim_1 with a simple retry on launch.
set tbs {
    tb_rv32i_basic
    tb_trap_smoke
    tb_lw_sw_stall
    tb_addi_dual
    tb_demo_muldiv
    muldiv_tb
    dma_tb
    mmio_decode_tb
    mem_concurrency_tb
}

proc safe_close_sim {} {
    if {[catch {current_sim}]} {
        return
    }
    catch {close_sim -force}
}

proc get_xsim_dir {} {
    if {[catch {set prj_dir [get_property DIRECTORY [current_project]]}]} {
        return ""
    }
    if {[catch {set prj_name [get_property NAME [current_project]]}]} {
        return ""
    }
    return [file normalize [file join $prj_dir "${prj_name}.sim" "sim_1" "behav" "xsim"]]
}

proc clean_xsim {} {
    set xsim_dir [get_xsim_dir]
    if {$xsim_dir ne "" && [file isdirectory $xsim_dir]} {
        puts "INFO: cleaning $xsim_dir"
        if {[catch {file delete -force $xsim_dir} err]} {
            puts "WARN: clean failed for $xsim_dir: $err"
        }
    }
}

proc delete_sim_log {} {
    set xsim_dir [get_xsim_dir]
    if {$xsim_dir eq ""} {
        return
    }
    set log_path [file join $xsim_dir "simulate.log"]
    if {![file exists $log_path]} {
        return
    }
    set attempt 0
    while {$attempt < 5} {
        incr attempt
        if {![catch {file delete -force $log_path}]} {
            return
        }
        after 1000
    }
    puts "WARN: could not delete $log_path (still in use)"
}

proc run_tb {tb} {
    puts "\n===== Running $tb ====="
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sim_1

    safe_close_sim
    delete_sim_log
    after 500

    set attempt 0
    set launched 0
    while {$attempt < 2 && !$launched} {
        incr attempt
        if {$attempt == 2} {
            clean_xsim
            delete_sim_log
            after 1000
        }
        if {[catch {launch_simulation} err]} {
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
    after 1000
}

foreach tb $tbs {
    if {[catch {run_tb $tb} err]} {
        puts "ERROR: $err"
        return -code error $err
    }
}

puts "\nAll simulations completed."
