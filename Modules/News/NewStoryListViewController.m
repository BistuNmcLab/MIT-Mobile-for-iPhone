#import <CoreData/CoreData.h>

#import "StoryListViewController.h"
#import "NewStoryListViewController.h"
#import "NavScrollerView.h"
#import "MITUIConstants.h"
#import "StoryThumbnailView.h"
#import "NewsStory.h"
#import "MIT_MobileAppDelegate.h"
#import "CoreDataManager.h"
#import "StoryUpdateOperation.h"
#import "StoryDetailViewController.h"

#define SCROLL_TAB_HORIZONTAL_PADDING 5.0
#define SCROLL_TAB_HORIZONTAL_MARGIN  5.0

#define THUMBNAIL_WIDTH 76.0
#define ACCESSORY_WIDTH_PLUS_PADDING 18.0
#define STORY_TEXT_PADDING_TOP 3.0 // with 15pt titles, makes for 8px of actual whitespace
#define STORY_TEXT_PADDING_BOTTOM 7.0 // from baseline of 12pt font, is roughly 5px
#define STORY_TEXT_PADDING_LEFT 7.0
#define STORY_TEXT_PADDING_RIGHT 7.0
#define STORY_TEXT_WIDTH (320.0 - STORY_TEXT_PADDING_LEFT - STORY_TEXT_PADDING_RIGHT - THUMBNAIL_WIDTH - ACCESSORY_WIDTH_PLUS_PADDING) // 8px horizontal padding
#define STORY_TEXT_HEIGHT (THUMBNAIL_WIDTH - STORY_TEXT_PADDING_TOP - STORY_TEXT_PADDING_BOTTOM) // 8px vertical padding (bottom is less because descenders on dekLabel go below baseline)
#define STORY_TITLE_FONT_SIZE 15.0
#define STORY_DEK_FONT_SIZE 12.0

#define SEARCH_BUTTON_TAG 7947
#define BOOKMARK_BUTTON_TAG 7948

@interface NewStoryListViewController () <UITableViewDataSource,UITableViewDelegate,NSFetchedResultsControllerDelegate,UISearchBarDelegate,MITSearchDisplayDelegate,NavScrollerDelegate>
@property (nonatomic,strong) NSOperationQueue *updateQueue;

@property (nonatomic,strong) NSManagedObjectContext *context;
@property (nonatomic,strong) NSFetchedResultsController *fetchController;
@property (nonatomic,strong) NSFetchedResultsController *queryFetchController;
@property (nonatomic,strong) UIView *loadMoreView;
@property (nonatomic,strong) id observerIdentifier;

@property (nonatomic,strong) NSString *searchQuery;
@property (nonatomic,strong) MITSearchDisplayController *searchController;


@property (nonatomic,weak) NavScrollerView *navScroller;
@property (nonatomic,weak) UITableView *tableView;
@property (nonatomic,weak) UIView *activityView;
@property (nonatomic,weak) UISearchBar *searchBar;

@property (nonatomic,assign) BOOL hasBookmarks;
@property (nonatomic,assign) BOOL isSearching;

- (void)pruneStories:(BOOL)asyncPrune;

@end

static NSString *StoryListCellIdentifier = @"StoryListCell";
enum : NSInteger {
    StoryListCellTitleTag = 1,
    StoryListCellSummaryTag = 2,
    StoryListCellThumbnailTag = 3,

    StoryViewActivityTag = 5,
    StoryViewActivityLabelTag = 6,
    StoryViewActivityProgressTag = 7,
    StoryViewActivityUpdatedTag = 8,
    
    StoryTableFooterButtonTag = 9,
    StoryTableFooterActivityTag = 10,

    StoryNavButtonSearchTag = (NSIntegerMax - 1),
    StoryNavButtonBookmarkTag = NSIntegerMax
};

@implementation NewStoryListViewController
+ (NSArray*)newsCategoryOrder
{
    return @[@(NewsCategoryIdTopNews),
                @(NewsCategoryIdCampus),
                @(NewsCategoryIdEngineering),
                @(NewsCategoryIdScience),
                @(NewsCategoryIdManagement),
                @(NewsCategoryIdArchitecture),
                @(NewsCategoryIdHumanities)];
}

+ (NSDictionary*)newsCategoryNames
{
    return @{@(NewsCategoryIdTopNews) : NewsCategoryTopNews,
                @(NewsCategoryIdCampus) : NewsCategoryCampus,
                @(NewsCategoryIdEngineering) : NewsCategoryEngineering,
                @(NewsCategoryIdScience) : NewsCategoryScience,
                @(NewsCategoryIdManagement) : NewsCategoryManagement,
                @(NewsCategoryIdArchitecture) : NewsCategoryArchitecture,
                @(NewsCategoryIdHumanities) : NewsCategoryHumanities};
}

- (id)init
{
    return [self initWithNibName:nil
                          bundle:nil];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        
        // 300 seconds == 5 minutes
        self.updateInterval = 300;
        _activeCategoryId = -1;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.observerIdentifier];
}

