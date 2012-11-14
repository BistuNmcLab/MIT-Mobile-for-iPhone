#import <UIKit/UIKit.h>
#import "StoryParser.h"
#import "MITSearchDisplayController.h"
#import "NavScrollerView.h"

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

@class NewsStory;

@interface StoryListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, MITSearchDisplayDelegate, StoryXMLParserDelegate, NavScrollerDelegate> {
	UITableView *storyTable;
    NSArray *_categories;
    NSInteger activeCategoryId;
	StoryParser *xmlParser;
    
    NSArray *navButtons;
    
	// Nav Scroll View
    NavScrollerView *navScrollView;
	// Search bits
	NSString *searchQuery;
	NSArray *searchResults;
	NSInteger searchTotalAvailableResults;
	UISearchBar *theSearchBar;
    MITSearchDisplayController *searchController;
	
	BOOL hasBookmarks;
	BOOL showingBookmarks;
	
    UIView *activityView;
    
    NSIndexPath *tempTableSelection;
    BOOL lastRequestSucceeded;
}

@property (nonatomic, retain) NSArray *stories;
@property (nonatomic, retain) NSString *searchQuery;
@property (nonatomic, retain) NSArray *searchResults;
@property (nonatomic, retain) NSArray *categories;
@property (nonatomic, assign) NSInteger activeCategoryId;
@property (nonatomic, retain) StoryParser *xmlParser;

- (void)pruneStories;
- (void)switchToCategory:(NewsCategoryId)category;
- (void)loadFromCache;
- (void)loadFromServer:(BOOL)loadMore;
- (void)loadSearchResultsFromCache;
- (void)loadSearchResultsFromServer:(BOOL)loadMore forQuery:(NSString *)query;
- (BOOL)canSelectPreviousStory:(NewsStory*)currentStory;
- (BOOL)canSelectNextStory:(NewsStory*)currentStory;
- (NewsStory *)selectPreviousStory:(NewsStory*)currentStory;
- (NewsStory *)selectNextStory:(NewsStory*)currentStory;
@end
