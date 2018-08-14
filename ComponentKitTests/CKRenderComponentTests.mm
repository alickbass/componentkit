/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <XCTest/XCTest.h>

#import <ComponentKit/CKBuildComponent.h>
#import <ComponentKit/CKRenderComponent.h>
#import <ComponentKit/CKComponentInternal.h>
#import <ComponentKit/CKComponentSubclass.h>
#import <ComponentKit/CKThreadLocalComponentScope.h>
#import <ComponentKit/CKComponentScopeRootFactory.h>

#import "CKTreeNodeWithChildren.h"

@interface CKTestRenderComponent : CKRenderComponent
@property (nonatomic, assign) NSUInteger renderCalledCounter;
@end

@implementation CKTestRenderComponent
- (CKComponent *)render:(id)state
{
  _renderCalledCounter++;
  return nil;
}

+ (id)initialState
{
  return nil;
}

@end

@interface CKRenderComponentTests : XCTestCase
@end

@implementation CKRenderComponentTests
{
  CKBuildComponentConfig _config;
  CKTestRenderComponent *_c;
  CKComponentScopeRoot *_scopeRoot;
}

- (void)setUp
{
  _config = {
    .enableFasterStateUpdates = YES,
  };

  // New Tree Creation.
  _c = [CKTestRenderComponent new];
  _scopeRoot = createNewTreeWithComponentAndReturnScopeRoot(_config, _c);
  XCTAssertEqual(_c.renderCalledCounter, 1);
}

- (void)test_fasterStateUpdate_componentIsNotBeingReused_onPropsUpdate
{
  // Simulate props update.
  CKThreadLocalComponentScope threadScope(nil, {});
  auto const c2 = [CKTestRenderComponent new];
  CKComponentScopeRoot *scopeRoot2 = [_scopeRoot newRoot];
  [c2 buildComponentTree:scopeRoot2.rootNode
          previousParent:_scopeRoot.rootNode
                  params:{
                    .scopeRoot = scopeRoot2,
                    .stateUpdates = {},
                    .treeNodeDirtyIds = {},
                    .buildTrigger = BuildTrigger::PropsUpdate,
                  }
                  config:_config
          hasDirtyParent:NO];

  [self verifyComponentIsNotBeingReused:_c c2:c2 scopeRoot:_scopeRoot scopeRoot2:scopeRoot2];
}

- (void)test_fasterStateUpdate_componentIsBeingReused_onStateUpdateOnADifferentComponentBranch
{
  // Simulate a state update on a different component branch:
  // 1. treeNodeDirtyIds with fake components ids.
  // 2. hasDirtyParent = NO
  CKThreadLocalComponentScope threadScope(nil, {});
  auto const c2 = [CKTestRenderComponent new];
  CKComponentScopeRoot *scopeRoot2 = [_scopeRoot newRoot];

  [c2 buildComponentTree:scopeRoot2.rootNode
          previousParent:_scopeRoot.rootNode
                  params:{
                    .scopeRoot = scopeRoot2,
                    .stateUpdates = {},
                    .treeNodeDirtyIds = {100, 101}, // Use a random id that represents a fake state update on a different branch.
                    .buildTrigger = BuildTrigger::StateUpdate,
                  }
                  config:_config
          hasDirtyParent:NO];

  // As the state update doesn't affect the c2, we should reuse c instead.
  [self verifyComponentIsBeingReused:_c c2:c2 scopeRoot:_scopeRoot scopeRoot2:scopeRoot2];
}

- (void)test_fasterStateUpdate_componentIsNotBeingReused_onStateUpdateOnAParent
{
  // Simulate a state update on a parent component:
  // 1. hasDirtyParent = YES
  // 2. treeNodeDirtyIds with a fake parent id.
  CKThreadLocalComponentScope threadScope(nil, {});
  CKComponentScopeRoot *scopeRoot2 = [_scopeRoot newRoot];

  auto const c2 = [CKTestRenderComponent new];
  [c2 buildComponentTree:scopeRoot2.rootNode
          previousParent:_scopeRoot.rootNode
                  params:{
                    .scopeRoot = scopeRoot2,
                    .stateUpdates = {},
                    .treeNodeDirtyIds = {100}, // Use a random id that represents a state update on a fake parent.
                    .buildTrigger = BuildTrigger::StateUpdate,
                  }
                  config:_config
          hasDirtyParent:YES];

  // As the state update affect c2, we should recreate its children.
  [self verifyComponentIsNotBeingReused:_c c2:c2 scopeRoot:_scopeRoot scopeRoot2:scopeRoot2];
}

