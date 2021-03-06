//
//  KPKEntry.m
//  KeePassKit
//
//  Created by Michael Starke on 12.07.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "KPKEntry.h"
#import "KPKEntry_Private.h"
#import "KPKNode_Private.h"
#import "KPKGroup.h"
#import "KPKBinary.h"
#import "KPKBinary_Private.h"
#import "KPKAttribute.h"
#import "KPKAttribute_Private.h"
#import "KPKAutotype.h"
#import "KPKAutotype_Private.h"
#import "KPKWindowAssociation.h"
#import "KPKFormat.h"
#import "KPKTimeInfo.h"
#import "KPKUTIs.h"
#import "KPKReferenceBuilder.h"

#import "KPKScopedSet.h"

NSString *const KPKMetaEntryBinaryDescription   = @"bin-stream";
NSString *const KPKMetaEntryTitle               = @"Meta-Info";
NSString *const KPKMetaEntryUsername            = @"SYSTEM";
NSString *const KPKMetaEntryURL                 = @"$";

NSString *const KPKMetaEntryUIState                 = @"Simple UI State";
NSString *const KPKMetaEntryDefaultUsername         = @"Default User Name";
NSString *const KPKMetaEntrySearchHistoryItem       = @"Search History Item";
NSString *const KPKMetaEntryCustomKVP               = @"Custom KVP";
NSString *const KPKMetaEntryDatabaseColor           = @"Database Color";
NSString *const KPKMetaEntryKeePassXCustomIcon      = @"KPX_CUSTOM_ICONS_2";
NSString *const KPKMetaEntryKeePassXCustomIcon2     = @"KPX_CUSTOM_ICONS_4";
NSString *const KPKMetaEntryKeePassXGroupTreeState  = @"KPX_GROUP_TREE_STATE";


@interface KPKEntry () {
@private
  NSMapTable *_attributeMap;
}

@property (nonatomic) BOOL isHistory;

@end


@implementation KPKEntry

@dynamic attributes;
@dynamic binaries;
@dynamic customAttributes;
@dynamic defaultAttributes;
@dynamic history;
@dynamic notes;
@dynamic title;
@dynamic updateTiming;

NSSet *_protectedKeyPathForAttribute(SEL aSelector) {
  NSString *keyPath = [[NSString alloc] initWithFormat:@"%@.%@", NSStringFromSelector(aSelector), NSStringFromSelector(@selector(value))];
  return [[NSSet alloc] initWithObjects:keyPath, nil];
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

+ (KPKEntry *)metaEntryWithData:(NSData *)data name:(NSString *)name {
  KPKEntry *metaEntry = [[KPKEntry alloc] init];
  metaEntry.title = KPKMetaEntryTitle;
  metaEntry.username = KPKMetaEntryUsername;
  metaEntry.url = KPKMetaEntryURL;
  /* Name is stored in the notes attribute of the entry */
  metaEntry.notes = name;
  KPKBinary *binary = [[KPKBinary alloc] init];
  binary.name = KPKMetaEntryBinaryDescription;
  binary.data = data;
  [metaEntry addBinary:binary];
  
  return metaEntry;
}

+ (NSSet *)keyPathsForValuesAffectingIsEditable {
  return [[NSSet alloc] initWithObjects:NSStringFromSelector(@selector(isHistory)), nil];
}

+ (NSSet *)keyPathsForValuesAffectingHistory {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableHistory))];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingBinaries {
  return  [NSSet setWithObject:NSStringFromSelector(@selector(mutableBinaries))];
}

/* The only storage for attributes is the mutableAttributes array, so all getter depend on it*/
+ (NSSet *)keyPathsForValuesAffectingAttributes {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableAttributes))];
}

+ (NSSet *)keyPathsForValuesAffectingCustomAttributes {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableAttributes))];
}

+ (NSSet *)keyPathsForValuesAffectingDefaultAttributes {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableAttributes))];
}

+ (NSSet *)keyPathsForValuesAffectingPassword {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableAttributes))];
}

+ (NSSet *)keyPathsForValuesAffectingUsername {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableAttributes))];
}

