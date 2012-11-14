#import "StoryParser.h"
#import "StoryUpdateOperation.h"

@interface StoryParser ()
@property (nonatomic,strong) NSOperationQueue *queue;
@property (nonatomic,weak) NSManagedObjectContext *parentContext;


@property (nonatomic, assign) BOOL parsingTopStories;
@property (nonatomic, assign) BOOL isSearch;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) NSInteger totalAvailableResults;
@property (nonatomic, retain) NSArray *addedStories;
@end

@implementation StoryParser
- (id)initWithParentContext:(NSManagedObjectContext *)context
{
    self = [super init];
    
    if (self)
    {
        NSOperationQueue *operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.maxConcurrentOperationCount = 1;
        self.queue = operationQueue;
        
        self.parentContext = context;
    }
    
    return self;
}

- (void)loadStoriesForCategory:(NSInteger)category
                  afterStoryId:(NSInteger)storyId
                         count:(NSInteger)count
{
    StoryUpdateOperation *operation = [[StoryUpdateOperation alloc] initWithCategory:category
                                                                         lastStoryID:storyId
                                                                          fetchLimit:count];
    operation.parentContext = self.parentContext;
    operation.progressBlock = ^(NSUInteger storyCount, NSUInteger expectedCount)
    {
        if ([self.delegate respondsToSelector:@selector(parser:didMakeProgress:)])
        {
            [self.delegate parser:self
                  didMakeProgress:((CGFloat)storyCount) / ((CGFloat)expectedCount)];
        }
    };
    
    operation.completeBlock = ^(NSArray* storyIds,NSArray* addedStoryIDs, NSUInteger offset, NSError* error)
    {
        self.totalAvailableResults = [storyIds count];
        self.addedStories = addedStoryIDs;
        self.loadingMore = (storyId > 0);
        self.parsingTopStories = (category == 0);
        self.isSearch = NO;
        
        if (error)
        {
            if (error.domain == NSURLErrorDomain)
            {
                if ([self.delegate respondsToSelector:@selector(parser:didFailWithDownloadError:)])
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate parser:self
                     didFailWithDownloadError:error];
                    });
                }
            }
            else
            {
                if ([self.delegate respondsToSelector:@selector(parser:didFailWithParseError:)])
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate parser:self
                        didFailWithParseError:error];
                    });
                }
            }
        }
        else
        {
            if ([self.delegate respondsToSelector:@selector(parserDidFinishParsing:)])
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate parserDidFinishParsing:self];
                });
            }
        }
    };
    
    [self.queue addOperation:operation];
}

- (void)loadStoriesforQuery:(NSString *)query
                 afterIndex:(NSInteger)start
                      count:(NSInteger)count
{
    if ([self.queue operationCount] > 0)
        [self.queue cancelAllOperations];
    
    StoryUpdateOperation *operation = [[StoryUpdateOperation alloc] initWithQuery:query
                                                                           offset:start
                                                                       fetchLimit:count];
    operation.parentContext = self.parentContext;
    operation.completeBlock = ^(NSArray* storyIds,NSArray *addedStoryIDs, NSUInteger offset, NSError* error)
    {
        self.totalAvailableResults = [storyIds count];
        self.addedStories = addedStoryIDs;
        self.loadingMore = (start > 0);
        self.parsingTopStories = NO;
        self.isSearch = YES;
        
        if (error)
        {
            if (error.domain == NSURLErrorDomain)
            {
                if ([self.delegate respondsToSelector:@selector(parser:didFailWithDownloadError:)])
                {
                    [self.delegate parser:self
                 didFailWithDownloadError:error];
                }
            }
            else
            {
                if ([self.delegate respondsToSelector:@selector(parser:didFailWithParseError:)])
                {
                    [self.delegate parser:self
                    didFailWithParseError:error];
                }
            }
        }
        else
        {
            if ([self.delegate respondsToSelector:@selector(parserDidFinishParsing:)])
            {
                [self.delegate parserDidFinishParsing:self];
            }
        }
    };
    
    [self.queue addOperation:operation];
}

- (void)abort
{
    if ([[self.queue operations] count] > 0)
    {
        [[[self.queue operations] lastObject] cancel];
    }
}
@end
