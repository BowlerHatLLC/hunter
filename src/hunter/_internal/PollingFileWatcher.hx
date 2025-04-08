/*
 * SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
 * SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
 * SPDX-License-Identifier: Apache-2.0
 */

package hunter._internal;

import haxe.ds.StringMap;
import haxe.io.Path;
import hx.concurrent.event.AsyncEventDispatcher;
import hx.concurrent.event.EventDispatcher;
import hx.concurrent.event.EventListenable;
import hx.concurrent.executor.Executor;
import hx.concurrent.lock.RLock;
import sys.FileSystem;

class PollingFileWatcher implements EventListenable<FileSystemEvent> {
	final executor:Executor;
	final eventDispatcher:EventDispatcher<FileSystemEvent>;

	final intervalMS:Int;

	var scanTask:Null<TaskFuture<Void>>;

	final watched = new StringMap<FSEntry>();
	final watchedSync = new RLock();

	private var state(default, set):ServiceState = STOPPED;

	function set_state(s:ServiceState) {
		switch (s) {
			case STARTING:
				trace('[$this] is starting...');
			case RUNNING:
				trace('[$this] is running.');
			case STOPPING:
				trace('[$this] is stopping...');
			case STOPPED:
				trace('[$this] is stopped.');
		}
		return state = s;
	}

	final _stateLock:RLock = new RLock();

	/**
	 * @param executor the executor to be used for scheduling/executing the background polling task and for notifying subscribers of FileSystemEvents (optional, defaults to hx.concurrent.event.SyncEventDispatcher)
	 * @param intervalMS polling interval in milliseconds
	 */
	public function new(executor:Executor, intervalMS:Int, autostart:Bool = true) {
		if (executor == null)
			throw "[executor] must not be null";

		this.executor = executor;
		eventDispatcher = new AsyncEventDispatcher(executor);

		if (intervalMS < 1)
			throw "[intervalMS] must be a positive value";

		this.intervalMS = intervalMS;

		if (autostart)
			start();
	}

	public function start():Void {
		_stateLock.execute(function() {
			switch (state) {
				case STARTING:
					{/*nothing to do*/};
				case RUNNING:
					{/*nothing to do*/};
				case STOPPING:
					throw 'Service [$this] is currently stopping!';
				case STOPPED:
					{
						state = STARTING;
						onStart();
						state = RUNNING;
					}
			}
		});
	}

	public function onStart():Void {
		scanTask = executor.submit(this.scanAll, Schedule.FIXED_DELAY(intervalMS, 0));
	}

	public function onStop():Void {
		if (scanTask == null) {
			return;
		}
		scanTask.cancel();
		scanTask = null;
	}

	inline public function subscribe(listener:FileSystemEvent->Void):Bool {
		return eventDispatcher.subscribe(listener);
	}

	inline public function unsubscribe(listener:FileSystemEvent->Void):Bool {
		return eventDispatcher.unsubscribe(listener);
	}

	public function watch(pathStr:String):Void {
		if (pathStr == null) {
			throw "[path] must not be null";
		}

		trace('[INFO] Watching [$pathStr]...');
		watchedSync.execute(function() {
			if (watched.exists(pathStr))
				return;

			if (scanTask == null) {
				watched.set(pathStr, FSEntry.UNSCANNED(pathStr));
			} else {
				scanPath(FSEntry.UNSCANNED(pathStr));
			}
		});
	}

	public function unwatch(pathStr:String):Void {
		if (pathStr == null) {
			return;
		}

		watchedSync.execute(function() {
			trace('[INFO] Unwatching [$pathStr]...');
			watched.remove(pathStr);
		});
	}

	private function scanAll():Void {
		final paths = watchedSync.execute(() -> [for (k in watched.keys()) k]);

		for (path in paths) {
			watchedSync.execute(function() {
				final fsEntry = watched.get(path);
				if (fsEntry == null) // if null, then the path has been unwachted in the meantime
					return;
				scanPath(fsEntry);
			});
		}
	}

