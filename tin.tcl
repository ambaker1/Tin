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
    # Tin and Auto-Tin database dictionary variables
    variable tin ""; # Installation info for packages and versions
    variable auto ""; # Auto-update information for packages
    # Define files for loading Tin: Tin comes prepackaged with a tinlist.tcl 
    # file, but the user can save their own added entries with "tin save".
    variable myLocation [file dirname [file normalize [info script]]]
    variable tinlistFile [file join $myLocation tinlist.tcl]
    variable userTinlistFile [file normalize [file join ~ .tinlist.tcl]]
    # Define the regular expression for getting version tags from GitHub.
    # The pattern is compatible with the package version rules for Tcl, and 
    # additionally does not permit leading zeros, as per semver rules.
    # Digit pattern for no leading zeros: (0|[1-9]\d*)
    # https://semver.org/
    # https://www.tcl.tk/man/tcl/TclCmd/package.html#M20
    variable tagPattern {^v(0|[1-9]\d*)(\.(0|[1-9]\d*))*([ab](0|[1-9]\d*)(\.(0|[1-9]\d*))*)?$}
    
    # Exported commands (ensemble with "tin")
    ## Modify the Tin and the Auto-Tin
    namespace export add remove fetch save clear reset
    ## Query the Tin and the Auto-Tin
    namespace export get packages versions
    ## Package installation commands
    namespace export install installed uninstall upgrade
    ## Package loading commands, with installation on the fly
    namespace export import require depend forget
    ## Package development utilities
    namespace export mkdir bake
    namespace ensemble create
}

## Modify the Tin and the Auto-Tin
################################################################################

# tin add --
#
# Add information for package and version for installation.
#
# Syntax
# tin add $name $version $repo $tag $file
# tin add -auto $name $repo $file $args...
#
# Arguments:
# name              Package name
# -auto             Option to add Auto-Tin configuration info
# version           Package version
# repo              Github repository URL
# tag               Repository tag (not with -auto option)
# file              Installer .tcl file (relative to repo main folder)
# requirement...    Auto-Tin package version requirements (see PkgRequirements)

proc ::tin::add {args} {
    variable tin
    variable auto
    if {[lindex $args 0] eq "-auto"} {
        # Add to the Auto-Tin
        set args [lrange $args 1 end]
        if {[llength $args] < 3} {
            WrongNumArgs "tin add -auto name repo file ?requirement...?" 
        }
        set reqs [PkgRequirements {*}[lassign $args name repo file]]
        ValidatePkgName $name
        dict set auto $name $repo $file $reqs
        return
    } else {
        # Add to the Tin
        if {[llength $args] != 5} {
            WrongNumArgs "tin add name version repo tag file" 
        }
        lassign $args name version repo tag file
        ValidatePkgName $name
        set version [NormalizeVersion $version]
        dict set tin $name $version $repo [list $tag $file]
        return
    }
}

# tin remove --
#
# Remove entries from the Tin. Returns blank, does not complain.
# Essentially "dict unset" for Tin and Auto-Tin dictionaries
#
# Syntax:
# tin remove $name <$version> <$repo>
# tin remove -auto $name <$repo> <$file>
# 
# Arguments:
# name          Package name (required)
# -auto         Option to remove Auto-Tin configuration info
# version       Package version in Tin
# repo          Repository in Tin or Auto-Tin associated with package
# file          Installer file in Auto-Tin for package and repo

proc ::tin::remove {args} {
    variable tin
    variable auto
    if {[lindex $args 0] eq "-auto"} {
        # Remove entries from the Auto-Tin
        set args [lrange $args 1 end]
        if {[llength $args] < 1 || [llength $args] > 3} {
            WrongNumArgs "tin remove -auto name ?repo? ?file?"
        }
        if {[dict exists $auto {*}$args]} {
            dict unset auto {*}$args
        }
    } else {
        # Remove entries from the Tin
        if {[llength $args] < 1 || [llength $args] > 3} {
            WrongNumArgs "tin remove name ?version? ?repo?"
        }
        # Normalize version input
        if {[llength $args] > 1} {
            lset args 1 [NormalizeVersion [lindex $args 1]]
        }
        if {[dict exists $tin {*}$args]} {
            dict unset tin {*}$args
        }
    }
    return
}

