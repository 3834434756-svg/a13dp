//
//  DOHiddenRootListController.h
//  Dopamine
//
//  Hidden root (RootHide style) blacklist management
//

#import "DOPSListController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOHiddenRootListController : DOPSListController

@property (nonatomic, strong) NSArray<NSDictionary *> *hiddenRootApps;

@end

NS_ASSUME_NONNULL_END
