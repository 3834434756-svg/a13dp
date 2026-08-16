#import <UIKit/UIKit.h>

@interface AIConversationVC : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) NSString *targetBundleId;
@property (nonatomic, strong) NSString *targetDataPath;
@property (nonatomic, strong) NSString *targetName;
@end