- (void)test_fasterStateUpdate_componentIsNotBeingReused_onStateUpdateOnTheComponent
{
  // Simulate a state update on the component itself:
  // 1. treeNodeDirtyIds contains the tree node identifier
  CKThreadLocalComponentScope threadScope(nil, {});
  CKComponentScopeRoot *scopeRoot2 = [_scopeRoot newRoot];

  auto const c2 = [CKTestRenderComponent new];
  [c2 buildComponentTree:scopeRoot2.rootNode
          previousParent:_scopeRoot.rootNode
                  params:{
                    .scopeRoot = scopeRoot2,
                    .stateUpdates = {},
                    .treeNodeDirtyIds = {
                      _c.scopeHandle.treeNode.nodeIdentifier
                    },
                    .buildTrigger = BuildTrigger::StateUpdate,
                  }
                  config:_config
          hasDirtyParent:NO];

  // As the state update affect c2, we should recreate its children.
  [self verifyComponentIsNotBeingReused:_c c2:c2 scopeRoot:_scopeRoot scopeRoot2:scopeRoot2];
}

- (void)test_fasterStateUpdate_componentIsNotBeingReused_onStateUpdateOnItsChild
{
  // Simulate a state update on the component child:
  // 1. treeNodeDirtyIds, contains the component tree node id.
  // 2. hasDirtyParent = NO
  CKThreadLocalComponentScope threadScope(nil, {});
  CKComponentScopeRoot *scopeRoot2 = [_scopeRoot newRoot];

  auto const c2 = [CKTestRenderComponent new];

  [c2 buildComponentTree:scopeRoot2.rootNode
          previousParent:_scopeRoot.rootNode
                  params:{
                    .scopeRoot = scopeRoot2,
                    .stateUpdates = {},
                    .treeNodeDirtyIds = {
                      _c.scopeHandle.treeNode.nodeIdentifier // Mark the component as dirty
                    },
                    .buildTrigger = BuildTrigger::StateUpdate,
                  }
                  config:_config
          hasDirtyParent:NO];

  // As the state update affect c2, we should recreate its children.
  [self verifyComponentIsNotBeingReused:_c c2:c2 scopeRoot:_scopeRoot scopeRoot2:scopeRoot2];
}

#pragma mark - Helpers

- (void)verifyComponentIsNotBeingReused:(CKTestRenderComponent *)c
                                     c2:(CKTestRenderComponent *)c2
                              scopeRoot:(CKComponentScopeRoot *)scopeRoot
                             scopeRoot2:(CKComponentScopeRoot *)scopeRoot2
{
  CKTreeNode *childNode = scopeRoot.rootNode.children[0];
  CKTreeNode *childNode2 = scopeRoot2.rootNode.children[0];
  XCTAssertTrue(verifyChildToParentConnection(scopeRoot2.rootNode, childNode2, c2));
  XCTAssertNotEqual(childNode, childNode2);
  XCTAssertEqual(c.renderCalledCounter, 1);
  XCTAssertEqual(c2.renderCalledCounter, 1);
}

- (void)verifyComponentIsBeingReused:(CKTestRenderComponent *)c
                                  c2:(CKTestRenderComponent *)c2
                           scopeRoot:(CKComponentScopeRoot *)scopeRoot
                          scopeRoot2:(CKComponentScopeRoot *)scopeRoot2
{
  CKTreeNode *childNode = scopeRoot.rootNode.children[0];
  CKTreeNode *childNode2 = scopeRoot2.rootNode.children[0];
  // In case we reuse the previous component, the reused component will be attached to the new root.
  XCTAssertTrue(verifyChildToParentConnection(scopeRoot2.rootNode, childNode2, c));
  // Both nodes from the previous and the existing parent will be equal.
  XCTAssertEqual(childNode, childNode2);
  // Make sure we don't call render again on c
  XCTAssertEqual(c.renderCalledCounter, 1);
  // We don't call render on c2 as we reuse c instead.
  XCTAssertEqual(c2.renderCalledCounter, 0);
}

static BOOL verifyChildToParentConnection(id<CKTreeNodeWithChildrenProtocol> parentNode, CKTreeNode *childNode, CKComponent *c) {
  auto const componentKey = [childNode componentKey];
  auto const childComponent = [parentNode childForComponentKey:componentKey].component;
  return [childComponent isEqual:c];
}

static const CKBuildComponentTreeParams newTreeParams(CKComponentScopeRoot *scopeRoot) {
  return {
    .scopeRoot = scopeRoot,
    .stateUpdates = {},
    .treeNodeDirtyIds = {},
    .buildTrigger = BuildTrigger::NewTree,
  };
}

static CKComponentScopeRoot *createNewTreeWithComponentAndReturnScopeRoot(const CKBuildComponentConfig &config, CKTestRenderComponent *c) {
  CKThreadLocalComponentScope threadScope(nil, {});
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  const CKBuildComponentTreeParams params = newTreeParams(scopeRoot);
  [c buildComponentTree:scopeRoot.rootNode
         previousParent:nil
                 params:params
                 config:config
         hasDirtyParent:NO];
  return scopeRoot;
}

@end

