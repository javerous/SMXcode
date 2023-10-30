/*
 * XcodeLiteral.swift
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
// MARK: - XcodeLiteral
//
public enum XcodeLiteral: Hashable, ExpressibleByStringLiteral
{
	// MARK: Cases
	case string(_ string: String)
	case ref(_ id: String, _ weakObject: XcodeWeakObject, _ silent: Bool)

	
	// MARK: Hashable
	public var hashValue: Int {
		switch self
		{
			case .string(let string):
				return string.hashValue

			case .ref(let id, _, _):
				return id.hashValue
		}
	}

	public func hash(into hasher: inout Hasher)
	{
		switch self
		{
			case .string(let string):
				string.hash(into: &hasher)

			case .ref(let id, _, _):
				id.hash(into: &hasher)
		}
	}

	
	// MARK: Equatable
	public static func == (lhs: Self, rhs: Self) -> Bool
	{
		switch lhs
		{
			case .string(let lstring):
				switch rhs
				{
					case .string(let rstring):
						return lstring == rstring

					case .ref(let rid, _, _):
						return lstring == rid
				}


			case .ref(let lid, _, _):
				switch rhs
				{
					case .string(let rstring):
						return lid == rstring

					case .ref(let rid, _, _):
						return lid == rid
				}
		}
	}

	
	// MARK: ExpressibleByStringLiteral
	public typealias StringLiteralType = String

	public init(stringLiteral: String)
	{
		self = .string(stringLiteral)
	}

	
	// MARK: Convenience
	public var string: String
	{
		get {
			switch self
			{
				case .string(let string):
					return string

				case .ref(let id, _, _):
					return id
			}
		}
	}
}


//
// MARK: - XcodeWeakObject
//
public struct XcodeWeakObject
{
	public weak var object: XcodeObject?

	public init(_ obj: XcodeObject)
	{
		self.object = obj
	}
}
