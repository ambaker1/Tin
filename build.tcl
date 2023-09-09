################################################################################
# Package configuration
set tin_version 1.0.1; # Full version (change this)

################################################################################
# Build package

# Source latest version of Tin
set dir [pwd]
source pkgIndex.tcl
package require tin; # Previous version (in main directory)

# Define configuration variables
set tin_version [tin::NormalizeVersion $tin_version]
set major [lindex [split $tin_version {.ab}] 0]
set config ""
dict set config VERSION $tin_version
dict set config AUTO_TIN_REQ 0.8-

# Substitute configuration variables and create build folder
file delete -force build; # Clear build folder
tin bake src build $config; # batch bake files
file copy README.md LICENSE build; # for self-install test

################################################################################
# Forget package and work from build folder
package forget tin
namespace delete tin
cd build

# Load the tcltest built-in package
package require tcltest
namespace import tcltest::*
if {[package prefer] eq "latest"} {
    error "tests require package prefer stable"
}

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
# forget
test tin::selfinstall {
    Ensures that installation file works
} -body {
    source install.tcl
    tin forget tin
    if {[namespace exists ::tin]} {
        error
    }
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
    tin remove -tin tintest
    tin add tintest 1.0 https://github.com/ambaker1/Tin-Test v1.0 install.tcl   
    tin add tintest 2.0 https://github.com/ambaker1/Tin-Test v2.0 install.tcl
    tin remove -auto tintest
    tin remove -tin tintest 2.0
    set tin $::tin::tinTin
    set auto $::tin::autoTin
    tin save
    tin reset
    expr {$tin eq $::tin::tinTin && $auto eq $::tin::autoTin}
} -result {1}

# Check contents of spoofed user tinlist (Difference of dictionaries)

