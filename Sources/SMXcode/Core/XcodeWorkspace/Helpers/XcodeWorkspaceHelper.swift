/*
 * XcodeWorkspaceHelper.swift
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


//
// MARK: - XcodeWorkspace
//
extension XcodeWorkspace
{
	// MARK: Enumerate

	// MARK: > Function
	public func enumerateProjects(options: XcodeProject.EnumerateOptions, using block: (_ enumeratedProject: XcodeProject.EnumeratedProject) throws -> Bool) rethrows
	{
		let count = self.xcodeProjecsCount
		var onceBucket = Set<URL>()

		// List every projects references by our workspace.
		for i in 0 ..< count
		{
			let projectRef = self.xcodeProject(at: i)

			// > Enforce once options.
			if options.contains(.once)
			{
				if onceBucket.contains(projectRef.url) {
					continue
				} else {
					onceBucket.insert(projectRef.url)
				}
			}

			// > Parse the project. Give the result to the caller.
			let project: XcodeProject

			do {
				project = try XcodeProject(project: projectRef.url)
			}
			catch
			{
				if try block(.error(url: projectRef.url, error: error)) {
					continue
				} else {
					return
				}
			}

			if try block(.project(project: project, parent: nil)) == false {
				return
			}

			// > Recurse deeply inside projects.
			if options.contains(.deep)
			{
				if try project.enumerateProjects(mode: .all, options: options, onceBucket: &onceBucket, using: block) == false {
					return
				}
			}
		}
	}
}