- (void)loadView
{
    CGRect screenFrame = [[MITAppDelegate() window] frame];
    
    if (self.navigationController && ([self.navigationController isNavigationBarHidden] == NO))
    {
        screenFrame.origin.y += CGRectGetHeight(self.navigationController.navigationBar.frame);
        screenFrame.size.height -= CGRectGetHeight(self.navigationController.navigationBar.frame);
    }
    
    UIView *mainView = [[UIView alloc] initWithFrame:screenFrame];
    CGRect mainBounds = mainView.bounds;
    
    // Setup the top scrolling navigation bar for categories
    {
        NavScrollerView *navScroller = [[NavScrollerView alloc] initWithFrame:CGRectMake(0,0,CGRectGetWidth(mainBounds),44.0)];
        navScroller.navScrollerDelegate = self;
        
        UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [searchButton setImage:[UIImage imageNamed:MITImageNameSearch]
                      forState:UIControlStateNormal];
        searchButton.adjustsImageWhenHighlighted = NO;
        searchButton.tag = StoryNavButtonSearchTag;
        [navScroller addButton:searchButton
               shouldHighlight:NO];
        
        if (self.hasBookmarks)
        {
            UIButton *bookmarkButton = [UIButton buttonWithType:UIButtonTypeCustom];
            [bookmarkButton setImage:[UIImage imageNamed:MITImageNameBookmark]
                            forState:UIControlStateNormal];
            bookmarkButton.adjustsImageWhenHighlighted = NO;
            bookmarkButton.tag = StoryNavButtonBookmarkTag;
            [navScroller addButton:bookmarkButton shouldHighlight:NO];
        }
        
        NSArray *orderedCategories = [NewStoryListViewController newsCategoryOrder];
        NSDictionary *categoryNames = [NewStoryListViewController newsCategoryNames];
        
        for (NSNumber *categoryId in orderedCategories)
        {
            NSString *categoryName = categoryNames[categoryId];
            
            if ([categoryName length])
            {
                UIButton *categoryButton = [UIButton buttonWithType:UIButtonTypeCustom];
                categoryButton.tag = [categoryId integerValue];
                [categoryButton setTitle:categoryName
                                forState:UIControlStateNormal];
                [navScroller addButton:categoryButton
                       shouldHighlight:YES];
            }
            else
            {
                DDLogError(@"category '%lu' does not have a valid name.", [categoryId unsignedLongValue]);
            }
        }
        
        self.navScroller = navScroller;
        [mainView addSubview:navScroller];
    }
    
    {
        UIView *activityView = [[UIView alloc] init];
        activityView.autoresizingMask = (UIViewAutoresizingFlexibleWidth |
                                         UIViewAutoresizingFlexibleTopMargin);
        activityView.tag = StoryViewActivityTag;
        activityView.backgroundColor = [UIColor blackColor];
        activityView.userInteractionEnabled = NO;
        self.activityView = activityView;
        
        
        UILabel *loadingLabel = [[UILabel alloc] initWithFrame:CGRectMake(8,0,0,0)];
        loadingLabel.autoresizingMask = (UIViewAutoresizingFlexibleWidth |
                                         UIViewAutoresizingFlexibleHeight);
        loadingLabel.tag = StoryViewActivityLabelTag;
        loadingLabel.text = @"Loading...";
        loadingLabel.textColor = [UIColor colorWithHexString:@"#DDDDDD"];
        loadingLabel.font = [UIFont boldSystemFontOfSize:14.0];
        loadingLabel.backgroundColor = [UIColor blackColor];
        loadingLabel.opaque = YES;
        loadingLabel.hidden = YES;
        [activityView addSubview:loadingLabel];
        
        
        CGSize labelSize = [loadingLabel.text sizeWithFont:loadingLabel.font
                                                  forWidth:CGRectGetWidth(mainBounds)
                                             lineBreakMode:UILineBreakModeTailTruncation];
        labelSize.width = ceil(labelSize.width);
        
        CGFloat activityHeight = (labelSize.height + 8);
        activityView.frame = CGRectMake(0,
                                        CGRectGetMaxY(mainBounds) - activityHeight,
                                        CGRectGetWidth(mainBounds),
                                        activityHeight);
        
        
        UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        progressView.tag = StoryViewActivityProgressTag;
        progressView.frame = CGRectMake((8.0 + labelSize.width) + 5.0,
                                        0,
                                        activityView.frame.size.width - (8.0 + labelSize.width) - 13,
                                        progressView.frame.size.height);
        progressView.center = CGPointMake(progressView.center.x, floor(activityView.frame.size.height / 2) + 1);
        progressView.hidden = YES;
        [activityView addSubview:progressView];
        
        
        UILabel *updatedLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, activityView.frame.size.width - 16, activityView.frame.size.height)];
        updatedLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        updatedLabel.tag = StoryViewActivityUpdatedTag;
        updatedLabel.textColor = [UIColor colorWithHexString:@"#DDDDDD"];
        updatedLabel.font = [UIFont boldSystemFontOfSize:14.0];
        updatedLabel.textAlignment = UITextAlignmentRight;
        updatedLabel.backgroundColor = [UIColor blackColor];
        updatedLabel.opaque = YES;
        [activityView addSubview:updatedLabel];
        
        self.activityView = activityView;
        [mainView addSubview:activityView];
    }
    
    {
        CGRect navScrollerFrame = self.navScroller.frame;
        CGRect tableBounds = CGRectMake(0,
                                        CGRectGetHeight(navScrollerFrame),
                                        CGRectGetWidth(mainBounds),
                                        CGRectGetHeight(mainBounds) - (CGRectGetHeight(navScrollerFrame) + CGRectGetHeight(self.activityView.frame)));
        UITableView *tableView = [[UITableView alloc] initWithFrame:tableBounds
                                                              style:UITableViewStylePlain];
        tableView.dataSource = self;
        tableView.delegate = self;
        tableView.autoresizingMask = (UIViewAutoresizingFlexibleWidth |
                                      UIViewAutoresizingFlexibleHeight);
        tableView.separatorColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        
        self.tableView = tableView;
        [mainView addSubview:tableView];
    }
    
    {
        CGRect footerFrame = CGRectMake(0,
                                        0,
                                        CGRectGetWidth(self.tableView.bounds),
                                        44.0);
        UIView *footerView = [[UIView alloc] initWithFrame:footerFrame];
        footerView.autoresizingMask = (UIViewAutoresizingFlexibleHeight |
                                       UIViewAutoresizingFlexibleWidth);
        footerView.autoresizesSubviews = YES;
        footerView.userInteractionEnabled = YES;
     
        
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.autoresizingMask = (UIViewAutoresizingFlexibleHeight |
                                   UIViewAutoresizingFlexibleWidth);
        button.frame = footerFrame;
        button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        
        [button setTitle:@"Load more articles..."
                forState:UIControlStateNormal];
        [button setTitleColor:[UIColor colorWithHexString:@"#990000"]
                     forState:UIControlStateNormal];
        [button setTitleColor:[UIColor darkGrayColor]
                     forState:UIControlStateDisabled];
        
        [button addTarget:self
                   action:@selector(loadMoreStories:)
         forControlEvents:UIControlEventTouchUpInside];
    
        button.backgroundColor = [UIColor whiteColor];
        button.showsTouchWhenHighlighted = YES;
        button.tag = StoryTableFooterButtonTag;
        [footerView addSubview:button];
        
        UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        activityView.hidesWhenStopped = YES;
        activityView.frame = footerFrame;
        activityView.tag = StoryTableFooterActivityTag;
        [footerView addSubview:activityView];
    

        self.loadMoreView = footerView;
    }
    
    self.view = mainView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = @"MIT News";
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Headlines"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:nil
                                                                            action:nil];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(refresh:)];
    
    {
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        context.undoManager = nil;
        context.persistentStoreCoordinator = [[CoreDataManager coreDataManager] persistentStoreCoordinator];
        self.context = context;
    }
    
    [self updateCategoryData];
    
    // Configure the fetch results controller! This should grab the list of top stories
    // by default
    {
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NewsStoryEntityName];
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"postDate" ascending:NO],
                                    [NSSortDescriptor sortDescriptorWithKey:@"featured" ascending:YES],
                                    [NSSortDescriptor sortDescriptorWithKey:@"story_id" ascending:NO]];
        
        NSFetchedResultsController *fetchController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                                                                          managedObjectContext:self.context
                                                                                            sectionNameKeyPath:nil
                                                                                                     cacheName:nil];
        fetchController.delegate = self;
        self.fetchController = fetchController;
    }
    
    {
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        self.updateQueue = queue;
    }
    
    self.activeCategoryId = NewsCategoryIdTopNews;
    
    self.observerIdentifier = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification
                                                                                object:nil
                                                                                 queue:[NSOperationQueue mainQueue]
                                                                            usingBlock:^(NSNotification *note) {
                                                                                [self pruneStories:NO];
                                                                            }];
}

