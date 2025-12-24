# Batch run all testbenches in sim_1
set tbs {
    tb_rv32i_basic
    tb_trap_smoke
    tb_lw_sw_stall
    tb_addi_dual
    muldiv_tb
    dma_tb
    mem_concurrency_tb
}

foreach tb $tbs {
    puts "\n===== Running $tb ====="
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sim_1
    if {[catch {launch_simulation} err]} {
        puts "ERROR: launch_simulation failed for $tb: $err"
        return -code error $err
    }
    if {[catch {run all} err]} {
        puts "ERROR: run failed for $tb: $err"
        close_sim -force
        return -code error $err
    }
    close_sim -force
}

puts "\nAll simulations completed."
