/* GTSEditSession.h - Apply/Cancel editing of one target domain.
   Stages changes in memory against a baseline snapshot; Apply commits only
   staged keys with optimistic conflict detection; Cancel drops them. Nothing
   touches disk until -apply. */
#import <Foundation/Foundation.h>

@class GTSDefaultsDomainStore, GTSDomainSnapshot, GTSSettingDescriptor;

@interface GTSEditSession : NSObject
{
  GTSDefaultsDomainStore *_store;
  NSString *_domain;
  GTSDomainSnapshot *_baseline;
  NSMutableDictionary *_staged;    /* key -> value or GTSRemoveValue */
  NSMutableSet *_restartKeys;
}
- (id) initWithStore: (GTSDefaultsDomainStore*)store domain: (NSString*)domain;
- (NSString*) domain;
- (GTSDomainSnapshot*) baseline;

/* Domain as it would look after Apply (baseline + staged). */
- (GTSDomainSnapshot*) pendingSnapshot;

/* Stage a value. Validates and stores the canonical form. Staging the
   baseline value again unstages the key. Returns NO + message if invalid. */
- (BOOL) stageValue: (id)value
         forSetting: (GTSSettingDescriptor*)setting
            problem: (NSString**)problem;
/* Stage removal of the override (reset to inherited/default). */
- (void) stageResetForSetting: (GTSSettingDescriptor*)setting;
/* Theme selection; nil = remove GSTheme from this domain. */
- (void) stageThemeSelection: (NSString*)themeName;

- (BOOL) hasChanges;
- (NSDictionary*) stagedChanges;
/* YES if any staged setting has Apply = restart (or GSTheme changed). */
- (BOOL) needsRestart;

/* Commit. On conflict nothing is written, staged changes are kept, and
   *conflicts lists them; caller may -rebase and retry. On success the
   baseline becomes the freshly committed state. */
- (BOOL) applyWithConflicts: (NSArray**)conflicts error: (NSError**)error;
/* Cancel: drop staged changes. */
- (void) discardChanges;
/* Re-read the domain; keep staged changes; return keys whose on-disk value
   changed since the old baseline (external edits). */
- (NSArray*) rebase;
@end
