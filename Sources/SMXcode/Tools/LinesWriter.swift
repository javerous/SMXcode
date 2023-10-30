/*
 * LinesWriter.swift
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


//
// MARK: - LinesWriter
//
internal class LinesWriter
{
	// MARK: Properties
	var nextAppendOnSameLine = false

	var isSingleLineMode: Bool {
		return _singleLineMode > 0
	}
	
	private let _indentationString: String
	private var _singleLineMode = 0
	private var _currentLine = String()
	private var _plines = [String]()
	private var _indentation = 0

	// MARK: Instance
	init(identationString: String = "\t")
	{
		self._indentationString = identationString
	}

	// MARK: Content
	func append(_ string: String)
	{
		if isSingleLineMode || nextAppendOnSameLine
		{
			if _currentLine.count == 0 {
				_currentLine = String(repeating: _indentationString, count: Int(_indentation))
			}
			_currentLine += string

			nextAppendOnSameLine = false
		}
		else
		{
			if _currentLine.count > 0
			{
				_plines.append(_currentLine)
				_currentLine = ""
			}

			_currentLine = String(repeating: _indentationString, count: Int(_indentation)) + string
		}
	}

	func appendRaw(_ string: String)
	{
		if _currentLine.count > 0
		{
			_plines.append(_currentLine)
			_currentLine = ""
			nextAppendOnSameLine = false
		}

		_plines.append(string)
	}

	// MARK: Indentation
	func increaseIndentation()
	{
		_indentation += 1
	}

	func decreaseIndentation()
	{
		assert(_indentation > 0)

		_indentation -= 1
	}

	// MARK: Single Line Mode
	func pushSingleLineMode()
	{
		_singleLineMode += 1
	}

	func popSingleLineMode()
	{
		assert(_singleLineMode > 0)

		_singleLineMode -= 1
	}

	func lines() -> [String]
	{
		if _currentLine.count > 0 {
			return _plines + [ _currentLine ]
		} else {
			return _plines
		}
	}
}
