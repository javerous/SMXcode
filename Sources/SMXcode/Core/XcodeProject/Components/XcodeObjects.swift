/*
 * XcodeObjects.swift
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
// MARK: - XcodeObjectFactory
//
class XcodeObjectFactory
{
	// MARK: Types
	public enum CreateError: Error, CustomStringConvertible
	{
		case isa // `isa` is missing.

		public var description: String
		{
			switch self
			{
				case .isa: return "missing isa"
			}
		}
	}
	
	// MARK: Properties
	private static let typedObjects: [XcodeTypedObject.Type] = [
		XcodeObjectBuildConfiguration.self,
		XcodeObjectBuildFile.self,
		XcodeObjectBuildRule.self,
		XcodeObjectConfigurationList.self,
		XcodeObjectContainerItemProxy.self,
		XcodeObjectCopyFilesBuildPhase.self,
		XcodeObjectFileReference.self,
		XcodeObjectFrameworksBuildPhase.self,
		XcodeObjectGroup.self,
		XcodeObjectHeadersBuildPhase.self,
		XcodeObjectLegacyTarget.self,
		XcodeObjectNativeTarget.self,
		XcodeObjectProject.self,
		XcodeObjectReferenceProxy.self,
		XcodeObjectResourcesBuildPhase.self,
		XcodeObjectShellScriptBuildPhase.self,
		XcodeObjectSourcesBuildPhase.self,
		XcodeObjectTargetDependency.self,
   ]
	
	private static var typedObjectsMap = {
		var result = [String: XcodeTypedObject.Type]()

		for type in typedObjects {
			result[type.isa] = type
		}
		
		return result
	}()

	// MARK: Creation
	static func createObjectFor(id: String, content: XcodeDictionary) throws -> XcodeObject
	{
		guard let isa: String = content["isa"] else {
			throw CreateError.isa
		}
		
		// Search for a class implementing this `isa`. Else fallback to generic type.
		if let typedObject = Self.typedObjectsMap[isa]  {
			return typedObject.init(id: id, content: content)
		} else {
			return XcodeObject(isa:isa, id: id, content: content)
		}
	}
}



//
// MARK: - XcodeObject
//
public class XcodeObject
{
	// MARK: Statics
	public static let nameKey = "name"

	
	// MARK: Properties
	public let isa: String
	public let id: String
	public internal(set) var content: XcodeDictionary
	
	private var _referencedBy = NSHashTable<XcodeObject>.weakObjects()

	
	// MARK: Instance
	public required init(isa: String, content: XcodeDictionary)
	{
		// Sanitize content.
		content["isa"] = isa
		
		// Genereate id.
		var idData = Data(count: 12)
		
		idData.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
			arc4random_buf(bytes.baseAddress, 12)
		}

		// Hold content.
		self.isa = isa
		self.id = idData.map { String(format: "%02hhX", $0) }.joined()
		self.content = content
	}
	
	internal required init(isa: String, id: String, content: XcodeDictionary)
	{
		// Sanitize content.
		content["isa"] = isa

		// Hold content.
		self.isa = isa
		self.id = id
		self.content = content
	}
	
	
	// MARK: Render
	public var renderComment: String?
	{
		return self.name ?? self.isa
	}

	public var renderSingleLine : Bool
	{
		return false
	}

	
	// MARK: Convenience
	public var name: String?
	{
		get { return content[Self.nameKey] }
		set { content[Self.nameKey] = newValue }
	}

	// MARK: References
	public func addReference(from: XcodeObject)
	{
		_referencedBy.add(from)
	}
	
	public func referencedBy() -> [XcodeObject]
	{
		return _referencedBy.allObjects
	}

	public func removeReference(from: XcodeObject)
	{
		_referencedBy.remove(from)
	}
}


//
// MARK: - Typed XcodeObject
//

// MARK: Typed Machinery
// All this mess is only because
//   - We want to facilitate creation of object with pre-defined `isa`
//   - Because Swift doesn't have pure virtual classes.
//
// If we had pure virtual classes in Swift, it would have been possible to
//   - Define a `XcodeTypedObject` class
//   - Define a pure virtual `isa` property to this class
//   - Define a convenient init wich call `XcodeObject` init with this `isa` as parameter.
// -> Subclasses of `XcodeTypedObject` would just have to override the `isa` property.

// Create a type combination, so objects we add in `definedIsa` have to be `XcodeObject` *and* `XcodeTypedProtocol`.
public typealias XcodeTypedObject = XcodeObject & XcodeTypedProtocol

// Create a protocol, so we can generically get the `isa` of each typed object.
public protocol XcodeTypedProtocol
{
	static var isa: String { get }
}

// Create an extension to `XcodeTypedProtocol` (we can't extend `XcodeTypedObject`) to define a convenient init.
// We have to constrain Self to be have the `XcodeObject` initializer be accessible.
extension XcodeTypedProtocol where Self: XcodeTypedObject
{
	public init(id: String, content: XcodeDictionary)
	{
		self.init(isa: Self.isa, id: id, content: content)
	}

	public init(content: XcodeDictionary)
	{
		self.init(isa: Self.isa, content: content)
	}
}


// MARK: XcodeObjectBuildConfiguration
public class XcodeObjectBuildConfiguration: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "XCBuildConfiguration"

	// Convenience.
	// > Base configuration reference.
	public static let baseConfigurationReferenceKey = "baseConfigurationReference"

	public var baseConfigurationReference: XcodeObjectFileReference?
	{
		get { return content[Self.baseConfigurationReferenceKey] }
		set { content[Self.baseConfigurationReferenceKey] = newValue }
	}

	// > Build settings.
	public static let buildSettingsKey = "buildSettings"

	public var buildSettings: XcodeDictionary?
	{
		get { return content[Self.buildSettingsKey] }
		set { content[Self.buildSettingsKey] = newValue }
	}
}


// MARK: XcodeObjectBuildFile
public class XcodeObjectBuildFile: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "PBXBuildFile"
	
	public override var renderComment: String?
	{
		if let fileRef: XcodeObject = content["fileRef"], let fileRefRenderComment = fileRef.renderComment, let parentBuildPhaseRenderComment = _parentBuildPhase?.renderComment {
			return "\(fileRefRenderComment) in \(parentBuildPhaseRenderComment)"
		}

		return nil
	}
	
	public override func addReference(from: XcodeObject)
	{
		super.addReference(from: from)
		
		if from is XcodeObjectBuildPhase {
			_parentBuildPhase = from
		}
	}

	public override func removeReference(from: XcodeObject)
	{
		super.removeReference(from: from)

		if _parentBuildPhase?.id == from.id {
			_parentBuildPhase = nil
		}
	}

	public override var renderSingleLine : Bool
	{
		return true
	}
	
	// Properties
	private weak var _parentBuildPhase: XcodeObject? = nil
}


// MARK: XcodeObject*BuildPhase
public protocol XcodeObjectBuildPhase: XcodeTypedObject { }

public class XcodeObjectCopyFilesBuildPhase: XcodeObject, XcodeObjectBuildPhase
{
	// XcodeTypedObject.
	public static let isa = "PBXCopyFilesBuildPhase"
	
	public override var renderComment: String
	{
		if let name = self.name {
			return name
		} else {
			return "CopyFiles"
		}
	}
}

public class XcodeObjectFrameworksBuildPhase: XcodeObject, XcodeObjectBuildPhase
{
	// XcodeTypedObject.
	public static let isa = "PBXFrameworksBuildPhase"

	public override var renderComment: String
	{
		return "Frameworks"
	}
}

public class XcodeObjectHeadersBuildPhase: XcodeObject, XcodeObjectBuildPhase
{
	// XcodeTypedObject.
	public static let isa = "PBXHeadersBuildPhase"

	public override var renderComment: String
	{
		return "Headers"
	}
}

public class XcodeObjectResourcesBuildPhase: XcodeObject, XcodeObjectBuildPhase
{
	// XcodeTypedObject.
	public static let isa = "PBXResourcesBuildPhase"

	public override var renderComment: String
	{
		return "Resources"
	}
}

public class XcodeObjectShellScriptBuildPhase: XcodeObject, XcodeObjectBuildPhase
{
	// XcodeTypedObject.
	public static let isa = "PBXShellScriptBuildPhase"
	
	public override var renderComment: String
	{
		if let name = self.name {
			return name
		} else {
			return "ShellScript"
		}
	}
}

public class XcodeObjectSourcesBuildPhase: XcodeObject, XcodeObjectBuildPhase
{
	// XcodeTypedObject.
	public static let isa = "PBXSourcesBuildPhase"

	public override var renderComment: String
	{
		return "Sources"
	}
}


// MARK: XcodeObjectBuildRule
public class XcodeObjectBuildRule: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "PBXBuildRule"
}


// MARK: XcodeObjectConfigurationList
public class XcodeObjectConfigurationList: XcodeTypedObject
{
	// XcodeTypedObject.
	// > Isa.
	public static let isa = "XCConfigurationList"

	// > Render.
	public override var renderComment: String?
	{
		if let parent = _parent
		{
			let parentName: String

			if let name = parent.name {
				parentName = name
			} else if let proj = parent as? XcodeObjectProject, let name = proj.projectName {
				parentName = name
			} else {
				return nil
			}
			return "Build configuration list for \(parent.isa) \"\(parentName)\""
		} else {
			return nil
		}
	}

	// > References.
	public override func addReference(from: XcodeObject)
	{
		super.addReference(from: from)
		
		if from is XcodeObjectNativeTarget {
			_parent = from
		} else if from is XcodeObjectLegacyTarget {
			_parent = from
		} else if from is XcodeObjectProject {
			_parent = from
		}
	}

	public override func removeReference(from: XcodeObject)
	{
		super.removeReference(from: from)

		if _parent?.id == from.id {
			_parent = nil
		}
	}


	// Properties
	private weak var _parent: XcodeObject? = nil


	// Convenience.
	// > Build Configurations
	public static let buildConfigurations = "buildConfigurations"

	public var buildConfigurations: XcodeArray?
	{
		get { return content[Self.buildConfigurations] }
		set { content[Self.buildConfigurations] = newValue}
	}

	public func buildConfigurationsList() -> [XcodeObject]?
	{
		return content[Self.buildConfigurations]
	}
}


// MARK: XcodeObjectContainerItemProxy
public class XcodeObjectContainerItemProxy: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "PBXContainerItemProxy"
}


// MARK: XcodeObjectFileReference
public class XcodeObjectFileReference: XcodeTypedObject
{
	// XcodeTypedObject.
	// > Isa.
	public static let isa = "PBXFileReference"

	// > Render.
	public override var renderComment: String?
	{
		if let name = self.name {
			return name
		} else {
			return self.path?.lastComponent?.string
		}
	}
	
	public override var renderSingleLine: Bool
	{
		return true
	}

	// > References.
	public override func addReference(from: XcodeObject)
	{
		super.addReference(from: from)

		if let group = from as? XcodeObjectGroup {
			self.parentGroup = group
		}
	}

	public override func removeReference(from: XcodeObject)
	{
		super.removeReference(from: from)

		if parentGroup?.id == from.id {
			parentGroup = nil
		}
	}


	// Convenience.
	public private(set) weak var parentGroup: XcodeObjectGroup? = nil

	// > Last known file type.
	public static let lastKnownFileTypeKey = "lastKnownFileType"

	public var lastKnownFileType: String?
	{
		get { return content[Self.lastKnownFileTypeKey] }
		set { content[Self.lastKnownFileTypeKey] = newValue }
	}

	// > Path.
	public static let pathKey = "path"

	public var path: FilePath?
	{
		get { return content[Self.pathKey] }
		set { content[Self.pathKey] = newValue }
	}

	// > Source Tree.
	public static let sourceTreeKey = "sourceTree"

	public var sourceTree: String?
	{
		get { return content[Self.sourceTreeKey] }
		set { content[Self.sourceTreeKey] = newValue }
	}
}


// MARK: XcodeObjectGroup
public class XcodeObjectGroup: XcodeTypedObject
{
	// XcodeTypedObject.
	// Isa.
	public static let isa = "PBXGroup"

	// > Render.
	public override var renderComment: String?
	{
		if let name = super.name {
			return name
		}

		return self.path?.lastComponent?.string
	}

	// > References.
	public override func addReference(from: XcodeObject)
	{
		super.addReference(from: from)

		if let group = from as? XcodeObjectGroup {
			self.parentGroup = group
		}
	}

	public override func removeReference(from: XcodeObject)
	{
		super.removeReference(from: from)

		if parentGroup?.id == from.id {
			parentGroup = nil
		}
	}


	// Convenience.
	public private(set) weak var parentGroup: XcodeObjectGroup? = nil

	// > Path.
	public static let pathKey = "path"

	public var path: FilePath?
	{
		get { return content[Self.pathKey] }
		set { content[Self.pathKey] = newValue }
	}

	// > Children.
	public static let childrenKey = "children"

	public var children: XcodeArray?
	{
		get { return content[Self.childrenKey] }
		set { content[Self.childrenKey] = newValue }
	}

	// > Source Tree.
	public static let sourceTreeKey = "sourceTree"

	public var sourceTree: String?
	{
		get { return content[Self.sourceTreeKey] }
		set { content[Self.sourceTreeKey] = newValue }
	}
}


// MARK: XcodeObjectLegacyTarget
public class XcodeObjectLegacyTarget: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "PBXLegacyTarget"
}


// MARK: XcodeObjectNativeTarget
public class XcodeObjectNativeTarget: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "PBXNativeTarget"


	// Convenience.
	// > Build configuration list.
	public static let buildConfigurationListKey = "buildConfigurationList"

	public var buildConfigurationList: XcodeObjectConfigurationList?
	{
		get { return content[Self.buildConfigurationListKey] }
		set { content[Self.buildConfigurationListKey] = newValue }
	}

	// > Product Reference.
	public static let productReferenceKey = "productReference"

	public var productReference: XcodeObjectFileReference?
	{
		get { return content[Self.productReferenceKey] }
		set { content[Self.productReferenceKey] = newValue }
	}

	// > Product type.
	public static let productTypeKey = "productType"

	public var productType: String?
	{
		get { return content[Self.productTypeKey] }
		set { content[Self.productTypeKey] = newValue }
	}
}


// MARK: XcodeObjectProject
public class XcodeObjectProject: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "PBXProject"
	
	public override var renderComment: String
	{
		return "Project object"
	}


	// Properties.
	private var _projectName: String?

	public var projectName: String?
	{
		get {
			if let name = _projectName {
				return name
			} else if let name = self.name {
				return name
			} else if let target = self.targetsList()?.first {
				return target.name
			}
			
			return nil
		}

		set {
			_projectName = newValue
		}
	}


	// Convenience.
	// > Targets.
	public static let targetsKey = "targets"

	public var targets: XcodeArray?
	{
		get { return content[Self.targetsKey] }
		set { content[Self.targetsKey] = newValue }
	}

	public func targetsList() -> [XcodeObject]?
	{
		return content[Self.targetsKey]
	}

	// > Project references.
	public static let projectReferencesKey = "projectReferences"

	public var projectReferences: XcodeArray?
	{
		get { return content[Self.projectReferencesKey] }
		set { content[Self.projectReferencesKey] = newValue }
	}

	// > Build configuration list.
	public static let buildConfigurationListKey = "buildConfigurationList"

	public var buildConfigurationList: XcodeObjectConfigurationList?
	{
		get { return content[Self.buildConfigurationListKey] }
		set { content[Self.buildConfigurationListKey] = newValue }
	}

	// > Main Group.
	public static let mainGroupKey = "mainGroup"

	public var mainGroup: XcodeObjectGroup?
	{
		get { return content[Self.mainGroupKey] }
		set { content[Self.mainGroupKey] = newValue }
	}
}


// MARK: XcodeObjectReferenceProxy
public class XcodeObjectReferenceProxy: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "PBXReferenceProxy"

	public override var renderComment: String?
	{
		return self.path?.lastComponent?.string
	}


	// Convenience.
	// > Path.
	public static let pathKey = "path"

	var path: FilePath?
	{
		get { return content[Self.pathKey] }
		set { content[Self.pathKey] = newValue }
	}
	
}


// MARK: XcodeObjectTargetDependency
public class XcodeObjectTargetDependency: XcodeTypedObject
{
	// XcodeTypedObject.
	public static let isa = "PBXTargetDependency"

	public override var renderComment: String
	{
		return self.isa
	}
}
