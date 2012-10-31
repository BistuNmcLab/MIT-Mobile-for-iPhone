#import <CoreData/CoreData.h>
#import "StoryUpdateOperation.h"

#import "GDataHTMLDocument.h"
#import "GDataXMLNode.h"
#import "NewsImage.h"
#import "NewsStory.h"
#import "NewsImageRep.h"
#import "CoreDataManager.h"
#import "MITMobileServerConfiguration.h"
#import "Foundation+MITAdditions.h"
#import "StoryXMLParser.h"

@interface StoryUpdateOperation ()
@property (nonatomic,assign,getter=isFinished) BOOL finished;
@property (nonatomic,assign,getter=isExecuting) BOOL executing;
@property (nonatomic,strong) NSError *error;
@property (nonatomic,strong) NSArray *storyIDs;
@property (nonatomic,strong) NSArray *addedStoryIDs;
@property (nonatomic,assign) dispatch_queue_t operationQueue;

@property (nonatomic,strong) NSDateFormatter *postDateFormatter;
@property (nonatomic,readonly) BOOL isTopStories;
@property (nonatomic,readonly) BOOL isQuery;
+ (NSOperationQueue*)networkRequestQueue;
@end

@implementation StoryUpdateOperation
+ (NSOperationQueue*)networkRequestQueue
{
    static NSOperationQueue *sharedQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedQueue = [[NSOperationQueue alloc] init];
        sharedQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    });
    
    return sharedQueue;
}

- (id)init
{
    return [self initWithCategory:0];
}

- (id)initWithCategory:(NSUInteger)category
{
    return [self initWithCategory:category
                      lastStoryID:0
                       fetchLimit:10];
}

- (id)initWithCategory:(NSUInteger)category
            lastStoryID:(NSUInteger)lastStoryID
            fetchLimit:(NSUInteger)limit
{
    self = [super init];
    
    if (self)
    {
        self.category = category;
        self.lastStoryId = lastStoryID;
        self.fetchLimit = limit;
    }
    
    return self;
}

- (id)initWithQuery:(NSString *)query
             offset:(NSUInteger)offset
         fetchLimit:(NSUInteger)limit
{
    self = [super init];
    
    if (self)
    {
        self.query = query;
        self.offset = offset;
        self.fetchLimit = limit;
    }
    
    return self;
}

#pragma mark - NSOperation Methods
- (void)start
{
    self.executing = YES;
    self.finished = NO;
    
    if ([self isCancelled])
    {
        [self finish];
        return;
    }
    
    self.operationQueue = dispatch_get_current_queue();
    
    [NSURLConnection sendAsynchronousRequest:[self urlRequest]
                                       queue:[StoryUpdateOperation networkRequestQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                               dispatch_async(self.operationQueue, ^{
                                   if (error)
                                   {
                                       self.error = error;
                                   }
                                   else if ([data length] == 0)
                                   {
                                       self.error = [NSError errorWithDomain:NSURLErrorDomain
                                                                        code:NSURLErrorBadServerResponse
                                                                    userInfo:nil];
                                   }
                                   else
                                   {
                                       [self parseStoryData:data];
                                   }
                                   
                                   [self finish];
                               });
                           }];
}

- (BOOL)isConcurrent
{
    return YES;
}


- (void)finish
{
    if ([self isCancelled])
    {
        NSDictionary *userInfo = nil;
        if (self.error)
        {
            userInfo = @{NSUnderlyingErrorKey : @[self.error]};
        }
        
        self.error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSUserCancelledError
                                     userInfo:userInfo];
    }

    if (self.error)
    {
        DDLogError(@"parse failed: %@", [self.error localizedDescription]);
    }

    if (self.completeBlock)
    {
        
        NSError *error = self.error;
        NSArray *storyIds = self.storyIDs;
        NSArray *addedIds = self.addedStoryIDs;
        NSUInteger offset = self.offset;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.completeBlock(storyIds,addedIds,offset,error);
        });
    }
    
    self.executing = NO;
    self.finished = YES;
}

#pragma mark - Dynamic Properties
- (BOOL)isQuery
{
    return ([self.query length] > 0);
}

- (BOOL)isTopStories
{
    return ((self.category == 0) && self.isQuery);
}

