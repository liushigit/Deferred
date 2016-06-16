//
//  FutureType.swift
//  Deferred
//
//  Created by Zachary Waldowski on 8/29/15.
//  Copyright © 2014-2015 Big Nerd Ranch. Licensed under MIT.
//

import Dispatch

/// A future models reading a value which may become available at some point.
///
/// A `FutureType` may be preferable to an architecture using completion
/// handlers; separating the mechanism for handling the completion from the call
/// that began it leads to a more readable code flow.
///
/// A future is primarily useful as a joining mechanism for asynchronous
/// operations. Though the protocol requires a synchronous accessor, its use is
/// not recommended outside of testing. `upon` is preferred for nearly all access:
///
///     myFuture.upon(dispatch_get_main_queue()) { value in
///       print("I now have the value: \(value)")
///     }
///
/// `FutureType` makes no requirement on conforming types regarding thread-safe
/// access, though ideally all members of the future could be called from any
/// thread.
///
public protocol FutureType: CustomDebugStringConvertible, CustomReflectable {
    /// A type that represents the result of some asynchronous operation.
    associatedtype Value

    /// Call some `body` closure once the value is determined.
    ///
    /// If the value is determined, the closure should be submitted to the
    /// `executor` immediately.
    ///
    /// - parameter executor: A context for handling the `body` on fill.
    /// - parameter body: A closure that uses the determined value.
    func upon(_ executor: ExecutorType, body: (Value) -> Void)

    /// Waits synchronously for the value to become determined.
    ///
    /// If the value is already determined, the call returns immediately with
    /// the value.
    ///
    /// - parameter time: A length of time to wait for the value to be determined.
    /// - returns: The determined value, if filled within the timeout, or `nil`.
    func wait(_ time: Timeout) -> Value?
}

private extension DispatchQoS.QoSClass {

    static func current() -> DispatchQoS.QoSClass {
        return .init(qos_class_self())
    }

    init(_ qos: qos_class_t) {
        switch qos {
        case QOS_CLASS_USER_INTERACTIVE:
            self = .userInteractive
        case QOS_CLASS_USER_INITIATED:
            self = .userInitiated
        case QOS_CLASS_DEFAULT:
            self = .`default`
        case QOS_CLASS_UTILITY:
            self = .utility
        case QOS_CLASS_BACKGROUND:
            self = .background
        default:
            self = .unspecified
        }

    }

}

private extension DispatchQueue {

    static func global(qos: DispatchQoS.QoSClass) -> DispatchQueue {
        let attributes: DispatchQueue.GlobalAttributes
        switch qos {
        case .background:
            attributes = .qosBackground
        case .utility:
            attributes = .qosUtility
        case .`default`:
            attributes = .qosDefault
        case .userInitiated:
            attributes = .qosUserInitiated
        case .userInteractive:
            attributes = .qosUserInteractive
        case .unspecified:
            attributes = []
        }
        return global(attributes: attributes)
    }
    
}

extension FutureType {
    /// A generic catch-all dispatch queue for use with futures, when you just
    /// want to throw some work into the concurrent pile. As an alternative to
    /// the `QOS_CLASS_UTILITY` global queue, work dispatched onto this queue
    /// on platforms with QoS will match the QoS of the caller, which is
    /// generally the right behavior for data flow.
    public static var genericQueue: DispatchQueue {
        // The technique is described and used in Core Foundation:
        // http://opensource.apple.com/source/CF/CF-1153.18/CFInternal.h
        // https://github.com/apple/swift-corelibs-foundation/blob/master/CoreFoundation/Base.subproj/CFInternal.h#L869-L889
        #if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
        return DispatchQueue.global(qos: .current())
        #else
        return DispatchQueue.global(attributes: .qosUtility)
        #endif
    }
}

extension FutureType {
    /// Call some `body` closure once the value is determined.
    ///
    /// If the value is determined, the closure will be submitted to `queue`
    /// immediately, but this call is always asynchronous.
    ///
    /// - seealso: `upon(_:body:)`.
    public func upon(_ queue: DispatchQueue, body: (Value) -> Void) {
        upon(QueueExecutor(queue), body: body)
    }

    /// Call some `body` closure in the background once the value is determined.
    ///
    /// If the value is determined, the closure will be enqueued immediately,
    /// but this call is always asynchronous.
    public func upon(_ body: (Value) -> Void) {
        upon(Self.genericQueue, body: body)
    }

    /// Call some `body` closure on the main queue once the value is determined.
    ///
    /// If the value is determined, the closure will be submitted to the
    /// main queue. It will always execute asynchronously, even if this call is
    /// made from the main queue.
    ///
    /// - parameter body: A closure that uses the determined value.
    public func uponMainQueue(_ body: (Value) -> Void) {
        upon(.main, body: body)
    }
}

extension FutureType {
    /// Checks for and returns a determined value.
    ///
    /// - returns: The determined value, if already filled, or `nil`.
    public func peek() -> Value? {
        return wait(.now)
    }

    /// Waits for the value to become determined, then returns it.
    ///
    /// This is equivalent to unwrapping the value of calling `wait(.Forever)`,
    /// but may be more efficient.
    ///
    /// This getter will unnecessarily block execution. It might be useful for
    /// testing, but otherwise it should be strictly avoided.
    ///
    /// - returns: The determined value.
    var value: Value {
        return wait(.forever).unsafelyUnwrapped
    }

    /// Check whether or not the receiver is filled.
    var isFilled: Bool {
        return wait(.now) != nil
    }
}

extension FutureType {

    /// A textual representation of `self`, suitable for debugging.
    public var debugDescription: String {
        var ret = "\(Self.self)"
        if Value.self == Void.self && isFilled {
            ret += " (filled)"
        } else if let value = peek() {
            ret += "(\(String(reflecting: value)))"
        } else {
            ret += " (not filled)"
        }
        return ret
    }

    /// Return the `Mirror` for `self`.
    public var customMirror: Mirror {
        if Value.self != Void.self, let value = peek() {
            return Mirror(self, children: [ "value": value ], displayStyle: .optional)
        } else {
            return Mirror(self, children: [ "isFilled": isFilled ], displayStyle: .tuple)
        }
    }

}
