#import <Foundation/Foundation.h>

@class StoryParser;
@class NewsImage;
@class NewsImageRep;

extern NSString * const NewsTagItem;
extern NSString * const NewsTagTitle;
extern NSString * const NewsTagAuthor;
extern NSString * const NewsTagCategory;
extern NSString * const NewsTagLink;
extern NSString * const NewsTagStoryId;
extern NSString * const NewsTagFeatured;
extern NSString * const NewsTagSummary;
extern NSString * const NewsTagPostDate;
extern NSString * const NewsTagBody;

extern NSString * const NewsTagImage;
extern NSString * const NewsTagOtherImages;
extern NSString * const NewsTagThumbnailURL;
extern NSString * const NewsTagThumbnail2xURL;
extern NSString * const NewsTagSmallURL;
extern NSString * const NewsTagFullURL;
extern NSString * const NewsTagImageCredits;
extern NSString * const NewsTagImageCaption;

extern NSString * const NewsTagImageWidth;
extern NSString * const NewsTagImageHeight;

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