+ (NSSet *)keyPathsForValuesAffectingUrl {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableAttributes))];
}

+ (NSSet *)keyPathsForValuesAffectingTitle {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableAttributes))];
}

+ (NSSet *)keyPathsForValuesAffectingNotes {
  return [NSSet setWithObject:NSStringFromSelector(@selector(mutableAttributes))];
}

- (instancetype)init {
  self = [self _init];
  return self;
}

- (instancetype)_init {
  self = [self initWithUUID:nil];
  return self;
}

- (instancetype)initWithUUID:(NSUUID *)uuid {
  self = [self _initWithUUID:uuid];
  return self;
}

- (instancetype)_initWithUUID:(NSUUID *)uuid {
  self = [super _initWithUUID:uuid];
  if (self) {
    /* !Note! - Title -> Name */
    _mutableAttributes = [[NSMutableArray alloc] init];
    /* create the default attributes */
    _attributeMap = [NSMapTable strongToWeakObjectsMapTable];
    for(NSString *key in [KPKFormat sharedFormat].entryDefaultKeys) {
      KPKAttribute *attribute = [[KPKAttribute alloc] initWithKey:key value:@""];
      attribute.entry = self;
      [_mutableAttributes addObject:attribute];
      [_attributeMap setObject:attribute forKey:key];
    }
    _mutableBinaries = [[NSMutableArray alloc] init];
    _mutableHistory = [[NSMutableArray alloc] init];
    _autotype = [[[KPKAutotype alloc] init] copy];
    
    _autotype.entry = self;
    _isHistory = NO;
  }
  return self;
}

- (void)dealloc {
  /* Remove us from the undo stack */
  [self.undoManager removeAllActionsWithTarget:self];
}

#pragma mark NSCopying
- (id)copyWithZone:(NSZone *)zone {
  return [self _copyWithUUID:self.uuid];
}

- (instancetype)_copyWithUUID:(nullable NSUUID *)uuid {
  KPKEntry *copy = [super _copyWithUUID:uuid];
  /* Default attributes */
  copy.overrideURL = self.overrideURL;
  
  copy.mutableBinaries = [[NSMutableArray alloc] initWithArray:self.mutableBinaries copyItems:YES];
  copy.mutableAttributes = [[NSMutableArray alloc] initWithArray:self.mutableAttributes copyItems:YES];
  copy.tags = self.tags;
  copy.autotype = self.autotype;
  /* Shallow copy skipps history */
  copy.isHistory = NO;
  
  /* Color */
  copy.foregroundColor = self.foregroundColor;
  copy.backgroundColor = self.backgroundColor;
  
  /* History */
  copy.mutableHistory = [[NSMutableArray alloc] initWithArray:self.mutableHistory copyItems:YES];
  copy.isHistory = self.isHistory;
  /* parent at last, to prevent undo/redo registration */
  copy.parent = self.parent;
  return copy;
}

