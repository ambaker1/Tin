# tin.tcl
################################################################################
# Tcl/Git package installation manager and package development tools
# https://github.com/ambaker1/Tin

# Copyright (C) 2025 Alex Baker, ambaker1@mtu.edu
# All rights reserved. 

# See the file "LICENSE" in the top level directory for information on usage, 
# redistribution, and for a DISCLAIMER OF ALL WARRANTIES.
################################################################################

namespace eval ::tin {
    # Internal variables
    # Tin database dictionary variable
    variable tinData ""; # Installation info for packages and versions
    # name {version {repo {tag file} ...} ...} ...
    # Exported commands (ensemble with "tin")
    ## Modify the package installation configuration database
    namespace export add autoadd remove clear
    ## Query the Tin
    namespace export get packages versions available
    ## Tcl package utilities 
    namespace export installed forget
    ## Package install/uninstall commands
    namespace export install depend uninstall
    ## Package upgrade commands
    namespace export check upgrade 
    ## Package loading commands
    namespace export import require 
    ## Package development utilities
    namespace export mkdir bake assert
    namespace ensemble create
}

## Modify the package installation database
################################################################################

# tin add --
#
# Add information for package and version for installation.
#
# Syntax
# tin add $name $version $repo $tag $file
#
# Arguments:
# name              Package name
# version           Package version (or version requirements)
# repo              Git repository URL
# tag               Repository tag
# file              Installer .tcl file (relative to repo main folder)

proc ::tin::add {name version repo tag file} {
    variable tinData
    ValidatePkgName $name
    set version [NormalizeVersion $version]
    dict set tinData $name $version $repo [list $tag $file]
    return
}

# tin autoadd --
#
# Auto-add available packages from a repository
# Returns versions
#
# Syntax
# tin autoadd $name $repo $file $req...
#
# Arguments:
# name              Package name
# repo              Git repository URL
# file              Installer .tcl file (relative to repo main folder)
# req...            Package version requirements (see PkgRequirements)

proc ::tin::autoadd {name repo file args} {
    set reqs [PkgRequirements {*}$args]
    ValidatePkgName $name
    # Define the regex for getting tags from a remote Git repository.
    # The pattern is compatible with the package version rules for Tcl, and 
    # additionally does not permit leading zeros, as per SemVer rules.
    # Digit pattern for no leading zeros: (0|[1-9]\d*)
    # https://semver.org/
    # https://www.tcl.tk/man/tcl/TclCmd/package.html#M20
    set tagPattern {^v(0|[1-9]\d*)(\.(0|[1-9]\d*))*([ab](0|[1-9]\d*)(\.(0|[1-9]\d*))*)?$}
    # Try to get version tags using git, and add valid ones to the Tin
    try {
        exec git ls-remote --tags $repo v*
    } on error {errMsg options} {
        # Raise warning, but do not throw error.
        puts "warning: failed to get tags for $name at $repo"
        puts $errMsg
    } on ok {result} {
        # Acquired tag data. Strip excess data, and filter for regexp
        set tags [lmap {~ path} $result {file tail $path}]
        set tags [lsearch -inline -all -regexp $tags $tagPattern]
        # Loop through tags, and add to the Tin if within specified reqs
        foreach tag $tags {
            set version [string range $tag 1 end]
            if {[package vsatisfies $version {*}$reqs]} {
                tin add $name $version $repo $tag $file
                lappend versions $version
            }
        }; # end foreach tag
        return $versions
    }; # end try
}

# tin remove --
#
# Remove entries. Returns blank, does not complain.
# Essentially "dict unset" for package installation database.
#
# Syntax:
# tin remove $name <$version> <$repo>
# 
# Arguments:
# name          Package name
# version       Package version
# repo          Git repository URL

proc ::tin::remove {name args} {
    variable tinData
    if {[llength $args] > 2} {
        WrongNumArgs "tin remove name ?version? ?repo?"
    }
    # Normalize version input
    if {[llength $args] > 0} {
        lset args 0 [NormalizeVersion [lindex $args 0]]
    }
    if {[dict exists $tinData $name {*}$args]} {
        dict unset tinData $name {*}$args
    }
    return
}

# tin clear --
#
# Clears the installation configuration data
#
# Syntax:
# tin clear

proc ::tin::clear {} {
    variable tinData
    set tinData ""
    return
}

## Query the Tin
################################################################################

# tin get --
#
# Get raw information from the Tin. Returns blank if no info.
# Equivalent to "dict get" for the Tin database, with the exception
# that it will not throw an error if the entry does not exist.
#
# Syntax:
# tin get $name <$version> <$repo>
#
# Arguments:
# name          Package name (required)
# version       Package version
# repo          Git repository URL

