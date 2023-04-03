# Set up Tin directory in installation of Tcl to add user library to path
set dir [file join {*}[file dirname [info library]] tin]
file delete -force $dir
file mkdir $dir
set fid [open [file join $dir pkgIndex.tcl] w]
puts $fid {if {![package vsatisfies [package provide Tcl] 8]} {return}}
puts $fid {set user_lib [file normalize ~/Tin]}
puts $fid {if {[lsearch -exact $::auto_path $user_lib] != -1} {return}}
puts $fid {lappend ::auto_path $user_lib}
puts $fid {unset user_lib}
close $fid
file mkdir [file normalize ~/Tin]
source tin.tcl
tin extract tin
