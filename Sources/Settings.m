#import "Flaco.h"
#import <QuartzCore/QuartzCore.h>

NSNotificationName const FLSettingsDidChange = @"FLSettingsDidChange";

@implementation FLSettings

/// The Swift Flaco's key and values: "off", "track" or "album".
+ (BOOL)replayGain {
    return ![[NSUserDefaults.standardUserDefaults stringForKey:@"replayGain"] isEqualToString:@"off"];
}

+ (void)setReplayGain:(BOOL)on {
    [NSUserDefaults.standardUserDefaults setObject:on ? @"album" : @"off" forKey:@"replayGain"];
    [NSNotificationCenter.defaultCenter postNotificationName:FLSettingsDidChange object:nil];
}

@end

#pragma mark - Pieces

/// A row in a card: a title, a value or a control on the right, and a bar under them when there's progress.
@interface FLRow : UIControl
@property (nonatomic, strong) UILabel *title, *value;
@property (nonatomic, strong, nullable) UIView *accessory;
@property (nonatomic) BOOL chevron, centered;
/// From 0 to 1, or negative for no bar.
@property (nonatomic) CGFloat bar;
@property (nonatomic, strong) FLTheme *theme;
+ (CGFloat)heightWithBar:(BOOL)bar;
@end

@implementation FLRow {
    UIImageView *_chevronView;
    UIView *_track, *_fill, *_highlight;
}

+ (CGFloat)heightWithBar:(BOOL)bar { return bar ? 62 : 48; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _highlight = [UIView new];
        _highlight.userInteractionEnabled = NO;
        _title = FLLabel([UIFont systemFontOfSize:14], NSTextAlignmentLeft);
        _value = FLLabel(FLMono(10.5), NSTextAlignmentRight);
        _value.adjustsFontSizeToFitWidth = YES;
        _value.minimumScaleFactor = 0.8;
        _chevronView = [[UIImageView alloc] initWithImage:FLIcon(@"chevron")];
        _track = [UIView new];
        _fill = [UIView new];
        _track.layer.cornerRadius = _fill.layer.cornerRadius = 1.5;
        _bar = -1;
        for (UIView *view in @[_highlight, _title, _value, _chevronView, _track, _fill]) [self addSubview:view];
    }
    return self;
}

- (void)setAccessory:(UIView *)accessory {
    [_accessory removeFromSuperview];
    _accessory = accessory;
    if (accessory) [self addSubview:accessory];
    [self setNeedsLayout];
}

- (void)setBar:(CGFloat)bar {
    _bar = bar;
    [self setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _highlight.backgroundColor = highlighted ? [_theme.text colorWithAlphaComponent:0.06] : UIColor.clearColor;
}

- (void)setTheme:(FLTheme *)theme {
    _theme = theme;
    _title.textColor = _centered ? theme.accent : theme.text;
    _value.textColor = theme.secondary;
    _chevronView.tintColor = theme.faint;
    _track.backgroundColor = theme.line;
    _fill.backgroundColor = theme.accent;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height, line = _bar >= 0 ? 24 : height / 2;
    _highlight.frame = self.bounds;
    _chevronView.hidden = !_chevron;
    CGFloat right = width - (_chevron ? 34 : 16);
    _chevronView.frame = CGRectMake(width - 34, line - 12, 24, 24);
    if (_centered) {
        _title.font = FLMono(11);
        _title.textAlignment = NSTextAlignmentCenter;
        _title.frame = self.bounds;
    } else {
        CGFloat titleWidth = ceil([_title sizeThatFits:CGSizeMake(CGFLOAT_MAX, 20)].width);
        _title.frame = CGRectMake(16, line - 10, titleWidth, 20);
        CGFloat x = MAX(16 + titleWidth + 12, 104);
        if (_accessory) {
            CGSize size = [_accessory isKindOfClass:UISwitch.class] ? _accessory.bounds.size : CGSizeMake(right - x, 40);
            _accessory.frame = CGRectMake(right - size.width, line - size.height / 2, size.width, size.height);
            // A switch keeps its value beside it; a text field takes the value's place.
            if ([_accessory isKindOfClass:UISwitch.class]) right = CGRectGetMinX(_accessory.frame) - 10;
        }
        _value.frame = CGRectMake(x, line - 10, right - x, 20);
    }
    _track.hidden = _fill.hidden = _bar < 0;
    _track.frame = CGRectMake(16, 44, width - 32, 3);
    _fill.frame = CGRectMake(16, 44, (width - 32) * MIN(MAX(_bar, 0), 1), 3);
}

@end

/// Rows on a panel with hairlines between them.
@interface FLCard : UIView
@property (nonatomic, copy) NSArray<UIView *> *rows;
- (CGFloat)layoutAt:(CGFloat)y width:(CGFloat)width;
- (void)apply:(FLTheme *)theme;
@end

@implementation FLCard {
    NSMutableArray<UIView *> *_lines;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 10;
        self.layer.borderWidth = FLHairline();
        self.clipsToBounds = YES;
        _lines = [NSMutableArray array];
    }
    return self;
}

