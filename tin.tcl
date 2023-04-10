# tin.tcl
################################################################################
# Tcl/Git package installation manager
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
    namespace export add remove; # Manipulate Tin database
    namespace export packages versions repositories; # Query Tin database
    namespace export update install library mkdir depend; # Install packages
    namespace export require import; # Load packages
    namespace ensemble create
}

# Manipulate Tin database
################################################################################

# tin add --
#
# Add version and corresponding tag to Tin database
#
# Arguments:
# name          Package name
# version       Package version
# repo          Github repository URL
# tag           Github release tag
# installer     Installer .tcl file (relative to repo main folder)

proc ::tin::add {name version repo tag installer} {
    variable tin
    dict set tin $name $version $repo [list $tag $installer]
    return
}

# tin remove --
#
# Remove an entry from the tin database
# 
# Arguments:
# name          Package name
# version       Package version
# repo          Package repository

proc ::tin::remove {name args} {
    variable tin
    # tin remove $name
    if {[llength $args] == 0} {
        dict unset tin $name
        return
    }
    # tin remove $name $version
    if {[llength $args] == 1} {
        set version [lindex $args 0]
        if {[dict exists $tin $name]} {
            dict unset tin $name $version
        }
        return
    }
    # tin remove $name $version $repo
    if {[llength $args] == 2} {
        lassign $args version repo
        if {[dict exists $tin $name $version]} {
            dict unset tin $name $version $repo
        }
        return
    }
    return -code error "wrong # args: want \"tin remove name ?version? ?repo?\""
}

# Query Tin database
################################################################################

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
    set versions [dict keys [dict get $tin $name tags]]
    # Filter for version requirements
    if {[llength $args]} {
        set versions [FilterVersions $versions {*}[PkgRequirements {*}$args]]
    }
    # Return sorted list
    return [lsort -command {package vcompare} $versions]
}

# tin repositories --
#
# Get list of available repositories for a package version

proc ::tin::repositories {name version} {
    variable tin
    if {![dict exists $tin $name $version]} {
        return ""
    }
    dict keys [dict get $tin $name $version]
}

# Installing and updating packages
################################################################################

# tin update --
#
# Look for Tin updates

proc ::tin::update {} {
    variable tin
    if {![dict exists $tin $name]} {
        return -code error "$name not found in Tin database"
    }
    # Try to get the tags from repository
    try {
        exec git ls-remote --tags https://github.com/ambaker1/Tin v\*
    } on error {errMsg options} {
        # Re-raise the error (stripped of excess git stuff)
        return -code error $errMsg
    } on ok {result} {
        # Trim excess data (only interested in tail)
        set tags [lmap {~ path} $result {file tail $path}]
    }
    
    # Filter for version numbers only (Tin follows this tag pattern)
    set exp {^v([0-9]+(\.[0-9]+)*([ab][0-9]+(\.[0-9]+)*)?)$}
    set tags [lsearch -inline -all -regexp $tags $exp]
    
    # Add to Tin database
    foreach tag $tags {
        set version [string range $tag 1 end]
        tin add tin $version https://github.com/ambaker1/Tin $tag installer.tcl
    }
    return
}

# tin upgrade --
# 
# Upgrade Tin


# tin install --
#
# Install package from repository
#
# Arguments:
# name          Package name
# args          User-input package version requirements (see PkgRequirements)

