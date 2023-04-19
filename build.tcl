################################################################################
# Package configuration
set version 0.4a0; # Full version (change this)
set permit_upgrade false; # Configure auto-Tin to allow major version upgrade

################################################################################
# Build package

# Source latest version of Tin
set dir [pwd]
source pkgIndex.tcl
package require tin; # Previous version (in main directory)

# Define configuration variables
set parts [tin::VersionParts $version]; # Returns -2 for alpha and -1 for beta
lassign $parts major minor patch
dict set config VERSION $version
dict set config MAJOR_VERSION $major
dict set config MINOR_VERSION $minor
dict set config PATCH_VERSION $patch
# Configure upgrade settings
if {$permit_upgrade} {
    # This signals that the auto-tin settings are the same at next major version
    dict set config AUTO_TIN_REQ $major-[expr {$major+1}]
} else {
    # This permits upgrades within current major version
    dict set config AUTO_TIN_REQ $major
}

# Substitute configuration variables and create build folder
file delete -force build; # Clear build folder
tin bake src/tin.tin build/tin.tcl $config
tin bake src/tinlist.tin build/tinlist.tcl $config
file copy build/tinlist.tcl build/tinlist0.tcl
tin bake src/pkgIndex.tin build/pkgIndex.tcl $config
tin bake src/install.tin build/install.tcl $config
file copy README.md LICENSE build; # for installation testing

################################################################################
# Reload package from build folder and perform unit tests
cd build
package forget tin
namespace delete tin
source pkgIndex.tcl
package require tin
tin import tcltest

# Check Tin version
test version_check {
    Ensure that version configuration worked
} -body {
    package present tin
} -result $version

# Check existing Tin library
test tin::library1 {
    Verifies that the Tin library is correct
} -body {
    tin library
} -result [file dirname [info library]]

# Change Tin library
test tin::library2 {
    Verifies that the Tin library is correct
} -body {
    tin library [pwd]
} -result [pwd]

# Install Tin as subset of build folder
test install_file {
    Check contents of installation folder
} -body {
    source install.tcl
    llength [glob -directory [dict get $config LIBRARY] *]
} -result 5

# tin::add
test tin::add {
    Verify that version numbers get normalized by tin add
} -body {
    tin add foo 1.0 https://github.com/username/foo v1.0 install_foo.tcl
} -result {1.0.0 {https://github.com/username/foo {v1.0 install_foo.tcl}}}

# tin::auto_add
test tin::auto_add {
    Verify that -auto option works
} -body {
    
}

################################################################################
# Tests passed, copy build files to main folder, and update doc version
file copy -force {*}[glob -directory build *] [pwd]
puts [open doc/template/version.tex w] "\\newcommand{\\version}{$version}"