- (void)viewWillAppear:(BOOL)animated
{
    if (self.isSearching == NO)
    {
        //    [self loadStoriesForCategory:self.activeCategoryId
        //               isLoadingMore:NO
        //                forceRefresh:NO];
    }

    [self.navScroller selectButtonWithTag:self.activeCategoryId];
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow]
                                  animated:YES];
    [self.searchDisplayController.searchResultsTableView deselectRowAtIndexPath:[self.searchDisplayController.searchResultsTableView indexPathForSelectedRow]
                                                                       animated:YES];
}

- (void)viewDidDisappear:(BOOL)animated
{
    if (self.parentViewController == nil)
    {
        [self pruneStories:YES];
    }
}

- (void)updateCategoryData
{
    NSError *fetchError = nil;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NewsCategoryEntityName];
    NSArray *categories = [self.context executeFetchRequest:request
                                                      error:&fetchError];
    if (fetchError)
    {
        DDLogError(@"'%@' fetch failed with error: %@",NewsCategoryEntityName, fetchError);
    }
    
    NSPredicate *categoryPredicate = [NSPredicate predicateWithFormat:@"category_id == $CATEGORY"];
    for (NSNumber *categoryId in [NewStoryListViewController newsCategoryNames])
    {
        NSPredicate *filterPredicate = [categoryPredicate predicateWithSubstitutionVariables:@{ @"CATEGORY" : categoryId }];
        NSManagedObject *category = [[categories filteredArrayUsingPredicate:filterPredicate] lastObject];
        
        if (category == nil)
        {
            category = [NSEntityDescription insertNewObjectForEntityForName:NewsCategoryEntityName
                                                     inManagedObjectContext:self.context];
            [category setValue:categoryId
                        forKey:@"category_id"];
        }
        
        // Not used but it needs to be set to zero for legacy reasons
        [category setValue:@(0)
                    forKey:@"expectedCount"];
    }
    
    [self.context save:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - CoreData Entity Management
- (void)pruneStories:(BOOL)asyncPrune
{
    void (*dispatch_func)(dispatch_queue_t,dispatch_block_t) = NULL;
    
    if (asyncPrune)
    {
        dispatch_func = &dispatch_async;
    }
    else
    {
        dispatch_func = &dispatch_sync;
    }
    
    dispatch_queue_t queue = dispatch_queue_create("news.prune", NULL);
    (*dispatch_func)(queue, ^{
        static NSUInteger articleSaveCount = 10;
        
        NSManagedObjectContext *pruneContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        pruneContext.parentContext = self.context;
        pruneContext.undoManager = nil;
        pruneContext.mergePolicy = NSOverwriteMergePolicy;
        [pruneContext lock];
        
        NSMutableSet *deleteSet = [NSMutableSet set];
        
        NSPredicate *notBookmarkedPredicate = [NSPredicate predicateWithFormat:@"(bookmarked == nil) || (bookmarked == NO)"];
        NSPredicate *templatePredicate = [NSPredicate predicateWithFormat:@"ANY categories.category_id == $CATEGORY"];
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:NewsStoryEntityName];
        fetchRequest.sortDescriptors = [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"postDate" ascending:NO]];
        
        [[NewStoryListViewController newsCategoryOrder] enumerateObjectsUsingBlock:^(NSNumber *categoryId, NSUInteger idx, BOOL *stop) {
            NSPredicate *catPredicate = [templatePredicate predicateWithSubstitutionVariables:@{ @"CATEGORY" : categoryId }];
            fetchRequest.predicate = [[NSCompoundPredicate alloc] initWithType:NSAndPredicateType
                                                                 subpredicates:@[notBookmarkedPredicate,
                                                                                    catPredicate]];
            NSArray *objects = [pruneContext executeFetchRequest:fetchRequest
                                                           error:nil];
            DDLogVerbose(@"fetched %d objects for category %@", [objects count], categoryId);
            NSInteger maxLen = MIN(articleSaveCount,[objects count]);
            
            [objects enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, maxLen)]
                                       options:0
                                    usingBlock:^(NSManagedObject *obj, NSUInteger idx, BOOL *stop) {
                                        [deleteSet removeObject:[obj objectID]];
                                    }];
            if ([objects count] > articleSaveCount)
            {
                [objects enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(articleSaveCount,[objects count] - articleSaveCount)]
                                           options:0
                                        usingBlock:^(NSManagedObject *obj, NSUInteger idx, BOOL *stop) {
                                            [deleteSet addObject:[obj objectID]];
                                        }];
            }
        }];
        
        for (NSManagedObjectID *objectId in deleteSet)
        {
            [pruneContext deleteObject:[pruneContext objectWithID:objectId]];
        }
        
        __block NSError *error = nil;
        [pruneContext save:&error];
        [pruneContext unlock];
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (error == nil)
            {
                [pruneContext.parentContext save:&error];
            }
        });
        
        if (error)
        {
            DDLogError(@"failed to save pruning context: %@", [error localizedDescription]);
        }
        else if (ddLogLevel == LOG_LEVEL_VERBOSE)
        {
            for (NSNumber *categoryId in [NewStoryListViewController newsCategoryOrder])
            {
                NSFetchRequest *countRequest = [NSFetchRequest fetchRequestWithEntityName:NewsStoryEntityName];
                countRequest.predicate = [templatePredicate predicateWithSubstitutionVariables:@{ @"CATEGORY" : categoryId }];
                NSUInteger count = [pruneContext countForFetchRequest:countRequest
                                                                error:nil];
                DDLogVerbose(@"category %@ has %lu articles after pruning", categoryId, (unsigned long)count);
            }
        }
    });
    
    dispatch_release(queue);
}