- (void)setRows:(NSArray<UIView *> *)rows {
    for (UIView *view in _rows) [view removeFromSuperview];
    for (UIView *line in _lines) [line removeFromSuperview];
    [_lines removeAllObjects];
    _rows = [rows copy];
    for (NSUInteger i = 0; i < rows.count; i++) {
        [self addSubview:rows[i]];
        if (i == 0) continue;
        UIView *line = [UIView new];
        [_lines addObject:line];
        [self addSubview:line];
    }
}

- (CGFloat)layoutAt:(CGFloat)y width:(CGFloat)width {
    CGFloat top = 0;
    for (NSUInteger i = 0; i < _rows.count; i++) {
        UIView *row = _rows[i];
        CGFloat height = [row isKindOfClass:FLRow.class] ? [FLRow heightWithBar:((FLRow *)row).bar >= 0] : row.bounds.size.height;
        if (i > 0) _lines[i - 1].frame = CGRectMake(16, top, width - 16, FLHairline());
        row.frame = CGRectMake(0, top, width, height);
        top += height;
    }
    self.frame = CGRectMake(12, y, width, top);
    return y + top;
}

- (void)apply:(FLTheme *)theme {
    self.backgroundColor = theme.panel;
    self.layer.borderColor = theme.line.CGColor;
    for (UIView *line in _lines) line.backgroundColor = theme.line;
    for (UIView *row in _rows) if ([row isKindOfClass:FLRow.class]) ((FLRow *)row).theme = theme;
}

@end

/// A pushed screen with the player's colours: a back button, a title, and a scrolling body.
@interface FLPage : UIViewController
@property (nonatomic, strong) FLTheme *theme;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, readonly) CGFloat top;
- (UILabel *)sectionLabel:(NSString *)text;
- (void)back;
@end

