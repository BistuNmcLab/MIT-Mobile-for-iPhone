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
#import "StoryListViewController.h"

NSString * const NewsTagItem            = @"item";
NSString * const NewsTagTitle           = @"title";
NSString * const NewsTagAuthor          = @"author";
NSString * const NewsTagCategory        = @"category";
NSString * const NewsTagLink            = @"link";
NSString * const NewsTagStoryId         = @"story_id";
NSString * const NewsTagFeatured        = @"featured";
NSString * const NewsTagSummary         = @"description";
NSString * const NewsTagPostDate        = @"postDate";
NSString * const NewsTagBody            = @"body";

NSString * const NewsTagImage           = @"image";
NSString * const NewsTagOtherImages     = @"otherImages";
NSString * const NewsTagThumbnailURL    = @"thumbURL";
NSString * const NewsTagThumbnail2xURL  = @"thumb152";
NSString * const NewsTagSmallURL        = @"smallURL";
NSString * const NewsTagFullURL         = @"fullURL";
NSString * const NewsTagImageCredits    = @"imageCredits";
NSString * const NewsTagImageCaption    = @"imageCaption";

NSString * const NewsTagImageWidth      = @"width";
NSString * const NewsTagImageHeight     = @"height";

@interface StoryUpdateOperation ()
@property (nonatomic,assign,getter=isFinished) BOOL finished;
@property (nonatomic,assign,getter=isExecuting) BOOL executing;
@property (nonatomic,strong) NSError *error;
@property (nonatomic,strong) NSArray *storyIDs;
@property (nonatomic,strong) NSArray *addedStoryIDs;
@property (nonatomic,assign) dispatch_queue_t operationQueue;

@property (nonatomic,strong) NSDateFormatter *postDateFormatter;
@property (nonatomic,readonly) BOOL isTopStories;
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
                                       NSData *xmlData = [self preprocessXMLData:data];
                                       [self parseStoryData:xmlData];
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
- (BOOL)isSearch
{
    return ([self.query length] > 0);
}

- (BOOL)isTopStories
{
    return ((self.category == NewsCategoryIdTopNews) && self.isSearch);
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
    if (self.isSearch)
    {
        NSMutableString *url = [NSMutableString stringWithString:@"http://web.mit.edu/newsoffice/index.php?option=com_search&view=isearch&ordering=newest"];
        [url appendFormat:@"&searchword=%@", [self.query urlEncodeUsingEncoding:NSUTF8StringEncoding]];
        [url appendFormat:@"&start=%lu", (unsigned long)self.offset];
        [url appendFormat:@"&limit=%lu", (unsigned long)self.fetchLimit];
        
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

- (NSData*)preprocessXMLData:(NSData*)data
{
    NSData *result = data;
    
    if ([data length])
    {
        NSMutableString *xmlString = [[NSMutableString alloc] initWithData:data
                                                                  encoding:NSUTF8StringEncoding];
        NSString *pattern = [NSString stringWithFormat:@"(%@|%@)",
                             [NSRegularExpression escapedPatternForString:@"<![CDATA["],
                             [NSRegularExpression escapedPatternForString:@"]]>"]];
        NSRegularExpression *cdataRex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                  options:0
                                                                                    error:nil];
        __block NSUInteger elementDepth = 0;
        __block NSUInteger offset = 0;
        NSUInteger offsetDelta = [@"]]]]><![CDATA[>" length] - [@"]]>" length];
        
        [cdataRex enumerateMatchesInString:[xmlString uppercaseString]
                                   options:NSRegularExpressionSearch
                                     range:NSMakeRange(0, [xmlString length])
                                usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                                    NSRange range = result.range;
                                    NSString *string = [xmlString substringWithRange:range];
                                    
                                    if ([string caseInsensitiveCompare:@"<![CDATA["] == NSOrderedSame)
                                    {
                                        ++elementDepth;
                                    }
                                    else if ([string caseInsensitiveCompare:@"]]>"] == NSOrderedSame)
                                    {
                                        if (elementDepth > 1)
                                        {
                                            NSRange offsetRange = NSMakeRange(range.location + offset, range.length + offset);
                                            [xmlString replaceCharactersInRange:offsetRange
                                                                     withString:@"]]]]><![CDATA[>"];
                                            offset += offsetDelta;
                                        }
                                        
                                        --elementDepth;
                                    }
                                }];
        
        result = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
    }

    return result;
}