- (void)loadStoriesForCategory:(NSUInteger)categoryId isLoadingMore:(BOOL)loadMore forceRefresh:(BOOL)forceRefresh
{
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NewsCategoryEntityName];
    request.predicate = [NSPredicate predicateWithFormat:@"category_id == %lu",(unsigned long)categoryId];
    
    NSError *fetchError = nil;
    NSArray *categories = [self.context executeFetchRequest:request
                                                      error:&fetchError];
    
    if (fetchError || ([categories count] == 0))
    {
        DDLogError(@"failed to fetch object for category '%lu'", (unsigned long)categoryId);
        return;
    }
    
    NSManagedObject *category = categories[0];
    NSUInteger lastStoryId = 0;
    NSUInteger fetchCount = 10;
    
    if (loadMore)
    {
        id<NSFetchedResultsSectionInfo> sectionInfo = [[self.fetchController sections] objectAtIndex:0];
        NewsStory *lastStory = [[[sectionInfo objects] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"story_id"
                                                                                                                   ascending:NO]]] lastObject];
        lastStoryId = [[lastStory story_id] unsignedIntegerValue];
    }
    
    
    NSDate *lastUpdated = [category valueForKey:@"lastUpdated"];
    NSDate *updateDate = [NSDate dateWithTimeIntervalSinceNow:self.updateInterval];
    BOOL shouldUpdate = (loadMore ||
                         forceRefresh ||
                         (lastUpdated == nil) ||
                         ([updateDate compare:lastUpdated] != NSOrderedAscending));
    if (shouldUpdate)
    {
        StoryUpdateOperation *operation =  [[StoryUpdateOperation alloc] initWithCategory:categoryId
                                                                              lastStoryID:lastStoryId
                                                                               fetchLimit:fetchCount];
        operation.parentContext = self.context;
        operation.completeBlock = ^(NSArray* storyIDs,NSArray* addedStoryIDs,NSUInteger offset,NSError* error)
        {
            if (error && (error.code != NSUserCancelledError))
            {
                DDLogError(@"error performing update for category '%lu': %@", (unsigned long)category, error);
            }
            else
            {
                NSDate *currentDate = [NSDate date];
                [category setValue:currentDate
                            forKey:@"lastUpdated"];
                
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateStyle:NSDateFormatterMediumStyle];
                [formatter setTimeStyle:NSDateFormatterShortStyle];
                
                UILabel *updateLabel = (UILabel*)[self.activityView viewWithTag:StoryViewActivityUpdatedTag];
                updateLabel.text = [NSString stringWithFormat:@"Last updated %@", [formatter stringFromDate:currentDate]];
            }
            

            if (self.isSearching == NO)
            {
                if ([storyIDs count])
                {
                    self.tableView.tableFooterView = self.loadMoreView;
                }
                else
                {
                    self.tableView.tableFooterView = nil;
                }
                
                [self setTableFooterLoading:NO
                                   animated:YES];
            }
        };
        
        if (self.isSearching == NO)
        {
            [self setTableFooterLoading:YES
                               animated:YES];
        }
        
        [self.updateQueue addOperation:operation];
    }
}