# tin fetch --
#
# Update the Tin from GitHub repositories listed in the Auto-Tin.
# Regex pattern for tags defined at top of file.
#
# Syntax:
# tin fetch <-all> 
# tin fetch $name
#
# Arguments:
# name          Package name. Default -all for all auto packages

proc ::tin::fetch {{name "-all"}} {
    variable auto
    variable tagPattern
    # Handle "fetch -all"
    if {$name eq "-all"} {
        foreach name [dict keys $auto] {
            uplevel 1 [list ::tin::fetch $name]
        }
        return
    }
    # Do not complain if package is not in Auto-Tin
    if {![dict exists $auto $name]} {
        return
    }
    # Loop through repositories for package
    dict for {repo subdict} [dict get $auto $name] {
        # Try to get version tags using git, and add valid ones to the Tin
        try {
            exec git ls-remote --tags $repo
        } on error {errMsg options} {
            # Raise warning, but do not throw error.
            puts "warning: failed to fetch tags for $name at $repo"
            puts $errMsg
        } on ok {result} {
            # Acquired tag data. Strip excess data, and filter for regexp
            set tags [lmap {~ path} $result {file tail $path}]
            set tags [lsearch -inline -all -regexp $tags $tagPattern]
            # Loop through tags, and add to the Tin if within specified reqs
            foreach tag $tags {
                set version [string range $tag 1 end]
                dict for {file reqs} $subdict {
                    if {[package vsatisfies $version {*}$reqs]} {
                        tin add $name $version $repo $tag $file
                    }
                }
            }; # end foreach tag
        }; # end try
    }; # end dict for 
    return
}

# tin save --
#
# Saves the Tin and Auto-Tin to the user tinlist file
#
# Syntax:
# tin save

proc ::tin::save {} {
    variable tin
    variable auto
    variable tinlistFile
    variable userTinlistFile
    
    # Save current Tin and Auto-Tin, and reset to factory settings
    set tin_save $tin
    set auto_save $auto
    tin reset -hard; # Resets to factory settings
    
    # Open a temporary file for writing "tin add" commands to.
    set fid [file tempfile tempfile]
    # Write "tin add" commands for entries in the Tin
    dict for {name data} $tin_save {
        dict for {version data} $data {
            dict for {repo data} $data {
                if {![dict exist $tin $name $version $repo]} {
                    lassign $data tag file
                    puts $fid [list tin add $name $version $repo $tag $file]
                }
            }
        }
    }
    # Write "tin add" commands for entries in the Auto-Tin
    dict for {name data} $auto_save {
        dict for {repo data} $data {
            dict for {file reqs} $data {
                if {![dict exist $auto $name $repo $file]} {
                    puts $fid [list tin add -auto $name $repo $file {*}$reqs]
                }
            }
        }
    }
    # Write "tin remove" commands for entries in Tin.
    dict for {name data} $tin {
        if {![dict exists $tin_save $name]} {
            puts $fid [list tin remove $name]
            continue
        }
        dict for {version data} $tin {
            if {![dict exists $tin_save $name $version]} {
                puts $fid [list tin remove $name $version]
                continue
            }
            dict for {repo data} $data {
                if {![dict exists $tin_save $name $version $repo]} {
                    puts $fid [list tin remove $name $version $repo]
                }
            }
        }
    }
    # Write "tin remove" commands for entries in Auto-Tin.
    dict for {name data} $auto {
        if {![dict exists $auto_save $name]} {
            puts $fid [list tin remove -auto $name]
            continue
        }
        dict for {repo data} $tin {
            if {![dict exists $auto_save $name $repo]} {
                puts $fid [list tin remove -auto $name $repo]
                continue
            }
            dict for {file reqs} $data {
                if {![dict exists $auto_save $name $repo $file]} {
                    puts $fid [list tin remove -auto $name $repo $file]
                }
            }
        }
    }
    # Copy the temp file over to the tin file.
    close $fid
    file copy -force $tempfile $userTinlistFile
    file delete -force $tempfile
    return
}

