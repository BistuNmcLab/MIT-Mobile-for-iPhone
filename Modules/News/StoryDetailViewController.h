#import <UIKit/UIKit.h>
#import <MessageUI/MessageUI.h>
#import "ShareDetailViewController.h"

@class NewsStory;
@class StoryListViewController;

@protocol StoryListPagingDelegate;

@interface StoryDetailViewController : ShareDetailViewController <UIWebViewDelegate, MFMailComposeViewControllerDelegate,ShareItemDelegate>

@property (strong) id<StoryListPagingDelegate> newsController;
@property (strong) NewsStory *story;

- (void)displayStory:(NewsStory *)aStory;

@end
