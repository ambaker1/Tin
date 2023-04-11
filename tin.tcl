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
    variable auto_tin ""; # Auto-update information for packages
    variable tinlib [file dirname [info library]]; # Default base directory
    
    # Exported commands (ensemble with "tin")
    namespace export add remove fetch; # Manipulate and Update Tin database
    namespace export packages versions repos; # Query Tin database
    namespace export install upgrade depend; # Install packages
    namespace export require import; # Package loading utilities
    namespace export library mkdir bake; # Package development utilities
    namespace ensemble create
}

# Manipulate Tin database
################################################################################

# tin add --
#
# Add information for package and version for installation.
#
# Syntax:
# tin add $name $version $repo $file $tag
# tin add $name -auto $repo $file $tag $args...
#
# Arguments:
# name          Package name
# version       Package version (-auto to pull from GitHub tags)
# repo          Github repository URL
# file          Installer .tcl file (relative to repo main folder)
# args...       User-input package version requirements (see PkgRequirements)

proc ::tin::add {name version repo file args} {
    variable tin
    variable auto_tin
    # Auto-add configuration
    if {$version eq "-auto"} {
        # The package and repo are one. Installation files are linked to reqs
        set reqs [PkgRequirements {*}$args]
        dict set auto_tin $name repo $repo
        dict set auto_tin $name reqs $file $reqs
        return
    }
    # Single tag entry
    if {[llength $args] == 1} {
        set tag [lindex $args 0]
        dict set tin $name $version $repo [list $file $tag]
    } else {
        return -code error \
                "wrong # args: want \"tin add name version repo file tag\""
    }
    return
}

# tin remove --
#
# Remove an entry from the tin database
#
# Syntax:
# tin remove $name
# tin remove $name -auto <$file>
# tin remove $name $version <$repo>
# 
# Arguments:
# name          Package name (required)
# -auto         Option to remove auto configuration
# file          Installer file for $name auto configuration (optional)
# version       Package version to remove (mutually exclusive with -auto)
# repo          Repository for $name $version

proc ::tin::remove {name args} {
    variable tin
    variable auto_tin
    # Check arity for error
    if {[llength $args] > 2} {
        if {[lindex $args 0] eq "-auto"} {
            return -code error \
                    "wrong # args: want \"tin remove name -auto ?file?\""
        }
        return -code error \
                "wrong # args: want \"tin remove name ?version? ?repo?\""
    }
    # Handle different removal cases
    if {[llength $args] == 0} {
        # tin remove $name; # Remove all data for package "$name"
        dict unset tin $name
        dict unset auto_tin $name
    } elseif {[lindex $args 0] eq "-auto"} {
        if {![dict exists $auto_tin $name]} {
            return
        }
        if {[llength $args] == 1} {
            # tin remove $name -auto; # Remove all auto-tin data
            dict unset auto_tin $name
        } else {
            # tin remove $name -auto $file; # Remove specific auto-tin data
            dict unset auto_tin $name reqs $file
        }
    } else {
        # Remove only tin data
        if {[dict exists $tin $name {*}$args]} {
            dict unset tin {*}$args
        }
    }
    return
}

# tin fetch --
#
# Fetch version numbers from a GitHub repository
# Add directly from a GitHub repository using version number releases.
# Must have prefix "v" and then the semantic versioning version number.
# Release tag regex: ^v([0-9]+(\.[0-9]+)*([ab][0-9]+(\.[0-9]+)*)?)$
#
# Arguments:
# pattern       Package name pattern (default *)

proc ::tin::fetch {{pattern *}} {
    variable auto_tin
    # Fetch version tags (using regexp), and add to Tin
    set exp {^v([0-9]+(\.[0-9]+)*([ab][0-9]+(\.[0-9]+)*)?)$}
    dict for {name data} [dict filter $auto_tin key $pattern] {
        # Define the regular expression for getting version tags
        try {
            exec git ls-remote --tags [dict get $data repo]
        } on error {errMsg options} {
            # Raise warning, but do not throw error.
            puts "warning: failed to fetch tags for $name at $repo"
            puts $errMsg
        } on ok {result} {
            # Acquired tag data. Strip excess data, and filter for regexp
            set tags [lmap {~ path} $result {file tail $path}]
            set tags [lsearch -inline -all -regexp $tags $exp]
            # Loop through tags, and add to Tin if within specified reqs
            foreach tag $tags {
                set version [string range $tag 1 end]
                dict for {file reqs} [dict get $data reqs] {
                    if {[package vsatisfies $version {*}$reqs]} {
                        tin add $name $version $repo $file $tag
                    }
                }
            }; # end foreach tag
        }; # end try
    }; # end dict for 
    return
}

