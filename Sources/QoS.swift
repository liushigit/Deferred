//
//  QoS.swift
//  Deferred
//
//  Created by Zachary Waldowski on 6/16/16.
//  Copyright © 2016 Big Nerd Ranch. All rights reserved.
//

import Dispatch

extension DispatchQueue {

    static func globalMatchingCurrentQoS() -> DispatchQueue {
        let attributes: DispatchQueue.GlobalAttributes
        switch qos_class_self() {
        case QOS_CLASS_USER_INTERACTIVE:
            attributes = .qosUserInteractive
        case QOS_CLASS_USER_INITIATED:
            attributes = .qosUserInitiated
        case QOS_CLASS_DEFAULT:
            attributes = .qosDefault
        case QOS_CLASS_UTILITY:
            attributes = .qosUtility
        case QOS_CLASS_BACKGROUND:
            attributes = .qosBackground
        default:
            attributes = []
        }
        return global(attributes: attributes)
    }
    
}