@implementation FLPage {
    CAGradientLayer *_glow;
    UIButton *_back;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _theme = FLCurrentTheme();
    self.view.backgroundColor = _theme.background;
    _glow = [CAGradientLayer layer];
    _glow.colors = @[(id)_theme.glow.CGColor, (id)[_theme.glow colorWithAlphaComponent:0].CGColor];
    [self.view.layer addSublayer:_glow];
    _scroll = [UIScrollView new];
    _scroll.alwaysBounceVertical = YES;
    _scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    if ([_scroll respondsToSelector:NSSelectorFromString(@"contentInsetAdjustmentBehavior")]) [_scroll setValue:@2 forKey:@"contentInsetAdjustmentBehavior"];
    [self.view addSubview:_scroll];
    _back = FLIconButton(@"back", @"Back");
    _back.tintColor = _theme.text;
    [_back addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
    _titleLabel = FLLabel([UIFont systemFontOfSize:15 weight:UIFontWeightSemibold], NSTextAlignmentCenter);
    _titleLabel.textColor = _theme.text;
    _titleLabel.text = self.title;
    [self.view addSubview:_titleLabel];
    [self.view addSubview:_back];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (CGFloat)top { return FLInsets(self.view).top + 44; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, inset = FLInsets(self.view).top;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glow.frame = CGRectMake(0, 0, width, inset + 280);
    [CATransaction commit];
    _back.frame = CGRectMake(4, inset, 44, 44);
    _titleLabel.frame = CGRectMake(60, inset, width - 120, 44);
    _scroll.frame = CGRectMake(0, self.top, width, self.view.bounds.size.height - self.top);
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *label = FLLabel(FLMono(10), NSTextAlignmentLeft);
    label.text = text;
    label.textColor = _theme.secondary;
    return label;
}

- (void)back {
    if (self.navigationController.viewControllers.firstObject == self) [self dismissViewControllerAnimated:YES completion:nil];
    else [self.navigationController popViewControllerAnimated:YES];
}

- (void)keyboard:(NSNotification *)note {
    CGRect frame = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat covered = MAX(0, CGRectGetMaxY(_scroll.frame) - CGRectGetMinY(frame));
    _scroll.contentInset = UIEdgeInsetsMake(0, 0, covered, 0);
    _scroll.scrollIndicatorInsets = _scroll.contentInset;
}

@end

/// Album covers from the server, for the chooser.
@interface FLRemoteCovers : NSObject
+ (void)load:(NSString *)coverID into:(UIImageView *)view;
@end

@implementation FLRemoteCovers

+ (NSCache *)cache {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 120; });
    return cache;
}

+ (void)load:(NSString *)coverID into:(UIImageView *)view {
    view.image = coverID ? [self.cache objectForKey:coverID] : nil;
    view.accessibilityIdentifier = coverID;
    if (!coverID || view.image) return;
    NSURL *url = [FLServer.shared coverURL:coverID size:120];
    if (!url) return;
    __weak UIImageView *weakView = view;
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.cache setObject:image forKey:coverID];
            if ([weakView.accessibilityIdentifier isEqualToString:coverID]) weakView.image = image;
        });
    }] resume];
}

@end

#pragma mark - Choosing albums

@interface FLChooseCell : UITableViewCell
- (void)showAlbum:(FLRemoteAlbum *)album ticked:(BOOL)ticked enabled:(BOOL)enabled theme:(FLTheme *)theme;
@end

@implementation FLChooseCell {
    UIImageView *_cover, *_check;
    UILabel *_title, *_detail, *_size;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _cover = [UIImageView new];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 2;
        _check = [[UIImageView alloc] initWithImage:FLIcon(@"check")];
        _title = FLLabel([UIFont systemFontOfSize:14 weight:UIFontWeightSemibold], NSTextAlignmentLeft);
        _detail = FLLabel([UIFont systemFontOfSize:12.5], NSTextAlignmentLeft);
        _size = FLLabel(FLMono(10), NSTextAlignmentRight);
        for (UIView *view in @[_cover, _check, _title, _detail, _size]) [self.contentView addSubview:view];
    }
    return self;
}