proc ::tin::get {name args} {
    variable tinData
    if {[llength $args] > 2} {
        WrongNumArgs "tin get name ?version? ?repo?"
    }
    # Normalize version input
    if {[llength $args] > 0} {
        lset args 0 [NormalizeVersion [lindex $args 0]]
    }
    if {[dict exists $tinData $name {*}$args]} {
        return [dict get $tinData $name {*}$args]
    }
    # Return blank otherwise
    return
}

# tin packages --
#
# Get list of packages available for install.
#
# Syntax:
# tin packages <$pattern>
# 
# Arguments:
# pattern       Optional "glob" pattern for matching against package names

proc ::tin::packages {{pattern *}} {
    variable tinData
    dict keys $tinData $pattern
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
    variable tinData
    if {![dict exists $tinData $name]} {
        return
    }
    # Get list of versions
    set versions [dict keys [dict get $tinData $name]]
    # Filter for version requirements
    if {[llength $args] > 0} {
        set versions [FilterVersions $versions [PkgRequirements {*}$args]]
    }
    # Return sorted list
    return $versions
}

# tin available --
# 
# Returns the version that would be installed with "tin installed".
# If not available, returns blank.
#
# Syntax:
# tin available $name <$reqs...>
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::available {name args} {
    set reqs [PkgRequirements {*}$args]
    if {![IsAvailable $name $reqs]} {
        return
    }
    SelectVersion [tin versions $name] $reqs
}

## Package utilities
################################################################################

# tin installed --
# 
# Returns the latest installed version meeting version requirements (normalized)
# Like "package present" but does not require package to be loaded.
# If not installed, returns blank
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

# tin forget --
#
# Package forget, but also deletes associated namespace.
#
# Syntax:
# tin forget $name ...
#
# Arguments:
# name          Package name

proc ::tin::forget {args} {
    foreach name $args {
        package forget $name
        if {[namespace exists ::$name]} {
            namespace delete ::$name
        }
    }
    return
}

