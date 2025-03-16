# This file builds and tests Tin
################################################################################
set tin_version 2.1.3; # Current version, updates the build files

# Build files (same code as in "tin bake")
file delete -force build; # Clear build folder
foreach inFile [glob src/*.tin] {
    set outFile [file join build [file rootname [file tail $inFile]].tcl]
    # Read from inFile
    set fid [open $inFile r]
    set data [read -nonewline $fid]
    close $fid
    # Perform substitution
    set data [string map [list @VERSION@ $tin_version] $data]
    # Write to outFile
    file mkdir [file dirname $outFile]
    set fid [open $outFile w]
    puts $fid $data
    close $fid
}

# Perform tests
cd test
source tests.tcl
cd ..

################################################################################
# Tests passed, copy build files to main folder, and update doc version
cd build
file copy -force {*}[glob *] ..; # Copy all files in build-folder to main folder
cd ..; # return to main folder
set fid [open doc/template/version.tex w]
puts $fid "\\newcommand{\\version}{$tin_version}"
close $fid
package forget tin
namespace delete tin
source install.tcl; # Install Tin in main library

# Build documentation
puts "Building documentation..."
cd doc
exec -ignorestderr pdflatex tin.tex
cd ..
