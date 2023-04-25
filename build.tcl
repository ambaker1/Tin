################################################################################
# Package configuration
set tin_version 0.4.1; # Full version (change this)
set permit_upgrade false; # Configure auto-Tin to allow major version upgrade

################################################################################
# Build package

# Source latest version of Tin
set dir [pwd]
source pkgIndex.tcl
package require tin; # Previous version (in main directory)

# Define configuration variables
set parts [tin::VersionParts $tin_version 3]; # Returns -2 for alpha and -1 for beta
lassign $parts major minor patch
dict set config VERSION $tin_version
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
tin bake src/pkgIndex.tin build/pkgIndex.tcl $config
tin bake src/install.tin build/install.tcl $config
file copy README.md LICENSE build; # for self-install test

################################################################################
# Forget package and work from build folder
package forget tin
namespace delete tin
cd build

# Load the tcltest built-in package
package require tcltest
namespace import tcltest::*

# Create temporary folder for testing
set temp [file normalize lib]
set tcllib [file join $temp [file tail [info library]]]
file mkdir $tcllib
configure -tmpdir $temp
# Save existing system variables and redefine for tests
set old_tcl_library $tcl_library
set old_auto_path $auto_path
set old_HOME $env(HOME)
set tcl_library $tcllib; # redefine for testing
set auto_path [list $temp]
set env(HOME) $temp

