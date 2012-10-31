#import <Foundation/Foundation.h>

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

@class StoryXMLParser;
@class NewsImage;
@class NewsImageRep;

@protocol StoryXMLParserDelegate <NSObject>

- (void)parserDidFinishParsing:(StoryXMLParser *)parser;

@optional
- (void)parserDidStartDownloading:(StoryXMLParser *)parser;
- (void)parserDidStartParsing:(StoryXMLParser *)parser;
- (void)parser:(StoryXMLParser *)parser didMakeProgress:(CGFloat)percentDone;
- (void)parser:(StoryXMLParser *)parser didFailWithDownloadError:(NSError *)error;
- (void)parser:(StoryXMLParser *)parser didFailWithParseError:(NSError *)error;
@end

@interface StoryXMLParser : NSObject <NSXMLParserDelegate>

@property (nonatomic, assign) id <StoryXMLParserDelegate> delegate;
@property (nonatomic, retain) NSXMLParser *xmlParser;
@property (nonatomic, assign) BOOL parsingTopStories;
@property (nonatomic, assign) BOOL isSearch;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) NSInteger totalAvailableResults;
@property (nonatomic, retain) NSString *currentElement;
@property (nonatomic, retain) NSMutableArray *currentStack;
@property (nonatomic, retain) NSMutableDictionary *currentContents;
@property (nonatomic, retain) NSMutableDictionary *currentImage;
@property (nonatomic, retain) NSMutableArray *addedStories;

// called by main thread
- (void)loadStoriesForCategory:(NSInteger)category afterStoryId:(NSInteger)storyId count:(NSInteger)count;
- (void)loadStoriesforQuery:(NSString *)query afterIndex:(NSInteger)start count:(NSInteger)count;
- (void)abort;

@end