- (void)showAlbum:(FLRemoteAlbum *)album ticked:(BOOL)ticked enabled:(BOOL)enabled theme:(FLTheme *)theme {
    [FLRemoteCovers load:album.coverArt into:_cover];
    _title.text = album.title;
    _detail.text = album.year ? [NSString stringWithFormat:@"%@ · %ld", album.artist, (long)album.year] : album.artist;
    _size.text = FLSize(album.size);
    _cover.backgroundColor = theme.line;
    _title.textColor = theme.text;
    _detail.textColor = theme.secondary;
    _size.textColor = theme.secondary;
    _check.tintColor = ticked ? theme.accent : [theme.text colorWithAlphaComponent:0.12];
    self.contentView.alpha = enabled ? 1 : 0.45;
    self.accessibilityTraits = UIAccessibilityTraitButton | (ticked ? UIAccessibilityTraitSelected : 0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    _cover.frame = CGRectMake(12, 8, 44, 44);
    _check.frame = CGRectMake(width - 40, 18, 24, 24);
    _size.frame = CGRectMake(width - 112, 20, 64, 20);
    _title.frame = CGRectMake(68, 11, width - 68 - 116, 19);
    _detail.frame = CGRectMake(68, 31, width - 68 - 116, 17);
}

@end

/// Everything, or the albums ticked. The 5c can't hold a whole library, so the bottom shows what fits.
@interface FLChooseViewController : FLPage <UITableViewDataSource, UITableViewDelegate>
@end

@implementation FLChooseViewController {
    UITableView *_table;
    FLCard *_card;
    UISwitch *_everything;
    UIView *_bottom;
    UILabel *_summary;
    UIButton *_done;
    NSMutableSet<NSString *> *_ticked;
}

- (void)viewDidLoad {
    self.title = @"Albums";
    [super viewDidLoad];
    FLSync *sync = FLSync.shared;
    _ticked = [NSMutableSet set];
    for (FLRemoteAlbum *album in sync.albums) if ([sync wants:album]) [_ticked addObject:album.albumID];

    _everything = [UISwitch new];
    _everything.on = sync.choice == FLChoiceEverything;
    _everything.onTintColor = self.theme.accent;
    [_everything addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
    FLRow *row = [FLRow new];
    row.title.text = @"Everything";
    row.value.text = @"NEW ALBUMS TOO";
    row.accessory = _everything;
    _card = [FLCard new];
    _card.rows = @[row];
    [_card apply:self.theme];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _table.rowHeight = 60;
    _table.dataSource = self;
    _table.delegate = self;
    [_table registerClass:FLChooseCell.class forCellReuseIdentifier:@"album"];
    if ([_table respondsToSelector:NSSelectorFromString(@"contentInsetAdjustmentBehavior")]) [_table setValue:@2 forKey:@"contentInsetAdjustmentBehavior"];
    _table.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 8 + 48 + 12)];
    [_table.tableHeaderView addSubview:_card];
    [self.scroll removeFromSuperview];
    [self.view insertSubview:_table belowSubview:self.titleLabel];

    _bottom = [UIView new];
    _bottom.backgroundColor = self.theme.background;
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4000, FLHairline())];
    line.backgroundColor = self.theme.line;
    [_bottom addSubview:line];
    _summary = FLLabel(FLMono(10.5), NSTextAlignmentLeft);
    _summary.textColor = self.theme.secondary;
    _summary.numberOfLines = 2;
    _done = [UIButton buttonWithType:UIButtonTypeCustom];
    [_done setTitle:@"DONE" forState:UIControlStateNormal];
    _done.titleLabel.font = FLMono(11);
    [_done setTitleColor:self.theme.accent forState:UIControlStateNormal];
    _done.backgroundColor = self.theme.tint;
    _done.layer.cornerRadius = 8;
    [_done addTarget:self action:@selector(done) forControlEvents:UIControlEventTouchUpInside];
    [_bottom addSubview:_summary];
    [_bottom addSubview:_done];
    [self.view addSubview:_bottom];
    [self summarize];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncChanged) name:FLSyncDidChange object:nil];
}

/// Right after signing in, the server's albums arrive after this opens.
- (void)syncChanged {
    NSArray *albums = FLSync.shared.albums;
    if (albums.count == [_table numberOfRowsInSection:0]) {
        [self summarize];
        [self tryPick];
        return;
    }
    for (FLRemoteAlbum *album in albums) if ([FLSync.shared wants:album]) [_ticked addObject:album.albumID];
    [_table reloadData];
    [self summarize];
    [self tryPick];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self tryPick];
}

