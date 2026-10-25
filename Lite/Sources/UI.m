#import "Lite.h"
#import <QuartzCore/QuartzCore.h>

UIFont *FLMono(CGFloat size) { return [UIFont fontWithName:@"Menlo-Regular" size:size] ?: [UIFont systemFontOfSize:size]; }

NSString *FLClock(double seconds) {
    long total = (long)MAX(0, floor(seconds));
    if (total >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", total / 3600, total / 60 % 60, total % 60];
    return [NSString stringWithFormat:@"%ld:%02ld", total / 60, total % 60];
}

static CGFloat FLHairline(void) { return 1 / UIScreen.mainScreen.scale; }

/// iOS 10 has no safe area: the status bar's 20 points. The simulator's newer iOS reports its own.
static UIEdgeInsets FLInsets(UIView *view) {
    if ([view respondsToSelector:NSSelectorFromString(@"safeAreaInsets")]) {
        UIEdgeInsets insets = [[view valueForKey:@"safeAreaInsets"] UIEdgeInsetsValue];
        if (insets.top > 0) return insets;
    }
    return UIEdgeInsetsMake(20, 0, 0, 0);
}

static NSString *FLSize(long long bytes) {
    double megabytes = bytes / 1e6;
    return megabytes >= 1000 ? [NSString stringWithFormat:@"%.1f GB", megabytes / 1000] : [NSString stringWithFormat:@"%.0f MB", megabytes];
}

static NSString *FLRate(double rate) {
    return [NSString stringWithFormat:@"%g", round(rate / 100) / 10];
}

static UILabel *FLLabel(UIFont *font, NSTextAlignment alignment) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

#pragma mark - Icons

/// iOS 10 has no SF Symbols, so the transport's icons are drawn here, 24 points square.
static UIImage *FLIcon(NSString *name) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache[name]) return cache[name];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 0);
    [UIColor.blackColor set];
    UIBezierPath *fill = [UIBezierPath bezierPath], *stroke = [UIBezierPath bezierPath];
    stroke.lineWidth = 1.8;
    stroke.lineCapStyle = kCGLineCapRound;
    stroke.lineJoinStyle = kCGLineJoinRound;
    void (^triangle)(CGFloat, CGFloat, CGFloat, CGFloat) = ^(CGFloat x0, CGFloat x1, CGFloat top, CGFloat bottom) {
        [fill moveToPoint:CGPointMake(x0, top)];
        [fill addLineToPoint:CGPointMake(x1, (top + bottom) / 2)];
        [fill addLineToPoint:CGPointMake(x0, bottom)];
        [fill closePath];
    };
    void (^arrow)(CGPoint, CGFloat) = ^(CGPoint tip, CGFloat direction) {
        [stroke moveToPoint:CGPointMake(tip.x - 2.6 * direction, tip.y - 2.6)];
        [stroke addLineToPoint:tip];
        [stroke addLineToPoint:CGPointMake(tip.x - 2.6 * direction, tip.y + 2.6)];
    };
    if ([name isEqualToString:@"stop"]) {
        [fill appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(5.5, 5.5, 13, 13) cornerRadius:1.5]];
    } else if ([name isEqualToString:@"play"]) {
        triangle(7, 19.5, 4.5, 19.5);
    } else if ([name isEqualToString:@"pause"]) {
        [fill appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(6, 4.5, 4.2, 15) cornerRadius:1]];
        [fill appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(13.8, 4.5, 4.2, 15) cornerRadius:1]];
    } else if ([name isEqualToString:@"next"]) {
        triangle(4.5, 15.5, 5.5, 18.5);
        [fill appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(16.5, 5.5, 3, 13) cornerRadius:0.8]];
    } else if ([name isEqualToString:@"previous"]) {
        triangle(19.5, 8.5, 5.5, 18.5);
        [fill appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(4.5, 5.5, 3, 13) cornerRadius:0.8]];
    } else if ([name isEqualToString:@"shuffle"]) {
        [stroke moveToPoint:CGPointMake(3.5, 7.5)];
        [stroke addLineToPoint:CGPointMake(7.5, 7.5)];
        [stroke addCurveToPoint:CGPointMake(15.5, 16.5) controlPoint1:CGPointMake(11.5, 7.5) controlPoint2:CGPointMake(11.5, 16.5)];
        [stroke addLineToPoint:CGPointMake(20, 16.5)];
        [stroke moveToPoint:CGPointMake(3.5, 16.5)];
        [stroke addLineToPoint:CGPointMake(7.5, 16.5)];
        [stroke addCurveToPoint:CGPointMake(15.5, 7.5) controlPoint1:CGPointMake(11.5, 16.5) controlPoint2:CGPointMake(11.5, 7.5)];
        [stroke addLineToPoint:CGPointMake(20, 7.5)];
        arrow(CGPointMake(20.5, 7.5), 1);
        arrow(CGPointMake(20.5, 16.5), 1);
    } else if ([name hasPrefix:@"repeat"]) {
        [stroke moveToPoint:CGPointMake(4, 12.5)];
        [stroke addLineToPoint:CGPointMake(4, 10.5)];
        [stroke addCurveToPoint:CGPointMake(7.5, 7) controlPoint1:CGPointMake(4, 8.5) controlPoint2:CGPointMake(5.5, 7)];
        [stroke addLineToPoint:CGPointMake(19.5, 7)];
        arrow(CGPointMake(19.5, 7), 1);
        [stroke moveToPoint:CGPointMake(20, 11.5)];
        [stroke addLineToPoint:CGPointMake(20, 13.5)];
        [stroke addCurveToPoint:CGPointMake(16.5, 17) controlPoint1:CGPointMake(20, 15.5) controlPoint2:CGPointMake(18.5, 17)];
        [stroke addLineToPoint:CGPointMake(4.5, 17)];
        arrow(CGPointMake(4.5, 17), -1);
        if ([name isEqualToString:@"repeat1"]) {
            NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:7.5 weight:UIFontWeightBold], NSForegroundColorAttributeName: UIColor.blackColor};
            [@"1" drawAtPoint:CGPointMake(10.2, 7.6) withAttributes:attributes];
        }
    } else if ([name isEqualToString:@"sliders"]) {
        CGFloat ys[3] = {6.5, 12, 17.5}, knobs[3] = {15, 8.5, 13};
        for (int i = 0; i < 3; i++) {
            [stroke moveToPoint:CGPointMake(3.5, ys[i])];
            [stroke addLineToPoint:CGPointMake(20.5, ys[i])];
            [fill appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(knobs[i] - 2.6, ys[i] - 2.6, 5.2, 5.2)]];
        }
    } else if ([name isEqualToString:@"mark"]) {
        triangle(8, 17, 7.5, 16.5);
    }
    [fill fill];
    [stroke stroke];
    UIImage *image = [UIGraphicsGetImageFromCurrentImageContext() imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIGraphicsEndImageContext();
    cache[name] = image;
    return image;
}

