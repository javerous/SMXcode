/*
 * XcodeWorkspace.swift
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
// MARK: - XcodeWorkspace
//
public class XcodeWorkspace
{
	// MARK: Types
	// MARK: > Error.
	public enum RenderError: Error, CustomStringConvertible
	{
		case render (String)
		
		public var description: String
		{
			switch self
			{
				case .render(let str):
					return "render - \(str)"
			}
		}
	}
	
	// MARK: > Xcode Project
	public struct XcodeProjectReference: Equatable
	{
		public let url: URL
		public let location: FilePath

		fileprivate let node: XMLNode
	}
	
	
	// MARK: Properties
	public let workspaceFile: URL
	public let workspaceBundle: URL
	public let workspaceDirectory: URL
	
	private let _xmlDoc: XMLDocument
	private var _xcodeProjects:[XcodeProjectReference]? = nil
	
	
	// MARK: Instance
	public init(workspace: URL) throws
	{
		// Read content.
		var tryWorkspaceFile = workspace
		
		let xmlDoc: XMLDocument
		let xmlOptions: XMLNode.Options = [
			.nodeLoadExternalEntitiesNever,
			.nodePreserveAll
		]
		
		if tryWorkspaceFile.lastPathComponent != "contents.xcworkspacedata" {
			tryWorkspaceFile.append(component: "contents.xcworkspacedata")
		}
		
		xmlDoc = try XMLDocument(contentsOf: tryWorkspaceFile, options: xmlOptions)
		
		workspaceFile = tryWorkspaceFile
		workspaceBundle = workspaceFile.deletingLastPathComponent()
		workspaceDirectory = workspaceBundle.deletingLastPathComponent()
		
		// Hold document.
		_xmlDoc = xmlDoc
	}
	
	
	// MARK: Content
	public var xcodeProjecsCount: Int
	{
		get { return xcodeProjectsCache().count }
	}
	
	public func xcodeProject(at index: Int) -> XcodeProjectReference
	{
		return xcodeProjectsCache()[index]
	}
	
	@discardableResult
	public func appendXcodeProject(url inProject: URL, absolute: Bool = false) -> XcodeProjectReference
	{
		return insertXcodeProject(url: inProject, absolute: absolute, at: xcodeProjecsCount)
	}
	
	@discardableResult
	public func insertXcodeProject(url inProject: URL, absolute: Bool = false, at index: Int) -> XcodeProjectReference
	{
		// Clean input URL.
		var projectURL = inProject
		
		if projectURL.lastPathComponent == "project.pbxproj" {
			projectURL.deleteLastPathComponent()
		}
		
		// Build projects cache.
		xcodeProjectsCache()
		
		// Create node.
		let element = XMLElement(name: "FileRef", stringValue: nil)
		let location: FilePath

		if absolute
		{
			location = FilePath(projectURL.path)
			element.setAttributesWith(["location": "absolute:\(location)"])
		}
		else
		{
			location = FilePath(projectURL.relativePath(from: workspaceDirectory))
			element.setAttributesWith(["location": "container:\(location)"])
		}

		// Add node in XML doc.
		if let rootElement = _xmlDoc.rootElement() {
			rootElement.addChild(element)
		}
		else
		{
			let rootElement = XMLElement(name: "Workspace")
			
			rootElement.addChild(element)
			
			_xmlDoc.setRootElement(rootElement)
		}
		
		// Add entry.
		let project = XcodeProjectReference(url: projectURL.canonical, location: location, node: element)
		
		_xcodeProjects?.insert(project, at: index)
		
		return project
	}
	
	@discardableResult
	public func removeXcodeProject(url: URL) -> Bool
	{
		let canonicalURL = url.canonical
		
		// Build projects cache.
		let projects = xcodeProjectsCache()
		
		for (i, project) in projects.enumerated()
		{
			if project.url == canonicalURL
			{
				_xcodeProjects?.remove(at: i)
				
				return removeRootChildNode(project.node)
			}
		}
		
		return false
	}
	
	@discardableResult
	public func removeXcodeProject(project: XcodeProjectReference) -> Bool
	{
		// Build projects cache.
		let projects = xcodeProjectsCache()
		
		guard let idx = projects.firstIndex(of: project) else {
			return false
		}
		
		// Remove project matching.
		_xcodeProjects?.remove(at: idx)
		
		return removeRootChildNode(project.node)
	}
	
	// MARK: Output
	public func write(to: URL? = nil) throws
	{
		// Render content.
		let content = try content()
		
		// Write.
		try content.write(to: (to ?? workspaceFile), atomically: true, encoding: .utf8)
	}
	
	public func content() throws -> String
	{
		let writer = LinesWriter(identationString: "   ")
		
		// Add header.
		writer.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
		
		// Render root node.
		if let rootElement = _xmlDoc.rootElement() {
			try Self.render(writer: writer, node: rootElement)
		}
		
		// Create string.
		var result = writer.lines().joined(separator: "\n")
		
		result.append("\n")
		
		// Return.
		return result
	}

	private func removeRootChildNode(_ node: XMLNode) -> Bool
	{
		guard let root = _xmlDoc.rootElement() else {
			return false
		}

		let count = root.childCount

		for i in 0 ..< count
		{
			guard let child = root.child(at: i) else {
				continue
			}

			if child == node
			{
				root.removeChild(at: i)
				return true
			}
		}

		return false
	}


	// MARK: Render
	private static let escapedAttributesCharacters = [
		("&", "&amp;"),
		("<", "&lt;"),
		(">", "&gt;"),
		("'", "&apos;"),
		("\"", "&quot;"),
	]
	
	private static func render(writer: LinesWriter, node: XMLNode) throws
	{
		guard let name = node.name else {
			throw RenderError.render("XML node doesn't have name")
		}
		
		// Open entry.
		writer.append("<\(name)")
		writer.increaseIndentation()
		
		// > Render attributes.
		var attributeParts = [String]()
		
		if let element = node as? XMLElement, let attributes = element.attributes
		{
			for attributeNode in attributes
			{
				// >> Get "key / value".
				guard let attributeName = attributeNode.name, var attributeValue = attributeNode.stringValue else {
					throw RenderError.render("XML node have invalid attributes")
				}
				
				// >> Encode value.
				for set in Self.escapedAttributesCharacters {
					attributeValue = attributeValue.replacingOccurrences(of: set.0, with: set.1, options: .literal)
				}
				
				guard let transformedAttributeValue = attributeValue.applyingTransform(.toXMLHex, reverse: false) else {
					throw RenderError.render("can't create XML representation of attribute '\(attributeName)'")
				}
				
				attributeValue = transformedAttributeValue
				
				// >> Append pair.
				attributeParts.append("\(attributeName) = \"\(attributeValue)\"")
			}
		}
		
		let attributesString = attributeParts.joined(separator: " ")
		
		writer.append("\(attributesString)>")
		
		// > Render child.
		if let children = node.children
		{
			for child in children {
				try render(writer: writer, node: child)
			}
		}
		
		// Close entry.
		writer.decreaseIndentation()
		writer.append("</\(name)>")
	}


	// MARK: Helpers
	@discardableResult
	private func xcodeProjectsCache() -> [XcodeProjectReference]
	{
		// Return cache.
		if let projects = _xcodeProjects {
			return projects
		}

		// Compute cache.
		var result = [XcodeProjectReference]()

		if let rootElement = _xmlDoc.rootElement() {
			Self.listXcodeProjects(currentNode: rootElement, workspaceDirectory: workspaceDirectory, currentDirectory: workspaceDirectory, currentLocation: FilePath(), output: &result)
		}

		_xcodeProjects = result

		return result
	}

	static private func listXcodeProjects(currentNode: XMLNode, workspaceDirectory: URL, currentDirectory: URL, currentLocation: FilePath, output: inout [XcodeProjectReference])
	{
		// Fetch children.
		guard let children = currentNode.children else {
			return
		}

		// Handle children.
		for child in children
		{
			// > Get location of this child.
			guard let element = child as? XMLElement, let attribute = element.attribute(forName: "location"), let location = attribute.stringValue else {
				continue
			}

			// > Resolve location.
			let nodeLocation: FilePath
			let nodeURL: URL

			if let groupRange = location.range(of: "group:", options: [ .anchored ])
			{
				let cleanLocation = String(location[groupRange.upperBound...])

				nodeLocation = currentLocation.appending(cleanLocation)
				nodeURL = currentDirectory.appending(path: cleanLocation)
			}
			else if let containerRange = location.range(of: "container:", options: [ .anchored ])
			{
				let cleanLocation = String(location[containerRange.upperBound...])

				nodeLocation = FilePath(cleanLocation)
				nodeURL = workspaceDirectory.appending(path: cleanLocation)
			}
			else if let absoluteRange = location.range(of: "absolute:", options: [ .anchored ])
			{
				let cleanLocation = String(location[absoluteRange.upperBound...])

				nodeLocation = FilePath(cleanLocation)
				nodeURL = URL(filePath: cleanLocation)
			}
			else {
				continue
			}

			// > Handle child type.
			switch child.name
			{
				case "FileRef":
					// > Filter-out non-xcode.
					guard nodeURL.pathExtension == "xcodeproj" else {
						continue
					}

					// > Add entry.
					output.append(XcodeProjectReference(url: nodeURL.standardizedFileURL, location: nodeLocation, node: child))

				case "Group":
					listXcodeProjects(currentNode: child, workspaceDirectory: workspaceDirectory, currentDirectory: nodeURL, currentLocation: nodeLocation, output: &output)

				default:
					continue
			}
		}
	}
}
