# tin.tcl
################################################################################
# Tcl package manager.
# https://github.com/ambaker1/Tin

# Copyright (C) 2023 Alex Baker, ambaker1@mtu.edu
# All rights reserved. 

# See the file "LICENSE" in the top level directory for information on usage, 
# redistribution, and for a DISCLAIMER OF ALL WARRANTIES.
################################################################################

namespace eval ::tin {
    # Internal variables
    variable provided_package; # Package name provided by "tin provide"
    variable provided_version; # Package version provided by "tin provide"
    variable tin; # Dictionary of packages and repositories
    
    # Get tin from file
    set dir [file dirname [file normalize [info script]]]
    set fid [open [file join $dir tin.txt] r]
    set tin [dict create {*}[read $fid]]
    close $fid
    unset fid dir
    
    # Exported commands (ensemble with "tin")
    namespace export add packages install extract provide depend require import
    namespace ensemble create
}

# tin add --
#
# Add repository to tin
#
# Arguments:
# package:      Package name
# repo:         Github repository URL

proc ::tin::add {package repo} {
    variable tin
    dict set tin $package $repo
    return
}

# tin packages --
#
# Get list of available tin packages

proc ::tin::packages {} {
    variable tin
    dict keys $tin
}

# tin install --
#
# Install package from repository
#
# Arguments:
# package               Package name
# requirement...        version requirements

proc ::tin::install {package args} {
    variable tin
    if {![dict exists $tin $package]} {
        return -code error "package $package not found in the tin"
    }
    # Get list of tags from GitHub
    set repo [dict get $tin $package]
    puts "attempting to access $repo to install $package $args ..."
    if {[catch {exec git ls-remote --tags $repo} result]} {
        return -code error $result
    }
    # Get version list from git result
    set tags [lmap {~ path} $result {file tail $path}]
    # Filter for version numbers only
    set exp {^v([0-9]+(\.[0-9]+)*([ab][0-9]+(\.[0-9]+)*)?)$}
    set tags [lsearch -inline -all -regexp $tags $exp]
    # Get version numbers and sort in decreasing order
    set versions [lmap tag $tags {string range $tag 1 end}]
    set versions [lsort -decreasing -command {package vcompare} $versions]
    if {[llength $versions] == 0} {
        return -code error "no version release tags found in $repo"
    }
    
    # Get release tag that satisfies version requirements
    if {[llength $args] == 0} {
        if {[package prefer] eq "latest"} {
            # Get latest version, regardless of stability
            set version [lindex $versions 0]
        } else {
            # Get latest stable version
            foreach version $versions {
                if {[string match {*[ab]*} $version]} {
                    continue
                }
                break
            }
        }
    } else {
        # Find latest tag that satisfies version requirement
        set n [llength $versions]
        for {set i 0} {$i < $n} {incr i} {
            set version [lindex $versions $i]
            if {[package vsatisfies $version {*}$args]} {
                break
            }
        }
        if {$i == $n} {
            return -code error "required version not found"
        }
    }
    set tag [string cat v $version]
    
    # Clone the repository into a temporary directory
    puts "installing $package $version ..."
    close [file tempfile temp]
    file delete $temp
    file mkdir $temp
    catch {exec git clone --depth 1 --branch $tag $repo $temp} result options
    if {[dict get $options -errorcode] ne "NONE"} {
        return -code error $result
    }

    # Extract the package from the cloned repository (must be exact version)
    tin extract $package $temp $version-$version
    puts "$package $version installed successfully"
    
    return $version
}

# tin extract --
#
# Extract package from local directory
#
# Arguments
# package:      Package name
# src:          Source directory. Default ".", or current directory
# requirement:  Version requirement. Default "0-", or any version
# args:         Additional version requirements

proc ::tin::extract {package {src .} {requirement 0-} args} {
    variable provided_package ""
    variable provided_version ""
    # Check for tinstall file
    if {![file exists [file join $src tinstall.tcl]]} {
        return -code error "tinstall.tcl file not found in $src"
    }
    # Create temp folder for installation
    close [file tempfile temp]
    file delete $temp
    file mkdir $temp
    # Run install script
    apply {{src dir} {source [file join $src tinstall.tcl]}} $src $temp
    # Check to see if tinstall.tcl script was valid
    if {$provided_package eq ""} {
        return -code error "tin provide statement missing from tinstall.tcl"
    }
    if {$provided_package ne $package} {
        return -code error "$package not found, found $provided_package instead"
    }
    if {![package vsatisfies $provided_version $requirement {*}$args]} {
        return -code error "$package does not satisfy version requirements"
    }
    # Create actual folder for library files
    set version $provided_version
    set lib [file join {*}[file dirname [info library]] $package-$version]
    file delete -force $lib
    file copy $temp $lib
    return $version
}

# tin provide --
#
# Place at the end of a tinstall.tcl file to verify package name and version
# Also forgets the package
#
# Arguments:
# package:          Package name
# version:          Version requirement (see "package require" documentation)

proc ::tin::provide {package version} {
    variable provided_package $package
    variable provided_version $version
}

# tin depend --
#
# Require that a package is available. If not installed, try installing.
#
# Arguments:
# package:          Package name
# args:             Version requirements (see "package require" documentation)

proc ::tin::depend {package {requirement 0-} args} {
    # Check if package is already loaded
    if {![catch {package present $package $requirement {*}$args}]} {
        return
    }
    # Check if the package is installed, but not loaded
    set versions [package versions $package]
    foreach version $versions {
        if {[package vsatisfies $version $requirement {*}$args]} {
            # Package is installed and meets the requirements
            return
        }
    }
    puts "$package not installed or does not satisfy version requirements"
    tin install $package $requirement {*}$args
    return
}

# tin require --
#
# Package require, but installs the package if it does not exist
#
# Arguments:
# package:          Package name
# args:             Version requirements (see "package require" documentation)

proc ::tin::require {package args} {
    tin depend $package {*}$args
    namespace eval :: [list package require $package {*}$args]
}

# tin import --
#
# Helper procedure to handle the majority of cases for importing Tcl packages
# Uses "tin require" to load the packages
# 
# tin import <$patterns from> $package <$requirements> <as $namespace>
# 
# $patterns:        Glob patterns for importing commands from package
# $package:         Package name (must have corresponding namespace)
# $requirements:    Version requirements
# $namespace:       Namespace to import into. Default current namespace.
# 
# Examples
# tin import foo
# tin import * from foo
# tin import bar from foo 1.0

proc ::tin::import {args} {
    # Parse arguments
    if {[llength $args] == 0 || [llength $args] > 6} {
        return -code error "wrong # of args"
    }
    # Default optional settings
    set patterns *
    set requirements ""
    set ns [uplevel 1 {namespace current}]
    # Switch for arity
    if {[llength $args] <= 2} {
        # Simplest case
        lassign $args package requirements
    } elseif {[lindex $args 1] eq "from"} {
        # User specified patterns
        lassign $args patterns from package requirements as ns
    } elseif {[lindex $args end-1] eq "as"} {
        # User specified namespace
        set package [lindex $args 0]
        set ns [lindex $args end]
        # Get optional version
        if {[llength $args] == 4} {
            set requirements [lindex $args 1]
        }
    } else {
        return -code error "incorrect input"
    }
    # Add prefixes to patterns
    set patterns [lmap pattern $patterns {string cat :: $package :: $pattern}]
    # Require package, import commands, and return version number
    set version [tin require $package {*}$requirements]
    namespace eval $ns [list namespace import {*}$patterns]
    return $version
}

# Finally, provide the package
package provide tin 0.1.3