#pragma mark NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder {
  self = [super _initWithCoder:aDecoder];
  if(self) {
    /* Disable timing since we init via coder */
    self.updateTiming = NO;
    /* use setter for internal consistency */
    self.mutableAttributes = [aDecoder decodeObjectOfClasses:[NSSet setWithArray:@[NSMutableArray.class, KPKAttribute.class]]
                                                      forKey:NSStringFromSelector(@selector(mutableAttributes))];
    self.mutableHistory = [aDecoder decodeObjectOfClasses:[NSSet setWithArray:@[NSMutableArray.class, KPKEntry.class]]
                                                   forKey:NSStringFromSelector(@selector(mutableHistory))];
    self.mutableBinaries = [aDecoder decodeObjectOfClasses:[NSSet setWithArray:@[NSMutableArray.class, KPKBinary.class]]
                                         forKey:NSStringFromSelector(@selector(mutableBinaries))];
    _tags = [[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(tags))] copy];
    _foregroundColor = [[aDecoder decodeObjectOfClass:NSUIColor.class forKey:NSStringFromSelector(@selector(foregroundColor))] copy];
    _backgroundColor = [[aDecoder decodeObjectOfClass:NSUIColor.class forKey:NSStringFromSelector(@selector(backgroundColor))] copy];
    _overrideURL = [[aDecoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(overrideURL))] copy];
    self.autotype = [aDecoder decodeObjectOfClass:KPKAutotype.class forKey:NSStringFromSelector(@selector(autotype))];
    _isHistory = [aDecoder decodeBoolForKey:NSStringFromSelector(@selector(isHistory))];
    
    self.updateTiming = YES;
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
  [super _encodeWithCoder:aCoder];
  [aCoder encodeObject:_mutableAttributes forKey:NSStringFromSelector(@selector(mutableAttributes))];
  [aCoder encodeObject:_mutableBinaries forKey:NSStringFromSelector(@selector(mutableBinaries))];
  [aCoder encodeObject:_tags forKey:NSStringFromSelector(@selector(tags))];
  [aCoder encodeObject:_foregroundColor forKey:NSStringFromSelector(@selector(foregroundColor))];
  [aCoder encodeObject:_backgroundColor forKey:NSStringFromSelector(@selector(backgroundColor))];
  [aCoder encodeObject:_overrideURL forKey:NSStringFromSelector(@selector(overrideURL))];
  [aCoder encodeObject:_mutableHistory forKey:NSStringFromSelector(@selector(mutableHistory))];
  [aCoder encodeObject:_autotype forKey:NSStringFromSelector(@selector(autotype))];
  [aCoder encodeBool:_isHistory forKey:NSStringFromSelector(@selector(isHistory))];
  return;
}

- (instancetype)copyWithTitle:(NSString *)titleOrNil options:(KPKCopyOptions)options {
  /* Copy sets a new UUID */
  KPKEntry *copy = [self _copyWithUUID:nil];
  if(!titleOrNil) {
    NSString *format = NSLocalizedStringFromTable(@"KPK_ENTRY_COPY_%@", @"KPKLocalizable", "");
    titleOrNil = [[NSString alloc] initWithFormat:format, self.title];
  }
  KPK_SCOPED_DISABLE_UNDO_BEGIN(copy.undoManager)
  copy.title = titleOrNil;
  
  if(options & kKPKCopyOptionReferencePassword) {
    copy.password = [KPKReferenceBuilder reference:KPKReferenceFieldPassword where:KPKReferenceFieldUUID is:self.uuid.UUIDString];
  }
  
  if(options & kKPKCopyOptionReferenceUsername) {
    copy.username = [KPKReferenceBuilder reference:KPKReferenceFieldUsername where:KPKReferenceFieldUUID is:self.uuid.UUIDString];
  }
  
  if(!(options & kKPKCopyOptionCopyHistory)) {
    [copy clearHistory];
  }
  
  KPK_SCOPED_DISABLE_UNDO_END
  [copy.timeInfo reset];
  return copy;
}

#if KPK_MAC

#pragma mark NSPasteBoardWriting/Reading

+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSUIPasteboard *)pasteboard {
  NSAssert([type isEqualToString:KPKEntryUTI], @"Only KPKEntryUTI type is supported");
  return NSPasteboardReadingAsKeyedArchive;
}

+ (NSArray *)readableTypesForPasteboard:(NSUIPasteboard *)pasteboard {
  return @[KPKEntryUTI];
}

- (NSArray *)writableTypesForPasteboard:(NSUIPasteboard *)pasteboard {
  return @[KPKEntryUTI];
}

- (id)pasteboardPropertyListForType:(NSString *)type {
  if([type isEqualToString:KPKEntryUTI]) {
    return [NSKeyedArchiver archivedDataWithRootObject:self];
  }
  return nil;
}

#endif

#pragma mark Equality

- (BOOL)isEqual:(id)object {
  if(![super isEqual:object]) {
    return NO;
  }
  if([object isKindOfClass:self.class]) {
    return [self isEqualToEntry:object];
  }
  return NO;
}

- (BOOL)isEqualToEntry:(KPKEntry *)entry {
  return [self _isEqualToNode:entry options:0];
}

