/*
 * XcodeProjectHelper.swift
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
import System


//
// MARK: - XcodeProject
//
extension XcodeProject
{
	// MARK: Enumerate
	// MARK: > Types
	public enum EnumerateMode
	{
		case all
		// case builtByTarget(targetName: String) // To be implemented.
	}
	
	public struct EnumerateOptions: OptionSet
	{
		public let rawValue: Int
		
		public init(rawValue: Int)
		{
			self.rawValue = rawValue
		}
		
		public static let deep = EnumerateOptions(rawValue: 1 << 0) // Recurse inside projects.
		public static let once = EnumerateOptions(rawValue: 1 << 0) // Don't re-enumerate projects already enumerated.
	}
	
	public enum EnumeratedProject
	{
		case project(project: XcodeProject, parent: XcodeProject?)
		case error(url: URL, error: Error)
	}
	
	// MARK: > Function
	public func enumerateProjects(mode: EnumerateMode, options: EnumerateOptions, using block: (_ enumeratedProject: EnumeratedProject) throws -> Bool) rethrows
	{
		var onceBucket = Set<URL>()
		
		let _ = try enumerateProjects(mode: mode, options: options, onceBucket: &onceBucket, using: block)
	}
	
	internal func enumerateProjects(mode: EnumerateMode, options: EnumerateOptions, onceBucket: inout Set<URL>, using block: (_ enumeratedProject: EnumeratedProject) throws -> Bool) rethrows -> Bool
	{
		// Fetch the project references array from root project.
		guard let rootProject = self.rootProject, let projectReferences = rootProject.projectReferences else {
			return true
		}

		// List each projects.
		for projectReferenceEntry in projectReferences
		{
			// > Get the project reference as a dictionary.
			guard let projectReference = projectReferenceEntry as? XcodeDictionary else {
				continue
			}

			// > Get the project reference object as file reference.
			guard let projectRef: XcodeObjectFileReference = projectReference["ProjectRef"] else {
				continue
			}

			// > Resolve location / URL of this project file reference.
			// > Note: the URL returned is already canonical.
			guard let (_, projectURLOpt) = resolveFileReferencePath(projectRef), let projectURL = projectURLOpt else {
				continue
			}

			// > Enforce once options.
			if options.contains(.once)
			{
				if onceBucket.contains(projectURL) {
					continue
				} else {
					onceBucket.insert(projectURL)
				}
			}
			
			// > Parse the project. Give the result to the caller.
			let project: XcodeProject
			
			do
			{
				project = try XcodeProject(project: projectURL)
				
				if try block(.project(project: project, parent: self)) == false {
					return false
				}
			}
			catch
			{
				if try block(.error(url: projectURL, error: error)) == false {
					return false
				}
				
				continue
			}
			
			// > Recurse.
			if options.contains(.deep)
			{
				if try project.enumerateProjects(mode: mode, options: options, onceBucket: &onceBucket, using: block) == false {
					return false
				}
			}
		}
		
		return true
	}
	

	// MARK: Remove
	public func removeObject(_ object: XcodeObject)
	{
		// Remove from objects.
		if let objects = self.objects
		{
			if let section = objects[object.isa]
			{
				section.removeValue(forKey: .string(object.id))

				if section.count == 0 {
					objects.removeValue(forKey: object.isa)
				}
			}
		}

		// Remove references to this object.
		for parent in object.referencedBy() {
			removeReferences(obj: object, inside: parent.content)
		}

		removeReferences(obj: object, inside: object.content)
	}
	
	private func removeReferences(obj: XcodeObject, inside: Any)
	{
		// Note: we also clean "referencedBy", even if it's backed by a weak container, to avoid inconsistencies while the object is not released from calls.

		// Handle dictionary.
		if let dict = inside as? XcodeDictionary
		{
			var removableKeys = [XcodeLiteral]()

			// > Mark key & entries directly referencing the object as to be removed, and recurse.
			for (key, entry) in dict
			{
				if case let .ref(id, kWeakObj, _) = key
				{
					if id == obj.id {
						removableKeys.append(key)
					}

					if let kObj = kWeakObj.object {
						kObj.removeReference(from: obj)
					}
				}
				else if let literal = entry as? XcodeLiteral, case let .ref(id, kWeakObj, _) = literal
				{
					if id == obj.id {
						removableKeys.append(key)
					}

					if let kObj = kWeakObj.object {
						kObj.removeReference(from: obj)
					}
				}
				else {
					removeReferences(obj: obj, inside: entry)
				}
			}

			// > Remove key & entries directly referencing the object.
			for removableKey in removableKeys {
				dict.removeValue(forKey: removableKey)
			}
		}

		// Handle array.
		else if let array = inside as? XcodeArray
		{
			var removableIndexes = [Int]()

			// > Mark entries directly referencing the object as to be removed, and recurse.
			for (idx, entry) in array.enumerated()
			{
				if case let .ref(id, kWeakObj, _) = entry as? XcodeLiteral
				{
					if id == obj.id {
						removableIndexes.append(idx)
					}

					if let kObj = kWeakObj.object {
						kObj.removeReference(from: obj)
					}
				}
				else {
					removeReferences(obj: obj, inside: entry)
				}
			}

			// > Remove entries directly referencing the object.
			for removableIndex in removableIndexes.reversed() {
				array.remove(at: removableIndex)
			}
		}
	}


	// MARK: Create
	public func createObject<T: XcodeTypedObject>() -> T
	{
		let obj = T.init(content: XcodeDictionary())

		if let sections = self.objects {
			sections.addObjectForKey(.ref(obj.id, XcodeWeakObject(obj), false), object: obj)
		}

		return obj
	}


	// MARK: Files
	// MARK: > Create
	public func createFileReference(file: URL, type: String, group: XcodeObjectGroup? = nil) -> XcodeObjectFileReference
	{
		let fileRef: XcodeObjectFileReference = createObject()
		let rootDirectory: URL
		var finalGroup: XcodeObjectGroup? = nil

		// Resolve group to use as target.
		if let tgroup = group {
			finalGroup = tgroup
		} else {
			finalGroup = self.rootProject?.mainGroup
		}

		// Resolve group path & add file to children.
		if let finalGroup = finalGroup
		{
			fileRef.addReference(from: finalGroup)

			if let (_, groupURLOpt) = resolveGroupPath(finalGroup), let groupURL = groupURLOpt {
				rootDirectory = groupURL
			} else {
				rootDirectory = self.projectDirectory
			}

			if let children = finalGroup.children {
				children.append(fileRef)
			}
			else
			{
				let children = XcodeArray()

				children.append(fileRef)
				finalGroup.children = children
			}
		}
		else {
			rootDirectory = self.projectDirectory
		}

		fileRef.lastKnownFileType = type
		fileRef.name = file.lastPathComponent
		fileRef.path = FilePath(file.relativePath(from: rootDirectory))
		fileRef.sourceTree = "<group>"

		return fileRef
	}

	// MARK: Groups
	// MARK: > Create / Reuse.
	public func groupFor(directory: URL, createIntermediates: Bool = true) -> XcodeObjectGroup?
	{
		var searchGroupDirectory = directory
		var searchGroup: XcodeObjectGroup? = nil
		var subGroupComponents = FilePath.ComponentView()

		// Search a group in which we can include our directory.
		while true
		{
			if let group = self.searchGroup(for: searchGroupDirectory)
			{
				searchGroup = group
				break
			}

			guard let component = FilePath.Component(searchGroupDirectory.lastPathComponent) else {
				break
			}

			subGroupComponents.insert(component, at: subGroupComponents.startIndex)
			searchGroupDirectory = searchGroupDirectory.deletingLastPathComponent()
		}

		// If we didn't find a re-usable group, use the main group.
		let startGroup: XcodeObjectGroup
		let startDirectory: URL

		if let group = searchGroup
		{
			startGroup = group
			startDirectory = searchGroupDirectory
		}
		else
		{
			guard let group = self.rootProject?.mainGroup, let (_, groupURLOpt) = resolveGroupPath(group), let groupURL = groupURLOpt else {
				return nil
			}

			startGroup = group
			startDirectory = groupURL
			subGroupComponents = FilePath(directory.relativePath(from: groupURL)).components
		}

		// The insertion group is the one request, just return it.
		if searchGroupDirectory == directory {
			return searchGroup
		}

		// Create the group(s)
		if createIntermediates
		{
			var currentGroup: XcodeObjectGroup? = startGroup
			var currentGroupDirectory = startDirectory
			var groupedComponents = FilePath.ComponentView()

			for component in subGroupComponents
			{
				if component.string == ".."
				{
					groupedComponents.append(component)
					continue
				}

				if groupedComponents.count > 0
				{
					groupedComponents.append(component)
					currentGroupDirectory.append(path: FilePath(root: nil, groupedComponents).string)
					groupedComponents.removeAll()
				}
				else {
					currentGroupDirectory.append(component: component.string)
				}

				currentGroup = createGroup(directory: currentGroupDirectory, parentGroup: currentGroup)
			}

			return currentGroup
		}
		else {
			return createGroup(directory: directory, parentGroup: startGroup)
		}
	}

	// MARK: > Create.
	public func createGroup(directory: URL, parentGroup: XcodeObjectGroup?) -> XcodeObjectGroup?
	{
		let group: XcodeObjectGroup = createObject()

		// Resolve group to use as target.
		guard let finalParentGroup = (parentGroup ?? self.rootProject?.mainGroup) else {
			return nil
		}

		// Add reference.
		group.addReference(from: finalParentGroup)

		// Resolve parent group path.
		let parentGroupURL: URL

		if let (_, groupURLOpt) = resolveGroupPath(finalParentGroup), let groupURL = groupURLOpt {
			parentGroupURL = groupURL
		} else {
			parentGroupURL = self.projectDirectory
		}

		// Add our new group to parent group cildren.
		if let children = finalParentGroup.children {
			children.append(group)
		}
		else
		{
			let children = XcodeArray()

			children.append(group)
			finalParentGroup.children = children
		}

		// Setup new group.
		group.name = directory.lastPathComponent
		group.path = FilePath(directory.relativePath(from: parentGroupURL))
		group.sourceTree = "<group>"

		return group
	}

	// MARK: > Resolve
	public func resolveFileReferencePath(_ fileRef: XcodeObjectFileReference) -> (location: FilePath, absoluteURL: URL?)?
	{
		// Get properties.
		guard let path = fileRef.path else {
			return nil
		}

		guard let sourceTree = fileRef.sourceTree else {
			return nil
		}

		let pathComponents = path.components

		// Handle special source tree.
		if let result = resolveSpecialSourceTree(components: pathComponents, sourceTree: sourceTree) {
			return result
		}

		// Handle file in group.
		// > Search the parent group.
		guard let fileGroup = fileRef.parentGroup else {
			return (location: FilePath(root: "/", pathComponents), absoluteURL: nil)
		}

		// > Resolve group path.
		guard let (groupLocation, groupURLOpt) = resolveGroupPath(fileGroup) else {
			return nil
		}

		let fileLocation = groupLocation.appending(pathComponents)

		guard let groupURL = groupURLOpt else {
			return (location: fileLocation, absoluteURL: nil)
		}

		return (location: fileLocation, absoluteURL: groupURL.appending(path: path.string).canonical)
	}

	public func resolveGroupPath(_ group: XcodeObjectGroup) -> (location: FilePath, absoluteURL: URL?)?
	{
		var pathComponents = FilePath.ComponentView()
		var runningGroup = group

		// Rewind hierarchy.
		while true
		{
			// > If there is no source tree, return only the location (it's probably incomplete, so an absolute URL is dangerous).
			guard let sourceTree = group.sourceTree else {
				return (location: FilePath(root: "/", pathComponents), absoluteURL: nil)
			}

			// > Resolve special source tree.
			if let result = resolveSpecialSourceTree(components: pathComponents, sourceTree: sourceTree) {
				return result
			}

			// > Insert path if there is one.
			if let path = runningGroup.path {
				pathComponents.insert(contentsOf: path.components, at: pathComponents.startIndex)
			}

			// > Search parent.
			if let parent = runningGroup.parentGroup {
				runningGroup = parent
			}
			else
			{
				let location = FilePath(root: nil, pathComponents)
				let url = self.projectDirectory.appending(path: location.string).canonical

				return (location: location, absoluteURL: url)
			}
		}
	}

	private func resolveSpecialSourceTree(components: FilePath.ComponentView, sourceTree: String) -> (location: FilePath, absoluteURL: URL?)?
	{
		var pathComponents = components

		// Relative to built product directory.
		if sourceTree == "BUILT_PRODUCTS_DIR"
		{
			pathComponents.insert("$(BUILT_PRODUCTS_DIR)", at: pathComponents.startIndex)

			return (location: FilePath(root: nil, pathComponents), absoluteURL: nil)
		}

		// Relative to SDK root.
		else if sourceTree == "SDKROOT" {
			return (location: FilePath(root: "/", pathComponents), absoluteURL: nil)
		}

		// Relative to source root (project directory).
		else if sourceTree == "SOURCE_ROOT"
		{
			let location = FilePath(root: nil, pathComponents)
			let url = self.projectDirectory.appending(path: location.string).canonical

			return (location: location, absoluteURL: url)
		}

		// Relative to developer directory.
		else if sourceTree == "DEVELOPER_DIR"
		{
			pathComponents.insert("$(DEVELOPER_DIR)", at: pathComponents.startIndex)

			return (location: FilePath(root: nil, pathComponents), absoluteURL: nil)
		}

		// Absolute.
		else if sourceTree == "<absolute>"
		{
			let location = FilePath(root: "/", pathComponents)
			let url = URL(fileURLWithPath: location.string).canonical

			return (location: location, absoluteURL: url)
		}

		return nil
	}

	// MARK: > Search
	public func searchFileReference(for fileURL: URL) -> XcodeObjectFileReference?
	{
		guard let sections = self.objects else {
			return nil
		}

		guard let section = sections[XcodeObjectFileReference.isa] else {
			return nil
		}

		let fileURLCanonical = fileURL.canonical

		for (_, obj) in section
		{
			if let fileRef = obj as? XcodeObjectFileReference, let (_, fileURLOpt) = resolveFileReferencePath(fileRef), let fileURL = fileURLOpt, fileURL == fileURLCanonical {
				return fileRef
			}
		}

		return nil
	}

	public func searchGroup(for directoryURL: URL) -> XcodeObjectGroup?
	{
		guard let sections = self.objects else {
			return nil
		}

		guard let section = sections[XcodeObjectGroup.isa] else {
			return nil
		}

		let directoryURLCanonical = directoryURL.canonical

		for (_, obj) in section
		{
			if let group = obj as? XcodeObjectGroup, let (_, groupURLOpt) = resolveGroupPath(group), let groupURL = groupURLOpt, groupURL == directoryURLCanonical {
				return group
			}
		}

		return nil
	}
}