- (void)tryPick {
#if TARGET_OS_SIMULATOR
    // `-FLPick YES` ticks the smallest album, to try a download.
    NSArray<FLRemoteAlbum *> *albums = FLSync.shared.albums;
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FLPick"] && albums.count && !_ticked.count && self.navigationController.topViewController == self) {
        FLRemoteAlbum *smallest = albums[0];
        for (FLRemoteAlbum *album in albums) if (album.size < smallest.size) smallest = album;
        [_ticked addObject:smallest.albumID];
        [_table reloadData];
        [self summarize];
        [self done];
    }
#endif
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height, bottom = 64 + FLInsets(self.view).bottom;
    _bottom.frame = CGRectMake(0, height - bottom, width, bottom);
    _summary.frame = CGRectMake(16, 10, width - 16 - 112, 44);
    _done.frame = CGRectMake(width - 100, 12, 88, 40);
    _table.frame = CGRectMake(0, self.top, width, height - self.top - bottom);
    [_card layoutAt:8 width:width - 24];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return FLSync.shared.albums.count;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    FLChooseCell *cell = [table dequeueReusableCellWithIdentifier:@"album" forIndexPath:path];
    FLRemoteAlbum *album = FLSync.shared.albums[path.row];
    [cell showAlbum:album ticked:_everything.on || [_ticked containsObject:album.albumID] enabled:!_everything.on theme:self.theme];
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (_everything.on) return;
    NSString *albumID = FLSync.shared.albums[path.row].albumID;
    if ([_ticked containsObject:albumID]) [_ticked removeObject:albumID];
    else [_ticked addObject:albumID];
    [table reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    [self summarize];
}

- (void)changed {
    [_table reloadData];
    [self summarize];
}

- (BOOL)keeps:(FLRemoteAlbum *)album {
    return _everything.on || [_ticked containsObject:album.albumID];
}

/// What comes down, what goes, and what's free.
- (void)summarize {
    long long adds = 0, removes = 0;
    for (FLRemoteAlbum *album in FLSync.shared.albums) {
        BOOL here = [FLSync.shared hasOnPhone:album];
        if ([self keeps:album] && !here) adds += album.size;
        if (![self keeps:album] && here) removes += album.size;
    }
    NSMutableArray *parts = [NSMutableArray array];
    if (adds) [parts addObject:[NSString stringWithFormat:@"+%@", FLSize(adds)]];
    if (removes) [parts addObject:[NSString stringWithFormat:@"−%@", FLSize(removes)]];
    if (!parts.count) [parts addObject:@"NO CHANGES"];
    long long free = FLSync.freeSpace;
    if (!FLSync.shared.albums.count) [parts setArray:@[FLSync.shared.phase == FLSyncFailed ? FLSync.shared.failure.uppercaseString ?: @"" : @"LOADING…"]];
    _summary.text = [NSString stringWithFormat:@"%@\n%@ FREE", [parts componentsJoinedByString:@"  "], FLSize(free)];
    _summary.textColor = adds - removes > free - 300000000 ? self.theme.accent : self.theme.secondary;
}