# tin clear --
#
# Clears the Tin. 
#
# Syntax:
# tin clear

proc ::tin::clear {} {
    variable tin
    variable auto
    set tin ""
    set auto ""
    return
}

# tin reset --
#
# Resets Tin and Auto-Tin to factory and user settings
#
# Syntax:
# tin reset <-hard>
#
# Arguments:
# -hard         Option to only reset factory settings

proc ::tin::reset {{option ""}} {
    variable tinlistFile
    variable userTinlistFile
    tin clear
    source $tinlistFile
    if {$option ne "-hard" && [file exists $userTinlistFile]} {
        source $userTinlistFile
    }
    return
}

## Query the Tin and the Auto-Tin
################################################################################

# tin get --
#
# Get raw information from the Tin or Auto-Tin. Returns blank if no info.
# Equivalent to "dict get" for Tin and Auto-Tin dictionaries, with the exception
# that it will not throw an error if the entry does not exist.
#
# Syntax:
# tin get $name <$version> <$repo>
# tin get -auto $name <$repo> <$file>
#
# Arguments:
# name          Package name (required)
# -auto         Option to get Auto-Tin configuration info
# version       Package version in Tin
# repo          Repository in Tin or Auto-Tin associated with package
# file          Installer file in Auto-Tin for package and repo

proc ::tin::get {args} {
    variable tin
    variable auto
    if {[lindex $args 0] eq "-auto"} {
        # Get info from the Auto-Tin
        set args [lrange $args 1 end]
        if {[llength $args] < 1 || [llength $args] > 3} {
            WrongNumArgs "tin get -auto name ?repo? ?file?"
        }
        if {[dict exists $auto {*}$args]} {
            return [dict get $auto {*}$args]
        }
    } else {
        # Get info from the Tin
        if {[llength $args] < 1 || [llength $args] > 3} {
            WrongNumArgs "tin get name ?version? ?repo?"
        }
        # Normalize version input
        if {[llength $args] > 1} {
            lset args 1 [NormalizeVersion [lindex $args 1]]
        }
        if {[dict exists $tin {*}$args]} {
            return [dict get $tin {*}$args]
        }
    }
    return
}

# tin packages --
#
# Get list of packages in the Tin or Auto-Tin, with optional "glob" pattern
#
# Syntax:
# tin packages <-auto> <$pattern>
# 
# Arguments:
# pattern           "glob" pattern for matching against package names

proc ::tin::packages {args} {
    variable tin
    variable auto
    if {[lindex $args 0] eq "-auto"} {
        # Packages in the Auto-Tin
        set args [lrange $args 1 end]
        if {[llength $args] == 0} {
            return [dict keys $auto]
        } elseif {[llength $args] == 1} {
            set pattern [lindex $args 0]
            return [dict keys $auto $pattern]
        }
    } else {
        # Packages in the Tin
        if {[llength $args] == 0} {
            return [dict keys $tin]
        } elseif {[llength $args] == 1} {
            set pattern [lindex $args 0]
            return [dict keys $tin $pattern]
        }
    }
    # All other paths return, throw syntax error.
    WrongNumArgs "tin packages ?-auto? ?pattern?"
}

# tin versions --
#
# Get list of available versions for tin packages satisfying requirements
#
# Syntax:
# tin versions $name <$reqs...> 
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

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

## Package installation commands
################################################################################

