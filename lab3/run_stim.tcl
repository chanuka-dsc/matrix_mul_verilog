# run_stim.tcl - compile + run the stand-alone stimulus test with Vivado's simulator,
# then build the functional-coverage HTML report with xcrg.
#
# Use from the Vivado Tcl console (works from any folder, any project):
#   source {<path to this folder>/run_stim.tcl}
#
# Output : printed in the Tcl console and saved in sim_run/xsim.log
# Report : xcrg_report/functionalCoverageReport/dashboard.html
set old_dir [pwd]
set here [file dirname [file normalize [info script]]]   ;# folder of this script
file mkdir $here/sim_run
cd $here/sim_run
file delete -force xvlog.log xelab.log xsim.log xsim.dir xsim.covdb ../xcrg_report
catch {exec xvlog -sv ../stimulus.sv ../stim_test.sv 2>@1} r1
catch {exec xelab stim_test -s stim_test_sim 2>@1} r2
catch {exec xsim stim_test_sim -R 2>@1} r3
puts "===== xsim output ====="
puts $r3
# coverage database (sim_run/xsim.covdb) -> HTML report (xcrg_report/)
catch {exec xcrg -report_format html -dir xsim.covdb -report_dir ../xcrg_report 2>@1} r4
file mkdir ../xcrg_report
set f [open ../xcrg_report/xcrg_console.txt w]; puts $f $r4; close $f
puts "===== coverage report: [file normalize ../xcrg_report/functionalCoverageReport/dashboard.html] ====="
cd $old_dir
