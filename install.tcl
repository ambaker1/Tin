# Install tin in library
package forget tin
if {[namespace exists tin]} {namespace delete tin}
source tin.tcl
set dir [tin mkdir -force tin 0.4a0]
file copy tin.tcl $dir
file copy tinlist.tcl $dir
file copy pkgIndex.tcl $dir
file copy README.md $dir
file copy LICENSE $dir