- (BOOL)_isEqualToNode:(KPKNode *)node options:(KPKNodeEqualityOptions)options {
  KPKEntry *entry = node.asEntry;
  NSAssert([entry isKindOfClass:KPKEntry.class], @"Test only allowed with KPKEntry classes");
  
  if(![super _isEqualToNode:node options:options]) {
    return NO;
  }
  
  /* Compare Attributes (do not care about order!) */
  if(self.mutableAttributes.count != entry.mutableAttributes.count) {
    return NO;
  }
  for(KPKAttribute *attribute in self.mutableAttributes) {
    KPKAttribute *otherAttribute = [entry attributeWithKey:attribute.key];
    if(NO == [otherAttribute isEqualToAttribute:attribute]) {
      return NO;
    }
  }
  
  /* Compare History - order has to match! */
  if(!(options & KPKNodeEqualityIgnoreHistoryOption)) {
    if(NO == [self.mutableHistory isEqualToArray:entry.mutableHistory]) {
      return NO;
    }
  }
  
  /* Compare Binaries - order has to macht! */
  if(NO == [self.mutableBinaries isEqualToArray:entry.mutableBinaries]) {
    return NO;
  }
  
  return [self.autotype isEqualToAutotype:entry.autotype];
}

#pragma mark -
#pragma mark Attribute accessors
- (NSArray *)defaultAttributes {
  return [self.mutableAttributes subarrayWithRange:NSMakeRange(0, kKPKDefaultEntryKeysCount)];
}

- (NSArray *)customAttributes {
  return [self.mutableAttributes subarrayWithRange:NSMakeRange(kKPKDefaultEntryKeysCount, self.mutableAttributes.count - kKPKDefaultEntryKeysCount)];
}

- (BOOL)hasCustomAttributes {
  return (self.mutableAttributes.count > kKPKDefaultEntryKeysCount);
}

- (NSArray<KPKAttribute *> *)attributes {
  return [self.mutableAttributes copy];
}

- (void)insertObject:(KPKAttribute *)object inMutableAttributesAtIndex:(NSUInteger)index {
  index = MIN(self.mutableAttributes.count, index);
  [self.mutableAttributes insertObject:object atIndex:index];
  [_attributeMap setObject:object forKey:object.key];
}

- (void)removeObjectFromMutableAttributesAtIndex:(NSUInteger)index {
  if(index < self.mutableAttributes.count) {
    NSString *key = self.mutableAttributes[index].key;
    [self.mutableAttributes removeObjectAtIndex:index];
    [_attributeMap removeObjectForKey:key];
  }
}

- (KPKAttribute *)attributeWithKey:(NSString *)key {
  if(!key) {
    return nil;
  }
  KPKAttribute *cachedAttribute = [_attributeMap objectForKey:key];
  if(!cachedAttribute || cachedAttribute.entry != self ) {
    [_attributeMap removeObjectForKey:key];
  }
  else if([cachedAttribute.key isEqualToString:key]) {
    return cachedAttribute;
  }
  else {
    [_attributeMap removeObjectForKey:key];
    [_attributeMap setObject:cachedAttribute forKey:cachedAttribute.key];
  }
  for(KPKAttribute *attribute in self.mutableAttributes) {
    if([attribute.key isEqualToString:key]) {
      [_attributeMap setObject:attribute forKey:key];
      return attribute;
    }
  }
  return nil;
}

- (BOOL)hasAttributeWithKey:(NSString *)key {
  return (nil != [self attributeWithKey:key]);
}

- (BOOL)_protectValueForKey:(NSString *)key {
  return [self attributeWithKey:key].isProtected;
}

- (void)_setProtect:(BOOL)protect valueForkey:(NSString *)key {
  [self attributeWithKey:key].isProtected = protect;
}

- (NSString *)valueForAttributeWithKey:(NSString *)key {
  return [self attributeWithKey:key].value;
}

- (void)_setValue:(NSString *)value forAttributeWithKey:(NSString *)key {
  [self attributeWithKey:key].value = value;
}

#pragma mark -
#pragma mark Properties
- (BOOL )protectNotes {
  return [self _protectValueForKey:kKPKNotesKey];
}

- (BOOL)protectPassword {
  return  [self _protectValueForKey:kKPKPasswordKey];
}

