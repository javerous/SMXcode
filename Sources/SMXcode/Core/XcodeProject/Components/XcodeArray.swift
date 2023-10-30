/*
 * XcodeArray.swift
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
// MARK: - XcodeArray
//
public class XcodeArray: ArrayObject<Any>
{
	// Content.
	public func append<T>(_ newElement: T)
	{
		if let element = convertToContainerValue(newElement) {
			self.append(element)
		}
	}

	public func insert<T>(_ newElement: T, at i: Int)
	{
		if let element = convertToContainerValue(newElement) {
			self.insert(element, at: 0)
		}
	}

	// Subscript.
	public subscript<T>(index: Int) -> T?
	{
		get { return convertFromContainerValue(super[index]) }
		set
		{
			if let value = convertToContainerValue(newValue) {
				super[index] = value
			}
		}
	}
}