- (void)setFinished:(BOOL)finished
{
    if (self.finished != finished)
    {
        [self willChangeValueForKey:@"isFinished"];
        _finished = finished;
        [self didChangeValueForKey:@"isFinished"];
    }
}

- (void)setExecuting:(BOOL)executing
{
    if (self.executing != executing)
    {
        [self willChangeValueForKey:@"isExecuting"];
        _executing = executing;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

#pragma mark - Story parsing methods
- (NSURLRequest*)urlRequest
{
    NSURLRequest *request = nil;
    if (self.isQuery)
    {
        NSMutableString *url = [NSMutableString stringWithString:@"http://web.mit.edu/newsoffice/index.php?option=com_search&view=isearch&ordering=newest"];
        [url appendFormat:@"&searchWord=%@", [self.query urlEncodeUsingEncoding:NSUTF8StringEncoding]];
        [url appendFormat:@"&start=%lu", (unsigned long)self.offset];
        [url appendFormat:@"&count=%lu", (unsigned long)self.fetchLimit];
        
        request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    }
    else
    {
        NSMutableString *newsURL = [NSMutableString stringWithString:[MITMobileWebGetCurrentServerURL() absoluteString]];
        
        if (MITMobileWebGetCurrentServerType() == MITMobileWebDevelopment)
        {
            [newsURL appendString:@"/newsoffice-dev/"];
        }
        else
        {
            [newsURL appendString:@"/newsoffice/"];
        }
        
        NSMutableArray *parameters = [NSMutableArray array];
        if (self.lastStoryId)
        {
            [parameters addObject:[NSString stringWithFormat:@"story_id=%lu",(unsigned long)self.lastStoryId]];
        }
        
        if (self.category)
        {
            [parameters addObject:[NSString stringWithFormat:@"channel=%lu",(unsigned long)self.category]];
        }
        
        if ([parameters count])
        {
            [newsURL appendFormat:@"?%@",[parameters componentsJoinedByString:@"&"]];
        }
        
        request = [NSURLRequest requestWithURL:[NSURL URLWithString:newsURL]];
    }
    
    return request;
}


- (void)parseStoryData:(NSData*)storyData
{
    NSMutableArray *stories = [NSMutableArray array];
    NSMutableArray *addedStories = [NSMutableArray array];
    NSError *error = nil;
    GDataXMLDocument *doc = [[GDataXMLDocument alloc] initWithData:storyData
                                                            options:(XML_PARSE_RECOVER |
                                                                     XML_PARSE_NOWARNING |
                                                                     XML_PARSE_NONET)
                                                              error:&error];
    
    if (error)
    {
        self.error = error;
        return;
    }
    
    
    NSManagedObjectContext *importContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    importContext.undoManager = nil;
    //importContext.persistentStoreCoordinator = [[CoreDataManager coreDataManager] persistentStoreCoordinator];
    importContext.mergePolicy = NSOverwriteMergePolicy;
    importContext.parentContext = self.parentContext;
    
    NSArray *items = [doc.rootElement nodesForXPath:@"//channel/item"
                                              error:&error];
    if (error)
    {
        self.error = error;
        return;
    }
    
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    [formatter setDateFormat:@"EEE, d MMM y HH:mm:ss zzz"];
    [formatter setTimeZone:[NSTimeZone localTimeZone]];
    self.postDateFormatter = formatter;
    
    
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:NewsStoryEntityName];
    request.predicate = [NSPredicate predicateWithFormat:@"ANY categories.category_id == %lu", (long unsigned)self.category];
    NSArray *allStories = [importContext executeFetchRequest:request
                                                       error:&error];
    if (error)
    {
        self.error = error;
        return;
    }
    
    
    [items enumerateObjectsUsingBlock:^(GDataXMLNode *storyNode, NSUInteger idx, BOOL *stop) {
        GDataXMLNode *idNode = [self nodeForXPath:NewsTagStoryId
                                     withRootNode:storyNode
                                            error:nil];
        NSString *storyId = [[idNode childAtIndex:0] stringValue];
        NewsStory *story = nil;
        
        if ([storyId length])
        {
            NSArray *objects = [allStories filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"'story_id' == %d",[storyId integerValue]]];
            
            if ([objects count])
            {
                story = objects[0];
            }
        }
        
        if (story == nil)
        {
            story = (NewsStory*)[NSEntityDescription insertNewObjectForEntityForName:NewsStoryEntityName
                                                              inManagedObjectContext:importContext];
            [addedStories addObject:story];
        }
        
        [self parseStoryNode:storyNode
           withManagedObject:story];
        
        [stories addObject:story];
        
        if (self.error || [self isCancelled])
        {
            (*stop) = YES;
        }
    }];
    
    if (self.error || [self isCancelled])
    {
        return;
    }
    else
    {
        __block NSError* saveError = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [importContext save:&saveError];
        });
        
        error = saveError;
        
        if (error)
        {
            self.error = error;
            for (NSError *nestedError in [[error userInfo] objectForKey:NSDetailedErrorsKey])
            {
                DDLogVerbose(@"\tError: %@",nestedError);
            }
        }
        else
        {
            NSMutableArray *addedIDs = [NSMutableArray array];
            [addedStories enumerateObjectsUsingBlock:^(NSManagedObject* obj, NSUInteger idx, BOOL *stop) {
                [addedIDs addObject:[obj objectID]];
            }];
            self.addedStoryIDs = addedIDs;
            
            NSMutableArray *storyIDs = [NSMutableArray array];
            [stories enumerateObjectsUsingBlock:^(NSManagedObject* obj, NSUInteger idx, BOOL *stop) {
                [storyIDs addObject:[obj objectID]];
            }];
            self.storyIDs = storyIDs;
        }
    }
}

