#import <Foundation/Foundation.h>

@class StoryUpdateOperation;
@class NewsImage;
@class NewsImageRep;

typedef void (^StoryUpdateProgressBlock)(NSUInteger storiesParsed,NSUInteger expectedCount);
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
