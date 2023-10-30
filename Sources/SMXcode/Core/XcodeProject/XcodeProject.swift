/*
 * XcodeProject.swift
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
// MARK: - XcodeProjectdescribing
//
public class XcodeProject
{
	// MARK: Types
	// MARK: > Error
	public enum ParseError: Error
	{
		case rootDictionaryNotFound
		case quotedStringNotClosed
		case objectsNotFound
		case invalidObjectsKeyType(key: XcodeLiteral)
		case invalidObjectsValueType(key: XcodeLiteral)
		case invalidLinking
		case objectsNotFoundPostLinking
		case invalidEntryInObjects(entry: Any)
		case misingStringClosingQuote(str: String)
		case unknownEscapeSequence(Character)
		case unexpectedString(expected: String, got: String)
	}
	
	public enum RenderError: Error
	{
		case unknownEntryType(entry: Any)
	}
	
	// MARK: Properties
	public let root: XcodeDictionary
	public let projectName: String
	public let projectFile: URL
	public let projectBundle: URL
	public let projectDirectory: URL
	

	// MARK: Conveniences
	// > Root project.
	public static let rootObjectKey = "rootObject"

	public var rootProject: XcodeObjectProject?
	{
		get { return root[Self.rootObjectKey] }
	}
	
	// > Objects
	public static let objectsKey = "objects"

	public var objects: XcodeSections?
	{
		get { root[Self.objectsKey] }
	}
	
	// MARK: Instance
	public init(project: URL) throws
	{
		// Parse content.
		var rootDict: XcodeDictionary
		var tryProjectFile = project
		
		if tryProjectFile.lastPathComponent != "project.pbxproj" {
			tryProjectFile.append(component: "project.pbxproj")
		}
		
		rootDict = try Self.parse(contentsOf: tryProjectFile)
		
		projectFile = tryProjectFile
		projectBundle = projectFile.deletingLastPathComponent()
		projectDirectory = projectBundle.deletingLastPathComponent()
		projectName = projectBundle.deletingPathExtension().lastPathComponent
		
		// Create objects.
		// > Fetch root objects dictionary.
		guard let objects: XcodeDictionary = rootDict[Self.objectsKey] else {
			throw ParseError.objectsNotFound
		}

		objects.isRootObjects = true

		// > Create objects from dictionaries.
		for key in objects.keys
		{
			guard case let .string(id) = key else {
				throw ParseError.invalidObjectsKeyType(key: key)
			}
			
			guard let value: XcodeDictionary = objects[key] else {
				throw ParseError.invalidObjectsValueType(key: key)
			}
			
			let object = try XcodeObjectFactory.createObjectFor(id: id, content: value)
			
			objects[key] = object

			// > Set project name.
			if let project = object as? XcodeObjectProject {
				project.projectName = projectName
			}
		}
		
		rootDict[Self.objectsKey] = objects
		
		// > Link references.
		guard let resolved = Self.link(objects: objects, content: rootDict, referencedBy: nil) as? XcodeDictionary else {
			throw ParseError.invalidLinking
		}
		
		rootDict = resolved
		
		// > Create sections.
		let sections = XcodeSections()
		
		guard let resolvedObjectsDict: XcodeDictionary = rootDict[Self.objectsKey] else {
			throw ParseError.objectsNotFoundPostLinking
		}
		
		for (key, entry) in resolvedObjectsDict
		{
			guard let object = entry as? XcodeObject else {
				throw ParseError.invalidEntryInObjects(entry: entry)
			}
			
			sections.addObjectForKey(key, object:object)
		}
		
		rootDict[.string(Self.objectsKey)] = sections
		
		// Store result.
		root = rootDict
	}
	
	
	// MARK: Output
	public func write(to: URL? = nil) throws
	{
		// Render string.
		let content = try content()
		
		// Write.
		try content.write(to: (to ?? projectFile), atomically: true, encoding: .utf8)
	}
	
	public func content() throws -> String
	{
		let writer = LinesWriter()
		
		// Add encoding.
		writer.append("// !$*UTF8*$!")
		
		// Render root dictionary.
		try Self.render(writer: writer, entry: root)
		
		// Create string.
		var result = writer.lines().joined(separator: "\n")
		
		result.append("\n")
		
		// Return.
		return result
	}
	
	
	// MARK: - Private
	private static let _quotableStringCharSet = Scanner._stringCharSet.inverted
	
	
	// MARK: Link
	private static func link(objects: XcodeDictionary, content: Any, referencedBy: XcodeObject?, silentLiterals: Bool = false) -> Any
	{
		if let dict = content as? XcodeDictionary {
			let ndict = XcodeDictionary()
			
			for (key, value) in dict
			{
				let nkey: XcodeLiteral
				var silentLiteral = silentLiterals
				
				if let obj: XcodeObject = objects[key]
				{
					// > Xcode official format doesn't show literal comment in this specific case, for an unknown reason, so we have to hack and bring a silent flag.
					silentLiteral = silentLiteral || (value is XcodeDictionary)
					
					nkey = .ref(obj.id, XcodeWeakObject(obj), silentLiteral)
				}
				else
				{
					// > Xcode official format doesn't show literal comment in this specific case, for an unknown reason, so we have to hack and bring a silent flag.
					silentLiteral = silentLiteral || (key.string == "remoteGlobalIDString")
					
					nkey = key
				}
				
				ndict[nkey] = link(objects:objects, content: value, referencedBy: referencedBy, silentLiterals: silentLiteral)
			}
			
			return ndict
		}
		else if let array = content as? XcodeArray
		{
			let narray = XcodeArray()
			
			for value in array {
				narray.append(link(objects:objects, content: value, referencedBy: referencedBy))
			}
			
			return narray
		}
		else if let literal = content as? XcodeLiteral, let obj: XcodeObject = objects[literal]
		{
			if let referencedBy = referencedBy {
				obj.addReference(from: referencedBy)
			}
			
			return XcodeLiteral.ref(obj.id, XcodeWeakObject(obj), silentLiterals)
		}
		else if let obj = content as? XcodeObject
		{
			if let resolved = link(objects: objects, content: obj.content, referencedBy: obj) as? XcodeDictionary {
				obj.content = resolved
			}
			
			return obj
		}
		
		return content
	}
	
	
	// MARK: Render
	private static func render(writer: LinesWriter, entry: Any) throws
	{
		// Helper.
		let renderKeyValue = { (key: XcodeLiteral, value: Any) throws in
			try render(writer: writer, entry: key)
			
			writer.nextAppendOnSameLine = true
			writer.append(" = ")
			
			writer.nextAppendOnSameLine = true
			try render(writer: writer, entry: value)
			
			writer.nextAppendOnSameLine = true
			writer.append(";")
			
			if writer.isSingleLineMode
			{
				writer.nextAppendOnSameLine = true
				writer.append(" ")
			}
		}
		
		// Handle entry.
		// > Sections.
		if let sections = entry as? XcodeSections
		{
			writer.append("{")
			writer.increaseIndentation()
			
			for (name, section) in sections
			{
				writer.appendRaw("")
				writer.appendRaw("/* Begin \(name) section */")
				
				for (key, value) in section {
					try renderKeyValue(key, value)
				}
				
				writer.appendRaw("/* End \(name) section */")
			}
			
			writer.decreaseIndentation()
			writer.append("}")
		}
		
		// > Dictionary.
		else if let dict = entry as? XcodeDictionary
		{
			writer.append("{")
			writer.increaseIndentation()
			
			for (key, value) in dict {
				try renderKeyValue(key, value)
			}
			
			writer.decreaseIndentation()
			writer.append("}")
		}
		
		// > Array.
		else if let array = entry as? XcodeArray
		{
			writer.append("(")
			writer.increaseIndentation()
			
			for value in array
			{
				try render(writer: writer, entry: value)
				
				writer.nextAppendOnSameLine = true
				writer.append(",")
				
				if writer.isSingleLineMode
				{
					writer.nextAppendOnSameLine = true
					writer.append(" ")
				}
			}
			
			writer.decreaseIndentation()
			writer.append(")")
		}
		
		// > Literal.
		else if let literal = entry as? XcodeLiteral
		{
			switch literal
			{
				case .string(let string):
					if string.rangeOfCharacter(from: _quotableStringCharSet) != nil || string.count == 0
					{
						var escapedString = string
						
						escapedString = escapedString.replacingOccurrences(of: "\\", with: "\\\\")
						escapedString = escapedString.replacingOccurrences(of: "\"", with: "\\\"")
						escapedString = escapedString.replacingOccurrences(of: "\t", with: "\\t")
						escapedString = escapedString.replacingOccurrences(of: "\n", with: "\\n")
						
						writer.append("\"\(escapedString)\"")
					}
					else {
						writer.append(string)
					}
					
				case .ref(let id, let weakObj, let silent):
					if let obj = weakObj.object, let comment = obj.renderComment, !silent {
						writer.append("\(id) /* \(comment) */")
					} else {
						writer.append("\(id)")
					}
			}
		}
		
		// > Object.
		else if let obj = entry as? XcodeObject
		{
			if obj.renderSingleLine {
				writer.pushSingleLineMode()
			}
			
			//writer.append("<object>")
			try render(writer: writer, entry: obj.content)
			
			if obj.renderSingleLine {
				writer.popSingleLineMode()
			}
		}
		
		// > Error.
		else {
			throw RenderError.unknownEntryType(entry: "<\(type(of:entry)); \(entry)>")
		}
	}
	
	
	// MARK: Parse
	// Note: we can use PropertyListDecoder, but it doesn't keep dictionary key orders.
	private static func parse(contentsOf: URL) throws -> XcodeDictionary
	{
		let str = try String(contentsOf: contentsOf, encoding: .utf8)
		let scanner = str.parseScanner()

		return try scanner.scanRoot()
	}
	
	
	// MARK: Content
	public func object(forID aID: String, isa: String? = nil) -> XcodeObject?
	{
		guard let entry: Any = root[.string("objects")] else {
			return nil
		}
		
		guard let sections = entry as? XcodeSections else {
			return nil
		}
		
		let idLiteral: XcodeLiteral = .string(aID)
		
		if let isa = isa
		{
			guard let section = sections[isa] else {
				return nil
			}
			
			return section[idLiteral]
		}
		else
		{
			for (_, section) in sections
			{
				if let obj = section[idLiteral] {
					return obj
				}
			}
			
			return nil
		}
	}
	
	public func setObject(_ anObject: XcodeObject)
	{
		guard let entry: Any = root[.string("objects")] else {
			return
		}
		
		guard let sections = entry as? XcodeSections else {
			return
		}
		
		sections.addObjectForKey(.ref(anObject.id, XcodeWeakObject(anObject), false), object: anObject)
	}
}

