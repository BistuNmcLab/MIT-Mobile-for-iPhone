#import <Foundation/Foundation.h>

@class StoryParser;
@class NewsImage;
@class NewsImageRep;

@protocol StoryXMLParserDelegate <NSObject>
- (void)parserDidFinishParsing:(StoryParser *)parser;

@optional
- (void)parserDidStartDownloading:(StoryParser *)parser;
- (void)parserDidStartParsing:(StoryParser *)parser;
- (void)parser:(StoryParser *)parser didMakeProgress:(CGFloat)percentDone;
- (void)parser:(StoryParser *)parser didFailWithDownloadError:(NSError *)error;
- (void)parser:(StoryParser *)parser didFailWithParseError:(NSError *)error;
@end

@interface StoryParser : NSObject

@property (nonatomic, assign) id<StoryXMLParserDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL parsingTopStories;
@property (nonatomic, assign, readonly) BOOL isSearch;
@property (nonatomic, assign, readonly) BOOL loadingMore;
@property (nonatomic, assign, readonly) NSInteger totalAvailableResults;
@property (nonatomic, retain, readonly) NSArray *addedStories;

- (id)initWithParentContext:(NSManagedObjectContext*)context;
- (void)loadStoriesForCategory:(NSInteger)category afterStoryId:(NSInteger)storyId count:(NSInteger)count;
- (void)loadStoriesforQuery:(NSString *)query afterIndex:(NSInteger)start count:(NSInteger)count;
- (void)abort;
@end