- (BOOL)protectTitle {
  return [self _protectValueForKey:kKPKTitleKey];
}

- (BOOL)protectUrl {
  return [self _protectValueForKey:kKPKURLKey];
}

- (BOOL)protectUsername {
  return [self _protectValueForKey:kKPKUsernameKey];
}

- (BOOL)isEditable {
  
  if(super.isEditable) {
    return !self.isHistory;
  }
  return NO;
}

- (NSArray *)binaries {
  return [self.mutableBinaries copy];
}

- (NSArray *)history {
  return [self.mutableHistory copy];
}

- (NSString *)title {
  return [self valueForAttributeWithKey:kKPKTitleKey];
}

- (NSString *)username {
  return [self valueForAttributeWithKey:kKPKUsernameKey];
}

- (NSString *)password {
  return [self valueForAttributeWithKey:kKPKPasswordKey];
}

- (NSString *)notes {
  return [self valueForAttributeWithKey:kKPKNotesKey];
}

- (NSString *)url {
  return [self valueForAttributeWithKey:kKPKURLKey];
}

- (BOOL)isMeta {
  /* Meta entries always contain data */
  KPKBinary *binary = self.mutableBinaries.lastObject;
  if(!binary) {
    return NO;
  }
  if(binary.data.length == 0) {
    return NO;
  }
  if(![binary.name isEqualToString:KPKMetaEntryBinaryDescription]) {
    return NO;
  }
  if(![self.title isEqualToString:KPKMetaEntryTitle]) {
    return NO;
  }
  if(![self.username isEqualToString:KPKMetaEntryUsername]) {
    return NO;
  }
  if(![self.url isEqualToString:KPKMetaEntryURL]) {
    return NO;
  }
  /* The Name of the type is stored as the note attribute */
  if(self.notes.length == 0) {
    return NO;
  }
  return YES;
}

- (KPKFileVersion)minimumVersion {
  KPKFileVersion version = { KPKDatabaseFormatKdb, kKPKKdbFileVersion };
  if(self.binaries.count > 1 ||
     self.customAttributes.count > 0 ||
     self.mutableHistory.count > 0  ||
     self.mutableCustomData.count > 0) {
    
    version.format = KPKDatabaseFormatKdbx;
    version.version = self.mutableCustomData.count > 0 ? kKPKKdbxFileVersion4 : kKPKKdbxFileVersion3;
  }
  return version;
}

- (void)setMutableAttributes:(NSMutableArray<KPKAttribute *> *)mutableAttributes {
  _mutableAttributes = mutableAttributes;
  [_attributeMap removeAllObjects];
  for(KPKAttribute *attribute in self.mutableAttributes) {
    attribute.entry = self;
    [_attributeMap setObject:attribute forKey:attribute.key];
  }
}

- (void)setMutableHistory:(NSMutableArray<KPKEntry *> *)mutableHistory {
  _mutableHistory = mutableHistory;
  for(KPKEntry *entry in self.mutableHistory) {
    entry.parent = self.parent;
  }
}

- (void)setParent:(KPKGroup *)parent {
  super.parent = parent;
  if(self.isHistory) {
    return;
  }
  for(KPKEntry *entry in self.mutableHistory) {
    entry.parent = parent;
  }
}

- (void)setProtectNotes:(BOOL)protectNotes {
  [self _setProtect:protectNotes valueForkey:kKPKNotesKey];
}

- (void)setProtectPassword:(BOOL)protectPassword {
  [self _setProtect:protectPassword valueForkey:kKPKPasswordKey];
}

- (void)setProtectTitle:(BOOL)protectTitle {
  [self _setProtect:protectTitle valueForkey:kKPKTitleKey];
}

- (void)setProtectUrl:(BOOL)protectUrl {
  [self _setProtect:protectUrl valueForkey:kKPKURLKey];
}

- (void)setProtectUsername:(BOOL)protectUsername {
  [self _setProtect:protectUsername valueForkey:kKPKUsernameKey];
}

- (void)setAutotype:(KPKAutotype *)autotype {
  if(autotype == _autotype) {
    return;
  }
  _autotype = [autotype copy];
  _autotype.entry = self;
}