- (void)done {
    NSInteger removing = 0;
    for (FLRemoteAlbum *album in FLSync.shared.albums) if (![self keeps:album] && [FLSync.shared hasOnPhone:album]) removing++;
    void (^commit)(void) = ^{
        if (self->_everything.on) [FLSync.shared chooseEverything];
        else [FLSync.shared chooseAlbums:self->_ticked];
        [self.navigationController popViewControllerAnimated:YES];
    };
    if (!removing) {
        commit();
        return;
    }
    NSString *title = removing == 1 ? @"Remove 1 album from this phone?" : [NSString stringWithFormat:@"Remove %ld albums from this phone?", (long)removing];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:@"They stay on the server." preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { commit(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Settings

/// Settings has little in it: the server, what comes down from it, and ReplayGain.
@interface FLSettingsPage : FLPage <UITextFieldDelegate>
@end

@implementation FLSettingsPage {
    UILabel *_serverLabel, *_downloadLabel, *_playbackLabel, *_note, *_footer;
    FLCard *_server, *_download, *_playback;
    UITextField *_address, *_user, *_password;
    UIButton *_eye;
    FLRow *_connect, *_albums, *_status, *_storage;
    BOOL _connecting;
    NSString *_problem;
}

- (void)viewDidLoad {
    self.title = @"Settings";
    [super viewDidLoad];
    _serverLabel = [self sectionLabel:@"SERVER"];
    _downloadLabel = [self sectionLabel:@"DOWNLOAD"];
    _playbackLabel = [self sectionLabel:@"PLAYBACK"];
    _note = FLLabel(FLMono(10), NSTextAlignmentLeft);
    _note.numberOfLines = 0;
    _note.textColor = self.theme.secondary;
    _footer = FLLabel(FLMono(10), NSTextAlignmentCenter);
    _footer.numberOfLines = 0;
    _footer.textColor = self.theme.faint;
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    _footer.text = [NSString stringWithFormat:@"FLACO %@\nFINDER → THIS IPHONE → FILES ADDS MUSIC TOO", version];
    _server = [FLCard new];
    _download = [FLCard new];
    _playback = [FLCard new];
    for (UIView *view in @[_serverLabel, _server, _note, _downloadLabel, _download, _playbackLabel, _playback, _footer]) [self.scroll addSubview:view];

    _address = [self field:@"music.example.com" secure:NO];
    _address.keyboardType = UIKeyboardTypeURL;
    _user = [self field:@"user" secure:NO];
    _password = [self field:@"password" secure:YES];
    _password.returnKeyType = UIReturnKeyGo;
    _eye = FLIconButton(@"eye", @"Show password");
    _eye.tintColor = self.theme.secondary;
    _eye.frame = CGRectMake(0, 0, 44, 44);
    [_eye addTarget:self action:@selector(toggleEye) forControlEvents:UIControlEventTouchUpInside];
    _password.rightView = _eye;
    _password.rightViewMode = UITextFieldViewModeAlways;

    _connect = [FLRow new];
    _connect.centered = YES;
    [_connect addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
    _albums = [FLRow new];
    _albums.title.text = @"Albums";
    _albums.chevron = YES;
    [_albums addTarget:self action:@selector(choose) forControlEvents:UIControlEventTouchUpInside];
    _status = [FLRow new];
    _status.title.text = @"Sync";
    [_status addTarget:FLSync.shared action:@selector(start) forControlEvents:UIControlEventTouchUpInside];
    _storage = [FLRow new];
    _storage.title.text = @"On this phone";
    _storage.userInteractionEnabled = NO;
    FLRow *gain = [FLRow new];
    gain.title.text = @"ReplayGain";
    gain.value.text = @"EVEN VOLUME";
    UISwitch *gainSwitch = [UISwitch new];
    gainSwitch.on = FLSettings.replayGain;
    gainSwitch.onTintColor = self.theme.accent;
    [gainSwitch addTarget:self action:@selector(gainChanged:) forControlEvents:UIControlEventValueChanged];
    gain.accessory = gainSwitch;
    _playback.rows = @[gain];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:FLSyncDidChange object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:FLLibraryDidChange object:nil];
    [self rebuild];
#if TARGET_OS_SIMULATOR
    // `-FLAddress … -FLUser … -FLPassword …` signs in without typing.
    NSUserDefaults *arguments = NSUserDefaults.standardUserDefaults;
    if ([arguments stringForKey:@"FLPassword"] && !FLServer.shared.configured) {
        _address.text = [arguments stringForKey:@"FLAddress"];
        _user.text = [arguments stringForKey:@"FLUser"];
        _password.text = [arguments stringForKey:@"FLPassword"];
        [self connectTapped];
    }
#endif
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (UITextField *)field:(NSString *)placeholder secure:(BOOL)secure {
    UITextField *field = [UITextField new];
    field.font = [UIFont systemFontOfSize:14];
    field.textColor = self.theme.text;
    field.tintColor = self.theme.accent;
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSForegroundColorAttributeName: self.theme.faint}];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.keyboardAppearance = UIKeyboardAppearanceDark;
    field.returnKeyType = UIReturnKeyNext;
    field.secureTextEntry = secure;
    field.delegate = self;
    return field;
}

- (FLRow *)rowTitled:(NSString *)title with:(UIView *)accessory {
    FLRow *row = [FLRow new];
    row.title.text = title;
    row.accessory = accessory;
    return row;
}

/// The server card has two faces: the sign-in fields, or who's signed in.
- (void)rebuild {
    FLServer *server = FLServer.shared;
    if (server.configured) {
        FLRow *host = [self rowTitled:@"Server" with:nil], *user = [self rowTitled:@"User" with:nil];
        host.value.text = server.host;
        user.value.text = server.user;
        host.userInteractionEnabled = user.userInteractionEnabled = NO;
        _connect.title.text = @"DISCONNECT";
        _server.rows = @[host, user, _connect];
    } else {
        if (!_address.text.length) _address.text = server.address.length ? server.host : @"";
        if (!_user.text.length) _user.text = server.user;
        _connect.title.text = _connecting ? @"CONNECTING…" : @"CONNECT";
        _server.rows = @[[self rowTitled:@"Address" with:_address], [self rowTitled:@"User" with:_user], [self rowTitled:@"Password" with:_password], _connect];
    }
    _download.rows = @[_albums, _status, _storage];
    for (FLCard *card in @[_server, _download, _playback]) [card apply:self.theme];
    [self refresh];
}

- (void)refresh {
    FLSync *sync = FLSync.shared;
    BOOL configured = FLServer.shared.configured;
    _downloadLabel.hidden = _download.hidden = !configured;
    NSInteger ticked = 0;
    long long tickedSize = 0;
    for (FLRemoteAlbum *album in sync.albums) {
        if (![sync wants:album]) continue;
        ticked++;
        tickedSize += album.size;
    }
    _albums.value.text = sync.choice == FLChoiceEverything ? @"EVERYTHING" : sync.choice == FLChoiceUndecided ? @"CHOOSE"
                         : [NSString stringWithFormat:@"%ld · %@", (long)ticked, FLSize(tickedSize)];
    _albums.value.textColor = sync.choice == FLChoiceUndecided ? self.theme.accent : self.theme.secondary;

    switch (sync.phase) {
        case FLSyncDownloading:
            _status.value.text = [NSString stringWithFormat:@"%@ / %@ · %@/S", FLSize(sync.bytesDone), FLSize(sync.bytesTotal), FLSize((long long)sync.speed)];
            _status.bar = sync.bytesTotal ? (CGFloat)sync.bytesDone / sync.bytesTotal : 0;
            break;
        case FLSyncChecking:
            _status.value.text = @"CHECKING…";
            _status.bar = -1;
            break;
        case FLSyncFailed:
            _status.value.text = sync.failure.uppercaseString ?: @"FAILED";
            _status.bar = -1;
            break;
        case FLSyncIdle:
            _status.value.text = sync.lastSynced ? [@"UP TO DATE · " stringByAppendingString:[self ago:sync.lastSynced]] : @"SYNC NOW";
            _status.bar = -1;
            break;
    }
    long long music = 0;
    for (FLTrack *track in FLLibrary.shared.tracks) music += track.size;
    long long free = FLSync.freeSpace, capacity = FLSync.capacity;
    _storage.value.text = [NSString stringWithFormat:@"%@ MUSIC · %@ FREE", FLSize(music), FLSize(free)];
    _storage.bar = capacity ? 1 - (CGFloat)free / capacity : 0;

    _note.text = _problem ?: (configured ? nil : @"Flaco downloads from Navidrome or any Subsonic server. It doesn't stream.");
    _note.textColor = _problem ? self.theme.accent : self.theme.secondary;
    [self.view setNeedsLayout];
}

- (NSString *)ago:(NSDate *)date {
    NSTimeInterval seconds = -date.timeIntervalSinceNow;
    if (seconds < 90) return @"NOW";
    if (seconds < 3600) return [NSString stringWithFormat:@"%.0f MIN AGO", seconds / 60];
    if (seconds < 86400) return [NSString stringWithFormat:@"%.0f H AGO", seconds / 3600];
    return [NSString stringWithFormat:@"%.0f DAYS AGO", seconds / 86400];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, inner = width - 24, y = 8;
    _serverLabel.frame = CGRectMake(28, y, inner, 26);
    y = [_server layoutAt:y + 26 width:inner];
    CGFloat noteHeight = _note.text.length ? ceil([_note sizeThatFits:CGSizeMake(inner - 32, 200)].height) : 0;
    _note.frame = CGRectMake(28, y + 8, inner - 32, noteHeight);
    y += noteHeight ? noteHeight + 16 : 0;
    if (!_download.hidden) {
        _downloadLabel.frame = CGRectMake(28, y + 14, inner, 26);
        y = [_download layoutAt:y + 40 width:inner];
    }
    _playbackLabel.frame = CGRectMake(28, y + 14, inner, 26);
    y = [_playback layoutAt:y + 40 width:inner];
    _footer.frame = CGRectMake(16, y + 24, width - 32, 30);
    self.scroll.contentSize = CGSizeMake(width, y + 24 + 30 + 24 + FLInsets(self.view).bottom);
}

#pragma mark Actions

- (void)toggleEye {
    // Switching secureTextEntry clears or moves the text on some systems; put it back as it was.
    NSString *text = _password.text;
    _password.secureTextEntry = !_password.secureTextEntry;
    _password.text = text;
    [_eye setImage:FLIcon(_password.secureTextEntry ? @"eye" : @"eyeOff") forState:UIControlStateNormal];
    _eye.accessibilityLabel = _password.secureTextEntry ? @"Show password" : @"Hide password";
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    if (field == _address) [_user becomeFirstResponder];
    else if (field == _user) [_password becomeFirstResponder];
    else [self connectTapped];
    return NO;
}

- (void)connectTapped {
    if (FLServer.shared.configured) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Disconnect from the server?"
                                                                       message:@"The music already downloaded stays on this phone."
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:@"Disconnect" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [FLServer.shared disconnect];
            self->_password.text = @"";
            [self rebuild];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (_connecting || !_address.text.length || !_user.text.length || !_password.text.length) return;
    [self.view endEditing:YES];
    _connecting = YES;
    _problem = nil;
    [self rebuild];
    NSString *address = _address.text, *user = _user.text, *password = _password.text;
    [FLServer.shared checkAddress:address user:user password:password completion:^(NSString *error) {
        self->_connecting = NO;
        if (error) {
            self->_problem = error;
            [self rebuild];
            return;
        }
        [FLServer.shared saveAddress:address user:user password:password];
        [self rebuild];
        [FLSync.shared start];
        [self choose];
    }];
}

- (void)choose {
    [self.navigationController pushViewController:[FLChooseViewController new] animated:YES];
}

- (void)gainChanged:(UISwitch *)toggle {
    FLSettings.replayGain = toggle.on;
}

@end

#pragma mark - Opening

/// Lets the back swipe work with the navigation bar hidden, except on the first page.
@interface FLNavigation : UINavigationController <UIGestureRecognizerDelegate>
@end

@implementation FLNavigation

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationBarHidden = YES;
    self.interactivePopGestureRecognizer.delegate = self;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    return self.viewControllers.count > 1;
}

@end

UIViewController *FLSettingsScreen(BOOL choosing) {
    FLNavigation *navigation = [[FLNavigation alloc] initWithRootViewController:[FLSettingsPage new]];
    if (choosing) [navigation pushViewController:[FLChooseViewController new] animated:NO];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    return navigation;
}