static UIButton *FLIconButton(NSString *name, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:FLIcon(name) forState:UIControlStateNormal];
    button.accessibilityLabel = label;
    return button;
}

#pragma mark - Spectrum

/// Bars with falling peak caps. Levels rise at once and fall smoothly, as in Flaco.
@interface FLSpectrumView : UIView
@property (nonatomic, strong) UIColor *barColor;
- (void)follow:(nullable const float *)targets dt:(double)dt;
@end

@implementation FLSpectrumView {
    float _levels[FLBands], _peaks[FLBands], _holds[FLBands];
    BOOL _moving;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)follow:(const float *)targets dt:(double)dt {
    BOOL moving = NO;
    float fall = dt * 1.6, capFall = dt * 0.5;
    for (int i = 0; i < FLBands; i++) {
        float target = targets ? targets[i] : 0;
        _levels[i] = target >= _levels[i] ? target : MAX(target, _levels[i] - fall);
        if (_levels[i] >= _peaks[i]) {
            _peaks[i] = _levels[i];
            _holds[i] = 0.45;
        } else if (_holds[i] > 0) {
            _holds[i] -= dt;
        } else {
            _peaks[i] = MAX(_levels[i], _peaks[i] - capFall);
        }
        if (_levels[i] > 0.001 || _peaks[i] > 0.001) moving = YES;
    }
    if (moving || _moving) [self setNeedsDisplay];
    _moving = moving;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height, gap = 2;
    CGFloat bar = (width - gap * (FLBands - 1)) / FLBands, reach = height - 5;
    for (int i = 0; i < FLBands; i++) {
        CGFloat x = i * (bar + gap);
        [[self.barColor colorWithAlphaComponent:0.2] setFill];
        CGContextFillRect(context, CGRectMake(x, height - 1, bar, 1));
        [self.barColor setFill];
        CGFloat h = _levels[i] * reach;
        if (h > 0.5) CGContextFillRect(context, CGRectMake(x, height - h, bar, h));
        if (_peaks[i] > 0.002) {
            [[self.barColor colorWithAlphaComponent:0.75] setFill];
            CGContextFillRect(context, CGRectMake(x, MAX(0, height - MAX(2, _peaks[i] * reach) - 3), bar, 2));
        }
    }
}

@end

#pragma mark - Waveform seekbar

@interface FLWaveView : UIControl
@property (nonatomic, strong, nullable) NSData *levels;
@property (nonatomic) CGFloat progress;
@property (nonatomic, readonly) CGFloat dragged;
@property (nonatomic, readonly) BOOL dragging;
@property (nonatomic, strong) UIColor *playedColor, *restColor, *headColor;
@end

@implementation FLWaveView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        self.accessibilityLabel = @"Position";
    }
    return self;
}

- (void)setLevels:(NSData *)levels {
    _levels = levels;
    [self setNeedsDisplay];
}

- (void)setProgress:(CGFloat)progress {
    CGFloat old = _progress;
    _progress = MIN(MAX(progress, 0), 1);
    if (fabs(old - _progress) * self.bounds.size.width >= 0.5) [self setNeedsDisplay];
}

- (CGFloat)fractionAt:(UITouch *)touch {
    return MIN(MAX([touch locationInView:self].x / MAX(self.bounds.size.width, 1), 0), 1);
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _dragging = YES;
    _dragged = [self fractionAt:touch];
    [self setNeedsDisplay];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _dragged = [self fractionAt:touch];
    [self setNeedsDisplay];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (touch) _dragged = [self fractionAt:touch];
    _progress = _dragged;
    _dragging = NO;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self setNeedsDisplay];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    _dragging = NO;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat pitch = width / FLWaveBars, bar = MAX(1, pitch * 0.62);
    const float *levels = _levels.length == FLWaveBars * sizeof(float) ? _levels.bytes : NULL;
    CGFloat shown = _dragging ? _dragged : _progress;
    int played = (int)(shown * FLWaveBars);
    for (int i = 0; i < FLWaveBars; i++) {
        float level = levels ? levels[i] : -1;
        CGFloat h = level < 0 ? 2 : MAX(2, level * height);
        UIColor *color = level < 0 ? [self.restColor colorWithAlphaComponent:0.5] : i < played ? self.playedColor : self.restColor;
        [color setFill];
        CGContextFillRect(context, CGRectMake(i * pitch + (pitch - bar) / 2, (height - h) / 2, bar, h));
    }
    [self.headColor setFill];
    CGContextFillRect(context, CGRectMake(MIN(MAX(shown * width - 1, 0), width - 2), 0, 2, height));
}

@end

#pragma mark - Header

/// The top of the player: cover and tags, the spectrum panel, and the waveform seekbar.
@interface FLHeader : UIView
@property (nonatomic, strong) UIImageView *cover;
@property (nonatomic, strong) UILabel *title, *subtitle;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) FLSpectrumView *spectrum;
@property (nonatomic, strong) FLWaveView *wave;
- (void)apply:(FLTheme *)theme;
@end