- (void)loadStoriesForQuery:(NSString*)query
                loadingMore:(BOOL)loadMore
{
    NSUInteger offset = 0;
    NSFetchRequest *loadRequest = [[self.queryFetchController fetchRequest] copy];
    
    if (loadMore)
    {
        loadRequest.resultType = NSCountResultType;
        NSArray *objectCount = [self.context executeFetchRequest:loadRequest
                                                           error:nil];
        offset = [[objectCount objectAtIndex:0] unsignedIntegerValue];
    }

    if ([query length] > 2)
    {
        StoryUpdateOperation *updateOperation = [[StoryUpdateOperation alloc] initWithQuery:query
                                                                                     offset:offset
                                                                                 fetchLimit:10];
        updateOperation.parentContext = self.context;
        updateOperation.completeBlock = ^(NSArray* storyIDs,NSArray* addedStoryIDs,NSUInteger offset,NSError* error)
        {
            
            if (error && (error.code != NSUserCancelledError))
            {
                DDLogError(@"error performing update for query '%@'[%lu,%d]: %@", query, (unsigned long)offset, 10, error);
            }
            else if (self.isSearching)
            {
                if ([storyIDs count] == 0)
                {
                    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:nil
                                                                        message:@"No matching articles found."
                                                                       delegate:self
                                                              cancelButtonTitle:@"OK"
                                                              otherButtonTitles:nil];
                    [alertView show];
                }
                else
                {
                    self.searchController.searchResultsTableView.hidden = NO;
                    [self.searchController hideSearchOverlayAnimated:YES];
                    
                    if ([storyIDs count])
                    {
                        self.searchController.searchResultsTableView.tableFooterView = self.loadMoreView;
                    }
                    else
                    {
                        self.searchController.searchResultsTableView.tableFooterView = nil;
                    }
                    
                    [self setTableFooterLoading:NO
                                       animated:YES];
                }
            }
        };
        
        if (self.isSearching)
        {
            [self setTableFooterLoading:YES
                               animated:YES];
        }
        
        [self.updateQueue cancelAllOperations];
        [self.updateQueue addOperation:updateOperation];
    }
}
#pragma mark -