- (void)parseStoryData:(NSData*)storyData
{
    NSMutableArray *stories = [NSMutableArray array];
    NSMutableArray *addedStories = [NSMutableArray array];
    NSError *error = nil;
    GDataXMLDocument *doc = [[GDataXMLDocument alloc] initWithData:storyData
                                                            options:((XML_PARSE_RECOVER |
                                                                     XML_PARSE_NOWARNING |
                                                                     XML_PARSE_NONET) |
                                                                     XML_PARSE_NOCDATA)
                                                              error:&error];
    
    if (error)
    {
        self.error = error;
        return;
    }
    
    
    NSManagedObjectContext *importContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    importContext.undoManager = nil;
    importContext.mergePolicy = NSOverwriteMergePolicy;
    if (self.parentContext)
    {
        importContext.parentContext = self.parentContext;
    }
    else
    {
        importContext.persistentStoreCoordinator = [[CoreDataManager coreDataManager] persistentStoreCoordinator];
    }
    
    NSArray *items = nil;
    
    if (self.isSearch)
    {
        items = [doc.rootElement nodesForXPath:@"./item"
                                         error:&error];
    }
    else
    {
        items = [doc.rootElement nodesForXPath:@"//channel/item"
                                         error:&error];
    }
    
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
    
    NSMutableArray *updatedIds = [NSMutableArray array];
    [items enumerateObjectsUsingBlock:^(GDataXMLNode *storyNode, NSUInteger idx, BOOL *stop) {
        GDataXMLNode *idNode = [self nodeForXPath:NewsTagStoryId
                                     withRootNode:storyNode
                                            error:nil];
        NSString *storyId = [[idNode childAtIndex:0] stringValue];
        
        if ([storyId length])
        {
            [updatedIds addObject:[NSNumber numberWithInteger:[storyId integerValue]]];
        }
    }];
    
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:NewsStoryEntityName];
    request.predicate = [NSPredicate predicateWithFormat:@"story_id IN %@",updatedIds];
    NSArray *allStories = [importContext executeFetchRequest:request
                                                        error:&error];
    
    if (error)
    {
        self.error = error;
        return;
    }
    
    __block NSUInteger storyCount = 0;
    [self updateProcessedStoryCount:storyCount
                 expectedStoryCount:[items count]];
    
    NSPredicate *storyPredicate = [NSPredicate predicateWithFormat:@"story_id == $STORYID"];
    [items enumerateObjectsUsingBlock:^(GDataXMLNode *storyNode, NSUInteger idx, BOOL *stop) {
        GDataXMLNode *idNode = [self nodeForXPath:NewsTagStoryId
                                     withRootNode:storyNode
                                            error:nil];
        NSString *storyId = [[idNode childAtIndex:0] stringValue];
        NewsStory *story = nil;
        
        if ([storyId length])
        {
            NSNumber *storyNumber = [NSNumber numberWithInteger:[storyId integerValue]];
            NSArray *objects = [allStories filteredArrayUsingPredicate:[storyPredicate predicateWithSubstitutionVariables:@{@"STORYID" : storyNumber}]];
            
            if ([objects count])
            {
                story = objects[0];
                
                if ([objects count] > 1)
                {
                    // Remove the dups!
                    [objects enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1,[objects count]-1)]
                                               options:0
                                            usingBlock:^(NSManagedObject *obj, NSUInteger idx, BOOL *stop) {
                                                [importContext deleteObject:obj];
                                            }]; 
                }
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
     
        ++storyCount;
        [self updateProcessedStoryCount:storyCount
                     expectedStoryCount:[items count]];
    }];
    
    
    NSFetchRequest *loadRequest = [NSFetchRequest fetchRequestWithEntityName:NewsStoryEntityName];
    loadRequest.predicate = [NSPredicate predicateWithFormat:@"(searchResult != nil) && (searchResult == YES)"];
    NSArray *objects = [importContext executeFetchRequest:loadRequest
                                                    error:nil];
    for (NewsStory *obj in objects)
    {
        if ([stories containsObject:obj] == NO)
        {
            obj.searchResult = [NSNumber numberWithBool:NO];
        }
    }
    
    if (self.error || [self isCancelled])
    {
        return;
    }
    else
    {
        __block NSError* saveError = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [importContext save:&saveError];
            [importContext.parentContext save:&saveError];
        });
        
        error = saveError;
        ++storyCount;
        
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
    
    if (category != self.category)
    {
        [story addCategory:self.category];
    }
    
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

- (void)updateProcessedStoryCount:(NSUInteger)processedCount expectedStoryCount:(NSUInteger)storyCount
{
    if (self.progressBlock)
    {
        self.progressBlock(processedCount,storyCount);
    }
}

@end
