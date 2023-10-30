/*
 * XcodeSections.swift
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
// MARK: - XcodeSections
//
public class XcodeSections: DictionaryObject<String, XcodeSection>
{
	// Interface.
	public func addObjectForKey(_ key:XcodeLiteral, object: XcodeObject)
	{
		// Get the section for this object type.
		let section: XcodeSection
		let isa = object.isa

		if let asection = self[isa] {
			section = asection
		}
		else
		{
			section = XcodeSection(sectionName: isa)
			self[isa] = section
		}
		
		// Add the object to the section.
		section[key] = object
	}
}


//
// MARK: - XcodeSection
//
public class XcodeSection: DictionaryObject<XcodeLiteral, XcodeObject>
{
	// Interface.
	public let sectionName: String

	init(sectionName: String)
	{
		self.sectionName = sectionName
	}
}
