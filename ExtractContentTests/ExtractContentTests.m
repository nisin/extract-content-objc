//
//  ExtractContentTests.m
//  ExtractContentTests
//
//  Created by hikida on 2016/06/17.
//  Copyright © 2016年 nisin. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "ExtractContent.h"

@interface ExtractContentTests : XCTestCase

@end

@implementation ExtractContentTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testAnalyse {
    ExtractContent* ec = [[ExtractContent alloc] init];
    NSString* html = [NSString stringWithContentsOfURL:[NSURL URLWithString:@"https://developer.apple.com/reference/messages"]];
    NSString* content = [ec analyse:html];
    NSLog(content);
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end
