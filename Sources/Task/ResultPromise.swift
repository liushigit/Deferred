//
//  ResultPromise.swift
//  Deferred
//
//  Created by Zachary Waldowski on 10/27/15.
//  Copyright © 2015-2016 Big Nerd Ranch. Licensed under MIT.
//

#if SWIFT_PACKAGE
import Deferred
import Result
#endif

extension PromiseType where Value: ResultType {
    /// Completes the task with a successful `value`, or a thrown error.
    ///
    /// - seealso: `fill(_:)`
    public func succeed(@autoclosure value: () throws -> Value.Value) -> Bool {
        return fill(Value(value: value))
    }

    /// Completes the task with a failed `error`.
    ///
    /// - seealso: `fill(_:)`
    public func fail(error: ErrorType) -> Bool {
        return fill(Value(error: error))
    }

    /// Derives the result of a task from a failable function `body`.
    ///
    /// - seealso: `fill(_:)`
    /// - seealso: `ResultType.init(with:)`
    public func fill(@noescape with body: () throws -> Value.Value) -> Bool {
        return fill(Value(value: try body()))
    }
}
