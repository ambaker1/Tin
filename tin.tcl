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
    variable tin ""; # Installation info for packages and versions
    variable tinlib [file dirname [info library]]; # Default base directory
    
    # Exported commands (ensemble with "tin")
    namespace export add remove; # Manipulate tin dictionary
    namespace export packages versions; # Query tin dictionary
    namespace export install library mkdir depend; # Install packages
    namespace export require import; # Load packages
    namespace ensemble create
}

# tin add --
#
# Add repository to tin
#
# Arguments:
# name          Package name
# version       Package version
# repo          Github repository URL
# tag           Github release tag
# installer     Installer .tcl file (relative to repo main folder)

proc ::tin::add {name version repo tag installer} {
    variable tin
    dict set tin $name $version [list $repo $tag $installer]
    return
}

# tin remove --
#
# Remove an entry from the tin database
# 
# Arguments:
# name          Package name
# version       Package version
# args          Additional versions to remove

proc ::tin::remove {name version args} {
    variable tin
    dict unset tin $name $version
    if {[llength $args] > 0} {
        tailcall remove $name {*}$args
    }
    return
}

# tin packages --
#
# Get list of available tin packages, using glob pattern
# 
# Arguments:
# pattern           "glob" pattern

proc ::tin::packages {{pattern *}} {
    variable tin
    dict keys $tin $pattern
}

# tin versions --
#
# Get list of available versions for tin packages satisfying requirements
#
# Arguments:
# name          Package name
# args...       Version requirements (e.g. <-exact> $version)

proc ::tin::versions {name args} {
    variable tin
    if {![dict exists $tin $name]} {
        return
    }
    # Get sorted list (ascending) of versions
    set versions [dict keys [dict get $tin $name]]
    set versions [lsort -command {package vcompare} $versions]
    if {[llength $args] == 0} {
        # All versions
        return $versions
    } else {
        # Filter for version requirements
        set reqs [PkgRequirements {*}$args]
        return [lmap version $versions {
            expr {[package vsatisfies $version {*}$reqs] ? $version : continue}
        }]
    }
}

# tin install --
#
# Install package from repository
#
# Arguments:
# package       Package name
# args...       Version requirements (e.g. <-exact> $version)

proc ::tin::install {name args} {
    variable tin
    variable oldPkgUnknown
    if {![dict exists $tin $name]} {
        return -code error "can't find $name in the tin"
    }
    # Validate package requirement inputs
    set reqs [PkgRequirements {*}$args]
    
    # Get sorted version list (decreasing) from tin
    set versions [dict keys [dict get $tin $name]]
    set versions [lsort -decreasing -command {package vcompare} $versions]
    
    # Get version that satisfies requirements
    # See documentation for Tcl "package" command
    set install_version ""; # Version to install
    foreach version $versions { 
        if {[package vsatisfies $version {*}$reqs]} {
            if {$install_version eq ""} {
                set install_version $version
            }
            if {[package prefer] eq "latest"} {
                break
            } elseif {![string match {*[ab]*} $version]} {
                # stable version found, override "latest"
                set install_version $version
                break
            }
        } elseif {$install_version ne ""} {
            break
        }
    }
    if {$install_version eq ""} {
        return -code error "can't find $name $args in the tin"
    }
    set version $install_version

    # Clone the repository into a temporary directory
    puts "installing $name $version ..."
    lassign [dict get $tin $name $version] repo tag installer
    close [file tempfile temp]
    file delete $temp
    file mkdir $temp
    catch {exec git clone --depth 1 --branch $tag $repo $temp} result options
    if {[dict get $options -errorcode] ne "NONE"} {
        return -code error $result
    }

    # Extract the package from the cloned repository, in fresh interpreter
    set home [pwd]
    cd $temp
    set child [interp create]
    if {[catch {$child eval [list source $installer]} result options]} {
        puts "error in running installer file"
        return -options $options $result
    }
    interp delete $child
    cd $home
    file delete -force $temp

    # Check for proper installation and return version 
    if {![PkgInstalled $name $reqs]} {
        puts "$name version $version installed successfully"
        return $version
    } else {
        return -code error "failed to install $name version $version"
    }
}

# PkgRequirements --
#
# Simplified processing of package version requirements. 
# Converts -exact $version to $version-$version, and no args to "0-"

proc ::tin::PkgRequirements {args} {
    # Deal with special cases
    if {[llength $args] == 0} {
        return "0-"
    }
    if {[llength $args] == 2 && [lindex $args 0] eq "-exact"} {
        set version [lindex $args 1]
        return [list $version-$version]
    }
    return $args
}

