if {![package vsatisfies [package provide Tcl] 8.6]} {return}
package ifneeded tin 2.0 [list source [file join $dir tin.tcl]]

# Add the local Tin folder to the auto_path
if {[lsearch -exact $::auto_path [file join ~ TclTin]] == -1} {
    lappend ::auto_path [file join ~ TclTin]
}
