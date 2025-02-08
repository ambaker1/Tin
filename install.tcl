source tin.tcl
# Tin is installed in the root directory
set dir [tin mkdir -force [file dirname [info library]] Tin 2a0]
file copy LICENSE README.md pkgIndex.tcl tin.tcl $dir