#pragma mark - Dynamic Properties
- (void)setTableFooterLoading:(BOOL)loading animated:(BOOL)animate
{
    UITableView *activeTableView = nil;
    
    if (self.isSearching)
    {
        activeTableView = self.searchController.searchResultsTableView;
    }
    else
    {
        activeTableView = self.tableView;
    }
    
    if (activeTableView.tableFooterView)
    {
    
        if (loading)
        {
            [UIView animateWithDuration:(animate ? 0.4 : 0)
                             animations:^{
                                 UIButton *loadButton = (UIButton*)[self.loadMoreView viewWithTag:StoryTableFooterButtonTag];
                                 UIActivityIndicatorView *activityView = (UIActivityIndicatorView*)[self.loadMoreView viewWithTag:StoryTableFooterActivityTag];
                                 loadButton.hidden = YES;
                                 [activityView startAnimating];
                             }];
        }
        else
        {
            [UIView animateWithDuration:(animate ? 0.4 : 0)
                             animations:^{
                                 UIButton *loadButton = (UIButton*)[self.loadMoreView viewWithTag:StoryTableFooterButtonTag];
                                 UIActivityIndicatorView *activityView = (UIActivityIndicatorView*)[self.loadMoreView viewWithTag:StoryTableFooterActivityTag];
                                 [activityView stopAnimating];
                                 loadButton.hidden = NO;
                             }];
        }
    }
}

- (void)setActiveCategoryId:(NSInteger)activeCategoryId
{
    if (activeCategoryId != _activeCategoryId)
    {
        _activeCategoryId = activeCategoryId;
        [self.navScroller selectButtonWithTag:activeCategoryId];
        
        if (self.isSearching == NO)
        {
            NSFetchRequest *request = self.fetchController.fetchRequest;
            
            request.predicate = [NSPredicate predicateWithFormat:@"ANY categories.category_id == %lu", self.activeCategoryId];
            [self.fetchController performFetch:nil];
            [self.tableView reloadData];
            
            [self loadStoriesForCategory:self.activeCategoryId
                           isLoadingMore:NO
                            forceRefresh:NO];
        }
    }
}

- (void)clearQueryResults
{
    //Clear out any current search results
    NSArray *objects = [self.context executeFetchRequest:self.queryFetchController.fetchRequest
                                                   error:nil];
    for (NewsStory *obj in objects)
    {
        obj.searchResult = [NSNumber numberWithBool:NO];
    }
    
    [self.context save:nil];
}

- (void)setSearchQuery:(NSString *)searchQuery
{
    if ([_searchQuery isEqualToString:searchQuery] == NO)
    {
        _searchQuery = searchQuery;
        [self clearQueryResults];
        
        [self loadStoriesForQuery:searchQuery
                              loadingMore:NO];
    }
}

#pragma mark - UITableView Delegate
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return THUMBNAIL_WIDTH;
}

#pragma mark - UITableView Data Source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    NSInteger count = 0;
    
    if (tableView == self.tableView)
    {
        count = [[self.fetchController sections] count];
    }
    else
    {
        count = [[self.queryFetchController sections] count];
    }
    
    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger count = 0;
    
    if (tableView == self.tableView)
    {
        count = [[[self.fetchController sections] objectAtIndex:section] numberOfObjects];
    }
    else
    {
        count = [[[self.queryFetchController sections] objectAtIndex:section] numberOfObjects];
        DDLogVerbose(@"found %d rows in section %d", count, section);
    }
    
    return count;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:StoryListCellIdentifier];
    
    UILabel *titleLabel = nil;
    UILabel *summaryLabel = nil;
    
    NewsStory *story = nil;
    
    if (tableView == self.tableView)
    {
        id<NSFetchedResultsSectionInfo> sectionInfo = [[self.fetchController sections] objectAtIndex:indexPath.section];
        story = [sectionInfo objects][indexPath.row];
    }
    else
    {
        id<NSFetchedResultsSectionInfo> sectionInfo = [[self.queryFetchController sections] objectAtIndex:indexPath.section];
        story = [sectionInfo objects][indexPath.row];
    }
    
    if (cell == nil)
    {
        // Set up the cell
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:StoryListCellIdentifier];
        
        // Title View
        titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.tag = StoryListCellTitleTag;
        titleLabel.font = [UIFont boldSystemFontOfSize:STORY_TITLE_FONT_SIZE];
        titleLabel.numberOfLines = 0;
        titleLabel.lineBreakMode = UILineBreakModeTailTruncation;
        [cell.contentView addSubview:titleLabel];
        
        // Summary View
        summaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        summaryLabel.tag = StoryListCellSummaryTag;
        summaryLabel.font = [UIFont systemFontOfSize:STORY_DEK_FONT_SIZE];
        summaryLabel.textColor = [UIColor colorWithHexString:@"#0D0D0D"];
        summaryLabel.highlightedTextColor = [UIColor whiteColor];
        summaryLabel.numberOfLines = 0;
        summaryLabel.lineBreakMode = UILineBreakModeTailTruncation;
        [cell.contentView addSubview:summaryLabel];
        
        StoryThumbnailView *thumbnailView = [[StoryThumbnailView alloc] initWithFrame:CGRectMake(0, 0, THUMBNAIL_WIDTH, THUMBNAIL_WIDTH)];
        thumbnailView.tag = StoryListCellThumbnailTag;
        [cell.contentView addSubview:thumbnailView];
        
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    
    [self configureCell:cell
           forIndexPath:indexPath
            usingObject:story];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    StoryDetailViewController *detailViewController = [[StoryDetailViewController alloc] init];
    detailViewController.newsController = self;
    NewsStory *story = nil;
    
    if (tableView == self.tableView)
    {
        id<NSFetchedResultsSectionInfo> sectionInfo = [[self.fetchController sections] objectAtIndex:indexPath.section];
        story = [sectionInfo objects][indexPath.row];
    }
    else
    {
        id<NSFetchedResultsSectionInfo> sectionInfo = [[self.queryFetchController sections] objectAtIndex:indexPath.section];
        story = [sectionInfo objects][indexPath.row];
    }
    
    detailViewController.story = story;
        
    [self.navigationController pushViewController:detailViewController
                                         animated:YES];
}