@implementation FLHeader

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _cover = [UIImageView new];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 2;
        _title = FLLabel([UIFont systemFontOfSize:15 weight:UIFontWeightSemibold], NSTextAlignmentLeft);
        _subtitle = FLLabel([UIFont systemFontOfSize:12.5], NSTextAlignmentLeft);
        _panel = [UIView new];
        _panel.layer.cornerRadius = 4;
        _panel.layer.borderWidth = 1;
        _spectrum = [FLSpectrumView new];
        _wave = [FLWaveView new];
        for (UIView *view in @[_cover, _title, _subtitle, _panel, _spectrum, _wave]) [self addSubview:view];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, x = 12 + 60 + 12;
    _cover.frame = CGRectMake(12, 0, 60, 60);
    _title.frame = CGRectMake(x, 11, width - x - 12, 20);
    _subtitle.frame = CGRectMake(x, 33, width - x - 12, 17);
    _panel.frame = CGRectMake(12, 70, width - 24, 44);
    _spectrum.frame = CGRectInset(_panel.frame, 7, 5);
    _wave.frame = CGRectMake(12, 122, width - 24, 36);
}

- (void)apply:(FLTheme *)theme {
    _title.textColor = theme.text;
    _subtitle.textColor = theme.secondary;
    _cover.backgroundColor = theme.line;
    _panel.backgroundColor = theme.panel;
    _panel.layer.borderColor = theme.line.CGColor;
    _spectrum.barColor = theme.accent;
    [_spectrum setNeedsDisplay];
    _wave.playedColor = [theme.text colorWithAlphaComponent:0.85];
    _wave.restColor = theme.faint;
    _wave.headColor = theme.accent;
    [_wave setNeedsDisplay];
}

@end

#pragma mark - Tabs

@interface FLTabs : UIView
@property (nonatomic, strong) UIButton *all, *library, *settings;
@property (nonatomic) NSInteger selected;
- (void)apply:(FLTheme *)theme;
@end

@implementation FLTabs {
    UIView *_underline, *_line;
    FLTheme *_theme;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _all = [UIButton buttonWithType:UIButtonTypeCustom];
        _library = [UIButton buttonWithType:UIButtonTypeCustom];
        [_all setTitle:@"All" forState:UIControlStateNormal];
        [_library setTitle:@"Library" forState:UIControlStateNormal];
        for (UIButton *button in @[_all, _library]) button.titleLabel.font = FLMono(11.5);
        _settings = FLIconButton(@"sliders", @"Settings");
        _underline = [UIView new];
        _line = [UIView new];
        for (UIView *view in @[_all, _library, _settings, _underline, _line]) [self addSubview:view];
    }
    return self;
}

- (void)setSelected:(NSInteger)selected {
    _selected = selected;
    [self apply:_theme];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 4, width = self.bounds.size.width;
    for (UIButton *button in @[_all, _library]) {
        CGFloat w = ceil([button.currentTitle sizeWithAttributes:@{NSFontAttributeName: FLMono(11.5)}].width) + 20;
        button.frame = CGRectMake(x, 0, w, 44);
        x += w;
    }
    UIButton *active = _selected == 0 ? _all : _library;
    _underline.frame = CGRectMake(CGRectGetMinX(active.frame), 42, active.frame.size.width, 2);
    _settings.frame = CGRectMake(width - 46, 0, 44, 44);
    _line.frame = CGRectMake(0, 44, width, FLHairline());
}

- (void)apply:(FLTheme *)theme {
    if (!theme) return;
    _theme = theme;
    [_all setTitleColor:_selected == 0 ? theme.text : theme.secondary forState:UIControlStateNormal];
    [_library setTitleColor:_selected == 1 ? theme.text : theme.secondary forState:UIControlStateNormal];
    _underline.backgroundColor = theme.text;
    _line.backgroundColor = theme.line;
    _settings.tintColor = theme.text;
}

@end

#pragma mark - Transport

@interface FLTransport : UIView
@property (nonatomic, strong) UIButton *stop, *previous, *play, *next, *shuffle, *repeat;
@property (nonatomic, strong) UILabel *status, *time;
- (void)showPlaying:(BOOL)playing shuffle:(BOOL)shuffle repeat:(FLRepeat)repeat;
- (void)apply:(FLTheme *)theme;
@end

@implementation FLTransport {
    UIView *_line;
    FLTheme *_theme;
    BOOL _shuffleOn;
    FLRepeat _repeatMode;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _stop = FLIconButton(@"stop", @"Stop");
        _previous = FLIconButton(@"previous", @"Previous");
        _play = FLIconButton(@"play", @"Play");
        _next = FLIconButton(@"next", @"Next");
        _shuffle = FLIconButton(@"shuffle", @"Shuffle");
        _repeat = FLIconButton(@"repeat", @"Repeat");
        _status = FLLabel(FLMono(10), NSTextAlignmentLeft);
        _status.adjustsFontSizeToFitWidth = YES;
        _status.minimumScaleFactor = 0.8;
        _time = FLLabel(FLMono(10.5), NSTextAlignmentRight);
        _line = [UIView new];
        for (UIView *view in @[_line, _stop, _previous, _play, _next, _shuffle, _repeat, _status, _time]) [self addSubview:view];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _line.frame = CGRectMake(0, 0, width, FLHairline());
    NSArray *left = @[_stop, _previous, _play, _next], *right = @[_repeat, _shuffle];
    for (NSUInteger i = 0; i < left.count; i++) [left[i] setFrame:CGRectMake(4 + i * 44, 6, 44, 44)];
    for (NSUInteger i = 0; i < right.count; i++) [right[i] setFrame:CGRectMake(width - 48 - i * 44, 6, 44, 44)];
    _status.frame = CGRectMake(12, 54, width - 124, 22);
    _time.frame = CGRectMake(width - 112, 54, 100, 22);
}

