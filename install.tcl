source tin.tcl
set dir [tin mkdir -force tin 0.6.1]
file copy LICENSE README.md pkgIndex.tcl tin.tcl tinlist.tcl $dir
