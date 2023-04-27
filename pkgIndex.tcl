if {![package vsatisfies [package provide Tcl] 8.6]} {return}
package ifneeded tin 0.4.5 [list source [file join $dir tin.tcl]]
