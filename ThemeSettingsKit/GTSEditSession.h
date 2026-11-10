/* GTSEditSession.h - Apply/Cancel editing of one target domain.
   Stages changes in memory against a baseline snapshot; Apply commits only
   staged keys with optimistic conflict detection; Cancel drops them. Nothing
   touches disk until -apply. Every failure keeps the baseline and the staged
   edits; nothing is silently replaced. */
#import <Foundation/Foundation.h>

@class GTSDefaultsDomainStore, GTSDomainSnapshot, GTSSettingDescriptor;

/* What a successful Apply did. */
@interface GTSApplyReceipt : NSObject
{
@public
  NSDictionary *_committed;   /* key -> value or GTSRemoveValue */
  int _requirement;           /* GTSApplyPolicy, strongest among committed */
  BOOL _refreshFailed;
  NSError *_refreshError;
}
- (NSDictionary*) committedChanges;
- (int) applyRequirement;
/* Saved, but re-reading the domain afterwards failed. The session's
   baseline is then the old baseline plus the committed changes (our best
   knowledge), and the session needs -rebase before further edits. Do not
   re-apply the same changes. */
- (BOOL) refreshFailed;
- (NSError*) refreshError;
@end

@interface GTSEditSession : NSObject
{
  GTSDefaultsDomainStore *_store;
  NSString *_domain;
  GTSDomainSnapshot *_baseline;
  NSMutableDictionary *_staged;      /* key -> value or GTSRemoveValue */
  NSMutableDictionary *_applyByKey;  /* key -> NSNumber(GTSApplyPolicy) */
  BOOL _needsRebase;
}
/* nil + error if the domain cannot be read reliably. */
- (id) initWithStore: (GTSDefaultsDomainStore*)store
              domain: (NSString*)domain
               error: (NSError**)error;
- (NSString*) domain;
- (GTSDomainSnapshot*) baseline;
/* YES after a refresh failure; Apply is refused until -rebase succeeds. */
- (BOOL) needsRebase;

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
/* Strongest Apply requirement among staged keys (GSTheme counts as
   restart). GTSApplyLive when nothing is staged. */
- (int) applyRequirement;
- (BOOL) needsRestart;

/* Commit. Returns a receipt on success (also when nothing was staged).
   Returns nil when nothing was saved: conflicts (*conflicts set), unreadable
   domain, invalid input, write failure, or needsRebase. Staged changes and
   baseline are kept in every nil case. */
- (GTSApplyReceipt*) applyWithConflicts: (NSArray**)conflicts error: (NSError**)error;
/* Cancel: drop staged changes. */
- (void) discardChanges;
/* Re-read the domain; keep staged changes; returns keys whose on-disk value
   changed since the old baseline, or nil + error (baseline and staged
   changes kept). */
- (NSArray*) rebaseWithError: (NSError**)error;
@end