//
// MARK: - Error + StringConvertyble
//
extension XcodeProject.ParseError: CustomStringConvertible
{
	public var description: String
	{
		switch self
		{
			case .rootDictionaryNotFound:
				return "no root dictionary found"
				
			case .objectsNotFound:
				return "'objects' dictionary not found"
				
			case .invalidObjectsKeyType(let key):
				return "key '\(key)' from 'objects' is not a string"
				
			case .invalidObjectsValueType(let key):
				return "object with key '\(key)' from 'objects' is not a dictionary"
				
			case .invalidLinking:
				return "invalid linking"
				
			case .objectsNotFoundPostLinking:
				return "'objects' dictionary not found after linking"
				
			case .invalidEntryInObjects(let entry):
				return "invalid entry in objects: \(entry)"
				
			case .misingStringClosingQuote(let str):
				return "string '\(str)' not terminated"
				
			case .quotedStringNotClosed:
				return "missing quoted string closing '\"'"
				
			case .unknownEscapeSequence(let char):
				return "unknown escape sequence \\\(char)"
				
			case .unexpectedString(let expected, let got):
				return "expected \(expected), got \(got)"
		}
	}
}

extension XcodeProject.RenderError: CustomStringConvertible
{
	public var description: String
	{
		switch self
		{
			case .unknownEntryType(let entry):
				return "unknown type to render \(entry)"
		}
	}
}