proc ::tin::install {name args} {
    variable tin
    puts "searching in Tin database for $name $args ..."
    if {![dict exists $tin $name]} {
        return -code error "can't find $name in Tin database"
    }
    # Get version based on version selection logic
    set reqs [PkgRequirements {*}$args]
    set version [SelectVersion [dict keys [dict get $tin $name]] {*}$reqs]
    if {$version eq ""} {
        return -code error "can't find $name $args in Tin database"
    }
    puts "found $name $version in Tin database"
    
    # Search for valid repository (allow for multiple repos)
    set ok 0; # boolean check variable
    dict for {repo data} [dict get $tin $name $version] {
        lassign $data tag installer
        puts "attempting to access $repo to install $name $version ..."
        try { 
            # Get list of tags from the repository
            exec git ls-remote --tags $repo
        } on error {errMsg options} {
            # Relay error message to screen
            puts $result
            continue
        } on ok {result} { 
            # Check if tag exists in repository
            set tags [lmap {~ path} $result {file tail $path}]
            if {$tag in $tags} {
                set ok 1
                break
            }
        }
    }
    if {!$ok} {
        return -code error "no valid repository found for $name $version"
    }
    
    # Clone the repository into a temporary directory
    puts "installing $name $version from $repo $tag ..."
    close [file tempfile temp]
    file delete $temp
    file mkdir $temp
    try {
        exec git clone --depth 1 --branch $tag $repo $temp
    } on error {result options} {
        if {[dict get $options -errorcode] ne "NONE"} {
            return -code error $result
        }
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
    if {![PkgInstalled $name {*}$reqs]} {
        puts "$name version $version installed successfully"
        return $version
    } else {
        return -code error "failed to install $name version $version"
    }
}

# Helper functions for writing installation scripts
################################################################################

# tin depend --
#
# Requires that the package is installed.
# Tries to install if package is missing, but does not load the package.
# Intended for use in installer files.
#
# Arguments:
# name          Package name
# args          User-input package version requirements (see PkgRequirements)

proc ::tin::depend {name args} {
    # Try to install if the package is not installed
    set reqs [PkgRequirements {*}$args]
    if {![PkgInstalled $name {*}$reqs]} {
        puts "can't find package $name $args, attempting to install ..."
        set version [tin install $name {*}$reqs]
    } else {
        # Return the version that would be selected
        set version [SelectVersion [package versions $name] {*}$reqs]
    }
    return $version
}

# tin library --
#
# Access or modify the base directory for "mkdir".
# Intended for use in installer files.
#
# Arguments:
# path          Optional argument, redefine tinlib. Otherwise returns existing

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

# Package loading utilities
################################################################################

# tin require --
#
# Same as "package require", but will try to install if needed.
#
# Arguments:
# name          Package name
# args          User-input package version requirements (see PkgRequirements)

proc ::tin::require {name args} {
    set reqs [PkgRequirements {*}$args]
    # Return if package is present (this includes dynamically loaded packages)
    if {![catch {package present $name {*}$reqs} version]} {
        return $version
    }
    # Depend on package being installed, and call "package require"
    tin depend $name {*}$reqs
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
# $reqs:        User-input package version requirements (see PkgRequirements)
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

# Private functions (internal API)
################################################################################

# PkgRequirements --
#
# Converts user input to be compatible with "package vsatisfies"
# See https://www.tcl.tk/man/tcl8.6/TclCmd/package.html#M15
#
# Syntax:
# PkgRequirements <<-exact> $version> <$req1 $req2 ...>
#
# Arguments:
# -exact            Option to install exact version. 
# $version          Package version. 
# $req1 $req2 ...   Version requirements, mutually exclusive with -exact option.
#
# Examples:
# PkgRequirements                   -> "0-" (default)
# PkgRequirements 1.2               -> "1.2"
# PkgRequirements -exact 1.2        -> "1.2-1.2"
# PkgRequirements 1.2 -1.5          -> "1.2 -1.5"

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

# PkgIndexed --
# Boolean, whether a package version satisfying requirements has been indexed
#
# Arguments:
# name          Package name
# args          Version requirements compatible with "package vsatisfies"

proc ::tin::PkgIndexed {name args} {
    foreach version [package versions $name] {
        if {[package vsatisfies $version {*}$args]} {
            return 1
        }
    }
    return 0
}

# PkgInstalled --
#
# Boolean, whether a package is installed or not
# Calls original "package unknown" to load files if first pass fails.
#
# Arguments:
# name          Package name
# args          Version requirements compatible with "package vsatisfies"

proc ::tin::PkgInstalled {name args} {
    if {![PkgIndexed $name {*}$args]} {
        uplevel "#0" [package unknown] [linsert {*}$args 0 $name]
        return [PkgIndexed $name {*}$args]
    }
    return 0
}

# FilterVersions --
# 
# Get versions that satisfy requirements. Does not sort.
# If no requirements, simply returns versions.
#
# Arguments:
# versions      List of versions
# args          Version requirements compatible with "package vsatisfies"

proc ::tin::FilterVersions {versions args} {
    if {[llength $args]} {
        set versions [lmap version $versions {
            expr {
                [package vsatisfies $version {*}$args] ? $version : [continue]
            }
        }]
    }
    return $versions
}

# SelectVersion --
#
# Get version of package based on requirements and "package prefer"
# Returns blank if no version is found.
#
# Arguments:
# versions      List of versions
# args          Version requirements compatible with "package vsatisfies"

proc ::tin::SelectVersion {versions args} {
    # Get sorted version list satisfying requirements
    set versions [FilterVersions $versions {*}$args]
    set versions [lsort -decreasing -command {package vcompare} $versions]
    # Get version that satisfies requirements
    # See documentation for Tcl "package" command
    set result ""
    foreach version $versions {
        if {$result eq ""} {
            set result $version
        }
        if {[package prefer] eq "latest"} {
            break
        } elseif {![string match {*[ab]*} $version]} {
            # stable version found, override "latest"
            set result $version
            break
        }
    }
    return $result
}

# Add repos with tinlist
source [file join [file dirname [info script]] tinlist.tcl]

# Finally, provide the package
package provide tin 0.4