- (void)setTitle:(NSString *)title {
  [[self.undoManager prepareWithInvocationTarget:self] setTitle:self.title];
  [self _setValue:title forAttributeWithKey:kKPKTitleKey];
}

- (void)setUsername:(NSString *)username {
  [[self.undoManager prepareWithInvocationTarget:self] setUsername:self.username];
  [self _setValue:username forAttributeWithKey:kKPKUsernameKey];
}

- (void)setPassword:(NSString *)password {
  [[self.undoManager prepareWithInvocationTarget:self] setPassword:self.password];
  [self _setValue:password forAttributeWithKey:kKPKPasswordKey];
}

- (void)setNotes:(NSString *)notes {
  [[self.undoManager prepareWithInvocationTarget:self] setNotes:self.notes];
  [self _setValue:notes forAttributeWithKey:kKPKNotesKey];
}

- (void)setUrl:(NSString *)url {
  [[self.undoManager prepareWithInvocationTarget:self] setUrl:self.url];
  [self _setValue:url forAttributeWithKey:kKPKURLKey];
}

- (KPKEntry *)asEntry {
  return self;
}

#pragma mark CustomAttributes
- (KPKAttribute *)customAttributeForKey:(NSString *)key {
  KPKAttribute *attribute = [self attributeWithKey:key];
  if(!attribute.isDefault) {
    return attribute;
  }
  return nil;
}

-(NSString *)proposedKeyForAttributeKey:(NSString *)key {
  NSUInteger counter = 1;
  NSString *base = key;
  while(nil != [self attributeWithKey:key]) {
    key = [NSString stringWithFormat:@"%@-%ld", base, counter++];
  }
  return key;
}

- (void)addCustomAttribute:(KPKAttribute *)attribute {
  [self _addCustomAttribute:attribute atIndex:self.mutableAttributes.count];
}

- (void)_addCustomAttribute:(KPKAttribute *)attribute atIndex:(NSUInteger)index {
  if(nil == attribute) {
    return; // no attribute
  }
  if(index > self.mutableAttributes.count) {
    return; // index out of bounds
  }
  [[self.undoManager prepareWithInvocationTarget:self] removeCustomAttribute:attribute];
  [self touchModified];
  [self insertObject:attribute inMutableAttributesAtIndex:index];
  attribute.entry = self;
}

- (void)removeCustomAttribute:(KPKAttribute *)attribute {
  NSUInteger index = [self.mutableAttributes indexOfObject:attribute];
  if(NSNotFound != index) {
    [[self.undoManager prepareWithInvocationTarget:self] _addCustomAttribute:attribute atIndex:index];
    [self touchModified];
    attribute.entry = nil;
    [self removeObjectFromMutableAttributesAtIndex:index];
  }
}
#pragma mark Attachments

- (void)addBinary:(KPKBinary *)binary {
  [self _addBinary:binary atIndex:self.mutableBinaries.count];
}

- (void)_addBinary:(KPKBinary *)binary atIndex:(NSUInteger)index {
  if(nil == binary) {
    return; // nil not allowed
  }
  if(index > self.mutableBinaries.count) {
    return; // index out of bounds!
  }
  [[self.undoManager prepareWithInvocationTarget:self] removeBinary:binary];
  [self touchModified];
  [self insertObject:binary inMutableBinariesAtIndex:index];
  
}

- (void)removeBinary:(KPKBinary *)binary {
  /*
   Attachments are stored on entries.
   Only on load the binaries are stored ad meta entries to the tree
   So we do not need to take care of cleanup after we did
   delete an attachment
   */
  NSUInteger index = [self.mutableBinaries indexOfObject:binary];
  if(index != NSNotFound) {
    [[self.undoManager prepareWithInvocationTarget:self] addBinary:binary];
    [self touchModified];
    [self removeObjectFromMutableBinariesAtIndex:index];
  }
}

- (void)_regenerateUUIDs {
  [super _regenerateUUIDs];
  for(KPKEntry *entry in self.mutableHistory) {
    entry->_uuid = self->_uuid;
  }
}

