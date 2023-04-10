package require math
trace add execution tclPkgUnknown enter {apply {{cmdString args} {puts $cmdString}}}
package require -exact foo 1.2