/*
 * URLExtensions.swift
 *
 * Copyright 2023 Avérous Julien-Pierre
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation

// Canonical.
public extension URL
{
	var canonical: URL
	{
		if let canonicalPath = try? self.resourceValues(forKeys: [ .canonicalPathKey ]).canonicalPath {
			return URL(fileURLWithPath: canonicalPath)
		} else {
			return self.resolvingSymlinksInPath()
		}
	}
}

// Relative.
// Note: code from Martin R, https://stackoverflow.com/questions/48351839/swift-equivalent-of-rubys-pathname-relative-path-from/48360631#48360631
public extension URL
{
	func relativePath(from base: URL) -> String
	{
		// Remove/replace "." and "..", make paths absolute.
		let destComponents = self.canonical.pathComponents
		let baseComponents = base.canonical.pathComponents

		// Find number of common path components.
		var i = 0

		while i < destComponents.count && i < baseComponents.count && destComponents[i] == baseComponents[i] {
			i += 1
		}

		// Build relative path.
		var relComponents = Array(repeating: "..", count: baseComponents.count - i)

		relComponents.append(contentsOf: destComponents[i...])

		return relComponents.joined(separator: "/")
	}
}
