/*
 * SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
 * SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
 * SPDX-License-Identifier: Apache-2.0
 */

package hunter._internal;

import sys.FileSystem;

@immutable
class FileAttrs {
	public final mtime:Float;
	public final uid:Int;
	public final gid:Int;
	public final mode:Int;
	public final size:Int;

	public static function fromFile(filePath:String) {
		#if (sys || macro || nodejs)
		if (!FileSystem.exists(filePath)) {
			throw "File does not exist";
		}
		final stat = FileSystem.stat(filePath);
		return new FileAttrs(stat.mtime.getTime(), stat.uid, stat.gid, stat.mode, stat.size);
		#else
		return new FileAttrs(-1, -1, -1, -1, 0);
		#end
	}

	inline public function new(mtime:Float, uid:Int, gid:Int, mode:Int, size:Int) {
		this.mtime = mtime;
		this.uid = uid;
		this.gid = gid;
		this.mode = mode;
		this.size = size;
	}

	inline public function equals(attrs:FileAttrs):Bool {
		return attrs.mtime == mtime && attrs.size == size && attrs.uid == uid && attrs.gid == gid && attrs.mode == mode;
	}
}
