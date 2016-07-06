//
//  DeferredTests.swift
//  DeferredTests
//
//  Created by John Gallagher on 7/19/14.
//  Copyright © 2014-2015 Big Nerd Ranch. Licensed under MIT.
//

import XCTest
@testable import Deferred

private let testTimeout = 2.0

class DeferredTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testWaitWithTimeout() {
        let deferred = Deferred<Int>()

        let expect = expectation(withDescription: "value blocks while unfilled")
        DispatchQueue.global(attributes: .qosDefault).after(when: .now() + 1) { 
            deferred.fill(42)
            expect.fulfill()
        }

        let peek = deferred.wait(.interval(0.5))
        XCTAssertNil(peek)

        waitForExpectations(withTimeout: 1.5, handler: nil)
    }

    func testPeek() {
        let d1 = Deferred<Int>()
        let d2 = Deferred(value: 1)
        XCTAssertNil(d1.peek())
        XCTAssertEqual(d2.value, 1)
    }

    func testValueOnFilled() {
        let filled = Deferred(value: 2)
        XCTAssertEqual(filled.value, 2)
    }

    func testValueBlocksWhileUnfilled() {
        let unfilled = Deferred<Int>()

        let expect = expectation(withDescription: "value blocks while unfilled")
        DispatchQueue.global().async {
            _ = unfilled.value
            XCTFail("value did not block")
        }
        DispatchQueue.main.after(when: .now() + 0.1, execute: expect.fulfill)
        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }

    func testValueUnblocksWhenUnfilledIsFilled() {
        let d = Deferred<Int>()
        let expect = expectation(withDescription: "value blocks until filled")
        DispatchQueue.global().async {
            XCTAssertEqual(d.value, 3)
            expect.fulfill()
        }
        DispatchQueue.main.after(when: .now() + 0.1) {
            d.fill(3)
        }
        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }

    func testFill() {
        let d = Deferred<Int>()
        d.fill(1)
        XCTAssertEqual(d.value, 1)
    }

    func testFillMultipleTimes() {
        let d = Deferred(value: 1)
        XCTAssertEqual(d.value, 1)
        d.fill(2, assertIfFilled: false)
        XCTAssertEqual(d.value, 1)
    }

    func testIsFilled() {
        let d = Deferred<Int>()
        XCTAssertFalse(d.isFilled)

        let expect = expectation(withDescription: "isFilled is true when filled")
        d.upon { _ in
            XCTAssertTrue(d.isFilled)
            expect.fulfill()
        }
        d.fill(1)
        waitForExpectations(withTimeout: 1, handler: nil)
    }

    func testUponWithFilled() {
        let d = Deferred(value: 1)

        for _ in 0 ..< 10 {
            let expect = expectation(withDescription: "upon blocks called with correct value")
            d.upon { value in
                XCTAssertEqual(value, 1)
                expect.fulfill()
            }
        }

        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }

    func testUponNotCalledWhileUnfilled() {
        let d = Deferred<Int>()

        d.upon { _ in
            XCTFail("unexpected upon block call")
        }

        let expect = expectation(withDescription: "upon blocks not called while deferred is unfilled")
        DispatchQueue.main.after(when: .now() + 0.1) {
            expect.fulfill()
        }

        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }

    func testUponCalledWhenFilled() {
        let d = Deferred<Int>()

        for _ in 0 ..< 10 {
            let expect = expectation(withDescription: "upon blocks not called while deferred is unfilled")
            d.upon { value in
                XCTAssertEqual(value, 1)
                XCTAssertEqual(d.value, value)
                expect.fulfill()
            }
        }

        d.fill(1)

        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }
    
    func testUponMainQueueCalledWhenFilled() {
        let d = Deferred<Int>()
        
        let expectation = self.expectation(withDescription: "uponMainQueue block called on main queue")
        d.upon(.main) { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(value, 1)
            XCTAssertEqual(d.value, 1)
            expectation.fulfill()
        }
        
        d.fill(1)
        waitForExpectations(withTimeout: 1, handler: nil)
    }

    func testConcurrentUpon() {
        let d = Deferred<Int>()
        let queue = DispatchQueue.global()

        // upon with an unfilled deferred appends to an internal array (protected by a write lock)
        // spin up a bunch of these in parallel...
        for i in 0 ..< 32 {
            let expectUponCalled = expectation(withDescription: "upon block \(i)")
            queue.async {
                d.upon { _ in expectUponCalled.fulfill() }
            }
        }

        // ...then fill it (also in parallel)
        queue.async { d.fill(1) }

        // ... and make sure all our upon blocks were called (i.e., the write lock protected access)
        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }

    func testAnd() {
        let d1 = Deferred<Int>()
        let d2 = Deferred<String>()
        let both = d1.and(d2)

        XCTAssertFalse(both.isFilled)

        d1.fill(1)
        XCTAssertFalse(both.isFilled)
        d2.fill("foo")

        let expectation = self.expectation(withDescription: "paired deferred should be filled")
        both.upon { _ in
            XCTAssert(d1.isFilled)
            XCTAssert(d2.isFilled)
            XCTAssertEqual(both.value.0, 1)
            XCTAssertEqual(both.value.1, "foo")
            expectation.fulfill()
        }

        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }

    func testJoinedValues() {
        var d = [Deferred<Int>]()

        for _ in 0 ..< 10 {
            d.append(Deferred())
        }

        let w = d.joinedValues
        let outerExpectation = expectation(withDescription: "all results filled in")
        let innerExpectation = expectation(withDescription: "paired deferred should be filled")

        // skip first
        for i in 1 ..< d.count {
            d[i].fill(i)
        }

        DispatchQueue.main.after(when: .now() + 0.1) {
            XCTAssertFalse(w.isFilled) // unfilled because d[0] is still unfilled
            d[0].fill(0)

            DispatchQueue.main.after(when: .now() + 0.1) {
                XCTAssertTrue(w.value == [Int](0 ..< d.count))
                innerExpectation.fulfill()
            }
            outerExpectation.fulfill()
        }

        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }

    func testJoinedValuesEmptyCollection() {
        let d = EmptyCollection<Deferred<Int>>().joinedValues
        XCTAssert(d.isFilled)
    }

    func testEarliestFilled() {
        let d = (0 ..< 10).map { _ in Deferred<Int>() }
        let w = d.earliestFilled

        d[3].fill(3)

        let outerExpectation = expectation(withDescription: "any is filled")
        let innerExpectation = expectation(withDescription: "any is not changed")

        DispatchQueue.main.after(when: .now() + 0.1) {
            XCTAssertEqual(w.value, 3)

            d[4].fill(4)

            DispatchQueue.main.after(when: .now() + 0.1) {
                XCTAssertEqual(w.value, 3)
                innerExpectation.fulfill()
            }

            outerExpectation.fulfill()
        }

        waitForExpectations(withTimeout: testTimeout, handler: nil)
    }

    /// Deferred values behave as values: All copies reflect the same value.
    /// The wrinkle of course is that the value might not be observable till a later
    /// date.
    func testAllCopiesOfADeferredValueRepresentTheSameDeferredValue() {
        let parent = Deferred<Int>()
        let child1 = parent
        let child2 = parent
        let allDeferreds = [parent, child1, child2]

        let anyValue = 42
        let expectedValues = [Int](repeating: anyValue, count: allDeferreds.count)

        let allShouldBeFulfilled = expectation(withDescription: "filling any copy fulfills all")
        allDeferreds.joinedValues.upon {
            [weak allShouldBeFulfilled] allValues in
            allShouldBeFulfilled?.fulfill()

            XCTAssertEqual(allValues, expectedValues, "all deferreds are the same value")
        }

        let randomIndex = arc4random_uniform(numericCast(allDeferreds.count))
        let oneOfTheDeferreds = allDeferreds[numericCast(randomIndex)]
        oneOfTheDeferreds.fill(anyValue)

        waitForExpectations(withTimeout: 0.5, handler: nil)
    }
    
    func testDeferredOptionalBehavesCorrectly() {
        let d = Deferred<Optional<Int>>(value: .none)

        let beforeExpectation = expectation(withDescription: "already filled with nil optional")
        d.upon {
            XCTAssert($0 == .none)
            beforeExpectation.fulfill()
        }

        d.fill(42, assertIfFilled: false)

        let afterExpectation = expectation(withDescription: "stays filled with same optional")
        d.upon {
            XCTAssert($0 == .none)
            afterExpectation.fulfill()
        }
        
        waitForExpectations(withTimeout: 0.5, handler: nil)
    }
    
    func testIsFilledCanBeCalledMultipleTimesNotFilled() {
        let d = Deferred<Int>()
        XCTAssertFalse(d.isFilled)
        XCTAssertFalse(d.isFilled)
        XCTAssertFalse(d.isFilled)
    }

    func testIsFilledCanBeCalledMultipleTimesWhenFilled() {
        let d = Deferred<Int>(value: 42)
        XCTAssertTrue(d.isFilled)
        XCTAssertTrue(d.isFilled)
        XCTAssertTrue(d.isFilled)
    }

    // The QoS APIs do not behave as expected on the iOS Simulator, so we only
    // run these tests on real devices. This check isn't the most future-proof;
    // if there's ever another archiecture that runs the simulator, this will
    // need to be modified.
    //
    // TODO: Add a clause for a tvOS test target
    #if os(OSX) || (os(iOS) && !(arch(i386) || arch(x86_64)))

    func testThatMainThreadPostsUponWithUserInitiatedQoSClass() {
        let d = Deferred<Int>()

        var qos = QOS_CLASS_UNSPECIFIED
        let expectation = self.expectation(withDescription: "deferred is filled in")

        d.upon { [weak expectation] _ in
            qos = qos_class_self()
            expectation?.fulfill()
        }

        d.fill(42)

        waitForExpectations(withTimeout: 1, handler: nil)
        XCTAssert((qos.rawValue & qos_class_main().rawValue) != 0)
    }

    func testThatLowerQoSPostsUponWithSameQoSClass() {
        let d = Deferred<Int>()
        let q = DispatchQueue.global(attributes: .qosUtility)

        var qos = QOS_CLASS_UNSPECIFIED
        let expectation = self.expectation(withDescription: "deferred is filled in")

        d.upon(q) { [weak expectation] _ in
            qos = qos_class_self()
            expectation?.fulfill()
        }

        d.fill(42)

        waitForExpectations(withTimeout: 1, handler: nil)
        XCTAssert((qos.rawValue & QOS_CLASS_UTILITY.rawValue) != 0)
    }

    #endif // end QoS tests that require a real device

    func testFillAndIsFilledPostcondition() {
        let deferred = Deferred<Int>()
        XCTAssertFalse(deferred.isFilled)
        deferred.fill(42)
        XCTAssertNotNil(deferred.peek())
        XCTAssertTrue(deferred.isFilled)
        XCTAssertNotNil(deferred.wait(.now))
        XCTAssertNotNil(deferred.wait(.interval(0.1)))  // pass
    }

}