## Package install/uninstall commands
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
    # Check if entry exists that satisfies requirements
    puts "searching in Tin for [concat $name $args] ..."
    set version [tin available $name {*}$args]
    if {$version eq ""} {
        return -code error "can't find [concat $name $args] in Tin"
    }
    
    # Now we know that there is a entry in the Tin for package "$name $version"
    # Loop through all added repositories for selected version 
    dict for {repo data} [tin get $name $version] {
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

# tin depend --
#
# Requires that the package is installed. Returns installed version.
# Tries to install if package is missing, but does not load the package.
# Intended for package installer files.
# 
# Syntax:
# tin depend $name <$reqs...> 
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

# tin uninstall --
#
# Uninstalls versions of a package, as long as it is in the Tin
# Removes package folder or runs "pkgUninstall.tcl" file in package folder.
#
# Syntax:
# tin uninstall $name <$reqs...>
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::uninstall {name args} {
    set reqs [PkgRequirements {*}$args]
    # Check if package is available for install (cannot uninstall non-Tin pkgs)
    if {![IsAvailable $name $reqs]} {
        return -code error "cannot uninstall: $name $args not available"
    }
    # Check if package is installed (return if not) (updates index)
    if {![IsInstalled $name $reqs]} {
        return
    }
    # Loop through all installed versions meeting version requirements
    foreach version [FilterVersions [package versions $name] $reqs] {
        # Delete all "name-version" folders on the auto_path
        set pkgFolder [PkgFolder $name $version]; # e.g. foo-1.0
        foreach basedir $::auto_path {
            set dir [file join [file normalize $basedir] $pkgFolder]
            if {[file exists [file join $dir pkgUninstall.tcl]]} {
                # Run pkgUninstall.tcl file to uninstall package.
                # This allows for modifying files outside the package folder.
                apply {{dir} {source [file join $dir pkgUninstall.tcl]}} $dir
            } else {
                # Just delete the package folder
                file delete -force $dir
            }
        }
        # Forget package
        package forget $name $version
    }
    # Ensure package was uninstalled
    if {[IsInstalled $name $reqs]} {
        return -code error "failed to uninstall $name $args"
    }
    # Package was uninstalled. Return blank
    return
}

## Package upgrading commands
################################################################################

# tin check --
#
# Check for upgradable packages
# Returns upgrade dictionary {name {old new ...} ...} if -all option is used,
# or list "old new" if a single package is queried.
# 
# Syntax:
# tin check $name <$reqs...>
# tin check -all <$names>

proc ::tin::check {args} {
    # tin check -all <$names>
    if {[lindex $args 0] eq "-all"} {
        if {[llength $args] > 2} {
            WrongNumArgs "tin check -all ?names?"
        }
        # Create name-version result dictionary
        set args [lrange $args 1 end]
        if {[llength $args] == 1} {
            set names [lindex $args 0]
        } else {
            set names [tin packages]
        }
        # Create upgrade result dictionary
        set upgrades ""
        foreach name $names {
            # Get latest installed package version
            set version [tin installed $name]
            if {$version eq ""} {
                continue; # package is not installed
            }
            # Get maximum major version number
            set n [lindex [SplitVersion $version] 0]
            # Upgrade all major versions (if they exist)
            for {set i 0} {$i <= $n} {incr i} {
                set upgrade [tin check $name $i]; # "old new"
                if {[llength $upgrade] > 0} {
                    dict set upgrades $name {*}$upgrade
                }
            }
        }
        return $upgrades
    }
    # tin check $name <$reqs ...>
    set reqs [PkgRequirements {*}[lassign $args name]]
    # Check if upgradable (return blank if not)
    if {![IsUpgradable $name $reqs]} {
        return
    }
    # Get old and new package versions
    set old [SelectVersion [package versions $name] $reqs]
    set new [SelectVersion [tin versions $name] $old $old]
    return [list $old $new]
}

# tin upgrade --
#
# Upgrades packages (installs new, then uninstalls old)
# Returns the results of "tin check"
#
# Syntax:
# tin upgrade $name <$reqs...>
# tin upgrade -all <$names>
#
# Arguments:
# -all          Option to upgrade all (major version 0-N, where N is largest)
# names         Packages names. Default all Tin packages
# name          Package name.
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::upgrade {args} {
    # tin upgrade -all <$names>
    if {[lindex $args 0] eq "-all"} {
        # tin upgrade -all $names
        if {[llength $args] > 2} {
            WrongNumArgs "tin check -all ?names?"
        }
        set upgrades [tin check {*}$args]
        dict for {name oldnew} $upgrades {
            dict for {old new} $oldnew {
                puts "upgrading $name v$old to v$new ..."
                tin install $name -exact $new
                tin uninstall $name -exact $old
            }
        }
        return $upgrades
    } 
    # tin upgrade $name <$reqs ...>
    set reqs [PkgRequirements {*}[lassign $args name]]
    set upgrades [tin check $name {*}$reqs]
    if {[llength $upgrades] == 2} {
        lassign $upgrades old new
        puts "upgrading $name v$old to v$new ..."
        tin install $name -exact $new
        tin uninstall $name -exact $old
    }
    return $upgrades
}

## Package loading commands, with installation on the fly
################################################################################

# tin import --
#
# Helper procedure to handle the majority of cases for importing Tcl packages
# Uses "tin require" to load the packages
# Returns version
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
    # Check for -force option
    set force {}; # default
    if {[lindex $args 0] eq "-force"} {
        set args [lassign $args force]; # Strip from args
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
    # Throw error if package does not have corresponding namespace.
    if {![namespace exists ::$name]} {
        return -code error "package $name does not have corresponding namespace"
    }
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
# tin require $name <$reqs...> 
#
# Arguments:
# name          Package name
# reqs...       Package version requirements (see PkgRequirements)

proc ::tin::require {name args} {
    # tin require $name $reqs ...
    set reqs [PkgRequirements {*}$args]
    # Return if package is present (this includes dynamically loaded packages)
    if {![catch {package present $name {*}$reqs} version]} {
        return $version
    }
    # Depend on package being installed, and call "package require"
    tin depend $name {*}$args
    tailcall ::package require $name {*}$reqs
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
# basedir       Optional, default searches auto_path to find a writable path
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
        lassign $args name version
        # Find a writable directory on the auto_path
        set basedir ""
        foreach path $::auto_path {
            if {[file exists $path]} {
                if {![file isdirectory $path]} {
                    continue
                }
                if {[file writable $path]} {
                    set basedir $path
                    # puts "$path writable, found"
                    break
                }
            } else {
                if {![catch {file mkdir $path}]} {
                    set basedir $path
                    # puts "$path created"
                    break
                }
            }
        }
        if {$basedir eq ""} {
            return -code error "no writable directory found in auto_path ($auto_path)"
        }
    } else { 
        WrongNumArgs "tin mkdir ?-force? ?basedir? name version"
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
# tin bake $inFile $outFile <$config> <$varName $value...>
#
# Arguments:
# inFile        File to read (with @VARIABLE@ declarations), or .tin folder
# outFile       File to write to after substitution, or .tcl folder
# config        Dictionary with keys of config variable names, and values.
# varName       Configuration variable name (mutually exclusive with $config)
# value         Configuration variable value (mutually exclusive with $config)

proc ::tin::bake {inFile outFile args} {
    # Check arity
    if {[llength $args] == 1} {
        set config [lindex $args 0]
    } elseif {[llength $args] % 2 == 0} {
        set config $args
    } else {
        WrongNumArgs "tin bake inFile outFile ?config?|?varName value ...?"
    }
    # Get string map for config variable names (must be uppercase alphanum)
    set mapping ""
    dict for {key value} $config {
        if {![regexp {[A-Z0-9_]+} $key]} {
            return -code error "config variables must be uppercase alphanum"
        }
        dict set mapping "@$key@" $value
    }
    
    # Check if inFile exists
    if {![file exists $inFile]} {
        return -code error \
                "couldn't open \"$inFile\": no such file or directory"
    }
    # Directory case (srcDir buildDir)
    if {[file isdirectory $inFile]} {
        set srcDir $inFile
        set buildDir $outFile
        set inFiles [glob -nocomplain -directory $srcDir *.tin]
        set outFiles [lmap inFile $inFiles {
            file join $buildDir [file rootname [file tail $inFile]].tcl 
        }]
        # Batch bake!
        foreach inFile $inFiles outFile $outFiles {
            tin bake $inFile $outFile $config
        }
        return
    }
    # Single file case (inFile outFile)
    # Read from inFile
    set fid [open $inFile r]
    set data [read -nonewline $fid]
    close $fid
    # Perform substitution
    set data [string map $mapping $data]
    # Write to outFile
    file mkdir [file dirname $outFile]
    set fid [open $outFile w]
    puts $fid $data
    close $fid
    return
}

# tin assert --
#
# Assert value or type, throwing error if result is not expected
# Useful for unit testing
#
# Syntax:
# tin assert $expr <$message>
# tin assert $value $op $expected <$message>
#
# Arguments:
# expr          Value to compare. If no "op" and "expected", just asserts true.
# op            tcl::mathop operator, or "is" for asserting type. Default "is".
# expected      Expected value or type. Default "true".
# message       Optional message. Default ""

proc ::tin::assert {args} {
    # Interpret input
    if {[llength $args] <= 2} {
        # tin assert $expr <$message>
        if {[llength $args] == 0} {
            WrongNumArgs "tin assert expr ?message?"
        }
        lassign $args expr message
        if {[uplevel 1 [list expr $expr]]} {
            return
        }
        if {$message eq ""} {
            tailcall return -code error "assert \"$expr\" failed"
        } else {
            tailcall return -code error "$message\nassert \"$expr\" failed"
        }
    } 
    # tin assert $value $op $expected <$message>
    if {[llength $args] > 4} {
        WrongNumArgs "tin assert value op expected ?message?"
    }
    lassign $args value op expected message
    # Add newline to message (if not blank)
    if {$message ne ""} {
        append message \n
    }
    # Switch for operator (type vs math op)
    if {$op eq {is}} {
        # Type comparison
        if {[string is $expected -strict $value]} {
            return
        }
        append message "expected $expected value but got \"$value\""
    } else {
        # Math operator
        if {[::tcl::mathop::$op $value $expected]} {
            return
        }
        append message [list assert $value $op $expected failed]
    }
    tailcall return -code error $message
}

# Private functions (internal API)
################################################################################

# WrongNumArgs --
#
# Utility function to throw a typical "wrong number arguments" error.
# Based on Tcl_WrongNumArgs API command
#
# Syntax:
# WrongNumArgs $want
#
# Arguments:
# want      Proper syntax options for command. 

proc ::tin::WrongNumArgs {want} {
    return -code error -level 2 "wrong # args: should be \"$want\""
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
        ValidateVersion $version
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

# ValidateVersion --
#
# Validates package requirement, using internal version matching
#
# Syntax:
# ValidateVersion $version
#
# Arguments:
# version       Package version

proc ::tin::ValidateVersion {version} {
    if {[catch {package vsatisfies $version 0-} errMsg]} {
        return -code error $errMsg
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
    JoinVersion [SplitVersion $version 2]
}

# SplitVersion --
#
# Splits Tcl version number into a minimum number of parts
#
# Syntax:
# SplitVersion $version <$n>
#
# Arguments:
# version       Package version
# n             Minimum number of version parts to return. Default 3

proc ::tin::SplitVersion {version {n 3}} {
    ValidateVersion $version
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
    # Ensure that alpha (a) or beta (b) parts are followed by a number.
    # In Tcl, a and b are seen as replacements for periods.
    if {[lindex $parts end] < 0} {
        lappend parts 0
    }
    return $parts
}

# JoinVersion --
#
# Join version parts with periods, replacing -2 with a and -1 with b
#
# Syntax:
# JoinVersion $parts
#
# Arguments:
# parts         List of version parts (-2 for alpha, -1 for beta)

proc ::tin::JoinVersion {parts} {
    string map {.-2. a .-1. b} [join $parts .]
}

# SortVersions --
#
# Sort versions in increasing order using "package vcompare"
#
# Syntax:
# SortVersions $versions
#
# Arguments:
# versions      List of versions

proc ::tin::SortVersions {versions} {
    lsort -command {package vcompare} $versions
}

# SelectVersion --
#
# Get version of package based on requirements and "package prefer"
# Returns blank if no version is found.
#
# Syntax:
# SelectVersion $versions $reqs <$min>
#
# Arguments:
# versions      List of versions
# reqs          Version requirements compatible with "package vsatisfies"
# min           Minimum version, must be larger. Default 0a0.

proc ::tin::SelectVersion {versions reqs {min 0a0}} {
    # Get sorted version list satisfying requirements
    set versions [SortVersions [FilterVersions $versions $reqs $min]]
    # Get version that satisfies requirements (go in reverse)
    # See documentation for Tcl "package" command
    set selected ""
    foreach version [lreverse $versions] {
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
# FilterVersions $versions $reqs <$min>
#
# Arguments:
# versions      List of versions
# reqs          Version requirements compatible with "package vsatisfies"
# min           Minimum version, must be larger. Default 0a0.

proc ::tin::FilterVersions {versions reqs {min 0a0}} {
    lmap version $versions {
        expr {[VersionSatisfies $version $reqs $min] ? $version : [continue]}
    }
}

# VersionSatisfies --
#
# Checks to see if a version satisfies version requirements and a minimum.
#
# Syntax:
# VersionSatisfies $version $reqs <$min>
#
# Arguments:
# version       Package version
# reqs          Version requirements compatible with "package vsatisfies"
# min           Minimum version, must be larger. Default 0a0.

proc ::tin::VersionSatisfies {version reqs {min 0a0}} {
    if {[package vsatisfies $version {*}$reqs]} {
        if {[package vcompare $version $min] == 1} {
            return 1
        }
    }
    return 0
}

# IsUpgradable --
#
# Get new version to upgrade to. Returns blank if no new version available.
# If upgradable: old is "tin installed" and new is "tin available"
#
# Syntax:
# IsUpgradable $name $reqs
#
# Arguments:
# name          Package name
# reqs          Package version

proc ::tin::IsUpgradable {name reqs} {
    # Ensure that the package is installed
    if {![IsInstalled $name $reqs]} {
        return 0
    }
    # Get installed version, and then return if an upgrade is available
    set version [SelectVersion [package versions $name] $reqs]
    IsAvailable $name $version $version
}

# IsAvailable --
#
# Boolean, whether a package with version requirements is available for install
# 
# Syntax:
# IsAvailable $name $reqs <$min>
#
# Arguments:
# name          Package name
# reqs          Version requirements compatible with "package vsatisfies"
# min           Minimum version, must be larger. Default 0a0.

proc ::tin::IsAvailable {name reqs {min 0a0}} {
    variable tinData
    if {![dict exists $tinData $name]} {
        return 0
    }
    foreach version [tin versions $name] {
        if {[VersionSatisfies $version $reqs $min]} {
            return 1
        }
    }
    return 0
}

# IsInstalled --
#
# Boolean, whether a package is installed or not. 
#
# Syntax:
# IsInstalled $name $reqs <$min>
#
# Arguments
# name          Package name
# reqs          Version requirements compatible with "package vsatisfies"
# min           Minimum version, must be larger. Default 0a0.

proc ::tin::IsInstalled {name reqs {min 0a0}} {
    # Check if already indexed
    if {[IsIndexed $name $reqs $min]} {
        return 1
    }
    # Update index and return whether indexed.
    UpdateIndex $name $reqs
    IsIndexed $name $reqs $min
}

# IsIndexed --
#
# Boolean, whether a package version satisfying requirements has been indexed
#
# Syntax:
# IsIndexed $name $reqs <$min>
#
# Arguments
# name          Package name
# reqs          Version requirements compatible with "package vsatisfies"
# min           Minimum version, must be larger. Default 0a0.

proc ::tin::IsIndexed {name reqs {min 0a0}} {
    foreach version [package versions $name] {
        if {[VersionSatisfies $version $reqs $min]} {
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

# Finally, provide the package
package provide tin 2.1