# tin install --
#
# Install package from repository (does not check if already installed)
#
# Syntax:
# tin install $name <$reqs...> 
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::install {name args} {
    variable tin
    puts "searching in the Tin for $name $args ..."
    if {![dict exists $tin $name]} {
        return -code error "can't find $name in the Tin"
    }
    # Get version based on version selection logic
    set reqs [PkgRequirements {*}$args]
    set version [SelectVersion [dict keys [dict get $tin $name]] $reqs]
    if {$version eq ""} {
        return -code error "can't find $name $args in the Tin"
    }
    
    # Now we know that there is a entry in the Tin for package "$name $version"
    # The dict for loop will execute, and so will the try block.
    
    # Loop through repositories for selected version 
    dict for {repo data} [dict get $tin $name $version] {
        lassign $data tag file
        try {
            # Try to clone the repository into a temporary directory
            close [file tempfile temp]
            file delete $temp
            file mkdir $temp
            try {
                exec git clone --depth 1 --branch $tag $repo $temp
            } on error {result options} {
                # Clean up and pass error if failed
                if {[dict get $options -errorcode] ne "NONE"} {
                    file delete -force $temp
                    return -code error $result
                }
            }

            # Install package from the cloned repository, in a fresh interpreter
            puts "installing $name $version from $repo $tag ..."
            set home [pwd]
            cd $temp
            set child [interp create]
            try {
                $child eval [list source $file]
            } on error {errMsg options} {
                puts "error in running installer file"
                return -options $options $errMsg
            } finally {
                # Clean up
                interp delete $child
                cd $home
                file delete -force $temp
            }

            # Check for proper installation and return version 
            if {[IsInstalled $name $version-$version]} {
                puts "$name version $version installed successfully"
            } else {
                return -code error "failed to install $name version $version"
            }
        } on error {errMsg options} {
            # Catch the error, and try another repository (if any)
            continue
        }
        # Try block was successful, return the version
        return $version
    }
    # Re-raise the error in the "try" block (which will always execute)
    return -options $options $errMsg
}

# tin installed --
# 
# Returns the latest installed version meeting version requirements (normalized)
# Like "package present" but does not require package to be loaded.
#
# Syntax:
# tin installed $name <$reqs...>
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::installed {name args} {
    set reqs [PkgRequirements {*}$args]
    if {![IsInstalled $name $reqs]} {
        return
    }
    NormalizeVersion [SelectVersion [package versions $name] $reqs]
}

# tin uninstall --
#
# Uninstalls versions of a package, as long as it is in the Tin or Auto-Tin
#
# Syntax:
# tin uninstall $name <$reqs...> 
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::uninstall {name args} {
    variable tin
    variable auto
    # Validate/interpret input
    if {![dict exists $tin $name] && ![dict exists $auto $name]} {
        return -code error "cannot uninstall: $name not in the Tin or Auto-Tin"
    }
    # Check if package is installed (return if not) (updates index)
    set reqs [PkgRequirements {*}$args]
    if {![IsInstalled $name $reqs]} {
        return
    }
    # Loop through all installed versions meeting version requirements
    foreach version [FilterVersions [package versions $name] $reqs] {
        # Delete all "name-version" folders on the auto_path
        set pkgFolder [PkgFolder $name $version]; # e.g. foo-1.0
        foreach basedir $::auto_path {
            file delete -force [file join [file normalize $basedir] $pkgFolder]
        }
        # Forget package
        package forget $name $version
    }
    # Ensure package was uninstalled
    if {[IsInstalled $name $reqs]} {
        return -code error "failed to uninstall $name $args"
    }
    # Package was uninstalled.
    return
}

# tin upgrade --
#
# Upgrades an existing package.
# Returns upgraded package version number.
#
# Syntax:
# tin upgrade $name <$reqs...> 
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::upgrade {name args} {
    variable tin
    if {![dict exists $tin $name]} {
        return -code error "can't find $name in the Tin"
    }
    # Normalize package version requirement inputs
    set reqs [PkgRequirements {*}$args]
    # Find version that would be selected with a "package require" statement
    if {![IsInstalled $name $reqs]} {
        return -code error "can't find $name $args"
    }
    set installed [SelectVersion [package versions $name] $reqs]; # e.g. "1.2"
    # Select an available version that upgrades the installed version
    set available [dict keys [dict get $tin $name]]; # e.g. "1.3 1.5 1.6a0 2.0"
    set version [SelectVersion $available $installed]; # e.g. "1.5"
    if {$version eq "" || [package vcompare $version $installed] == 0} {
        puts "no upgrade available for $name $args"
        return $installed
    }
    puts "upgrading $name v$installed to v$version ..."
    tin install $name -exact $version
    tin uninstall $name -exact $installed
    return $version
}

## Package loading commands, with installation on the fly
################################################################################