#pragma mark Mergin
- (BOOL)_updateFromNode:(KPKNode *)node options:(KPKUpdateOptions)options {
  BOOL didChange = [super _updateFromNode:node options:options];
  
  NSComparisonResult result = [self.timeInfo.modificationDate compare:node.timeInfo.modificationDate];
  if(NSOrderedDescending == result || (options & KPKUpdateOptionIgnoreModificationTime)) {
    KPKEntry *sourceEntry = node.asEntry;
    if(!sourceEntry) {
      return didChange;
    }
    
    /* collections */
    self.mutableAttributes = [[NSMutableArray alloc] initWithArray:sourceEntry.mutableAttributes copyItems:YES];
    self.mutableHistory = [[NSMutableArray alloc] initWithArray:sourceEntry.mutableHistory copyItems:YES];
    if(options & KPKUpdateOptionIncludeHistory) {
      self.mutableBinaries = [[NSMutableArray alloc] initWithArray:sourceEntry.mutableBinaries copyItems:YES];
    }
    
    self.overrideURL = sourceEntry.overrideURL;
    self.tags = sourceEntry.tags;
    self.autotype = sourceEntry.autotype;
    
    self.foregroundColor = sourceEntry.foregroundColor;
    self.backgroundColor = sourceEntry.backgroundColor;
    
    NSDate *oldMovedTime = self.timeInfo.locationChanged;
    self.timeInfo = sourceEntry.timeInfo;
    if(!(options & KPKUpdateOptionIncludeMovedTime )) {
      self.timeInfo.locationChanged = oldMovedTime;
    }
    return YES;
  }
  return didChange;
}

#pragma mark History
- (void)_addHistoryEntry:(KPKEntry *)entry {
  [self insertObject:entry inMutableHistoryAtIndex:self.mutableHistory.count];
}

- (void)removeHistoryEntry:(KPKEntry *)entry {
  NSUInteger index = [self.mutableHistory indexOfObject:entry];
  if(index != NSNotFound) {
    [self removeObjectFromMutableHistoryAtIndex:index];
  }
}

- (void)pushHistory {
  if(!self.tree.metaData.isHistoryEnabled) {
    return; // Pushing history but it's disabled
  }
  NSAssert(!self.isHistory, @"Pushing history on a history entry is not possible!");
  if(self.isHistory) {
    return; // Pushin history on a history entry is wrong!
  }
  [self _addHistoryEntry:[self _copyWithUUID:self.uuid]];
  [self _maintainHistory];
}

- (void)clearHistory {
  NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.mutableHistory.count)];
  [self removeMutableHistoryAtIndexes:indexes];
}

- (BOOL)hasHistoryOfEntry:(KPKEntry *)entry {
  for(KPKEntry *historyEntry in self.mutableHistory) {
    if([historyEntry _isEqualToNode:entry options:(KPKNodeEqualityIgnoreAccessDateOption|KPKNodeEqualityIgnoreModificationDateOption)]) {
      return YES;
    }
  }
  return NO;
}

- (void)revertToEntry:(KPKEntry *)entry {
  NSAssert([self.mutableHistory containsObject:entry], @"Supplied entry is not part of history of this entry!");
  NSAssert([entry.uuid isEqual:self.uuid], @"UUID of history entry needs to be the same as receivers");
  self.title = entry.title;
  self.iconId = entry.iconId;
  self.iconUUID = entry.iconUUID;
  self.password = entry.password;
  self.username = entry.username;
  self.url = entry.url;
  self.tags = entry.tags;
  self.foregroundColor = entry.foregroundColor;
  self.backgroundColor = entry.backgroundColor;
  self.overrideURL = entry.overrideURL;
  
  self.autotype = entry.autotype;
  
  self.timeInfo.expires = entry.timeInfo.expires;
  self.timeInfo.expirationDate = entry.timeInfo.expirationDate;
  
  self.mutableAttributes = [[NSMutableArray alloc] initWithArray:entry.mutableAttributes copyItems:YES];
  self.mutableCustomData = [[NSMutableDictionary alloc] initWithDictionary:entry.mutableCustomData copyItems:YES];
  self.mutableBinaries = [[NSMutableArray alloc] initWithArray:entry.mutableBinaries copyItems:YES];
}

