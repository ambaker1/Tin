if {![package vsatisfies [package provide Tcl] 8.6-]} {return}
package ifneeded tin 2.1.4 [list source [file join $dir tin.tcl]]