# tin import --
#
# Helper procedure to handle the majority of cases for importing Tcl packages
# Uses "tin require" to load the packages
# 
# Syntax
# tin import <-force> <$patterns from> $name <$reqs...> <as $ns>
# 
# Arguments:
# -force        Option to overwrite existing commands
# patterns      Glob patterns for importing commands from package
# name          Package name (must have corresponding namespace)
# reqs...       User-input package version requirements (see PkgRequirements)
# ns            Namespace to import into. Default global namespace.
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

# tin require --
#
# Same as "package require", but will try to install if needed.
#
# Syntax:
# tin versions $name <$reqs...> 
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

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

# tin depend --
#
# Requires that the package is installed. Returns installed version.
# Tries to install if package is missing, but does not load the package.
# Intended for package installer files.
# 
# Syntax:
# tin versions $name <$reqs...> 
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::depend {name args} {
    # Try to install if the package is not installed
    set version [tin installed $name {*}$args]
    if {$version eq ""} {
        puts "can't find package $name $args, attempting to install ..."
        set version [tin install $name {*}$args]
    }
    return $version
}

# tin forget --
#
# Convenience procedure for reloading pure Tcl packages
# Forgets package and also deletes any corresponding namespace
#
# Syntax: 
# tin forget $name
#
# Arguments:
# name          Package name

proc ::tin::forget {name} {
    package forget $name
    if {[namespace exists $name]} {
        namespace delete $name
    }
    return
}

## Package development utilities
################################################################################

# tin mkdir --
#
# Helper procedure to make library folders. Returns directory name. 
# Intended for package installer files.
#
# Syntax:
# tin mkdir <-force> <$basedir> $name $version
#
# Arguments:
# -force        Option to clear out the folder. 
# basedir       Optional, default one folder up from "info library"
# name          Package name
# version       Package version

proc ::tin::mkdir {args} {
    # Extract the -force option from the input, 
    if {[lindex $args 0] eq "-force"} {
        set force true
        set args [lrange $args 1 end]
    } else {
        set force false
    }
    # Handle optional "basedir" input
    if {[llength $args] == 3} {
        lassign $args basedir name version
    } elseif {[llength $args] == 2} {
        set basedir [file dirname [info library]]
        lassign $args name version
    } else { 
        WrongNumArgs "tin mklib ?-force? ?basedir? name version"
    }
    # Create package directory, and return full path to user.
    set dir [file join $basedir [PkgFolder $name $version]]
    if {$force} {
        file delete -force $dir
    }
    file mkdir $dir
    return $dir
}

# tin bake --
#
# Perform substitution on file contents and write to new files
# Allows for uppercase alphanum variable substitution (e.g. @VARIABLE@)
# Intended for package build files.
#
# Syntax:
# tin bake $inFile $outFile $config
#
# Arguments:
# inFile        File to read (with @VARIABLE@ declarations).
# outFile       File to write to after substitution.
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
    file mkdir [file dirname $outFile]
    set fid [open $outFile w]
    puts $fid $data
    close $fid
    return
}

# Private functions (internal API)
################################################################################

# WrongNumArgs --
#
# Utility function to make a typical wrong number arguments command.
# Based on Tcl_WrongNumArgs API command

proc ::tin::WrongNumArgs {message} {
    tailcall return -code error "wrong # args: should be \"$message\""
}

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
    # Handle all input cases
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
    # Validate requirements
    if {[catch {package vsatisfies 0 {*}$reqs} errMsg]} {
        return -code error $errMsg
    }
    # Return validated requirements.
    return $reqs
}

# PkgFolder --
#
# Returns a standardized package name for a package/version
#
# Syntax:
# PkgFolder $name $version
# 
# Arguments:
# name          Package name
# version       Package version

proc ::tin::PkgFolder {name version} {
    # Ensure that package name is valid (alphanum, with :: separators)
    ValidatePkgName $name
    # Validate and normalize package version (minimum major.minor)
    set version [NormalizeVersion $version]
    # Construct package folder name, ensuring valid directory name for
    # nested packages (e.g. foo::bar -> foo_bar)
    return [string cat [string map {:: _} $name] - $version]
}