- (void)parseStoryNode:(GDataXMLNode*)node withManagedObject:(NewsStory*)story
{
    NSArray *flatElements = @[NewsTagTitle, NewsTagAuthor, NewsTagCategory,
    NewsTagLink, NewsTagStoryId, NewsTagFeatured,
    NewsTagSummary, NewsTagPostDate, NewsTagBody];
    
    NSMutableDictionary *elements = [NSMutableDictionary dictionary];
    for (NSString *elementName in flatElements)
    {
        id obj = [[[self nodeForXPath:elementName
                         withRootNode:node
                                error:nil] childAtIndex:0] stringValue];
        if (obj)
        {
            elements[elementName] = obj;
        }
    }
    
    story.story_id = [NSNumber numberWithInteger:[elements[NewsTagStoryId] integerValue]];
    story.title = elements[NewsTagTitle];
    story.author = elements[NewsTagAuthor];
    story.summary = (elements[NewsTagSummary] == nil) ? @"" : elements[NewsTagSummary];
    story.body = elements[NewsTagBody];
    story.link = elements[NewsTagLink];
    
    story.postDate = [self.postDateFormatter dateFromString:elements[NewsTagPostDate]];
    story.featured = [NSNumber numberWithBool:[elements[NewsTagFeatured] boolValue]];
    story.searchResult = [NSNumber numberWithBool:self.isSearch];
    
    NSInteger category = [elements[NewsTagCategory] integerValue];
    [story addCategory:category];
    
    story.topStory = [NSNumber numberWithBool:(story.topStory || self.isTopStories)];
    
    
    GDataXMLNode *imageNode = [self nodeForXPath:NewsTagImage
                                    withRootNode:node
                                           error:nil];
    story.inlineImage = [self newsImageWithNode:imageNode
                              withObjectContext:story.managedObjectContext];
    
    GDataXMLNode *otherImagesNode = [self nodeForXPath:NewsTagOtherImages
                                          withRootNode:node
                                                 error:nil];
    
    if (otherImagesNode)
    {
        NSArray *otherImages = [otherImagesNode nodesForXPath:NewsTagImage
                                                        error:nil];
        [otherImages enumerateObjectsUsingBlock:^(GDataXMLNode *imageNode, NSUInteger idx, BOOL *stop) {
            NewsImage *otherImage = [self newsImageWithNode:imageNode
                                          withObjectContext:story.managedObjectContext];
            if (otherImage)
            {
                otherImage.ordinality = [NSNumber numberWithUnsignedInteger:idx];
                [story addGalleryImage:otherImage];
            }
        }];
    }
}

