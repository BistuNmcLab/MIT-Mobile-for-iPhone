#import <UIKit/UIKit.h>

@class NewsStory;

typedef enum {
    NewsCategoryIdTopNews = 0,
    NewsCategoryIdEngineering = 1,
    NewsCategoryIdScience = 2,
    NewsCategoryIdManagement = 3,
    NewsCategoryIdArchitecture = 5,
    NewsCategoryIdHumanities = 6,
    NewsCategoryIdCampus = 99
} NewsCategoryId;

extern NSString *const NewsCategoryTopNews;
extern NSString *const NewsCategoryCampus;
extern NSString *const NewsCategoryEngineering;
extern NSString *const NewsCategoryScience;
extern NSString *const NewsCategoryManagement;
extern NSString *const NewsCategoryArchitecture;
extern NSString *const NewsCategoryHumanities;

@protocol StoryListPagingDelegate <NSObject>
- (BOOL)canSelectNextStory:(NewsStory*)currentStory;
- (BOOL)canSelectPreviousStory:(NewsStory*)currentStory;

- (NewsStory*)selectNextStory:(NewsStory*)currentStory;
- (NewsStory*)selectPreviousStory:(NewsStory*)currentStory;
@end

@interface StoryListViewController : UIViewController <StoryListPagingDelegate>
@property (nonatomic,assign) NSInteger activeCategoryId;
@property (nonatomic,assign) NSTimeInterval updateInterval;
@end
