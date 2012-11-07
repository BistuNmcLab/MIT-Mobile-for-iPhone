#import <Foundation/Foundation.h>

@class StoryUpdateOperation;
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

typedef void (^StoryUpdateProgressBlock)(CGFloat percentDownloaded, NSUInteger storiesParsed,NSUInteger expectedCount);
typedef void (^StoryUpdateResultBlock)(NSArray* storyIDs,NSArray* addedStoryIDs,NSUInteger offset,NSError* error);

@interface StoryUpdateOperation : NSOperation
@property (copy) StoryUpdateProgressBlock progressBlock;
@property (copy) StoryUpdateResultBlock completeBlock;
@property (weak) NSManagedObjectContext *parentContext;

@property (nonatomic,readonly) BOOL isSearch;
@property (strong) NSString *query;
@property (assign) NSUInteger category;
@property (assign) NSUInteger lastStoryId;
@property (assign) NSUInteger offset;
@property (assign) NSUInteger fetchLimit;

- (id)init;
- (id)initWithCategory:(NSUInteger)category;
- (id)initWithCategory:(NSUInteger)category
           lastStoryID:(NSUInteger)storyId
            fetchLimit:(NSUInteger)limit;
- (id)initWithQuery:(NSString*)query
            offset:(NSUInteger)offset
            fetchLimit:(NSUInteger)limit;
@end
