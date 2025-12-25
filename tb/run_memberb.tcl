# Run Member B regression set in the current Vivado project.
# Usage (Vivado Tcl console): source tb/run_memberb.tcl

# Fix Windows spawn/encoding issues on non-ASCII paths.
if {[string match "Windows*" $::tcl_platform(os)]} {
    catch {encoding system utf-8}
    catch {fconfigure stdout -encoding utf-8}
    catch {fconfigure stderr -encoding utf-8}
}

set tbs {
    muldiv_tb
    dma_tb
    mem_concurrency_tb
    mmio_decode_tb
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

proc delete_sim_log {} {
    set xsim_dir [get_xsim_dir]
    if {$xsim_dir eq ""} {
        return
    }
    set log_path [file join $xsim_dir "simulate.log"]
    if {![file exists $log_path]} {
        return
    }
    if {[catch {file delete -force $log_path} err]} {
        puts "WARN: could not delete $log_path: $err"
    }
}

proc ensure_include_dir {dir} {
    set fs [get_filesets sim_1]
    set cur [get_property include_dirs $fs]
    if {$cur eq ""} {
        set cur {}
    }
    if {[lsearch -exact $cur $dir] < 0} {
        set_property include_dirs [concat $cur $dir] $fs
        puts "INFO: added include dir $dir"
    }
}

proc ensure_tb_file {pattern fallback} {
    if {[llength [get_files -quiet $pattern]] == 0} {
        if {[file exists $fallback]} {
            add_files -fileset sim_1 $fallback
            puts "INFO: added $fallback"
        } else {
            puts "WARN: missing testbench file $fallback"
        }
    }
}

ensure_include_dir [file normalize "rtl"]
ensure_tb_file "*muldiv_tb.sv" [file normalize "tb/muldiv_tb.sv"]
ensure_tb_file "*dma_tb.sv" [file normalize "tb/dma_tb.sv"]
ensure_tb_file "*mem_concurrency_tb.sv" [file normalize "tb/mem_concurrency_tb.sv"]
ensure_tb_file "*mmio_decode_tb.sv" [file normalize "tb/mmio_decode_tb.sv"]

proc run_tb {tb} {
    puts "\n===== Running $tb ====="
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sim_1

    safe_close_sim
    delete_sim_log
    after 500

    if {[catch {launch_simulation} err]} {
        puts "ERROR: launch_simulation failed for $tb: $err"
        safe_close_sim
        return -code error $err
    }

    if {[catch {run all} err]} {
        puts "ERROR: run failed for $tb: $err"
        safe_close_sim
        return -code error $err
    }
    safe_close_sim
    after 500
}

foreach tb $tbs {
    if {[catch {run_tb $tb} err]} {
        puts "ERROR: $err"
        return -code error $err
    }
}

puts "\nMember B regression completed."
