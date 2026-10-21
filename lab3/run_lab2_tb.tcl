# run_lab2_tb.tcl - run the course's Lab 2 testbench (src/hdl/mat_mul_tb.v, 64x64) on
# src/hdl/mat_mul.v WITHOUT a project. Expect: "HW/SW result match!"
#   source {<path to lab3 folder>/run_lab2_tb.tcl}
set old_dir [pwd]
set here [file dirname [file normalize [info script]]]
file mkdir $here/lab2_run
cd $here/lab2_run
file delete -force xsim.dir xvlog.log xelab.log xsim.log
catch {exec xvlog ../../src/hdl/mat_mul.v ../../src/hdl/mat_mul_tb.v 2>@1} r1
catch {exec xelab mat_mul_tb -s lab2_sim 2>@1} r2
catch {exec xsim lab2_sim -R 2>@1} r3
puts "===== Lab 2 testbench output ====="
foreach l [split $r3 "\n"] { if {[regexp {match|mismatch|stop|finish|ERROR|Error} $l]} { puts $l } }
cd $old_dir
