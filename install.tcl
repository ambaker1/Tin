source tin.tcl
set dir [tin mkdir -force tin 0.5]
file copy LICENSE README.md pkgIndex.tcl tin.tcl tinlist.tcl $dir
