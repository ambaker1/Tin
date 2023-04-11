source tin.tcl
dict set config LIBRARY tin0.4
dict set config VERSION 0.4.0
tin build src/tin.tin tin.tcl $config
tin build src/tinlist.tin tinlist.tcl $config
tin build src/pkgIndex.tin pkgIndex.tcl $config
tin build src/install.tin install.tcl $config