- (void)showPlaying:(BOOL)playing shuffle:(BOOL)shuffle repeat:(FLRepeat)repeat {
    [_play setImage:FLIcon(playing ? @"pause" : @"play") forState:UIControlStateNormal];
    _play.accessibilityLabel = playing ? @"Pause" : @"Play";
    [_repeat setImage:FLIcon(repeat == FLRepeatOne ? @"repeat1" : @"repeat") forState:UIControlStateNormal];
    _shuffleOn = shuffle;
    _repeatMode = repeat;
    [self apply:_theme];
}

- (void)apply:(FLTheme *)theme {
    if (!theme) return;
    _theme = theme;
    _line.backgroundColor = theme.line;
    for (UIButton *button in @[_stop, _previous, _play, _next]) button.tintColor = theme.text;
    _shuffle.tintColor = _shuffleOn ? theme.accent : theme.secondary;
    _repeat.tintColor = _repeatMode != FLRepeatOff ? theme.accent : theme.secondary;
    _status.textColor = theme.secondary;
    _time.textColor = theme.text;
}

@end

#pragma mark - The list

@interface FLTrackRow : UIControl
@property (nonatomic, strong) FLTrack *track;
@property (nonatomic) BOOL current;
- (void)showTrack:(FLTrack *)track position:(NSInteger)position;
- (void)apply:(FLTheme *)theme;
@end

@implementation FLTrackRow {
    UIView *_highlight;
    UILabel *_number, *_title, *_duration;
    UIImageView *_mark;
    FLTheme *_theme;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _highlight = [UIView new];
        _highlight.layer.cornerRadius = 4;
        _highlight.userInteractionEnabled = NO;
        _number = FLLabel(FLMono(11), NSTextAlignmentRight);
        _title = FLLabel([UIFont systemFontOfSize:13.5], NSTextAlignmentLeft);
        _duration = FLLabel(FLMono(11.5), NSTextAlignmentRight);
        _mark = [[UIImageView alloc] initWithImage:FLIcon(@"mark")];
        for (UIView *view in @[_highlight, _number, _mark, _title, _duration]) [self addSubview:view];
    }
    return self;
}

- (void)showTrack:(FLTrack *)track position:(NSInteger)position {
    _track = track;
    _number.text = [NSString stringWithFormat:@"%ld", (long)(track.number > 0 ? track.number : position)];
    _title.text = track.title;
    _duration.text = FLClock(round(track.duration));
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", track.title, _duration.text];
}

- (void)setCurrent:(BOOL)current {
    _current = current;
    [self restyle];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self restyle];
}

- (void)apply:(FLTheme *)theme {
    _theme = theme;
    [self restyle];
}

- (void)restyle {
    if (!_theme) return;
    _highlight.backgroundColor = _current ? _theme.tint : self.highlighted ? [_theme.text colorWithAlphaComponent:0.06] : UIColor.clearColor;
    _title.textColor = _current ? _theme.accent : _theme.text;
    _number.textColor = _theme.secondary;
    _duration.textColor = _theme.secondary;
    _mark.tintColor = _theme.accent;
    _number.hidden = _current;
    _mark.hidden = !_current;
    self.accessibilityValue = _current ? @"Playing" : nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _highlight.frame = self.bounds;
    _number.frame = CGRectMake(4, 0, 22, 44);
    _mark.frame = CGRectMake(10, 10, 24, 24);
    _duration.frame = CGRectMake(width - 8 - 48, 0, 48, 44);
    _title.frame = CGRectMake(36, 0, CGRectGetMinX(_duration.frame) - 8 - 36, 44);
}

@end

/// An album: the cover with its details beside it, then its tracks across the full width.
@interface FLAlbumCell : UITableViewCell
@property (nonatomic, copy) void (^onTap)(FLTrack *track);
+ (CGFloat)heightFor:(FLAlbum *)album first:(BOOL)first;
- (void)showAlbum:(FLAlbum *)album first:(BOOL)first current:(nullable FLTrack *)current theme:(FLTheme *)theme;
- (void)setCurrent:(nullable FLTrack *)current;
- (void)apply:(FLTheme *)theme;
@end

@implementation FLAlbumCell {
    UIView *_line;
    UIImageView *_cover;
    UILabel *_title, *_artist, *_summary, *_format;
    NSMutableArray<FLTrackRow *> *_rows;
    NSUInteger _count;
    CGFloat _top;
}

+ (CGFloat)heightFor:(FLAlbum *)album first:(BOOL)first {
    return (first ? 8 : 20) + 88 + 8 + album.tracks.count * 44;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _line = [UIView new];
        _cover = [UIImageView new];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 2;
        _title = FLLabel([UIFont systemFontOfSize:15 weight:UIFontWeightSemibold], NSTextAlignmentLeft);
        _title.numberOfLines = 2;
        _artist = FLLabel([UIFont systemFontOfSize:13], NSTextAlignmentLeft);
        _summary = FLLabel(FLMono(10), NSTextAlignmentLeft);
        _format = FLLabel(FLMono(10), NSTextAlignmentLeft);
        _rows = [NSMutableArray array];
        for (UIView *view in @[_line, _cover, _title, _artist, _summary, _format]) [self.contentView addSubview:view];
    }
    return self;
}