test usertinlist {
    Checks contents of user-tin list
} -body {
    viewFile .tinlist.tcl
} -result {tin add -tin foo 1.0 https://github.com/user/foo v1.0 install.tcl
tin add -tin tintest 1.0 https://github.com/ambaker1/Tin-Test v1.0 install.tcl
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
    tin remove -tin tintest
    ::tin::SortVersions [tin versions tintest]
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

# Assert command

test assert_is {
    # Ensure that assert type works
} -body {
    tin assert 5.0 is double; # Asserts that 5.0 is indeed a number
    tin assert {hello world} is integer; # This is false
} -result "expected integer value but got \"hello world\""

test assert_== {
    # Ensure that math assert works
} -body {
    tin assert {2 + 2 == 4}; # Asserts that math works
    tin assert [expr {2 + 1}] == 4; # false
} -result "assert 3 == 4 failed"

test assert_noArgs {
    # Ensure that assert does not work without args
} -body {
    catch {tin assert} result
    set result
} -result "wrong # args: should be \"tin assert expr ?message?\""

test assert_1arg {
    # Ensure that assert works with only one argument
} -body {
    tin assert false
} -result {expected true value but got "false"}

test assert_2args {
    # Ensure that assert works with two args
} -body {
    tin assert false "input must be true"
} -result {input must be true
expected true value but got "false"}

test assert_too_many_args {
    # Ensure that assert does not work with too many args
} -body {
    catch {tin assert hello there hi there hey} result
    set result
} -result "wrong # args: should be \"tin assert value op expected ?message?\""

test assert_proc1 {
    # Validate input type in a proc
} -body {
    proc foo {a} {
        tin assert $a is double "\"a\" must be a number"
    }
    catch {foo bar} result
    set result
} -result {"a" must be a number
expected double value but got "bar"}

test assert_proc2 {
    # Validate input values in a proc
} -body {
    proc subtract {x y} {
        tin assert $x > $y {x must be greater than y}
        expr {$x - $y}
    }
    catch {subtract 2.0 3.0} result
    set result
} -result {x must be greater than y
assert 2.0 > 3.0 failed}

# fetch
# add
# versions
test tin::versions {
    Verifies the versions in tintest
} -body {
    tin fetch tintest
    ::tin::SortVersions [tin versions tintest]
} -result {0.1 0.1.1 0.2 0.3 0.3.1 0.3.2 1a0 1a1 1b0 1.0 1.1 1.2a0}

test tin::auto_fetch {
    Query the state of autoFetch (default)
} -body {
    tin auto 
} -result {1}

test tin::auto_fetch2 {
    Turn off auto-fetch and check if package is available
} -body { 
    tin remove -tin tintest
    tin auto off
    tin available tintest 
} -result {}

test tin::auto_fetch3 {
    Turn on auto-fetch and check if package is available
} -body { 
    tin auto on
    tin available tintest 
} -result {1.1}

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

# install/fetch
test tin::install {
    Tries to install tintest on computer
} -body {
    set versions ""
    tin remove -tin tintest; # forces a fetch when tin install is called
    lappend versions [tin install tintest 0]
    lappend versions [tin install tintest -exact 0.3]
    lappend versions [tin install tintest -exact 0.3.1]
    lappend versions [tin install tintest -exact 1a0]
    lappend versions [tin install tintest 1a0-1b10]
    lappend versions [tin install tintest 1-1]
    lappend versions [tin install tintest]
    set versions
} -result {0.3.2 0.3 0.3.1 1a0 1b0 1.0 1.1}

# installed
test tin::installed {
    Use the "installed" command to check installed version number
} -body {
    set versions ""
    lappend versions [tin installed tintest 0]
    lappend versions [tin installed tintest -exact 0.3]
    lappend versions [tin installed tintest -exact 0.3.1]
    lappend versions [tin installed tintest -exact 1a0]
    lappend versions [tin installed tintest 1a0-1b10]
    lappend versions [tin installed tintest 1-1]
    lappend versions [tin installed tintest]
    set versions
} -result {0.3.2 0.3 0.3.1 1a0 1b0 1.0 1.1}

# uninstall
test tin::uninstall-0 {
    Versions installed after uninstalling versions with major number 0
} -body {
    tin uninstall tintest 0.3.1
    ::tin::SortVersions [package versions tintest]
} -result {0.3 1a0 1b0 1.0 1.1}

test tin::uninstall {
    Uninstall exact packages
} -body {
    tin uninstall tintest -exact 1b0
    tin uninstall tintest -exact 1.0
    tin uninstall tintest -exact 1.1
    ::tin::SortVersions [package versions tintest]
} -result {0.3 1a0}

test tin::upgrade_stable {
    Upgrade to a stable version (does not upgrade to unstable version)
} -body {
    tin upgrade tintest 1a0; # Upgrades 1a0 to 1.1
    ::tin::SortVersions [package versions tintest]
} -result {0.3 1.1}


test tin::upgrade_withinmajor {
   Upgrades latest major version 1 package and uninstalls the one it upgraded
} -body {
    tin upgrade tintest 0.3; # Upgrades 0.3 to 0.3.2
    ::tin::SortVersions [package versions tintest]
} -result {0.3.2 1.1}

# upgrade an exact package version
test tin::upgrade_unstable {
    Upgrades latest major version 1 package and uninstalls the one it upgraded
} -body {
    tin install tintest -exact 1a1
    tin uninstall tintest -exact 1.1
    tin remove -tin tintest 1.1
    tin remove -tin tintest 1.2a0
    tin upgrade tintest -exact 1a1; # Upgrades v1a1 to v1.0
    ::tin::SortVersions [package versions tintest]
} -result {0.3.2 1.0}

# more uninstall tests
test tin::uninstall-1 {
    Versions installed after uninstalling versions with major number 1
} -body {
    tin uninstall tintest 1
    ::tin::SortVersions [package versions tintest]
} -result {0.3.2}

test tin::uninstall-all {
    Uninstall a package that is not installed (does not complain)
} -body {
    tin uninstall tintest
} -result {}

# remove
test tin::remove {
    Get tin versions for tintest after removing alpha versions
} -body {
    tin fetch
    tin remove -tin tintest 1a0
    tin remove -tin tintest 1a1
    tin remove -tin tintest 1.2a0
    ::tin::SortVersions [tin versions tintest]
} -result {0.1 0.1.1 0.2 0.3 0.3.1 0.3.2 1b0 1.0 1.1}

# pkgUninstall file
test tin::install_1.1 {
    Install version with pkgUninstall.tcl file
} -body {
    tin install tintest
} -result {1.1}

test tin::uninstall_1.1 {
    Uninstall with pkgUninstall.tcl file
} -body {
    tin uninstall tintest 1.1; # deletes pkgIndex.tcl file, keeps folder
    file exists [file join [file dirname [info library]] tintest-1.1]
} -result {1}

test tin::cleanup_1.1 {
    Cleans up folder for Tin-Test, and remove from tin list
} -body {
    tin remove -tin tintest 1.1
    file delete -force [tin mkdir tintest 1.1]
    file exists [file join [file dirname [info library]] tintest-1.1]
} -result {0}

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

# upgrade to latest package test 
# NOTE: PACKAGE PREFER LATEST IS PERMANENT. IDK WHY

test tin::upgrade_latest {
    Upgrades latest major version 1 package and uninstalls the one it upgraded
} -body {
    tin uninstall tintest
    tin fetch tintest
    tin install tintest; # Installs version 1.1
    package prefer latest
    tin upgrade tintest; # Upgrades 1.1 to 1.2a0
} -result {1.1 1.2a0}

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
tin remove tintest; # dont include in documentation
set fid [open doc/template/TinList.tex w]

if {[llength [tin packages -tin]] > 0} {
puts $fid {\subsubsection{Tin Packages}}
puts $fid {begin{tabular}{lllll}
\toprule
Package & Version & Repo & Tag & File \\
\midrule}
foreach name [lsort [tin packages -tin]] {
    dict for {version data} [tin get -tin $name] {
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
Package & Repo & File & Available Versions \\
\midrule}
foreach name [lsort [tin packages -auto]] {
    dict for {repo data} [tin get -auto $name] {
        dict for {file reqs} $data {
            puts $fid "$name & \\url{$repo} & $file & $reqs \\\\"
        }
    }
}
puts $fid {\bottomrule
\end{tabular}}
}