- (void)_maintainHistory {
  if(!self.tree.metaData) {
    return;
  }
  /* if size or count is set to zero, just clear the history */
  if(self.tree.metaData.historyMaxItems <= 0 || self.tree.metaData.historyMaxSize <= 0) {
    [self clearHistory];
    return;
  }
  NSAssert(self.tree.metaData.historyMaxItems > 0, @"Invalid maxium history count!");
  NSAssert(self.tree.metaData.historyMaxSize > 0, @"Invalid maxium history size!");
  /* remove item if count is too high */
  NSInteger removeCount = self.mutableHistory.count - self.tree.metaData.historyMaxItems;
  if(removeCount > 0) {
    [self removeMutableHistoryAtIndexes:[[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, removeCount)]];
  }
  /* remove items if size it to big */
  NSUInteger historySize = 0;
  NSInteger removeIndex = -1;
  NSEnumerator *enumerator = self.mutableHistory.reverseObjectEnumerator;
  KPKEntry *historyEntry;
  while(historyEntry = [enumerator nextObject]){
    historySize += historyEntry.estimatedByteSize;
    if(historySize > self.tree.metaData.historyMaxSize) {
      removeIndex = [self.mutableHistory indexOfObject:historyEntry];
      break;
    }
  }
  if(removeIndex >= 0) {
    [self removeMutableHistoryAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(removeIndex, self.mutableHistory.count - removeIndex)]];
  }
}


- (NSUInteger)estimatedByteSize {
  
  NSUInteger __block size = 128; // KeePass suggest this as the inital size
  
  /* Attributes */
  for(KPKAttribute *attribute in self.mutableAttributes) {
    size += attribute.value.length;
    size += attribute.key.length;
  }
  
  /* Binaries */
  for(KPKBinary *binary in self.binaries) {
    size += binary.name.length;
    size += binary.data.length;
  }
  
  /* Autotype */
  size += self.autotype.defaultKeystrokeSequence.length;
  for(KPKWindowAssociation *association in self.autotype.associations ) {
    size += association.windowTitle.length;
    size += association.keystrokeSequence.length;
  }
  
  /* Misc */
  size += self.overrideURL.length;
  
  /* Tags */
  for(NSString *tag in self.tags) {
    size +=tag.length;
  }
  
  /* History */
  for(KPKEntry *entry in self.mutableHistory) {
    size += entry.estimatedByteSize;
  }
  
  /* Color? */
  return size;
}

#pragma mark -
#pragma mark KVO

/* Binaries */
- (void)insertObject:(KPKBinary *)binary inMutableBinariesAtIndex:(NSUInteger)index {
  /* Clamp the index to make sure we do not add at wrong places */
  index = MIN([self.mutableBinaries count], index);
  [self.mutableBinaries insertObject:binary atIndex:index];
}

- (void)removeObjectFromMutableBinariesAtIndex:(NSUInteger)index {
  if(index < self.mutableBinaries.count) {
    [self.mutableBinaries removeObjectAtIndex:index];
  }
}

/* History */
- (void)insertObject:(KPKEntry *)entry inMutableHistoryAtIndex:(NSUInteger)index {
  index = MIN(self.mutableHistory.count, index);
  /* Entries in history should not have a history of their own */
  [entry clearHistory];
  NSAssert(entry.history.count == 0, @"History entries cannot hold a history of their own!");
  entry.isHistory = YES;
  entry.parent = self.parent;
  [self.mutableHistory insertObject:entry atIndex:index];
}

- (void)removeObjectFromMutableHistoryAtIndex:(NSUInteger)index {
  [self removeMutableHistoryAtIndexes:[NSIndexSet indexSetWithIndex:index]];
}

- (void)removeMutableHistoryAtIndexes:(NSIndexSet *)indexes {
  [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
    KPKEntry *historyEntry = self.mutableHistory[idx];
    NSAssert(historyEntry != nil, @"History indexes need to be valid!");
    historyEntry.isHistory = NO;
  }];
  [self.mutableHistory removeObjectsAtIndexes:indexes];
}

#pragma mark -
#pragma mark Private Helper



@end
