/*
 * XcodeConfig.swift
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


// Thanks to Mattt and his very helpful article https://nshipster.com/xcconfig/

import Foundation
import Collections
import System


//
// MARK: - XcodeConfig
//
public class XcodeConfig
{
	// MARK: Types
	// MARK: > Error
	public enum ParseError: Error
	{
		case invalidLine(String)
		
		// Include.
		case missingOpeningQuoteInInclude
		case missingClosingQuoteInInclude
		case unexpectedCharactersAfterInclude
		
		
		// Configuration.
		// > Key.
		case misingKeyInConfiguration
		
		// > Conditional.
		case invalidConditionalKeyInConfiguration(String)
		case misingConditionalEqualInConfiguration
		case misingClosingConditionalBraketInConfiguration
		
		// > Equal.
		case misingEqualInConfiguration
		
		// > Value.
		case misingClosingQuoteInConfigurationValue
		case misingUnfinishedEscapeSequenceInConfigurationValue
		case unknownEscapeSequenceInConfigurationValue(Character)
		
		case unexpectedCharactersAfterConfiguration
	}

	// MARK: > Aliases
	public typealias ConfigTree = DictionaryObject<String, Any>

	// MARK: > Value
	public struct Content
	{
		fileprivate init(source: XcodeConfig, values: Array<String>)
		{
			self.source = source
			self.values = values
		}
		
		public private(set) weak var source: XcodeConfig?
		public let values: Array<String>
	}
	
	// MARK: > Conditionals
	public struct Conditionals
	{
		private static let configKey = "config"
		private static let sdkKey = "sdk"
		private static let archKey = "arch"
		
		public init(configuration: String? = nil, sdk: String? = nil, architecture: String? = nil)
		{
			if let value = configuration {
				self.configuration = value
			}
			
			if let value = sdk {
				self.sdk = value
			}
			
			if let value = architecture {
				self.architecture = value
			}
		}
		
		fileprivate init(storage: OrderedDictionary<String, String>) throws
		{
			let validKeys = Set<String>(arrayLiteral: Self.configKey, Self.sdkKey, Self.archKey)
			
			for (key, _) in storage
			{
				if !validKeys.contains(key) {
					throw ParseError.invalidConditionalKeyInConfiguration(key)
				}
			}
			
			self._storage = storage
		}
		
		public var configuration: String
		{
			get { return _storage[Self.configKey] ?? "*"  }
			set { _storage[Self.configKey] = (newValue == "*" ? nil : newValue) }
		}
		
		public var sdk: String
		{
			get { return _storage[Self.sdkKey] ?? "*"  }
			set { _storage[Self.sdkKey] = (newValue == "*" ? nil : newValue) }
		}
		
		public var architecture: String
		{
			get { return _storage[Self.archKey] ?? "*"  }
			set { _storage[Self.archKey] = (newValue == "*" ? nil : newValue) }
		}

		public var render: String
		{
			var str = String()

			for (condKey, condValue) in _storage {
				str.append("[\(condKey)=\(condValue)]")
			}

			return str
		}

		// Use a dictionary to keep ordering.
		fileprivate var _storage = OrderedDictionary<String, String>()
	}
	
	// MARK: > Line
	public enum Line
	{
		case include(path: FilePath, optional: Bool, resolvedURL:URL, config: XcodeConfig? = nil)
		case comment(String)
		case config(key:String, conditionals: Conditionals, values: Array<String>, comment: String?)
		case empty
	}
	
	
	// MARK: Properties
	public let configFile: URL
	public let configDirectory: URL
	
	private var _lines = [Line]()
	private var _downstreamIncludes = NSHashTable<XcodeConfig>.weakObjects()
	
	// Levels:
	// [0] -> Config name.
	// [1] -> SDK.
	// [2] -> Architecture.
	// [3] -> key -> value.
	public let configTree = ConfigTree() // We don't need ordered dictionary, but I don't want to deal with annoying nested value containers.

	
	// MARK: Instance
	public convenience init(configuration: URL, includes: Bool = false) throws
	{
		var includesBucket = Set<URL>()
		
		try self.init(configuration: configuration, includes: includes, includesBucket: &includesBucket)
	}
	
	private init(configuration: URL, includes: Bool, includesBucket: inout Set<URL>) throws
	{
		// Forge URLs.
		self.configFile = configuration.canonical
		self.configDirectory = self.configFile.deletingLastPathComponent()
		
		includesBucket.insert(self.configFile)
		
		// Read content.
		let string = try String(contentsOf: configuration, encoding: .utf8)
		let lines = string.components(separatedBy: .newlines)
		
		// Parse lines.
		var included = [XcodeConfig]()
		
		for line in lines
		{
			let pline = try Self.parseLine(line, configDirectory:self.configDirectory)
			
			// > Handle include (load it).
			if case let .include(path, optional, resolvedURL, _) = pline
			{
				var config: XcodeConfig? = nil
				
				// > We don't support circular inclusion, or diamond-like inclusions. We use `includesBucket` to block these scenarios.
				if includes && includesBucket.contains(resolvedURL) == false
				{
					includesBucket.insert(resolvedURL)
					
					if optional {
						config = try? XcodeConfig(configuration: resolvedURL, includes: true, includesBucket: &includesBucket)
					} else {
						config = try XcodeConfig(configuration: resolvedURL, includes: true, includesBucket: &includesBucket)
					}
					
					if let config = config {
						included.append(config)
					}
				}
				
				_lines.append(.include(path: path, optional: optional, resolvedURL: resolvedURL, config: config))
				
				continue
			}
			
			// > Add parsed line.
			_lines.append(pline)
		}
		
		// Link us to included config, so we are notified when it change, so we can update our own config tree.
		for include in included {
			include._downstreamIncludes.add(self)
		}
		
		// Update our configuration tree.
		updateConfigurationTree()
	}
	
	
	// MARK: Output
	public func write(lines: [Line]? = nil, to: URL? = nil) throws
	{
		// Render content.
		let content = try content(lines: lines)
		
		// Write.
		try content.write(to: (to ?? configFile), atomically: true, encoding: .utf8)
	}
	
	public func content(lines: [Line]? = nil) throws -> String
	{
		let writer = LinesWriter()
		
		// Render root dictionary.
		try Self.render(writer: writer, lines: (lines ?? _lines))
		
		// Create string.
		return writer.lines().joined(separator: "\n")
	}
	
	
	// MARK: Render
	private static let _quotableStringCharSet = CharacterSet.whitespaces
	
	private static func render(writer: LinesWriter, lines: [Line]) throws
	{
		for line in lines
		{
			switch line
			{
				case .include(let path, let optional, _, _):
					
					if optional {
						writer.append("#include? \"\(path.string)\"")
					} else {
						writer.append("#include \"\(path.string)\"")
					}
					
				case .comment(let comment):
					if comment.isEmpty {
						writer.append("//")
					} else {
						writer.append("// \(comment)")
					}
					
				case .config(let key, let conditionals, let values, let comment):
					var line = String()
					
					line.append(key)
					line.append(conditionals.render)
					line.append(" =")
					
					for value in values
					{
						var escapedString = value
						
						escapedString = escapedString.replacingOccurrences(of: "\\", with: "\\\\")
						escapedString = escapedString.replacingOccurrences(of: "\"", with: "\\\"")
						escapedString = escapedString.replacingOccurrences(of: "\t", with: "\\t")
						escapedString = escapedString.replacingOccurrences(of: "\n", with: "\\n")
						
						line.append(" ")
						
						if value.rangeOfCharacter(from: _quotableStringCharSet) != nil || value.count == 0 {
							line.append("\"\(escapedString)\"")
						} else {
							line.append(escapedString)
						}
					}
					
					if let comment = comment
					{
						if comment.isEmpty {
							line.append(" //")
						} else {
							line.append(" // \(comment)")
						}
					}
					
					writer.append(line)
					
				case .empty:
					writer.appendRaw("")
			}
		}
	}
	
	
	// MARK: Parse
	private static func parseLine(_ line: String, configDirectory: URL) throws -> Line
	{
		let scanner = line.parseScanner()
		
		// Trim.
		let _ = scanner.scanCharacters(from: Scanner._whitespacesSet)
		
		// Scan line.
		if scanner.currentIndex == line.endIndex {
			return .empty
		} else if let comment = scanner.scanComment() {
			return .comment(comment)
		}
		else if let (path, optional) = try scanner.scanInclude()
		{
			let resolvedURL: URL
			
			if path.isAbsolute {
				resolvedURL = URL(filePath: path.string).canonical
			} else {
				resolvedURL = configDirectory.appending(path: path.string).canonical
			}
			
			return .include(path: path, optional: optional, resolvedURL: resolvedURL, config: nil)
		}
		else if let (key, conditionals, values, comment) = try scanner.scanConfig() {
			return .config(key: key, conditionals: conditionals, values: values, comment: comment)
		} else {
			throw ParseError.invalidLine(line)
		}
	}
	
	
	// MARK: Content
	public func valueForKey(key: String, configuration: String = "*", sdk: String = "*", architecture: String = "*") -> Content?
	{
		return Self.contentForKeyFromTree(tree: configTree, key: key, configuration: configuration, sdk: sdk, architecture: architecture)
	}

	public func valueForKey(key: String, conditionals: Conditionals) -> Content?
	{
		return Self.contentForKeyFromTree(tree:configTree, key:key, conditionals: conditionals)
	}

	public var linesCount: Int
	{
		get { return _lines.count }
	}
	
	public func line(at index: Int) -> Line
	{
		return _lines[index]
	}
	
	public func appendLine(_ newElement: Line)
	{
		_lines.append(newElement)
		updateConfigurationTree()
	}
	
	public func insertLine(_ anObject: Line, at index: Int)
	{
		_lines.insert(anObject, at: index)
		updateConfigurationTree()
	}
	
	public func removeLine(at index: Int)
	{
		_lines.remove(at: index)
		updateConfigurationTree()
	}
	
	public func replaceLine(at index: Int, with anObject: Line)
	{
		_lines[index] = anObject
		updateConfigurationTree()
	}
	
	
	// MARK: Tree
	private func updateConfigurationTree()
	{
		// Flush our config tree.
		configTree.removeAll()
		
		// Update our config tree.
		for line in _lines
		{
			// > Integrate our own config line.
			if case let .config(key, conditionals, values, _) = line {
				Self.integrateContentInTree(tree: configTree, key: key, conditionals: conditionals, content: Content(source: self, values: values))
			}
			
			// > Integrate included config tree.
			else if case let .include(_, _, _, config) = line
			{
				guard let config = config else {
					continue
				}
				
				Self.integrateConfigurationTreeInTree(tree: configTree, sourceTree: config.configTree)
			}
		}
		
		// Brodcast update request to downstream.
		for config in _downstreamIncludes.allObjects {
			config.updateConfigurationTree()
		}
	}
	
	// MARK: > Integrate
	private static func integrateConfigurationTreeInTree(tree: ConfigTree, sourceTree: ConfigTree)
	{
		enumerateContentInTree(tree: sourceTree, block:{ (key: String, conditionals: Conditionals, content: Content) in
			integrateContentInTree(tree: tree, key: key, conditionals: conditionals, content: content)
		})
	}

	public static func integrateContentInTree<C>(tree: ConfigTree, key: String, conditionals: Conditionals, content: C)
	{
		// Extract conditional.
		let configConditional = conditionals.configuration
		let sdkConditional = conditionals.sdk
		let archConditional = conditionals.architecture

		// Walk in the tree.
		// > Config layer.
		let configLayer: DictionaryObject<String, Any>

		if let layer = tree[configConditional] as? DictionaryObject<String, Any> {
			configLayer = layer
		}
		else
		{
			configLayer = DictionaryObject<String, Any>()
			tree[configConditional] = configLayer
		}

		// > SDK layer.
		let sdkLayer: DictionaryObject<String, Any>

		if let layer = configLayer[sdkConditional] as? DictionaryObject<String, Any> {
			sdkLayer = layer
		}
		else
		{
			sdkLayer = DictionaryObject<String, Any>()
			configLayer[sdkConditional] = sdkLayer
		}

		// > Arch layer.
		let archLayer: DictionaryObject<String, C>

		if let layer = sdkLayer[archConditional] as? DictionaryObject<String, C> {
			archLayer = layer
		}
		else
		{
			archLayer = DictionaryObject<String, C>()
			sdkLayer[archConditional] = archLayer
		}

		// Set the content.
		archLayer[key] = content
	}

	// MARK: > Enumerate
	public static func enumerateContentInTree<C>(tree: ConfigTree, block: (_ key: String, _ conditionals: Conditionals, _ content: C) -> Void) -> Void
	{
		for (configKey, configLayerEntry) in tree
		{
			guard let configLayer = configLayerEntry as? DictionaryObject<String, Any> else {
				continue
			}

			for (sdkKey, sdkLayerEntry) in configLayer
			{
				guard let sdkLayer = sdkLayerEntry as? DictionaryObject<String, Any> else {
					continue
				}

				for (archKey, archLayerEntry) in sdkLayer
				{
					guard let archLayer = archLayerEntry as? DictionaryObject<String, C> else {
						continue
					}

					let conditionals = Conditionals(configuration: configKey, sdk: sdkKey, architecture: archKey)

					for (key, content) in archLayer {
						block(key, conditionals, content)
					}
				}
			}
		}
	}

	// MARK: > Content
	public static func contentForKeyFromTree<C>(tree: ConfigTree, key: String, configuration: String = "*", sdk: String = "*", architecture: String = "*") -> C?
	{
		let contents : DictionaryObject<String, C>? = contentsFromTree(tree: tree, key: key, configuration: configuration, sdk: sdk, architecture: architecture)
		
		return contents?[key]
	}

	public static func contentForKeyFromTree<C>(tree: ConfigTree, key: String, conditionals: Conditionals) -> C?
	{
		let contents : DictionaryObject<String, C>? = contentsFromTree(tree: tree, key: key, conditionals: conditionals)

		return contents?[key]
	}

	public static func contentsFromTree<C>(tree: ConfigTree, key: String, configuration: String = "*", sdk: String = "*", architecture: String = "*") -> DictionaryObject<String, C>?
	{
		guard let configLayer = tree[configuration] as? DictionaryObject<String, Any> else {
			return nil
		}
		
		guard let sdkLayer = configLayer[sdk] as? DictionaryObject<String, Any> else {
			return nil
		}
		
		if let archLayer = sdkLayer[architecture] as? DictionaryObject<String, C> {
			return archLayer
		} else {
			return nil
		}
	}

	public static func contentsFromTree<C>(tree: ConfigTree, key: String, conditionals: Conditionals) -> DictionaryObject<String, C>?
	{
		return contentsFromTree(tree: tree, key: key, configuration: conditionals.configuration, sdk: conditionals.sdk, architecture: conditionals.architecture)
	}


	// MARK: > Remove
	@discardableResult
	public static func removeKeyFromTree<C>(tree: ConfigTree, key: String, configuration: String = "*", sdk: String = "*", architecture: String = "*") -> C?
	{
		// Fetch the layers.
		guard let configLayer = tree[configuration] as? DictionaryObject<String, Any> else {
			return nil
		}

		guard let sdkLayer = configLayer[sdk] as? DictionaryObject<String, Any> else {
			return nil
		}

		guard let archLayer = sdkLayer[architecture] as? DictionaryObject<String, C> else {
			return nil
		}

		// Remove key.
		let result = archLayer.removeValue(forKey: key)

		// Cascade cleaning.
		if archLayer.count == 0 {
			sdkLayer.removeValue(forKey: architecture)
		}

		if sdkLayer.count == 0 {
			configLayer.removeValue(forKey: sdk)
		}

		if configLayer.count == 0 {
			tree.removeValue(forKey: configuration)
		}

		// Return previous content.
		return result
	}

	@discardableResult
	public static func removeKeyFromTree<C>(tree: ConfigTree, key: String, conditionals: Conditionals) -> C?
	{
		return removeKeyFromTree(tree: tree, key: key, configuration: conditionals.configuration, sdk: conditionals.sdk, architecture: conditionals.architecture)
	}
}


//
// MARK: - Error + StringConvertyble
//
extension XcodeConfig.ParseError: CustomStringConvertible
{
	public var description: String
	{
		switch self
		{
			case .invalidLine(let line):
				return "invalid line '\(line)'"
				
				
				
			case .missingOpeningQuoteInInclude:
				return "missing opening '\"' in include"
				
			case .missingClosingQuoteInInclude:
				return "missing opening '\"' in include"
				
			case .unexpectedCharactersAfterInclude:
				return "unexpected characters after include"
				
				
				
			case .misingKeyInConfiguration:
				return "missing configuration key"
				
			case .invalidConditionalKeyInConfiguration(let key):
				return "invalid conditional key '\(key)'"
				
			case .misingClosingConditionalBraketInConfiguration:
				return "missing closing ']' in configuration conditional"
				
				
				
			case .misingConditionalEqualInConfiguration:
				return "missing '=' in conditional"
				
				
			case .misingEqualInConfiguration:
				return "missing '=' between key and value in configuration"
				
				
			case .misingClosingQuoteInConfigurationValue:
				return "missing closing '\"' in value"
				
			case .misingUnfinishedEscapeSequenceInConfigurationValue:
				return "unfinished escape sequence"
				
			case .unknownEscapeSequenceInConfigurationValue(let char):
				return "unknown escape sequence \\\(char)"
				
			case .unexpectedCharactersAfterConfiguration:
				return "unexpected characters after configuration"
		}
	}
}


//
// MARK: - Scanner
//
public extension Scanner
{
	fileprivate static let _keyCharSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
	fileprivate static let _allCharacterSet = CharacterSet().inverted
	fileprivate static let _whitespacesSet = CharacterSet.whitespaces
	
	// MARK: Comment
	fileprivate func scanComment() -> String?
	{
		// Consume '//'.
		guard let _ = scanString("//") else {
			return nil
		}
		
		// Skip possible whitespace (single character, to don't totally break possible deliberate formating).
		var result = String()
		
		guard let char = scanCharacter() else {
			return ""
		}
		
		if !char.isWhitespace {
			result += String(char)
		}
		
		if let remaining = scanCharacters(from: Self._allCharacterSet) {
			result += remaining
		}
		
		return result
	}
	
	// MARK: Include
	fileprivate func scanInclude() throws -> (path: FilePath, optional: Bool)?
	{
		// Consume '#include' / '#include?'
		let optional: Bool
		
		if let _ = scanString("#include?") {
			optional = true
		} else if let _ = scanString("#include") {
			optional = false
		} else {
			return nil
		}
		
		// Skip whitespace.
		let _ = scanCharacters(from: Self._whitespacesSet)
		
		// Consume the opening '"'
		guard let _ = scanString("\"") else {
			throw XcodeConfig.ParseError.missingOpeningQuoteInInclude
		}
		
		// Scan up to closing '"'. Apparently, xcodeconfig doesn't support " inside the path, as it's not possible to escape one.
		guard let path = scanUpToString("\"") else {
			throw XcodeConfig.ParseError.missingClosingQuoteInInclude
		}
		
		// Consume the closing '"'
		let _ = scanCharacter()
		
		// Remove traling whitespace.
		let _ = scanCharacters(from: Self._whitespacesSet)
		
		guard self.currentIndex == self.string.endIndex else {
			throw XcodeConfig.ParseError.unexpectedCharactersAfterInclude
		}
		
		// Return
		return (path: FilePath(path), optional: optional)
	}
	
	// MARK: Config
	fileprivate func scanConfig() throws -> (key:String, conditionals: XcodeConfig.Conditionals, values: Array<String>, comment: String?)?
	{
		// Scan key and conditionals.
		let (key, conditionals) = try scanKeyCluster()
		
		// Skip possible whitespace after key cluster.
		let _ = scanCharacters(from: Self._whitespacesSet)
		
		// Consume '='.
		guard let _ = scanString("=") else {
			throw XcodeConfig.ParseError.misingEqualInConfiguration
		}
		
		// Skip possible whitespace after '='.
		let _ = scanCharacters(from: Self._whitespacesSet)
		
		// Scan values.
		let values = try scanValueCluster()
		
		// Skip possible whitespace after values cluster.
		let _ = scanCharacters(from: Self._whitespacesSet)
		
		// Scan end-of-line comment.
		let comment = scanComment()
		
		// Check we consumed everything.
		guard self.currentIndex == self.string.endIndex else {
			throw XcodeConfig.ParseError.unexpectedCharactersAfterConfiguration
		}
		
		// Return.
		return (key: key, conditionals: conditionals, values: values, comment: comment)
	}
	
	// > Key Cluster (key + conditionals)
	func scanKeyCluster() throws -> (key: String, conditionals: XcodeConfig.Conditionals)
	{
		// Extract key.
		guard let key = scanCharacters(from: Self._keyCharSet), key.count > 0 else {
			throw XcodeConfig.ParseError.misingKeyInConfiguration
		}
		
		// Extract conditionals.
		var conditionals = OrderedDictionary<String, String>()
		
		while true
		{
			// > Check if we have an actual conditionals. Spaces aren't supported between conditionals.
			guard let _ = scanString("[") else {
				break
			}
			
			// > Check if it's an empty conditional.
			if let _ = scanString("]") {
				break
			}
			
			// > Scan up to conditional close. It's not support to have a conditional value with an ']' inside.
			guard let conditional = scanUpToString("]") else {
				throw XcodeConfig.ParseError.misingClosingConditionalBraketInConfiguration
			}
			
			let _ = scanCharacter()
			
			// > Search for the first '=' (conditional values can contain an '=', for configurations names, for example)
			guard let equalRange = conditional.firstRange(of: "=") else {
				throw XcodeConfig.ParseError.misingConditionalEqualInConfiguration
			}
			
			// > Extract key/value.
			let conditionalKey = String(conditional[..<equalRange.lowerBound])
			let conditionalValue = String(conditional[equalRange.upperBound...])
			
			conditionals[conditionalKey] = conditionalValue
		}
		
		return (key: key, conditionals: try XcodeConfig.Conditionals(storage: conditionals))
	}
	
	// > Value Cluster (values)
	private func scanValueCluster() throws -> Array<String>
	{
		var result = Array<String>()
		
		var inQuote: Bool = false
		var lastEscaped = false
		var value = String()
		
		while true
		{
			// Comments are brutal finish (they can't be escaped, and are recognized inside quoted string).
			let beforeIndex = self.currentIndex
			
			if let _ = scanString("//") {
				if inQuote {
					throw XcodeConfig.ParseError.misingClosingQuoteInConfigurationValue
				} else if lastEscaped {
					throw XcodeConfig.ParseError.misingUnfinishedEscapeSequenceInConfigurationValue
				}
				
				if value.count > 0 {
					result.append(value)
				}
				
				self.currentIndex = beforeIndex
				
				return result
			}
			
			// Get a character.
			guard let char = scanCharacter() else
			{
				if inQuote {
					throw XcodeConfig.ParseError.misingClosingQuoteInConfigurationValue
				} else if lastEscaped {
					throw XcodeConfig.ParseError.misingUnfinishedEscapeSequenceInConfigurationValue
				}
				
				if value.count > 0 {
					result.append(value)
				}
				
				return result
			}
			
			// Handle character. 
			// XXX - Can we make this common with what is done in XcodeProject ? Not that easy, because of slight different format with quote & spaces.
			if lastEscaped
			{
				switch char
				{
					case "n":
						value.append("\n")
						
					case "t":
						value.append("\t")
						
					case "\"":
						value.append("\"")
						
					case "\\":
						value.append("\\")
						
					default:
						throw XcodeConfig.ParseError.unknownEscapeSequenceInConfigurationValue(char)
				}
				
				lastEscaped = false
			}
			else if inQuote
			{
				if char == "\""
				{
					result.append(value)
					
					value = ""
					inQuote = false
				}
				else if char == "\\" {
					lastEscaped = true
				} else {
					value.append(char)
				}
			}
			else if char == "\"" {
				inQuote = true
			} else if char == "\\" {
				lastEscaped = true
			}
			else if char.isWhitespace
			{
				let _ = scanCharacters(from: Self._whitespacesSet)
				
				if value.count > 0 {
					result.append(value)
				}
				
				value = ""
			}
			else {
				value.append(char)
			}
		}
	}
}