//
// MARK: - Scanner
//
fileprivate extension Scanner
{
	static let _keyCharSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
	static let _stringCharSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/"))
	
	// MARK: Root
	func scanRoot() throws -> XcodeDictionary
	{
		// Cleaning.
		try clean()
		
		// Skip encoding.
		if scanString("//") != nil {
			let _ = scanCharacters(from: .newlines.inverted)
		}
		
		// Parse root dictionary.
		guard let rootDict = try scanDictionary() else {
			throw XcodeProject.ParseError.rootDictionaryNotFound
		}
		
		return rootDict
	}
	
	// MARK: Dictionary
	func scanDictionary() throws -> XcodeDictionary?
	{
		// Clean.
		try clean()
		
		// Check we have dictionary start.
		if scanString("{") == nil {
			return nil
		}
		
		// Parse keys - values.
		let result = XcodeDictionary()
		
		while true
		{
			// Cleaning.
			try clean()
			
			// Finish '}'.
			if scanString("}") != nil {
				break
			}
			
			// Parse key.
			let key: String
			
			if let qkey = try scanQuotedString() {
				key = qkey
			} else if let qkey = scanCharacters(from: Self._keyCharSet), qkey.count > 0 {
				key = qkey
			} else {
				throw createParseError(expectedString: "<key>")
			}
			
			// Cleaning.
			try clean()
			
			// Remove '='.
			if scanString("=") == nil {
				throw createParseError(expectedString: "'='")
			}
			
			// Parse value.
			result.updateValue(try scanValue(), forKey: .string(key))
			
			// Cleaning.
			try clean()
			
			// Remove separator.
			if scanString(";") == nil {
				throw createParseError(expectedString: "';'")
			}
		}
		
		// Result.
		return result
	}
	
	// MARK: Array
	func scanArray() throws -> XcodeArray?
	{
		// Cleaning.
		try clean()
		
		// Check we have array start.
		if scanString("(") == nil {
			return nil
		}
		
		// Parse values.
		let result = XcodeArray()
		
		while true
		{
			// Finish ')'.
			try clean()
			
			if scanString(")") != nil {
				break
			}
			
			// Parse value.
			result.append(try scanValue())
			
			// Cleaning.
			try clean()
			
			// Remove separator.
			if scanString(",") == nil {
				throw createParseError(expectedString: "','")
			}
		}
		
		// Result.
		return result
	}
	
	// MARK: Comment
	func scanComment() throws -> String?
	{
		// Clean whitespaces.
		let _ = scanCharacters(from: .whitespacesAndNewlines)
		
		// Consume the comment start.
		if scanString("/*") == nil {
			return nil
		}
		
		// Consume the comment.
		if let comment = scanUpToString("*/")
		{
			let _ = scanString("*/")
			
			return comment.trimmingCharacters(in: .whitespaces)
		}
		else {
			throw createParseError(expectedString: "'*/'")
		}
	}
	
	// MARK: String
	func scanQuotedString() throws -> String?
	{
		// Clean.
		try clean()
		
		// Consume the string start.
		if scanString("\"") == nil {
			return nil
		}
		
		// Forge result.
		var result = String()
		var lastEscaped = false
		
		while true
		{
			guard let char = scanCharacter() else {
				throw XcodeProject.ParseError.misingStringClosingQuote(str: result)
			}
			
			if lastEscaped
			{
				switch char
				{
					case "n":
						result.append("\n")
						
					case "t":
						result.append("\t")
						
					case "\"":
						result.append("\"")
						
					case "\\":
						result.append("\\")
						
					default:
						throw XcodeProject.ParseError.unknownEscapeSequence(char)
				}
				
				lastEscaped = false
			}
			else
			{
				if char == "\""{
					break
				}
				else if char == "\\"
				{
					lastEscaped = true
					continue
				}
				
				result.append(char)
			}
		}
		
		return result
	}
	
	// MARK: Value
	func scanValue() throws -> Any
	{
		let backupIndex = currentIndex
		
		self.currentIndex = backupIndex
		
		// Clean.
		try clean()
		
		// Try to parse.
		if let val = scanCharacters(from: Self._stringCharSet) {
			return XcodeLiteral.string(val)
		} else if let val = try scanQuotedString() {
			return XcodeLiteral.string(val)
		} else if let val = try scanDictionary() {
			return val
		} else if let val = try scanArray() {
			return val
		} else {
			self.currentIndex = backupIndex
			throw createParseError(expectedString: "<value>")
		}
	}
	
	// MARK: Helpers
	func createParseError(expectedString: String) -> XcodeProject.ParseError
	{
		let gotString: String
		
		if let char = scanCharacter()
		{
			var str = String(char)
			
			for _ in 1...20
			{
				if let charb = scanCharacter() {
					str += String(charb)
				} else {
					break
				}
			}
			
			gotString = "'\(str)'"
		}
		else {
			gotString = "<eos>"
		}
		
		return .unexpectedString(expected: expectedString, got: gotString)
	}
	
	@discardableResult
	func clean() throws -> [String]?
	{
		var comments = [String]()
		
		while true
		{
			// Clean whitespaces.
			let _ = scanCharacters(from: .whitespacesAndNewlines)
			
			// Extract comment.
			guard let comment = try scanComment() else {
				break
			}
			
			comments.append(comment)
		}
		
		// Remove possible trailing whitespaces.
		let _ = scanCharacters(from: .whitespacesAndNewlines)
		
		return comments
	}
}
