# run_tb.tcl - compile + run tb_top (DUT + stimulus + class tb) with Vivado's simulator
# WITHOUT a project, then build the coverage HTML report (stimulus + FSM) with xcrg.
#
# Use from the Vivado Tcl console (any folder, any project):
#   source {<path to lab3 folder>/run_tb.tcl}
#
# Notes (see README_tb_top.md):
#  - compile order: mat_mul.v, then stimulus.sv BEFORE tb_top.sv
#  - xelab is run WITHOUT --debug typical (that setting makes xelab hang on c_small)
# Output : printed in the Tcl console and saved in tb_run/xsim.log
# Report : xcrg_tb_report/functionalCoverageReport/dashboard.html
set old_dir [pwd]
set here [file dirname [file normalize [info script]]]
file mkdir $here/tb_run
cd $here/tb_run
file delete -force xvlog.log xelab.log xsim.log xsim.dir xsim.covdb ../xcrg_tb_report
catch {exec xvlog ../../src/hdl/mat_mul.v 2>@1} r0
catch {exec xvlog -sv ../stimulus.sv ../tb_top.sv 2>@1} r1
catch {exec xelab tb_top -s tb_top_sim 2>@1} r2
catch {exec xsim tb_top_sim -R 2>@1} r3
puts "===== xsim output ====="
puts $r3
catch {exec xcrg -report_format html -dir xsim.covdb -report_dir ../xcrg_tb_report 2>@1} r4
file mkdir ../xcrg_tb_report
set f [open ../xcrg_tb_report/xcrg_console.txt w]; puts $f $r4; close $f
puts "===== coverage report: [file normalize ../xcrg_tb_report/functionalCoverageReport/dashboard.html] ====="
cd $old_dir
