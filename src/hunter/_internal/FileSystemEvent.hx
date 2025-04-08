/*
 * SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com) and contributors
 * SPDX-FileContributor: Sebastian Thomschke, Vegard IT GmbH
 * SPDX-License-Identifier: Apache-2.0
 */

package hunter._internal;

enum FileSystemEvent {
	DIR_CREATED(dirPath:String);

	DIR_DELETED(dirPath:String);

	/**
	 * @param old attributes at the time before the event occurred, may be null depending on implementation
	 * @param now attributes at the time when the event occurred, may be null depending on implementation
	 */
	DIR_MODIFIED(dirPath:String, ?old:DirAttrs, ?now:DirAttrs);

	FILE_CREATED(filePath:String);

	FILE_DELETED(filePath:String);

	/**
	 * @param old attributes at the time before the event occurred, may be null depending on implementation
	 * @param now attributes at the time when the event occurred, may be null depending on implementation
	 */
	FILE_MODIFIED(filePath:String, ?old:FileAttrs, ?now:FileAttrs);
}
