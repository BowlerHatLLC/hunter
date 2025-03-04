/*
	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
 */

package hunter;

import haxe.MainLoop;
import haxe.io.Eof;
import hx.concurrent.executor.Executor;
import hx.files.watcher.PollingFileWatcher;
import hxargs.Args;
import sys.FileSystem;
import sys.io.Process;

/**
	Run `haxelib run hunter <command> [...directory] [OPTIONS]` to start
	watching one or more directories for changes, and to run the command when
	changes are detected. If no directory is specified, the current working
	directory is used.
**/
class Run {
	/**
		Entry point.
	**/
	public static function main():Void {
		var args = Sys.args();
		if (Sys.getEnv("HAXELIB_RUN") == "1" && Sys.getEnv("HAXELIB_RUN_NAME") == "hunter") {
			var cwd = args.pop();
			Sys.setCwd(cwd);
		}

		haxe.Log.trace = function(v:Dynamic, ?infos:haxe.PosInfos) {
			// silence traces
		}

		var sawOptions = false;
		var command:String = null;
		var directories:Array<String> = [];
		var pollingInterval:Int = 200;
		var wait:Int = 0;
		var ignoreDotFiles:Bool = false;
		var silent:Bool = false;
		var argHandler:ArgHandler = null;
		argHandler = Args.generate([
			@doc('specify the polling, in seconds (default: 0.2)')
			["--interval"] => function(seconds:String) {
				sawOptions = true;
				var parsedSeconds = Std.parseFloat(seconds);
				if (Math.isNaN(parsedSeconds)) {
					Sys.println('Invalid interval: ${seconds}');
					Sys.exit(1);
				}
				pollingInterval = Std.int(parsedSeconds * 1000);
			},
			@doc('specify an additional delay after running the command, in seconds (default: 0.0)')
			["--wait"] => function(seconds:String) {
				sawOptions = true;
				var parsedSeconds = Std.parseFloat(seconds);
				if (Math.isNaN(parsedSeconds)) {
					Sys.println('Invalid wait: ${seconds}');
					Sys.exit(1);
				}
				wait = Std.int(parsedSeconds * 1000);
			},
			@doc('specify if changes to dot files are ignored (default: false)')
			["--ignoreDotFiles"] => function(ignore:Bool) {
				sawOptions = true;
				ignoreDotFiles = ignore;
			},
			@doc('specify if hunter should hide status messages (default: false)')
			["--silent"] => function(value:Bool) {
				sawOptions = true;
				silent = value;
			},
			@doc('print this help message')
			["--help"] => function() {
				sawOptions = true;
				Sys.println("Usage: haxelib run hunter <command> [...directories] [OPTIONS]");
				Sys.println("Options:");
				Sys.println(argHandler.getDoc());
				Sys.exit(0);
			},
			_ => function(current:String) {
				if (sawOptions) {
					Sys.println('Unknown command: ${command}');
					Sys.exit(1);
				}
				if (command == null) {
					command = current;
				} else {
					if (FileSystem.exists(current) && FileSystem.isDirectory(current)) {
						directories.push(current);
					} else {
						Sys.println('Invalid directory: ${current}');
						Sys.exit(1);
					}
				}
			}
		]);
		argHandler.parse(args);

		if (directories.length == 0) {
			directories.push(Sys.getCwd());
		}

		var executor = Executor.create();
		var fileWatcher = new PollingFileWatcher(executor, pollingInterval);

		var commandPending:Bool = true;
		fileWatcher.subscribe(function(event) {
			switch (event) {
				case DIR_CREATED(dir):
					if (ignoreDotFiles && StringTools.startsWith(dir.path.toString(), ".")) {
						return;
					}
					commandPending = true;
				case DIR_DELETED(dir):
					if (ignoreDotFiles && StringTools.startsWith(dir.path.toString(), ".")) {
						return;
					}
					commandPending = true;
				case DIR_MODIFIED(dir, _):
					if (ignoreDotFiles && StringTools.startsWith(dir.path.toString(), ".")) {
						return;
					}
					commandPending = true;
				case FILE_CREATED(file):
					if (ignoreDotFiles && StringTools.startsWith(file.path.toString(), ".")) {
						return;
					}
					commandPending = true;
				case FILE_DELETED(file):
					if (ignoreDotFiles && StringTools.startsWith(file.path.toString(), ".")) {
						return;
					}
					commandPending = true;
				case FILE_MODIFIED(file, _):
					if (ignoreDotFiles && StringTools.startsWith(file.path.toString(), ".")) {
						return;
					}
					commandPending = true;
			}
		});

		for (directory in directories) {
			if (!silent) {
				Sys.println('Watching: ${directory}');
			}
			fileWatcher.watch(directory);
		}

		var firstRun:Bool = true;
		function commandJob():Void {
			if (!commandPending) {
				executor.submit(commandJob, ONCE(pollingInterval));
				return;
			}
			if (!silent) {
				if (!firstRun) {
					Sys.println("Change detected...");
				}
				Sys.println("Running command: " + command);
			}
			var process = new Process(command);
			process.exitCode(true);
			try {
				while (true) {
					var line = process.stdout.readLine();
					Sys.stdout().writeString(line + "\n");
				}
			} catch (e:Eof) {
				// no more stdout
				Sys.stdout().flush();
			}
			try {
				while (true) {
					var line = process.stderr.readLine();
					Sys.stderr().writeString(line + "\n");
				}
			} catch (e:Eof) {
				// no more stderr
				Sys.stderr().flush();
			}
			commandPending = false;
			firstRun = false;
			executor.submit(commandJob, ONCE(wait + pollingInterval));
		}
		// run the command once immediately on startup
		executor.submit(commandJob, ONCE(0));

		MainLoop.add(() -> {
			// this keeps the process from exiting
		});
	}
}