# Query Tin database (not auto_tin)
################################################################################

# tin packages --
#
# Get list of available tin packages, including auto_tin, using glob pattern
# 
# Arguments:
# pattern           "glob" pattern for matching against package names

proc ::tin::packages {{pattern *}} {
    variable tin
    variable auto_tin
    concat [dict keys $tin $pattern] [dict keys $auto_tin $pattern]
}

# tin versions --
#
# Get list of available versions for tin packages satisfying requirements
#
# Arguments:
# name          Package name
# args          User-input package version requirements (see PkgRequirements)

proc ::tin::versions {name args} {
    variable tin
    if {![dict exists $tin $name]} {
        return
    }
    # Get sorted list (ascending) of versions
    set versions [dict keys [dict get $tin $name]]
    # Filter for version requirements
    if {[llength $args]} {
        set versions [FilterVersions $versions [PkgRequirements {*}$args]]
    }
    # Return sorted list
    return [lsort -command {package vcompare} $versions]
}

# tin repos --
#
# Get list of available repositories for a package version
#
# Arguments:
# name          Package name
# version       Package version

proc ::tin::repos {name version} {
    variable tin
    if {[dict exists $tin $name $version]} {
        return [dict keys [dict get $tin $name $version]]
    }
    return
}

# Installing and updating packages
################################################################################

# tin install --
#
# Install package from repository (does not check if already installed)
#
# Arguments:
# name          Package name
# args          User-input package version requirements (see PkgRequirements)

proc ::tin::install {name args} {
    variable tin
    variable auto_tin
    puts "searching in Tin database for $name $args ..."
    if {![dict exists $tin $name]} {
        return -code error "can't find $name in Tin database"
    }
    # Get version based on version selection logic
    set reqs [PkgRequirements {*}$args]
    set version [SelectVersion [dict keys [dict get $tin $name]] $reqs]
    if {$version eq ""} {
        return -code error "can't find $name $args in Tin database"
    }
    
    # Loop through repositories for selected version
    dict for {repo data} [dict get $tin $name $version] {
        lassign $data file tag
        try {
            # Try to clone the repository into a temporary directory
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

            # Install package from the cloned repository, in a fresh interpreter
            puts "installing $name $version from $repo $tag ..."
            set home [pwd]
            cd $temp
            set child [interp create]
            if {[catch {$child eval [list source $file]} result options]} {
                puts "error in running installer file"
                return -options $options $result
            }
            interp delete $child
            cd $home
            file delete -force $temp

            # Check for proper installation and return version 
            if {![PkgInstalled $name $version-$version]} {
                puts "$name version $version installed successfully"
            } else {
                return -code error "failed to install $name version $version"
            }
        } on error {errMsg options} {
            # Catch the error, and try another repository (if any)
            continue
        }
        return $version
    }
    # Re-raise the error in the "try" block
    return -options $options $errMsg
}

# tin upgrade --
#
# Upgrades existing packages within version requirements.
# Returns most upgraded package version number.
#
# Arguments:
# name          Package name
# args          User-input package version requirements (see PkgRequirements)

proc ::tin::upgrade {name args} {
    variable tin
    if {![dict exists $tin $name]} {
        return -code error "can't find $name in Tin database"
    }
    # Find version that would be selected with a "package require" statement
    set installed [PkgVersion $name [PkgRequirements {*}$args]]
    if {$installed eq ""} {
        return -code error "can't find $name $args"
    }
    # Select an available version that upgrades the installed version
    set available [dict keys [dict get $tin $name]]
    set version [SelectVersion $available $installed]
    if {$version eq "" || [package vcompare $version $installed] == 0} {
        puts "no upgrade available for $name $args"
        return $installed
    }
    puts "upgrading $name v$installed to v$version ..."
    tin install $name -exact $version
    return $version
}

