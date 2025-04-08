/*
 * SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
 * SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
 * SPDX-License-Identifier: Apache-2.0
 */

package hunter._internal;

import sys.FileSystem;

@immutable
class DirAttrs {
	public final mtime:Float;
	public final uid:Int;
	public final gid:Int;
	public final mode:Int;

	public static function fromDir(dirPath:String) {
		#if (sys || macro || nodejs)
		if (!FileSystem.exists(dirPath)) {
			throw "Directory does not exist";
		}
		if (!FileSystem.isDirectory(dirPath)) {
			throw "File is not directory";
		}
		final stat = FileSystem.stat(dirPath);
		return new DirAttrs(stat.mtime.getTime(), stat.uid, stat.gid, stat.mode);
		#else
		return new DirAttrs(-1, -1, -1, -1);
		#end
	}

	inline public function new(mtime:Float, uid:Int, gid:Int, mode:Int) {
		this.mtime = mtime;
		this.uid = uid;
		this.gid = gid;
		this.mode = mode;
	}

	inline public function equals(attrs:DirAttrs):Bool {
		return attrs.mtime == mtime && attrs.uid == uid && attrs.gid == gid && attrs.mode == mode;
	}
}
