# Tin
Tcl package manager. 

## How to install and use Tin:

First install: Download the latest release, extract the files, and run "installer.tcl" in a Tcl interpreter, and [install git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git). 

Once tin and git are installed, upgrading tin is easy!
```tcl
package require tin
tin install tin
```

Full documentation [here](doc/tin.pdf).

## Adding a package to the Tin database

Tin comes with a list of available packages, listed [here](tinlist.tcl).
To add a repository that is not on this list, either fork this repository and submit a pull request to add it to the list, or use "tin add" to add it manually, as shown below:

```tcl
package require tin
tin add foo 1.0 https://github.com/username/foo v1.0 install_foo.tcl
tin install foo
```


