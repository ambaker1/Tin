source tin.tcl
set dir [tin mkdir -force tin 0.6.2]
file copy LICENSE README.md pkgIndex.tcl tin.tcl tinlist.tcl $dir
