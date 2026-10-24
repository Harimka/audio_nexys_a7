# Run from any directory: vivado -mode batch -source <path>/build.tcl
set probe_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $probe_dir ../..]]
set out_dir [file join $repo_dir build usb_host_probe]
# Refuse overwrite: preserve any previous diagnostic project and reports.
if {[file exists [file join $out_dir usb_host_probe.xpr]]} {
    error "Diagnostic project already exists: $out_dir. Open it or move that folder before rebuilding."
}
create_project usb_host_probe $out_dir -part xc7a100tcsg324-1
add_files [list [file join $probe_dir audio_nexys_a7.sv] \
    [file join $probe_dir ps2_probe_rx.sv] \
    [file join $repo_dir src rtl reset_sync.sv] \
    [file join $repo_dir src rtl midi_note_decoder.sv] \
    [file join $repo_dir src rtl midi_note_state.sv]]
add_files -fileset constrs_1 [file join $probe_dir probe.xdc]
set_property top audio_nexys_a7 [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed" }
open_run impl_1
report_timing_summary -file [file join $out_dir timing_summary.rpt]
report_cdc -file [file join $out_dir cdc.rpt]
report_drc -file [file join $out_dir drc.rpt]
puts "BITSTREAM: [file join $out_dir usb_host_probe.runs impl_1 audio_nexys_a7.bit]"
puts "Build complete; review reports before treating this as a validated hardware design."