# tin depend --
#
# Requires that the package is installed.
# Tries to install if package is missing, but does not load the package.
#
# Arguments:
# name          Package name
# args          User-input package version requirements (see PkgRequirements)

proc ::tin::depend {name args} {
    # Try to install if the package is not installed
    set version [PkgVersion $name [PkgRequirements {*}$args]]
    if {$version eq ""} {
        puts "can't find package $name $args, attempting to install ..."
        set version [tin install $name {*}$args]
    }
    return $version
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
    tin depend $name {*}$args
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
    # Require package, import commands, and return version number
    set version [uplevel 1 ::tin::require [linsert $args 0 $name]]
    # Add package name prefix to patterns, and import
    set patterns [lmap pattern $patterns {string cat :: $name :: $pattern}]
    namespace eval ::$ns [list namespace import {*}$force {*}$patterns]
    return $version
}


# Helper functions for writing installation scripts
################################################################################

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

# tin bake --
#
# Perform substitution on file contents and write to new files
# Allows for uppercase alphanum variable substitution (e.g. @VARIABLE@)
#
# Arguments:
# inFile        File to read (with @VARIABLE@ declarations)
# outFile       File to write to after substitution
# config        Dictionary with keys of config variable names, and values.

proc ::tin::bake {inFile outFile config} {
    # Get string map for config variable names (must be uppercase alphanum)
    set mapping ""
    dict for {key value} $config {
        if {![regexp {[A-Z0-9_]+} $key]} {
            return -code error "config variables must be uppercase alphanum"
        }
        dict set mapping "@$key@" $value
    }
    # Read from in file
    set fid [open $inFile r]
    set data [read -nonewline $fid]
    close $fid
    # Perform substitution
    set data [string map $mapping $data]
    # Write to out file
    set fid [open $outFile w]
    puts $fid $data
    close $fid
    return
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
    if {[llength $args] == 0} {
        # Any version
        set reqs "0-"
    } elseif {[llength $args] == 2 && [lindex $args 0] eq "-exact"} {
        # Exact version
        set version [lindex $args 1]
        set reqs [list $version-$version]
    } else {
        # User inputted list of reqs
        set reqs $args
    }
    return $reqs
}

# PkgIndexed --
#
# Boolean, whether a package version satisfying requirements has been indexed
#
# Arguments:
# name          Package name
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::PkgIndexed {name reqs} {
    foreach version [package versions $name] {
        if {[package vsatisfies $version {*}$reqs]} {
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
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::PkgInstalled {name reqs} {
    if {[PkgIndexed $name $reqs]} {
        return 1
    }
    # Try "package unknown" to load Tcl modules and pkgIndex.tcl files
    uplevel "#0" [package unknown] [linsert $reqs 0 $name]
    PkgIndexed $name $reqs
}

# PkgVersion --
# 
# Get installed package version satisfying requirements. Blank if none.
#
# Arguments:
# name          Package name
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::PkgVersion {name reqs} {
    if {![PkgInstalled $name $reqs]} {
        return ""
    } else {
        SelectVersion [package versions $name] $reqs
    }
}

# FilterVersions --
# 
# Get versions that satisfy requirements. Does not sort.
# If no requirements, simply returns versions.
#
# Arguments:
# versions      List of versions
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::FilterVersions {versions reqs} {
    lmap version $versions {
        expr {
            [package vsatisfies $version {*}$reqs] ? $version : [continue]
        }
    }
}

# SelectVersion --
#
# Get version of package based on requirements and "package prefer"
# Returns blank if no version is found.
#
# Arguments:
# versions      List of versions
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::SelectVersion {versions reqs} {
    # Get sorted version list satisfying requirements
    set versions [FilterVersions $versions $reqs]
    set versions [lsort -decreasing -command {package vcompare} $versions]
    # Get version that satisfies requirements
    # See documentation for Tcl "package" command
    set selected ""
    foreach version $versions {
        if {$selected eq ""} {
            set selected $version
        }
        if {[package prefer] eq "latest"} {
            break
        } elseif {![string match {*[ab]*} $version]} {
            # stable version found, override "latest"
            set selected $version
            break
        }
    }
    return $selected
}

# Add repos with tinlist
source [file join [file dirname [info script]] tinlist.tcl]

# Finally, provide the package
package provide tin 0.4.0