- (void)showAlbum:(FLAlbum *)album first:(BOOL)first current:(FLTrack *)current theme:(FLTheme *)theme {
    _top = first ? 8 : 20;
    _line.hidden = first;
    _title.text = album.title;
    _artist.text = album.artist;
    NSMutableArray *summary = [NSMutableArray array];
    if (album.year) [summary addObject:[NSString stringWithFormat:@"%ld", (long)album.year]];
    [summary addObject:album.tracks.count == 1 ? @"1 TRACK" : [NSString stringWithFormat:@"%lu TRACKS", (unsigned long)album.tracks.count]];
    [summary addObject:FLClock(album.duration)];
    _summary.text = [summary componentsJoinedByString:@" · "];
    FLTrack *lead = album.tracks.firstObject;
    NSString *resolution = lead.bits > 0 ? [NSString stringWithFormat:@"%@ %ld/%@", lead.format, (long)lead.bits, FLRate(lead.sampleRate)]
                                           : [NSString stringWithFormat:@"%@ %@ kHz", lead.format, FLRate(lead.sampleRate)];
    _format.text = [NSString stringWithFormat:@"%@ · %@", resolution, FLSize(album.size)];
    _cover.image = [FLLibrary.shared coverForAlbum:album large:NO];
    _count = album.tracks.count;
    while (_rows.count < _count) {
        FLTrackRow *row = [FLTrackRow new];
        [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:row];
        [_rows addObject:row];
    }
    for (NSUInteger i = 0; i < _rows.count; i++) {
        _rows[i].hidden = i >= _count;
        if (i < _count) [_rows[i] showTrack:album.tracks[i] position:i + 1];
    }
    [self apply:theme];
    [self setCurrent:current];
    [self setNeedsLayout];
}

- (void)rowTapped:(FLTrackRow *)row {
    if (self.onTap) self.onTap(row.track);
}

- (void)setCurrent:(FLTrack *)current {
    for (NSUInteger i = 0; i < _count; i++) _rows[i].current = [_rows[i].track isEqual:current];
}

- (void)apply:(FLTheme *)theme {
    _title.textColor = theme.text;
    _artist.textColor = theme.secondary;
    _summary.textColor = theme.secondary;
    _format.textColor = theme.secondary;
    _line.backgroundColor = theme.line;
    _cover.backgroundColor = theme.line;
    for (FLTrackRow *row in _rows) [row apply:theme];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width, x = 12 + 88 + 12, textWidth = width - x - 12;
    _line.frame = CGRectMake(12, 0, width - 24, FLHairline());
    _cover.frame = CGRectMake(12, _top, 88, 88);
    CGFloat titleHeight = MIN(ceil([_title sizeThatFits:CGSizeMake(textWidth, 100)].height), 38);
    _title.frame = CGRectMake(x, _top + 1, textWidth, titleHeight);
    _artist.frame = CGRectMake(x, CGRectGetMaxY(_title.frame) + 1, textWidth, 17);
    _format.frame = CGRectMake(x, _top + 88 - 15, textWidth, 15);
    _summary.frame = CGRectMake(x, CGRectGetMinY(_format.frame) - 16, textWidth, 15);
    for (NSUInteger i = 0; i < _count; i++) _rows[i].frame = CGRectMake(8, _top + 96 + i * 44, width - 16, 44);
}

@end

/// A row of the Library tab.
@interface FLAlbumRow : UITableViewCell
- (void)showAlbum:(FLAlbum *)album theme:(FLTheme *)theme;
@end

@implementation FLAlbumRow {
    UIImageView *_cover;
    UILabel *_title, *_detail;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectedBackgroundView = [UIView new];
        _cover = [UIImageView new];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 2;
        _title = FLLabel([UIFont systemFontOfSize:14 weight:UIFontWeightSemibold], NSTextAlignmentLeft);
        _detail = FLLabel([UIFont systemFontOfSize:12.5], NSTextAlignmentLeft);
        for (UIView *view in @[_cover, _title, _detail]) [self.contentView addSubview:view];
    }
    return self;
}

- (void)showAlbum:(FLAlbum *)album theme:(FLTheme *)theme {
    _cover.image = [FLLibrary.shared coverForAlbum:album large:NO];
    _title.text = album.title;
    _detail.text = album.year ? [NSString stringWithFormat:@"%@ · %ld", album.artist, (long)album.year] : album.artist;
    _cover.backgroundColor = theme.line;
    _title.textColor = theme.text;
    _detail.textColor = theme.secondary;
    self.selectedBackgroundView.backgroundColor = [theme.text colorWithAlphaComponent:0.06];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    _cover.frame = CGRectMake(12, 8, 44, 44);
    _title.frame = CGRectMake(68, 11, width - 68 - 12, 19);
    _detail.frame = CGRectMake(68, 31, width - 68 - 12, 17);
}

@end

#pragma mark - Main

@interface FLMainViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation FLMainViewController {
    CAGradientLayer *_glow;
    FLHeader *_header;
    FLTabs *_tabs;
    UITableView *_all, *_library;
    FLTransport *_transport;
    UIView *_empty, *_info;
    UILabel *_emptyHint;
    CADisplayLink *_link;
    FLTheme *_theme, *_from, *_to;
    CFTimeInterval _fadeStart, _lastTick;
    FLTrack *_shown;
    long _shownSecond;
    NSArray<NSString *> *_letters;
    NSArray<NSArray<FLAlbum *> *> *_sections;
    BOOL _scrolledToCurrent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // iOS 10's way; newer systems read contentInsetAdjustmentBehavior, set on each table.
    self.automaticallyAdjustsScrollViewInsets = NO;
#pragma clang diagnostic pop
    _theme = FLTheme.neutral;
    _glow = [CAGradientLayer layer];
    [self.view.layer addSublayer:_glow];

    _header = [FLHeader new];
    [_header.wave addTarget:self action:@selector(seek:) forControlEvents:UIControlEventValueChanged];
    _tabs = [FLTabs new];
    [_tabs.all addTarget:self action:@selector(showAll) forControlEvents:UIControlEventTouchUpInside];
    [_tabs.library addTarget:self action:@selector(showLibrary) forControlEvents:UIControlEventTouchUpInside];
    [_tabs.settings addTarget:self action:@selector(showInfo) forControlEvents:UIControlEventTouchUpInside];

