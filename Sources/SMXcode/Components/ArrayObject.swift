/*
 * ArrayObject.swift
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


// Swift array being value types is one of the most annoying thing in Swift.

//
// MARK: - ArrayObject
//
public class ArrayObject <Value>: Sequence, CustomStringConvertible
{
	// MARK: Properties
	private var _array = Array<Value>()
	

	// MARK: Instance
	public init() { }


	// MARK: Subscript
	public subscript(index: Int) -> Element
	{
		get { return _array[index] }
		set { _array[index] = newValue }
	}

	
	// MARK: Sequence
	public typealias Element = Array<Value>.Element
	public typealias Iterator = Array<Value>.Iterator

	public func makeIterator() -> Iterator
	{
		return _array.makeIterator()
	}

	public var underestimatedCount: Int
	{
		return _array.underestimatedCount
	}

	public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<ArrayObject.Element>) throws -> R) rethrows -> R?
	{
		return try _array.withContiguousStorageIfAvailable(body)
	}
	
	
	// MARK: Sequence Extension
	public var first: Element?
	{
		return _array.first
	}

	
	// MARK: CustomStringConvertible
	public var description: String
	{
		return _array.description
	}

	public var debugDescription: String
	{
		return _array.debugDescription
	}


	// MARK: Content
	public var count: Int
	{
		return _array.count
	}

	public func append(_ newElement: Element)
	{
		_array.append(newElement)
	}

	public func insert(_ newElement: Element, at i: Int)
	{
		_array.insert(newElement, at: i)
	}

	@discardableResult
	public func remove(at index: Int) -> Element
	{
		return _array.remove(at: index)
	}

	public func removeAll(where shouldBeRemoved: (Element) throws -> Bool) rethrows
	{
		try _array.removeAll(where: shouldBeRemoved)
	}
}