- (NewsImage*)newsImageWithNode:(GDataXMLNode*)node withObjectContext:(NSManagedObjectContext*)context
{
    NewsImage *newsImage = nil;
    GDataXMLNode *fullURLNode = [self nodeForXPath:NewsTagSmallURL
                                      withRootNode:node
                                             error:nil];
    
    if (fullURLNode && ([fullURLNode kind] == GDataXMLElementKind))
    {
        GDataXMLElement *fullElement = (GDataXMLElement*)fullURLNode;
        NSString *url = [[fullElement childAtIndex:0] stringValue];
        
        // Check to see if the story exists first
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:NewsImageEntityName];
        request.predicate = [NSPredicate predicateWithFormat:@"fullImage.url == %@", url];
        NSArray *images = [context executeFetchRequest:request
                                                 error:nil];
        
        if ([images count] == 0)
        {
            newsImage = [NSEntityDescription insertNewObjectForEntityForName:NewsImageEntityName
                                                      inManagedObjectContext:context];
        }
        else
        {
            newsImage = images[0];
        }
        
        
        NSInteger width = [[[fullElement attributeForName:@"width"] stringValue] integerValue];
        NSInteger height = [[[fullElement attributeForName:@"height"] stringValue] integerValue];
        
        newsImage.fullImage = [self imageRepForURLString:url
                                             withContext:context];
        newsImage.fullImage.width = [NSNumber numberWithInteger:width];
        newsImage.fullImage.height = [NSNumber numberWithInteger:height];
        
    }
    
    
    GDataXMLNode *smallURLNode = [self nodeForXPath:NewsTagFullURL
                                       withRootNode:node
                                              error:nil];
    if (smallURLNode && ([smallURLNode kind] == GDataXMLElementKind))
    {
        GDataXMLElement *smallElement = (GDataXMLElement*)smallURLNode;
        
        NSString *url = [[smallElement childAtIndex:0] stringValue];
        NSInteger width = [[[smallElement attributeForName:@"width"] stringValue] integerValue];
        NSInteger height = [[[smallElement attributeForName:@"height"] stringValue] integerValue];
        
        newsImage.smallImage = [self imageRepForURLString:url
                                              withContext:context];
        newsImage.smallImage.width = [NSNumber numberWithInteger:width];
        newsImage.smallImage.height = [NSNumber numberWithInteger:height];
    }
    
    
    newsImage.credits = [[[self nodeForXPath:NewsTagImageCredits
                                withRootNode:node
                                       error:nil] childAtIndex:0] stringValue];
    newsImage.caption = [[[self nodeForXPath:NewsTagImageCaption
                                withRootNode:node
                                       error:nil] childAtIndex:0] stringValue];
    
    NSString *thumbURL = [[[self nodeForXPath:[self newsTagThumbURL]
                                 withRootNode:node
                                        error:nil] childAtIndex:0] stringValue];
    if ([thumbURL length])
    {
        newsImage.thumbImage = [self imageRepForURLString:thumbURL
                                              withContext:context];
    }
    
    return newsImage;
}

- (GDataXMLNode*)nodeForXPath:(NSString*)path
                 withRootNode:(GDataXMLNode*)rootNode
                        error:(NSError**)error
{
    NSArray *nodes = [rootNode nodesForXPath:path
                                       error:error];
    GDataXMLNode *result = nil;
    
    if ([nodes count])
    {
        result = nodes[0];
    }
    
    return result;
}

- (NewsImageRep*)imageRepForURLString:(NSString*)urlString withContext:(NSManagedObjectContext*)context
{
    NewsImageRep *imageRep = nil;
    if ([urlString length])
    {
        // Check to see if the story exists first
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:NewsImageRepEntityName];
        request.predicate = [NSPredicate predicateWithFormat:@"url == %@", urlString];
        NSArray *images = [context executeFetchRequest:request
                                                 error:nil];
        
        if ([images count] == 0)
        {
            imageRep = [NSEntityDescription insertNewObjectForEntityForName:NewsImageRepEntityName
                                                     inManagedObjectContext:context];
            imageRep.url = urlString;
        }
        else
        {
            imageRep = images[0];
        }
        
    }
    
    return imageRep;
}

- (NSString *)newsTagThumbURL {
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]
        && [[UIScreen mainScreen] scale] == 2.0)
    {
        return NewsTagThumbnail2xURL;
    }
    return NewsTagThumbnailURL;
}
@end