    _all = [self table];
    [_all registerClass:FLAlbumCell.class forCellReuseIdentifier:@"album"];
    _library = [self table];
    [_library registerClass:FLAlbumRow.class forCellReuseIdentifier:@"row"];
    _library.rowHeight = 60;
    _library.hidden = YES;

    _transport = [FLTransport new];
    FLPlayer *player = FLPlayer.shared;
    [_transport.stop addTarget:player action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    [_transport.previous addTarget:player action:@selector(previous) forControlEvents:UIControlEventTouchUpInside];
    [_transport.play addTarget:player action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [_transport.next addTarget:player action:@selector(next) forControlEvents:UIControlEventTouchUpInside];
    [_transport.shuffle addTarget:self action:@selector(toggleShuffle) forControlEvents:UIControlEventTouchUpInside];
    [_transport.repeat addTarget:self action:@selector(cycleRepeat) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *view in @[_header, _tabs, _all, _library, _transport]) [self.view addSubview:view];
    [self buildEmpty];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(libraryChanged) name:FLLibraryDidChange object:nil];
    [center addObserver:self selector:@selector(playerChanged) name:FLPlayerDidChange object:nil];
    [center addObserver:self selector:@selector(waveformChanged:) name:FLWaveformDidChange object:nil];
    [center addObserver:self selector:@selector(appeared) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(disappeared) name:UIApplicationDidEnterBackgroundNotification object:nil];

    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    _link.preferredFramesPerSecond = 30;
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    _theme = [FLLibrary.shared themeForTrack:player.current];
    [self applyTheme:_theme];
    [self libraryChanged];
    [self playerChanged];
}

- (UITableView *)table {
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.backgroundColor = UIColor.clearColor;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    table.dataSource = self;
    table.delegate = self;
    table.contentInset = UIEdgeInsetsMake(0, 0, 8, 0);
    if ([table respondsToSelector:NSSelectorFromString(@"contentInsetAdjustmentBehavior")]) [table setValue:@2 forKey:@"contentInsetAdjustmentBehavior"];
    // iOS 15 and later add space above section headers that iOS 10 never had.
    if ([table respondsToSelector:NSSelectorFromString(@"sectionHeaderTopPadding")]) [table setValue:@0 forKey:@"sectionHeaderTopPadding"];
    return table;
}

- (void)buildEmpty {
    _empty = [UIView new];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Icon-60"]];
    icon.frame = CGRectMake(0, 0, 76, 76);
    icon.layer.cornerRadius = 17;
    icon.clipsToBounds = YES;
    icon.tag = 1;
    UILabel *title = FLLabel([UIFont systemFontOfSize:17 weight:UIFontWeightSemibold], NSTextAlignmentCenter);
    title.text = @"No music yet";
    title.tag = 2;
    _emptyHint = FLLabel(FLMono(10.5), NSTextAlignmentCenter);
    _emptyHint.numberOfLines = 0;
    _emptyHint.tag = 3;
    for (UIView *view in @[icon, title, _emptyHint]) [_empty addSubview:view];
    _empty.hidden = YES;
    [self.view addSubview:_empty];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = FLInsets(self.view);
    CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height, top = insets.top + 8;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glow.frame = CGRectMake(0, 0, width, top + 280);
    [CATransaction commit];
    _header.frame = CGRectMake(0, top, width, 162);
    _tabs.frame = CGRectMake(0, CGRectGetMaxY(_header.frame), width, 45);
    CGFloat transport = 84 + insets.bottom;
    _transport.frame = CGRectMake(0, height - transport, width, transport);
    CGRect list = CGRectMake(0, CGRectGetMaxY(_tabs.frame), width, CGRectGetMinY(_transport.frame) - CGRectGetMaxY(_tabs.frame));
    _all.frame = list;
    _library.frame = list;
    _empty.frame = self.view.bounds;
    CGFloat y = height * 0.36;
    [_empty viewWithTag:1].center = CGPointMake(width / 2, y);
    [_empty viewWithTag:2].frame = CGRectMake(16, y + 52, width - 32, 22);
    _emptyHint.frame = CGRectMake(24, y + 80, width - 48, 34);
    _info.frame = self.view.bounds;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self scrollToCurrent];
}

#pragma mark State

