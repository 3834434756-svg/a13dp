#import <UIKit/UIKit.h>

@interface AIConversationVC : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) NSString *targetBundleId;
@property (nonatomic, strong) NSString *targetDataPath;
@property (nonatomic, strong) NSString *targetName;
@property (nonatomic, strong) UITextField *baseURLField;
@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UITextField *inputField;
@end
