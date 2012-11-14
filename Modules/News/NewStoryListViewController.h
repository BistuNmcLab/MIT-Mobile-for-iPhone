#import <UIKit/UIKit.h>

@class NewsStory;

@protocol StoryListPagingDelegate <NSObject>
- (BOOL)canSelectNextStory:(NewsStory*)currentStory;
- (BOOL)canSelectPreviousStory:(NewsStory*)currentStory;

- (NewsStory*)selectNextStory:(NewsStory*)currentStory;
- (NewsStory*)selectPreviousStory:(NewsStory*)currentStory;
@end

@interface NewStoryListViewController : UIViewController <StoryListPagingDelegate>
@property (nonatomic,assign) NSInteger activeCategoryId;
@property (nonatomic,assign) NSTimeInterval updateInterval;
@end
