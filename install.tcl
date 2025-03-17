source tin.tcl
set dir [tin mkdir -force tin 2.1.4]
file copy LICENSE README.md pkgIndex.tcl tin.tcl $dir