# Create spoof user-tin file
makeFile {tin add foo 1.0 https://github.com/user/foo v1.0 install.tcl} .tinlist.tcl

# Check that installation file works
test tin::selfinstall {
    Ensures that installation file works
} -body {
    source install.tcl
    package forget tin
    namespace delete tin
    package require tin
} -result $tin_version

# clear
# reset
# save
# add
# fetch
# add
# remove
test tin::save {
    Spoofs a user tinlist file, and ensures that "save" and "reset" work right
} -body {
    tin fetch tintest
    tin remove tintest
    tin add tintest 1.0 https://github.com/ambaker1/Tin-Test v1.0 install.tcl   
    tin add tintest 2.0 https://github.com/ambaker1/Tin-Test v2.0 install.tcl
    tin remove -auto tintest
    tin remove tintest 2.0
    set tin $::tin::tin
    set auto $::tin::auto
    tin save
    tin reset
    expr {$tin eq $::tin::tin && $auto eq $::tin::auto}
} -result {1}

# Check contents of spoofed user tinlist (Difference of dictionaries)

test usertinlist {
    Checks contents of user-tin list
} -body {
    viewFile .tinlist.tcl
} -result {tin add foo 1.0 https://github.com/user/foo v1.0 install.tcl
tin add tintest 1.0 https://github.com/ambaker1/Tin-Test v1.0 install.tcl
tin remove -auto tintest}

# Reset default Tcl vars
set env(HOME) $old_HOME
set auto_path $old_auto_path
set tcl_library $old_tcl_library
lappend auto_path $temp; # For spoofed install

# Check that user-tin file works
test tin::usertin {
    Ensures that spoofed user-tin file was successful
} -body {
    tin get foo
} -result {1.0 {https://github.com/user/foo {v1.0 install.tcl}}}

# get
test tin::get-0 {
    Get the entire entry in Tin for one package
} -body {
    tin get tintest
} -result {1.0 {https://github.com/ambaker1/Tin-Test {v1.0 install.tcl}}}

test tin::get-1 {
    Get the entry in Tin for a package/version
} -body {
    tin get tintest 1.0
} -result {https://github.com/ambaker1/Tin-Test {v1.0 install.tcl}}

test tin::get-2 {
    Get the entry in Tin for a package/version/repo (tag & file)
} -body {
    tin get tintest 1.0 https://github.com/ambaker1/Tin-Test
} -result {v1.0 install.tcl}

test tin::reset {
    Ensure that reset "hard" gets rid of added tintest entry
} -body {
    tin reset -hard
    tin get tintest
} -result {}

test tin::get-auto-0 {
    Get the entire entry in Auto-Tin for one package
} -body {
    tin get -auto tintest
} -result {https://github.com/ambaker1/Tin-Test {install.tcl 0-}}

test tin::get-auto-1 {
    Get the entire entry in Auto-Tin for one package/repo
} -body {
    tin get -auto tintest https://github.com/ambaker1/Tin-Test
} -result {install.tcl 0-}

test tin::get-auto-2 {
    Get the entire entry in Auto-Tin for one package/repo/file (reqs)
} -body {
    tin get -auto tintest https://github.com/ambaker1/Tin-Test install.tcl
} -result {0-}

# remove
test tin::remove {
    Remove the "tintest" entry in Tin
} -body {
    tin remove tintest
    tin versions tintest
} -result {}

# mkdir 
test tin::mkdir {
    Test the name and version normalization features
} -body {
    set dirs ""
    lappend dirs [tin mkdir foo 1.5]
    lappend dirs [tin mkdir foo::bar 1.4]
    lappend dirs [tin mkdir foo 2.0.0]
    lmap dir $dirs {file tail $dir}
} -result {foo-1.5 foo_bar-1.4 foo-2.0}
file delete -force {*}$dirs

test tin::mkdir-versionerror {
    Throws error because version number is invalid
} -body {
    catch {tin mkdir -force $basedir foo 1.04}
} -result {1}

test tin::mkdir-nameerror {
    Throws error because package name is invalid
} -body {
    catch {tin mkdir -force $basedir foo_bar 1.5}
} -result {1}

# bake 
test tin::bake {
    Verify the text replacement of tin::bake
} -body {
    set doughFile [makeFile {Hello @WHO@!} dough.txt]
    set breadFile [makeFile {} bread.txt]
    tin bake $doughFile $breadFile {WHO World}
    viewFile $breadFile
} -result {Hello World!}

# fetch
# add
# versions
test tin::versions {
    Verifies the versions in tintest
} -body {
    tin fetch tintest
    set versions [tin versions tintest]
} -result {0.1 0.1.1 0.2 0.3 0.3.1 0.3.2 1a0 1a1 1b0 1.0}

# packages 
test tin::packages {
    Verifies that tintest was added to the Tin
} -body {
    expr {"tintest" in [tin packages]}
} -result {1}

# uninstall (all)
test tin::uninstall-prep {
    Uninstall all versions of tintest prior to tests
} -body {
    tin uninstall tintest
    tin installed tintest
} -result {}

# install
test tin::install {
    Tries to install tintest on computer
} -body {
    set versions ""
    lappend versions [tin install tintest 0]
    lappend versions [tin install tintest -exact 0.3]
    lappend versions [tin install tintest -exact 0.3.1]
    lappend versions [tin install tintest 1a0]
    lappend versions [tin install tintest -exact 1a0]
    lappend versions [tin install tintest 1a0-1b10]
    set versions
} -result {0.3.2 0.3 0.3.1 1.0 1a0 1b0}

# installed
test tin::installed {
    Use the "installed" command to check installed version number
} -body {
    set versions ""
    lappend versions [tin installed tintest 0]
    lappend versions [tin installed tintest -exact 0.3]
    lappend versions [tin installed tintest -exact 0.3.1]
    lappend versions [tin installed tintest 1a0]
    lappend versions [tin installed tintest -exact 1a0]
    lappend versions [tin installed tintest 1a0-1b10]
    set versions
} -result {0.3.2 0.3 0.3.1 1.0 1a0 1b0}

# uninstall
test tin::uninstall-0 {
    Versions installed after uninstalling versions with major number 0
} -body {
    tin uninstall tintest 0.3.1
    lsort -command {package vcompare} [package versions tintest]
} -result {0.3 1a0 1b0 1.0}

test tin::uninstall-exact {
    Uninstall exactly one package
} -body {
    tin uninstall tintest -exact 1.0
    lsort -command {package vcompare} [package versions tintest]
} -result {0.3 1a0 1b0}

# upgrade (and "package prefer") test
test tin::upgrade {
    Upgrades latest major version 1 package and uninstalls the one it upgraded
} -body {
    package prefer latest
    tin upgrade tintest
    package prefer stable
    lsort -command {package vcompare} [package versions tintest]
} -result {0.3 1a0 1.0}

# more uninstall tests
test tin::uninstall-1 {
    Versions installed after uninstalling versions with major number 1
} -body {
    tin uninstall tintest 1
    lsort -command {package vcompare} [package versions tintest]
} -result {0.3}

test tin::uninstall-all {
    Uninstall a package that is not installed (does not complain)
} -body {
    tin uninstall tintest
} -result {}

# remove
test tin::remove {
    Get tin versions for tintest after removing alpha versions
} -body {
    tin remove tintest 1a0
    tin remove tintest 1a1
    tin versions tintest
} -result {0.1 0.1.1 0.2 0.3 0.3.1 0.3.2 1b0 1.0}

# import
# require
# depend

test tin::import-0 {
    Installs tintest, after requiring and depending the exact version
} -body {
    tin import tintest -exact 0.1.1 as tt
    lsort [info commands tt::*]
} -result {::tt::bar ::tt::foo}

test tin::import-1 {
    Installs tintest, after requiring and depending the exact version
} -body {
    namespace delete tintest
    package forget tintest
    tin import -force tintest 1.0 as tt
    lsort [info commands tt::*]
} -result {::tt::bar ::tt::bar_foo ::tt::boo ::tt::far ::tt::foo ::tt::foo_bar}

# depend
test tin::depend {
    Ensure that tin depend does not install when package is installed
} -body {
    set i 0
    trace add execution ::tin::install enter {apply {args {global i; incr i}}}
    tin depend tintest 0.3; # installs 0.3.2
    tin depend tintest 0.3
    tin depend tintest 0.3
    tin depend tintest 0.3
    tin depend tintest 0.3
    tin depend tintest 0.3
    set i
} -result {1}

test tin::require {
    Ensure that tin require loads package (and does not install)
} -body {
    namespace delete tintest
    package forget tintest
    set version [tin require tintest 0.3]; # Should be 0.3.2
    list $i $version [lsort [info commands tintest::*]]
} -result {1 0.3.2 {::tintest::bar ::tintest::foo ::tintest::foobar}}

# Check number of failed tests
set nFailed $tcltest::numTests(Failed)

# Clean up
file delete -force $temp
cleanupTests

# If tests failed, return error
if {$nFailed > 0} {
    error "$nFailed tests failed"
}

################################################################################
# Tests passed, copy build files to main folder, and update doc version
file delete README.md LICENSE; # don't bother overwriting in main folder
file copy -force {*}[glob *] ..; # Copy all files in build-folder to main folder
cd ..; # return to main folder
puts [open doc/template/version.tex w] "\\newcommand{\\version}{$tin_version}"
package forget tin
namespace delete tin
source install.tcl; # Install Tin in main library

# Generate TinList table for LaTeX
tin reset -hard
set fid [open doc/template/TinList.tex w]

if {[llength [tin packages]] > 0} {
puts $fid {\subsubsection{Tin Packages}}
puts $fid {begin{tabular}{lllll}
\toprule
Package & Version & Repo & Tag & File \\
\midrule}
dict for {name data} $::tin::tin {
    dict for {version data} $data {
        dict for {repo data} $data {
            lassign $data tag file
            puts $fid "$name & $version & \\url{$repo} & $tag & $file \\\\"
        }
    }
}
puts $fid {\bottomrule
\end{tabular}}
}

if {[llength [tin packages -auto]] > 0} {
puts $fid {\subsubsection{Auto-Tin Packages}}
puts $fid {\begin{tabular}{llll}
Package & Repo & File & Version Requirements \\
\midrule}
dict for {name data} $::tin::auto {
    dict for {repo data} $data {
        dict for {file reqs} $data {
            puts $fid "$name & \\url{$repo} & $file & $reqs \\\\"
        }
    }
}
puts $fid {\bottomrule
\end{tabular}}
}