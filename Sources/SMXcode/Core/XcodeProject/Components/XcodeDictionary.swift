/*
 * XcodeDictionary.swift
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
// MARK: - XcodeDictionary
//
public class XcodeDictionary: DictionaryObject<XcodeLiteral, Any>
{
	// Properties.
	var isRootObjects = false

	// Init.
	public override init()
	{
		super.init()
	}

	// Content.
	public func object<T>(forKey aKey: XcodeLiteral, isa: String? = nil) -> T?
	{
		return self[aKey]
	}

	// Subscript.
	public subscript<T>(key: String) -> T?
	{
		get { return self[.string(key)] }
		set { self[.string(key)] = newValue }
	}

	public subscript<T>(key: XcodeLiteral) -> T?
	{
		get { return convertFromContainerValue(super[key]) }
		set { super[key] = convertToContainerValue(newValue, storeDirectObject: isRootObjects) }
	}
}