# PkgInstalled --
#
# Boolean, whether a package is installed or not
# Calls "package unknown" to load files if first pass fails.

proc ::tin::PkgInstalled {name reqs} {
    if {![PkgIndexed $name $reqs]} {
        uplevel "#0" [package unknown] [linsert $reqs 0 $name]
        return [PkgIndexed $name $reqs]
    }
    return 0
}

# PkgIndexed --
# Boolean, whether a package version satisfying requirements has been indexed

proc ::tin::PkgIndexed {name reqs} {
    foreach version [package versions $name] {
        if {[package vsatisfies $version {*}$reqs]} {
            return 1
        }
    }
    return 0
}

# tin library --
#
# Access or modify the base directory for "mkdir".
# Intended for use in installer files.

proc ::tin::library {args} {
    variable tinlib
    if {[llength $args] == 0} {
        return $tinlib
    } elseif {[llength $args] == 1} {
        return [set tinlib [file normalize [lindex $args 0]]]
    } else {
        return -code error "wrong # args: want \"tin library ?path?\""
    }
}

# tin mkdir --
#
# Helper procedure to make library folders. Returns directory name. 
# Intended for use in installer files.
#
# Arguments:
# -force        Option to clear out the library folder. 
# path          Path relative to main Tcl lib folder

proc ::tin::mkdir {args} {
    variable tinlib
    if {[llength $args] == 1} {
        set path [lindex $args 0]
    } elseif {[llength $args] == 2} {
        lassign $args option path
    } else {
        return -code error "wrong # args: want \"tin mklib ?-force? path\""
    }
    set dir [file join $tinlib $path]
    switch $option {
        -force { # Clear out folder if it exists
            file delete -force $dir
        }
        default {
            return -code error "unknown option \"$option\""
        }
    }
    file mkdir $dir
    return $dir
}

# tin depend --
#
# Requires that the package is installed.
# Tries to install if package is missing.
# Intended for use in installer files.
#
# Arguments:
# name:         Package name
# args:         Version requirements

proc ::tin::depend {name args} {
    set reqs [PkgRequirements {*}$args]
    # Try to install if the package is not present or installed
    if {![PkgInstalled $name $reqs]} {
        puts "can't find package $name $args, attempting to install ..."
        tin install $name {*}$args
    }
    return
}

# tin require --
#
# Requires that a package is present or installed, and then loads the package.
#
# Arguments:
# name:         Package name
# args:         Version requirements

proc ::tin::require {name args} {
    set reqs [PkgRequirements {*}$args]
    if {![package present $name {*}$reqs} {
        tin depend $name {*}$reqs
    }
    tailcall ::package require $name {*}$reqs
}

# tin import --
#
# Helper procedure to handle the majority of cases for importing Tcl packages
# Uses "tin require" to load the packages
# 
# tin import <-force> <$patterns from> $name <$reqs...> <as $ns>
# 
# $patterns:    Glob patterns for importing commands from package
# $name:        Package name (must have corresponding namespace)
# $reqs:        Version requirements
# $ns:          Namespace to import into. Default global namespace.
# 
# Examples
# tin import foo
# tin import -force foo
# tin import * from foo
# tin import -force bar from foo -exact 1.0 as f

proc ::tin::import {args} {
    # <-force> <$patterns from> $name <$reqs...> <as $ns>
    # Check if "force" import
    set force {}; # default
    if {[lindex $args 0] eq "-force"} {
        set args [lassign $args force]
    }
    # <$patterns from> $name <$reqs...> <as $ns>
    # Get patterns to import
    set patterns {*}; # default
    if {[lindex $args 1] eq "from"} {
        set args [lassign $args patterns from]
    }
    # $name <$reqs...> <as $ns>
    # Get namespace to import into
    set ns {}; # default
    if {[lindex $args end-1] eq "as"} {
        set ns [lindex $args end]
        set args [lrange $args 0 end-2]
    }
    # $name <$reqs...>
    # Get package name
    set args [lassign $args name]
    # <$reqs...>
    # Get package requirements
    set reqs [PkgRequirements {*}$args]
    # Require package, import commands, and return version number
    set version [uplevel 1 ::tin::require [linsert $reqs 0 $name]]
    # Add package name prefix to patterns, and import
    set patterns [lmap pattern $patterns {string cat :: $name :: $pattern}]
    namespace eval ::$ns [list namespace import {*}$force {*}$patterns]
    return $version
}

# Add repos with tinlist
source [file join [file dirname [file normalize [info script]]] tinlist.tcl]

# Finally, provide the package
package provide tin 0.3