- (void)configureCell:(UITableViewCell*)cell
         forIndexPath:(NSIndexPath*)indexPath
          usingObject:(id)obj;
{
    UILabel *titleLabel = nil;
    UILabel *summaryLabel = nil;
    StoryThumbnailView *thumbnailView = nil;
    NewsStory *story = (NewsStory*)obj;
    
    titleLabel = (UILabel *)[cell viewWithTag:StoryListCellTitleTag];
    summaryLabel = (UILabel *)[cell viewWithTag:StoryListCellSummaryTag];
    thumbnailView = (StoryThumbnailView *)[cell viewWithTag:StoryListCellThumbnailTag];
    
    titleLabel.text = story.title;
    summaryLabel.text = story.summary;
    
    titleLabel.textColor = ([story.read boolValue]) ? [UIColor colorWithHexString:@"#666666"] : [UIColor blackColor];
    titleLabel.highlightedTextColor = [UIColor whiteColor];
    
    // Calculate height
    CGFloat availableHeight = STORY_TEXT_HEIGHT;
    CGSize titleDimensions = [titleLabel.text sizeWithFont:titleLabel.font
                                         constrainedToSize:CGSizeMake(STORY_TEXT_WIDTH, availableHeight)
                                             lineBreakMode:UILineBreakModeTailTruncation];
    availableHeight -= titleDimensions.height;
    
    CGSize summaryDimensions = CGSizeZero;
    // if not even one line will fit, don't show the deck at all
    if (availableHeight > summaryLabel.font.lineHeight)
    {
        summaryDimensions = [summaryLabel.text sizeWithFont:summaryLabel.font
                                          constrainedToSize:CGSizeMake(STORY_TEXT_WIDTH, availableHeight)
                                              lineBreakMode:UILineBreakModeTailTruncation];
    }
    
    
    titleLabel.frame = CGRectMake(THUMBNAIL_WIDTH + STORY_TEXT_PADDING_LEFT,
                                  STORY_TEXT_PADDING_TOP,
                                  STORY_TEXT_WIDTH,
                                  titleDimensions.height);
    summaryLabel.frame = CGRectMake(THUMBNAIL_WIDTH + STORY_TEXT_PADDING_LEFT,
                                    ceil(CGRectGetMaxY(titleLabel.frame)),
                                    STORY_TEXT_WIDTH,
                                    summaryDimensions.height);
    
    thumbnailView.imageRep = story.inlineImage.thumbImage;
    [thumbnailView loadImage];
}

#pragma mark - Search UI Management
- (void)showSearchBar
{
    if (self.searchBar == nil)
    {
        UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0.0, 0.0, CGRectGetWidth(self.view.bounds), 44.0)];
        searchBar.tintColor = SEARCH_BAR_TINT_COLOR;
        searchBar.hidden = YES;
        searchBar.translucent = NO;
        searchBar.delegate = self;
        
        self.searchBar = searchBar;
        [self.view addSubview:searchBar];
    }
    
    if (self.searchController == nil)
    {
        MITSearchDisplayController *searchController = [[MITSearchDisplayController alloc] initWithFrame:self.tableView.frame
                                                                                               searchBar:self.searchBar
                                                                                      contentsController:self];
        searchController.delegate = self;
        searchController.searchResultsDelegate = self;
        searchController.searchResultsDataSource = self;
        searchController.searchResultsTableView.hidden = YES;
        [self.view insertSubview:searchController.searchResultsTableView
                    aboveSubview:self.tableView];
        self.searchController = searchController;
    }
    
    if (self.queryFetchController == nil)
    {
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NewsStoryEntityName];
        request.predicate = [NSPredicate predicateWithFormat:@"(searchResult != nil) && (searchResult == YES)"];
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"postDate" ascending:NO],
                                    [NSSortDescriptor sortDescriptorWithKey:@"story_id" ascending:NO]];
        
        NSFetchedResultsController *queryController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                                                                          managedObjectContext:self.context
                                                                                            sectionNameKeyPath:nil
                                                                                                     cacheName:nil];

        self.queryFetchController = queryController;
    }
    
    self.queryFetchController.delegate = self;
    [self.queryFetchController performFetch:nil];
    
    [UIView transitionWithView:self.view
                      duration:0.4
                       options:UIViewAnimationOptionBeginFromCurrentState
                    animations:^{
                        [self.view bringSubviewToFront:self.searchBar];
                        self.searchBar.hidden = NO;
                    }
                    completion:^(BOOL finished) {
                        if (finished)
                        {
                            self.isSearching = YES;
                            [self.searchController setActive:YES
                                                    animated:YES];
                        }
                    }];
}