- (void)libraryChanged {
    FLLibrary *library = FLLibrary.shared;
    NSMutableArray *letters = [NSMutableArray array], *sections = [NSMutableArray array];
    for (FLAlbum *album in library.albums) {
        NSString *name = album.artist.lowercaseString;
        if ([name hasPrefix:@"the "]) name = [name substringFromIndex:4];
        NSString *letter = name.length ? [name substringToIndex:1].uppercaseString : @"#";
        if ([letter rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) letter = @"#";
        if (![letters.lastObject isEqualToString:letter]) {
            [letters addObject:letter];
            [sections addObject:[NSMutableArray array]];
        }
        [sections.lastObject addObject:album];
    }
    _letters = letters;
    _sections = sections;
    [_all reloadData];
    [_library reloadData];
    BOOL empty = library.tracks.count == 0;
    _emptyHint.text = library.scanning && empty ? @"READING…" : @"FINDER → THIS IPHONE → FILES\n→ FLACO LITE";
    _empty.hidden = !empty;
    for (UIView *view in @[_header, _tabs, _all, _library, _transport]) view.hidden = empty;
    _library.hidden = empty || _tabs.selected != 1;
    _all.hidden = empty || _tabs.selected != 0;
    _glow.hidden = empty;
    _shown = nil;
    [self playerChanged];
    if (!empty) [self scrollToCurrent];
#if TARGET_OS_SIMULATOR
    // For trying it without touching it: `simctl launch … -FLPlay 3 -FLSeek 60 -FLTab 1 -FLInfo YES`.
    static BOOL tried;
    NSUserDefaults *arguments = NSUserDefaults.standardUserDefaults;
    if (!empty && !tried && !library.scanning) {
        tried = YES;
        if ([arguments objectForKey:@"FLPlay"]) {
            NSInteger index = MIN([arguments integerForKey:@"FLPlay"], (NSInteger)library.tracks.count - 1);
            [self play:library.tracks[index]];
            if ([arguments doubleForKey:@"FLSeek"] > 0) [FLPlayer.shared seekTo:[arguments doubleForKey:@"FLSeek"]];
        }
        if ([arguments integerForKey:@"FLTab"] == 1) [self showLibrary];
        if ([arguments boolForKey:@"FLInfo"]) [self showInfo];
    }
#endif
}

- (void)playerChanged {
    FLPlayer *player = FLPlayer.shared;
    FLTrack *track = player.current;
    [_transport showPlaying:player.playing shuffle:player.shuffle repeat:player.repeatMode];
    _transport.status.text = track.status;
    _shownSecond = -1;
    if ((track || _shown) && [track isEqual:_shown]) return;
    _shown = track;
    FLAlbum *album = track ? [FLLibrary.shared albumForTrack:track] : nil;
    _header.cover.image = album ? [FLLibrary.shared coverForAlbum:album large:NO] : nil;
    _header.title.text = track ? track.title : @"Flaco Lite";
    _header.subtitle.text = track ? [NSString stringWithFormat:@"%@ — %@", track.artist, track.album] : @"Tap a song to play it";
    _header.wave.levels = [FLWaveforms.shared levelsFor:track];
    if (track) [FLWaveforms.shared prepare:track];
    for (FLAlbumCell *cell in _all.visibleCells) [cell setCurrent:track];
    [self fadeTo:[FLLibrary.shared themeForTrack:track]];
}

- (void)waveformChanged:(NSNotification *)note {
    if ([note.object isEqual:_shown.path]) _header.wave.levels = [FLWaveforms.shared levelsFor:_shown];
}

- (void)scrollToCurrent {
    FLTrack *track = FLPlayer.shared.current;
    FLAlbum *album = track ? [FLLibrary.shared albumForTrack:track] : nil;
    NSUInteger row = album ? [FLLibrary.shared.albums indexOfObject:album] : NSNotFound;
    if (row == NSNotFound || _scrolledToCurrent || _all.bounds.size.height == 0) return;
    _scrolledToCurrent = YES;
    [_all layoutIfNeeded];
    CGRect cell = [_all rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    CGFloat y = cell.origin.y + (row == 0 ? 8 : 20) + 96 + [album.tracks indexOfObject:track] * 44 - 44 * 2;
    CGFloat limit = MAX(0, _all.contentSize.height + _all.contentInset.bottom - _all.bounds.size.height);
    [_all setContentOffset:CGPointMake(0, MIN(MAX(0, y), limit)) animated:NO];
}

- (void)appeared {
    _link.paused = NO;
    FLPlayer.shared.analyzes = YES;
    FLWaveforms.shared.paused = NO;
}

- (void)disappeared {
    _link.paused = YES;
    FLPlayer.shared.analyzes = NO;
    FLWaveforms.shared.paused = YES;
}

#pragma mark Colours

- (void)fadeTo:(FLTheme *)theme {
    if ([theme isEqual:_to ?: _theme]) return;
    _from = _theme;
    _to = theme;
    _fadeStart = CACurrentMediaTime();
}

- (void)applyTheme:(FLTheme *)theme {
    _theme = theme;
    self.view.backgroundColor = theme.background;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glow.colors = @[(id)theme.glow.CGColor, (id)[theme.glow colorWithAlphaComponent:0].CGColor];
    [CATransaction commit];
    [_header apply:theme];
    [_tabs apply:theme];
    [_transport apply:theme];
    _library.sectionIndexColor = theme.secondary;
    _library.sectionIndexBackgroundColor = UIColor.clearColor;
    _library.sectionIndexTrackingBackgroundColor = [theme.text colorWithAlphaComponent:0.06];
    for (FLAlbumCell *cell in _all.visibleCells) [cell apply:theme];
    for (NSIndexPath *path in _library.indexPathsForVisibleRows) {
        FLAlbumRow *row = [_library cellForRowAtIndexPath:path];
        [row showAlbum:_sections[path.section][path.row] theme:theme];
    }
    for (NSInteger section = 0; section < _library.numberOfSections; section++) {
        UITableViewHeaderFooterView *header = [_library headerViewForSection:section];
        header.backgroundView.backgroundColor = theme.background;
        header.textLabel.textColor = theme.secondary;
    }
    UILabel *title = [_empty viewWithTag:2];
    title.textColor = theme.text;
    _emptyHint.textColor = theme.secondary;
    _empty.backgroundColor = theme.background;
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp, dt = _lastTick ? MIN(0.1, now - _lastTick) : 1.0 / 30;
    _lastTick = now;
    FLPlayer *player = FLPlayer.shared;
    float bands[FLBands];
    BOOL heard = player.playing && [player spectrum:bands];
    [_header.spectrum follow:heard ? bands : NULL dt:dt];

    double duration = player.current.duration, position = player.position;
    if (!_header.wave.dragging) _header.wave.progress = duration > 0 ? position / duration : 0;
    double shown = _header.wave.dragging ? _header.wave.dragged * duration : position;
    long second = (long)floor(shown);
    if (second != _shownSecond) {
        _shownSecond = second;
        _transport.time.text = player.current ? [NSString stringWithFormat:@"%@ / %@", FLClock(shown), FLClock(round(duration))] : @"";
    }

    if (_fadeStart > 0) {
        double t = MIN(1, (CACurrentMediaTime() - _fadeStart) / 0.6);
        double eased = t * t * (3 - 2 * t);
        [self applyTheme:t >= 1 ? _to : [_from mix:_to amount:eased]];
        if (t >= 1) {
            _fadeStart = 0;
            _theme = _to;
            _to = nil;
        }
    }
}

#pragma mark Actions

- (void)seek:(FLWaveView *)wave {
    [FLPlayer.shared seekTo:wave.progress * FLPlayer.shared.current.duration];
}

- (void)toggleShuffle {
    FLPlayer.shared.shuffle = !FLPlayer.shared.shuffle;
}

- (void)cycleRepeat {
    FLPlayer *player = FLPlayer.shared;
    player.repeatMode = (player.repeatMode + 1) % 3;
}

- (void)showAll {
    _tabs.selected = 0;
    _all.hidden = NO;
    _library.hidden = YES;
}

- (void)showLibrary {
    _tabs.selected = 1;
    _all.hidden = YES;
    _library.hidden = NO;
}

- (void)play:(FLTrack *)track {
    [FLPlayer.shared playTrack:track inList:FLLibrary.shared.tracks];
}

/// Settings has little to set: what's on the phone, and how to add more.
- (void)showInfo {
    FLLibrary *library = FLLibrary.shared;
    long long total = 0;
    for (FLTrack *track in library.tracks) total += track.size;
    NSDictionary *system = [NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    NSArray *rows = @[
        @[@"SONGS", [NSString stringWithFormat:@"%lu · %lu albums", (unsigned long)library.tracks.count, (unsigned long)library.albums.count]],
        @[@"SIZE", FLSize(total)],
        @[@"FREE", [NSString stringWithFormat:@"%@ of %@", FLSize([system[NSFileSystemFreeSize] longLongValue]), FLSize([system[NSFileSystemSize] longLongValue])]],
        @[@"ADD", @"Finder → iPhone → Files"],
        @[@"VERSION", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @""],
    ];
    UIControl *info = [[UIControl alloc] initWithFrame:self.view.bounds];
    info.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    [info addTarget:self action:@selector(hideInfo) forControlEvents:UIControlEventTouchUpInside];
    CGFloat width = MIN(self.view.bounds.size.width - 32, 340), rowHeight = 34;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 16 + rows.count * rowHeight + 60)];
    card.backgroundColor = _theme.panel;
    card.layer.cornerRadius = 12;
    card.layer.borderWidth = 1;
    card.layer.borderColor = _theme.line.CGColor;
    card.userInteractionEnabled = NO;
    for (NSUInteger i = 0; i < rows.count; i++) {
        UILabel *key = FLLabel(FLMono(10), NSTextAlignmentLeft), *value = FLLabel([UIFont systemFontOfSize:13.5], NSTextAlignmentRight);
        key.text = rows[i][0];
        value.text = rows[i][1];
        key.textColor = _theme.secondary;
        value.textColor = _theme.text;
        key.frame = CGRectMake(16, 8 + i * rowHeight, 80, rowHeight);
        value.frame = CGRectMake(90, 8 + i * rowHeight, width - 106, rowHeight);
        [card addSubview:key];
        [card addSubview:value];
    }
    UIButton *rescan = [UIButton buttonWithType:UIButtonTypeCustom];
    [rescan setTitle:@"READ THE FILES AGAIN" forState:UIControlStateNormal];
    rescan.titleLabel.font = FLMono(10.5);
    [rescan setTitleColor:_theme.accent forState:UIControlStateNormal];
    rescan.backgroundColor = _theme.tint;
    rescan.layer.cornerRadius = 8;
    rescan.frame = CGRectMake(12, CGRectGetHeight(card.frame) - 52, width - 24, 40);
    [rescan addTarget:self action:@selector(rescan) forControlEvents:UIControlEventTouchUpInside];
    card.center = CGPointMake(info.bounds.size.width / 2, info.bounds.size.height / 2);
    rescan.frame = [info convertRect:rescan.frame fromView:card];
    [info addSubview:card];
    [info addSubview:rescan];
    info.alpha = 0;
    [self.view addSubview:info];
    _info = info;
    [UIView animateWithDuration:0.2 animations:^{ info.alpha = 1; }];
}

- (void)hideInfo {
    UIView *info = _info;
    _info = nil;
    [UIView animateWithDuration:0.2 animations:^{ info.alpha = 0; } completion:^(BOOL finished) { [info removeFromSuperview]; }];
}

- (void)rescan {
    [FLLibrary.shared scan];
    [self hideInfo];
}

#pragma mark Tables

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return table == _all ? 1 : _sections.count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return table == _all ? FLLibrary.shared.albums.count : _sections[section].count;
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    if (table != _all) return 60;
    return [FLAlbumCell heightFor:FLLibrary.shared.albums[path.row] first:path.row == 0];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (table == _all) {
        FLAlbumCell *cell = [table dequeueReusableCellWithIdentifier:@"album" forIndexPath:path];
        [cell showAlbum:FLLibrary.shared.albums[path.row] first:path.row == 0 current:FLPlayer.shared.current theme:_theme];
        __weak FLMainViewController *weakSelf = self;
        cell.onTap = ^(FLTrack *track) { [weakSelf play:track]; };
        return cell;
    }
    FLAlbumRow *row = [table dequeueReusableCellWithIdentifier:@"row" forIndexPath:path];
    [row showAlbum:_sections[path.section][path.row] theme:_theme];
    return row;
}

- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return table == _library ? _letters[section] : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return table == _library ? 26 : 0;
}

- (void)tableView:(UITableView *)table willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    if (!header.backgroundView) header.backgroundView = [UIView new];
    header.backgroundView.backgroundColor = _theme.background;
    header.textLabel.font = FLMono(10.5);
    header.textLabel.textColor = _theme.secondary;
}

- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)table {
    return table == _library && _letters.count > 6 ? _letters : nil;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (table != _library) return;
    [table deselectRowAtIndexPath:path animated:YES];
    NSUInteger row = [FLLibrary.shared.albums indexOfObject:_sections[path.section][path.row]];
    [self showAll];
    if (row != NSNotFound) [_all scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
}

@end
