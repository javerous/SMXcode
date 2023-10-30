/*
 * DictionaryObject.swift
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
import Collections


// Swift dictionaries being value types is one of the most annoying thing in Swift.

//
// MARK: - DictionaryObject
//
public class DictionaryObject <Key: Hashable, Value>: Sequence, CustomStringConvertible
{
	// MARK: Properties
	private var _dict = OrderedDictionary<Key, Value>()
	

	// MARK: Instance
	public init() { }


	// MARK: Subscript
	public subscript(key: Key) -> Value?
	{
		get { return _dict[key] }
		set { _dict[key] = newValue }
	}

	
	// MARK: Sequence
	public typealias Element = OrderedDictionary<Key, Value>.Element
	public typealias Iterator = OrderedDictionary<Key, Value>.Iterator

	public func makeIterator() -> Iterator
	{
		return _dict.makeIterator()
	}

	public var underestimatedCount: Int
	{
		return _dict.underestimatedCount
	}

	public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<DictionaryObject.Element>) throws -> R) rethrows -> R?
	{
		return try _dict.withContiguousStorageIfAvailable(body)
	}

	
	// MARK: CustomStringConvertible
	public var description: String
	{
		return _dict.description
	}

	public var debugDescription: String
	{
		return _dict.debugDescription
	}

	
	// MARK: Content
	public var keys: OrderedSet<Key>
	{
		return _dict.keys
	}

	public var count: Int
	{
		return _dict.count
	}

	public func object(forKey aKey: Key, isa: String? = nil) -> Value?
	{
		return _dict[aKey]
	}

	@discardableResult
	public func updateValue(_ value: Value, forKey key: Key) -> Value?
	{
		return _dict.updateValue(value, forKey:key)
	}

	@discardableResult
	public func removeValue(forKey key: Key) -> Value?
	{
		return _dict.removeValue(forKey: key)
	}

	func removeAll()
	{
		_dict.removeAll(keepingCapacity: false)
	}
}