# ValidatePkgName --
#
# Validates package name (must be alphanumeric, with :: separator allowed)
# Returns blank if valid name, else error.
#
# Syntax:
# ValidatePkgName $name
#
# Arguments:
# name          Package name

proc ::tin::ValidatePkgName {name} {
    foreach part [split [string map {:: :} $name] :] {
        if {![string is alnum -strict $part]} {
            return -code error "invalid package name $name"
        }
    }
    return
}

# NormalizeVersion --
#
# Normalizes version numbers, compatible with "package require"
# https://www.tcl.tk/man/tcl8.6/TclCmd/package.html#M20
#
# Syntax:
# NormalizeVersion $version
#
# Arguments:
# version       Package version

proc ::tin::NormalizeVersion {version} {
    # Get version number parts (at least major.minor)
    set parts [VersionParts $version 2]
    # Ensure that alpha (a) or beta (b) parts are followed by a number.
    # In Tcl, a and b are seen as replacements for periods.
    if {[lindex $parts end] < 0} {
        lappend parts 0
    }
    # Restore version number from parts
    set version [string map {.-2. a .-1. b} [join $parts .]]
    return $version
}

# VersionParts --
#
# Splits Tcl version number into a minimum number of parts
#
# Syntax:
# VersionParts $version <$n>
#
# Arguments:
# version       Package version
# n             Minimum number of version parts to return. Default 3

proc ::tin::VersionParts {version {n 3}} {
    # Check using internal version matching
    if {[catch {package vsatisfies 0 $version} errMsg]} {
        return -code error $errMsg
    }
    set parts [split [string map {a .-2. b .-1.} $version] .]
    # Ensure that there are no leading zeros
    if {[lsearch -regexp $parts {0+\d+}] != -1} {
        return -code error "cannot have leading zeros in version parts"
    }
    # Trim trailing zeros, but keep at least one number.
    while {[lindex $parts end] == 0 && [llength $parts] > 0} {
        set parts [lreplace $parts end end]
    }
    # Ensure minimum number of version parts
    while {[llength $parts] < $n} {
        lappend parts 0
    }
    return $parts
}

# SelectVersion --
#
# Get version of package based on requirements and "package prefer"
# Returns blank if no version is found.
#
# Syntax:
# SelectVersion $versions $reqs
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

# FilterVersions --
# 
# Get versions that satisfy requirements. Does not sort.
# If no requirements, simply returns versions.
#
# Syntax:
# FilterVersions $versions $reqs
#
# Arguments:
# versions      List of versions
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::FilterVersions {versions reqs} {
    lmap version $versions {
        expr {[package vsatisfies $version {*}$reqs] ? $version : [continue]}
    }
}

# IsInstalled --
#
# Boolean, whether a package is installed or not. 
#
# Syntax:
# IsInstalled $name $reqs
#
# Arguments
# name          Package name
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::IsInstalled {name reqs} {
    # Check if already indexed
    if {[IsIndexed $name $reqs]} {
        return 1
    }
    # Update index and return whether indexed.
    UpdateIndex $name $reqs
    return [IsIndexed $name $reqs]
}

# IsIndexed --
#
# Boolean, whether a package version satisfying requirements has been indexed
#
# Syntax:
# IsIndexed $name $reqs
#
# Arguments
# name          Package name
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::IsIndexed {name reqs} {
    foreach version [package versions $name] {
        if {[package vsatisfies $version {*}$reqs]} {
            # Found one that satisifies, return.
            return 1
        }
    }
    # None met the criteria.
    return 0
}

# UpdateIndex --
#
# Updates the package index database, using "package unknown"
#
# Syntax:
# UpdateIndex $name $reqs
#
# Arguments
# name          Package name
# reqs          Version requirements compatible with "package vsatisfies"

proc ::tin::UpdateIndex {name reqs} {
    uplevel "#0" [package unknown] [linsert $reqs 0 $name]
}

# Initialize Tin and Auto-Tin databases
namespace eval ::tin {
    source $tinlistFile
    if {[file exists $userTinlistFile]} {
        source $userTinlistFile
    }
}

# Finally, provide the package
package provide tin 0.4a0
