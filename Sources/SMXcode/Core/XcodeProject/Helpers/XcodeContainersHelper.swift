/*
 * XcodeContainersHelper.swift
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


internal func convertFromContainerValue<T>(_ value: Any?) -> T?
{
	if let literal = value as? XcodeLiteral
	{
		if T.self is String.Type {
			return literal.string as? T
		} else if T.self is FilePath.Type {
			return FilePath(literal.string) as? T
		} else if T.self is XcodeObject.Type, case let .ref(_, weakObj, _) = literal, let obj = weakObj.object {
			return obj as? T
		}
	}
	else if let array = value as? XcodeArray
	{
		if T.self is Array<XcodeObject>.Type
		{
			var narray = Array<XcodeObject>()

			for entry in array
			{
				if let literal = entry as? XcodeLiteral, case let .ref(_, weakObj, _) = literal, let obj = weakObj.object {
					narray.append(obj)
				}
			}

			return narray as? T
		}
	}

	return value as? T
}

internal func convertToContainerValue<T>(_ newValue: T?, storeDirectObject: Bool = false) -> Any?
{
	if let value = newValue
	{
		if let obj = value as? XcodeObject
		{
			if storeDirectObject {
				return obj
			} else {
				return XcodeLiteral.ref(obj.id, XcodeWeakObject(obj), false)
			}
		}
		else if let path = value as? FilePath {
			return XcodeLiteral.string(path.string)
		}
		else if let str = value as? String {
			return XcodeLiteral.string(str)
		}
		else if let array = value as? Array<XcodeObject>
		{
			let narray = XcodeArray()

			for item in array {
				narray.append(item)
			}

			return narray
		}
		else if let dict = value as? XcodeDictionary {
			return dict // Exaustive to avoid the fatal error.
		}
		else if let array = value as? XcodeArray {
			return array // Exaustive to avoid the fatal error.
		}
		else if let literal = value as? XcodeLiteral {
			return literal // Exaustive to avoid the fatal error.
		} else if let sections = value as? XcodeSections {
			return sections // Exaustive to avoid the fatal error.
		} else {
			fatalError("invalid type")
		}
	}

	// Fallback.
	return nil
}
