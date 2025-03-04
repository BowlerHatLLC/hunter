# Hunter file watcher for Haxe

Run a command that watches (hunts) for changes to files in one or more directories.

## Installation

Use the [**haxelib install**](https://lib.haxe.org/documentation/using-haxelib/#install) command to download Hunter.

```sh
haxelib install hunter
```

Requires Haxe 4.0 or newer.

## Command Line

Use the [**haxelib run**](https://lib.haxe.org/documentation/using-haxelib/#run) command to launch Hunter. Pass in the command to run, followed by directory paths to watch, and any desired options. If no directories are specified, the current working directory will be used.

```sh
haxelib run hunter <command> [...directories] [OPTIONS]
```

### Options

The following options can be added to the **haxelib run hunter** command to customize its behavior.

- **--interval _seconds_**

  specify the polling, in seconds (default: 0.2)

- **--wait _path/to/dir_**

  specify an additional delay after running the command, in seconds (default: 0.0)

- **--ignoreDotFiles**

  specify if changes to dot files are ignored (default: false)

- **--help**

  print usage instructions

Example:

```sh
haxelib run hunter haxe compile.hxml src --interval 0.5 --wait 1.0 --ignoreDotFiles
```