- (void)hideSearchBar
{
    if (self.searchBar)
    {
        self.queryFetchController.delegate = nil;
        [UIView transitionWithView:self.view
                          duration:0.4
                           options:UIViewAnimationOptionBeginFromCurrentState
                        animations:^{
                            self.searchBar.hidden = YES;
                            self.searchController.searchResultsTableView.hidden = YES;
                        }
                        completion:^(BOOL finished) {
                            if (finished)
                            {
                                [self.searchController setActive:NO
                                                        animated:YES];
                                
                                self.searchController.searchResultsTableView.tableFooterView = nil;
                                self.isSearching = NO;
                            }
                        }];
    }
}


#pragma mark - IBAction Handlers
- (IBAction)loadMoreStories:(id)sender
{
    UIButton *loadButton = (UIButton*)[self.loadMoreView viewWithTag:StoryTableFooterButtonTag];
    UIActivityIndicatorView *activityView = (UIActivityIndicatorView*)[self.loadMoreView viewWithTag:StoryTableFooterActivityTag];
    [UIView animateWithDuration:0.4
                     animations:^{
                         loadButton.hidden = YES;
                     }
                     completion:^(BOOL finished) {
                         if (finished)
                         {
                             [activityView startAnimating];
                         }
                     }];
    
    if (self.isSearching)
    {
        [self loadStoriesForQuery:self.searchQuery
                      loadingMore:YES];
    }
    else
    {
        [self loadStoriesForCategory:self.activeCategoryId
                       isLoadingMore:YES
                        forceRefresh:NO];
    }
}

- (IBAction)refresh:(id)sender
{
    if (self.isSearching)
    {
        [self loadStoriesForQuery:self.searchQuery
                      loadingMore:NO];
    }
    else
    {
        [self loadStoriesForCategory:self.activeCategoryId
                       isLoadingMore:NO
                        forceRefresh:YES];
    }
}


#pragma mark - NavScrollerDelegate
- (void)buttonPressed:(id)sender
{
    UIButton *pressedButton = (UIButton *)sender;
    if (pressedButton.tag == StoryNavButtonSearchTag)
    {
        [self showSearchBar];
    }
    else
    {
        self.activeCategoryId = pressedButton.tag;
    }
}

#pragma mark - MITSearchController Delegation
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self hideSearchBar];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    self.searchQuery = searchBar.text;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    if ([searchText length] == 0)
    {
        self.searchController.searchResultsTableView.hidden = YES;
        [self.searchController showSearchOverlayAnimated:YES];
    }
}


#pragma mark - StoryListPagingDelegate
- (BOOL)canSelectNextStory:(NewsStory*)currentStory
{
    id<NSFetchedResultsSectionInfo> sectionInfo = [self.fetchController sections][0];
    
    return (([[sectionInfo objects] containsObject:currentStory]) &&
            ([[sectionInfo objects] indexOfObject:currentStory] < ([sectionInfo numberOfObjects] - 1)));
}

- (BOOL)canSelectPreviousStory:(NewsStory*)currentStory
{
    id<NSFetchedResultsSectionInfo> sectionInfo = [self.fetchController sections][0];
    
    return (([[sectionInfo objects] containsObject:currentStory]) &&
            ([[sectionInfo objects] indexOfObject:currentStory] > 0));
}

- (NewsStory*)selectNextStory:(NewsStory*)currentStory
{
    id<NSFetchedResultsSectionInfo> sectionInfo = [self.fetchController sections][0];
    
    if ([self canSelectNextStory:currentStory])
    {
        return [[sectionInfo objects] objectAtIndex:[[sectionInfo objects] indexOfObject:currentStory] + 1];
    }

    return nil;
}

- (NewsStory*)selectPreviousStory:(NewsStory*)currentStory
{
    id<NSFetchedResultsSectionInfo> sectionInfo = [self.fetchController sections][0];
    
    if ([self canSelectPreviousStory:currentStory])
    {
        return [[sectionInfo objects] objectAtIndex:[[sectionInfo objects] indexOfObject:currentStory] - 1];
    }
    
    return nil;
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    if (controller == self.fetchController)
    {
        [self.tableView beginUpdates];
    }
    else
    {
        [self.searchController.searchResultsTableView beginUpdates];
    }
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {
    
    UITableView *tableView = nil;
    
    if (controller == self.fetchController)
    {
        tableView = self.tableView;
    }
    else
    {
        tableView = self.searchController.searchResultsTableView;
    }
    
    switch(type) {
            
        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
            
        case NSFetchedResultsChangeUpdate:
        {
            [tableView reloadRowsAtIndexPaths:@[indexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
        }
            
        case NSFetchedResultsChangeMove:
            [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            [tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath]
                             withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    if (controller == self.fetchController)
    {
        [self.tableView endUpdates];
    }
    else
    {
        [self.searchController.searchResultsTableView endUpdates];
    }
}
@end
