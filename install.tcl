source tin.tcl
switch -- $::tcl_platform(os) {
    Linux {
        set uid [exec id -u]
        if {$uid == 0} {
            puts stderr "This program should not run as root user."
            exit 1
        } else {
            puts "Check auto_path for writable directory..."
            set d ""
            foreach path $auto_path {
                if {[file exists $path]} {
                    if {![file isdirectory $path]} {
                        puts stderr "$path is not a directory, exiting ..."
                        exit 1
                    }
                    if {[file writable $path]} {
                        set d $path
                        puts "$path writable, found"
                        break
                    }
                } else {
                    if {![catch {file mkdir $path}]} {
                        set d $path
                        puts "$path created"
                        break
                    }
                }
            }
            if {$d eq ""} {
                puts stderr "no writable directory found in auto_path ($auto_path)"
                puts stderr "Error: unable to install"
                puts stderr "Set TCLLIBPATH environment variable to appropriate value,"
                puts stderr "for example, TCLLIB=[file join $env(HOME) .local share tcl]"
                puts stderr "and start Tin installation again"
                exit 1
            } else {
                set dir [tin mkdir -force $d tin 2.1.2]
            }
        }
    }
    default {
        set dir [tin mkdir -force tin 2.1.2]
    }
}
file copy LICENSE README.md pkgIndex.tcl tin.tcl $dir