	private function compareFSEntry(old:FSEntry, now:FSEntry):Void {
		switch (old : FSEntry) {
			case DIR(dirPath, attrs, childrenOld):
				switch (now) {
					case DIR(_, attrsNow, childrenNow): {
							if (!attrs.equals(attrsNow))
								eventDispatcher.fire(FileSystemEvent.DIR_MODIFIED(dirPath, attrs, attrsNow));

							for (childName => child in childrenOld) {
								var childNow = childrenNow.get(childName);

								if (childNow == null)
									childNow = FSEntry.NONEXISTANT(null);
								compareFSEntry(child, childNow);
							}

							for (childName => childNow in childrenOld) {
								final child = childrenOld.get(childName);
								if (child == null) {
									compareFSEntry(FSEntry.NONEXISTANT(null), childNow);
								}
							}
						}
					case FILE(filePath, _):
						eventDispatcher.fire(FileSystemEvent.DIR_DELETED(dirPath));
						eventDispatcher.fire(FileSystemEvent.FILE_CREATED(filePath));
					case NONEXISTANT(_) | UNKNOWN(_):
						final deletedDirs:Array<String> = [dirPath];

						// traverse the captured children of the deleted directory
						// to fire deletion events
						final work = [childrenOld];
						var workItem:Null<StringMap<FSEntry>>;
						while ((workItem = work.pop()) != null) {
							for (child in workItem) {
								switch (child) {
									case DIR(dir, attrsNow, children):
										deletedDirs.push(dir);
										work.push(children);
									case FILE(file, _):
										eventDispatcher.fire(FileSystemEvent.FILE_DELETED(file));
									default:
										// nothing to do
								}
							}
						}

						deletedDirs.reverse();
						for (dir in deletedDirs) {
							eventDispatcher.fire(FileSystemEvent.DIR_DELETED(dir));
						}

					case UNSCANNED(_):
						// nothing to do
				}
			case FILE(filePath, attrs):
				switch (now) {
					case DIR(dirPath, _, _):
						eventDispatcher.fire(FileSystemEvent.FILE_DELETED(filePath));
						compareFSEntry(FSEntry.NONEXISTANT(dirPath), now);
					case FILE(_, attrsNow):
						if (!attrs.equals(attrsNow)) {
							eventDispatcher.fire(FileSystemEvent.FILE_MODIFIED(filePath, attrs, attrsNow));
						}
					case NONEXISTANT(_) | UNKNOWN(_):
						eventDispatcher.fire(FileSystemEvent.FILE_DELETED(filePath));
					case UNSCANNED(_):
						// nothing to do
				}
			case NONEXISTANT(_) | UNKNOWN(_):
				switch (now) {
					case DIR(dir, _, childrenNow):
						eventDispatcher.fire(FileSystemEvent.DIR_CREATED(dir));

						final work = [childrenNow];
						var workItem:Null<StringMap<FSEntry>>;
						while ((workItem = work.pop()) != null) {
							for (child in workItem) {
								switch (child) {
									case DIR(dirPath, _, children):
										eventDispatcher.fire(FileSystemEvent.DIR_CREATED(dirPath));
										work.push(children);
									case FILE(filePath, _):
										eventDispatcher.fire(FileSystemEvent.FILE_CREATED(filePath));
									default:
										// nothing to do
								}
							}
						}
					case FILE(file, _):
						eventDispatcher.fire(FileSystemEvent.FILE_CREATED(file));
					default:
						// nothing to do
				}
			case UNSCANNED(_):
				// nothing to do
		}
	}

	private function scanPath(fsEntry:FSEntry):Void {
		switch (fsEntry) {
			case DIR(dirPath, _, _):
				{
					final fsEntryNow = createFSEntry_DIR(dirPath);
					compareFSEntry(fsEntry, fsEntryNow);
					watched.set(dirPath, fsEntryNow);
				}

			case FILE(filePath, _):
				{
					final fsEntryNow = createFSEntry_FILE(filePath);
					compareFSEntry(fsEntry, fsEntryNow);
					watched.set(filePath, fsEntryNow);
				}

			case NONEXISTANT(path):
				{
					if (path == null || !FileSystem.exists(path))
						return;

					if (FileSystem.isDirectory(path)) {
						final fsEntryNow = createFSEntry_DIR(path);
						compareFSEntry(fsEntry, fsEntryNow);
						watched.set(path.toString(), fsEntryNow);
					} else {
						final fsEntryNow = createFSEntry_FILE(path);
						compareFSEntry(fsEntry, fsEntryNow);
						watched.set(path.toString(), fsEntryNow);
					}
				}

			case UNSCANNED(path):
				{
					if (!FileSystem.exists(path)) {
						watched.set(path, FSEntry.NONEXISTANT(path));
						return;
					}

					if (FileSystem.isDirectory(path)) {
						watched.set(path, createFSEntry_DIR(path));
					} else {
						watched.set(path, createFSEntry_FILE(path));
					}
				}

			case UNKNOWN(path):
				{
					if (!FileSystem.exists(path)) {
						watched.set(path, FSEntry.NONEXISTANT(path));
						return;
					}

					scanPath(FSEntry.NONEXISTANT(path));
				}
		}
	}

	private function createFSEntry_DIR(dirPath:String):FSEntry {
		if (!FileSystem.exists(dirPath))
			return FSEntry.NONEXISTANT(dirPath);

		final children = new StringMap<FSEntry>();

		for (fileName in FileSystem.readDirectory(dirPath)) {
			final filePath = Path.join([dirPath, fileName]);
			if (FileSystem.isDirectory(filePath)) {
				children.set(fileName, createFSEntry_DIR(filePath));
			} else {
				children.set(fileName, createFSEntry_FILE(filePath));
			}
		}

		// check if dir was deleted meanwhile
		return FileSystem.exists(dirPath) ? FSEntry.DIR(dirPath, DirAttrs.fromDir(dirPath), children) : FSEntry.NONEXISTANT(dirPath);
	}

	inline private function createFSEntry_FILE(filePath:String):FSEntry {
		return FileSystem.exists(filePath) ? FSEntry.FILE(filePath, FileAttrs.fromFile(filePath)) : FSEntry.NONEXISTANT(filePath);
	}
}

private enum FSEntry {
	DIR(dir:String, attrs:DirAttrs, children:StringMap<FSEntry>);
	FILE(file:String, attrs:FileAttrs);
	NONEXISTANT(?path:String);
	UNSCANNED(path:String);
	UNKNOWN(path:String);
}

private enum ServiceState {
	STARTING;
	RUNNING;
	STOPPING;
	STOPPED;
}
